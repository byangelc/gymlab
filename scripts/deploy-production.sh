#!/bin/bash
set -euo pipefail

APP_DIR="/root/opengym"
BACKUP_DIR="/root/gymlab-backups"
DEPLOY_LOG="${BACKUP_DIR}/deployments.log"
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.prod.yml"

cd "$APP_DIR"
mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
CURRENT="$(git rev-parse HEAD)"
TARGET="unknown"
BACKUP_FILE="unknown"
DEPLOY_STARTED=false
LOGGED=false
TMP_BACKUP_OUTPUT="$(mktemp)"

cleanup() {
  rm -f "$TMP_BACKUP_OUTPUT"
}
trap cleanup EXIT

log_deploy() {
  local result="$1"
  local target_commit="$2"

  if [[ "$LOGGED" == true ]]; then
    return
  fi

  printf '%s | %s | %s -> %s | backup: %s\n' \
    "$TIMESTAMP" \
    "$result" \
    "$CURRENT" \
    "$target_commit" \
    "$BACKUP_FILE" >> "$DEPLOY_LOG"

  chmod 600 "$DEPLOY_LOG"
  LOGGED=true
}

on_error() {
  local exit_code=$?

  if [[ "$DEPLOY_STARTED" == true ]]; then
    log_deploy "FAILED" "$TARGET"
  fi

  echo
  echo "ERROR: el deploy terminó con código $exit_code."
  echo "Revisa el estado de producción antes de continuar."

  exit "$exit_code"
}

trap on_error ERR

echo "=== Gymlab · deploy de producción ==="
echo

echo "1. Verificando repositorio..."
if [[ -n "$(git status --short)" ]]; then
  echo "ERROR: hay cambios locales sin guardar."
  git status --short
  exit 1
fi

echo "✓ Working tree limpio"
echo

echo "2. Versión actual:"
git log -1 --oneline
echo

echo "3. Actualizando referencias de GitHub..."
git fetch origin
echo

echo "4. Versión disponible en origin/main:"
TARGET="$(git rev-parse origin/main)"
git log -1 --oneline origin/main
echo

echo "5. Comprobando cambios de código e imágenes..."

CODE_CHANGED=false
if [[ "$CURRENT" != "$TARGET" ]]; then
  CODE_CHANGED=true
  echo "Nueva versión de código detectada:"
  echo "  Actual: $CURRENT"
  echo "  Nueva:  $TARGET"
  git log --oneline "$CURRENT..$TARGET"
else
  echo "✓ El código ya coincide con origin/main."
fi
echo

echo "6. Registrando las imágenes que están en ejecución..."
API_CONTAINER_ID="$($COMPOSE ps -q api 2>/dev/null || true)"
WEB_CONTAINER_ID="$($COMPOSE ps -q web 2>/dev/null || true)"
RUNNING_API_IMAGE_ID=""
RUNNING_WEB_IMAGE_ID=""

if [[ -n "$API_CONTAINER_ID" ]]; then
  RUNNING_API_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$API_CONTAINER_ID")"
fi
if [[ -n "$WEB_CONTAINER_ID" ]]; then
  RUNNING_WEB_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$WEB_CONTAINER_ID")"
fi
echo

if [[ "$CODE_CHANGED" == true ]]; then
  DEPLOY_STARTED=true

  echo "7. Ejecutando backup antes de actualizar el código..."
  ./scripts/backup-production.sh | tee "$TMP_BACKUP_OUTPUT"
  BACKUP_FILE="$(awk -F': ' '/  Archivo:/ {print $2}' "$TMP_BACKUP_OUTPUT" | tail -1)"
  [[ -n "$BACKUP_FILE" ]] || BACKUP_FILE="unknown"
  echo

  echo "8. Actualizando código..."
  git pull --ff-only origin main
  echo
else
  echo "7. No hay cambios de código que integrar."
fi

echo "9. Validando Docker Compose..."
$COMPOSE config >/dev/null
echo "✓ Compose válido"
echo

API_IMAGE="$($COMPOSE config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["api"]["image"])')"
WEB_IMAGE="$($COMPOSE config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["web"]["image"])')"

echo "10. Comprobando imágenes disponibles en el registro..."
echo "API: $API_IMAGE"
echo "Web: $WEB_IMAGE"
$COMPOSE pull
echo

PULLED_API_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$API_IMAGE")"
PULLED_WEB_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$WEB_IMAGE")"

IMAGE_CHANGED=false
if [[ -z "$RUNNING_API_IMAGE_ID" || "$RUNNING_API_IMAGE_ID" != "$PULLED_API_IMAGE_ID" ]]; then
  IMAGE_CHANGED=true
  echo "• La imagen de la API es nueva o cambió."
fi
if [[ -z "$RUNNING_WEB_IMAGE_ID" || "$RUNNING_WEB_IMAGE_ID" != "$PULLED_WEB_IMAGE_ID" ]]; then
  IMAGE_CHANGED=true
  echo "• La imagen web es nueva o cambió."
fi

if [[ "$CODE_CHANGED" == false && "$IMAGE_CHANGED" == false ]]; then
  echo "✓ No hay cambios de código ni de imágenes."
  log_deploy "NO-CHANGE" "$TARGET"
  echo
  echo "=== FIN: no fue necesario recrear los servicios ==="
  exit 0
fi

if [[ "$CODE_CHANGED" == false ]]; then
  DEPLOY_STARTED=true
  echo
  echo "11. Ejecutando backup antes de recrear los servicios..."
  ./scripts/backup-production.sh | tee "$TMP_BACKUP_OUTPUT"
  BACKUP_FILE="$(awk -F': ' '/  Archivo:/ {print $2}' "$TMP_BACKUP_OUTPUT" | tail -1)"
  [[ -n "$BACKUP_FILE" ]] || BACKUP_FILE="unknown"
  echo
fi

echo "12. Recreando servicios..."
$COMPOSE up -d --force-recreate
echo

echo "13. Esperando a que API y web estén saludables (máximo 16 minutos)..."

API_STATUS=""
WEB_STATUS=""

for ((attempt=1; attempt<=192; attempt++)); do
  API_STATUS="$($COMPOSE ps --format '{{.Service}} {{.Health}}' | awk '$1 == "api" {print $2}')"
  WEB_STATUS="$($COMPOSE ps --format '{{.Service}} {{.Health}}' | awk '$1 == "web" {print $2}')"

  if [[ "$API_STATUS" == "healthy" && "$WEB_STATUS" == "healthy" ]]; then
    break
  fi

  if [[ "$API_STATUS" == "unhealthy" || "$WEB_STATUS" == "unhealthy" ]]; then
    break
  fi

  if (( attempt % 6 == 0 )); then
    echo "Esperando: API=${API_STATUS:-desconocido}, Web=${WEB_STATUS:-desconocido}"
  fi
  sleep 5
done

echo
echo "14. Comprobando estado final..."
$COMPOSE ps
echo

if [[ "$API_STATUS" != "healthy" ]]; then
  echo "ERROR: API no está healthy."
  log_deploy "FAILED-API" "$TARGET"
  exit 1
fi

if [[ "$WEB_STATUS" != "healthy" ]]; then
  echo "ERROR: Web no está healthy."
  log_deploy "FAILED-WEB" "$TARGET"
  exit 1
fi

echo "✓ API healthy"
echo "✓ Web healthy"

log_deploy "SUCCESS" "$TARGET"

echo
echo "=== FIN ==="
echo "✓ Deploy completado correctamente."
echo "✓ Despliegue registrado en:"
echo "  $DEPLOY_LOG"
