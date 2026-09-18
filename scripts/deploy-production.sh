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

echo "5. Comprobando si hay una nueva versión..."

if [[ "$CURRENT" == "$TARGET" ]]; then
  echo "✓ Producción ya está actualizada."
  echo "✓ No se modificó producción."
  echo
  echo "=== FIN ==="
  exit 0
fi

DEPLOY_STARTED=true

echo "Nueva versión detectada:"
echo "  Actual:   $CURRENT"
echo "  Nueva:    $TARGET"
echo

echo "Cambios que se desplegarán:"
git log --oneline "$CURRENT..$TARGET"
echo

echo "6. Ejecutando backup antes del despliegue..."
./scripts/backup-production.sh | tee "$TMP_BACKUP_OUTPUT"

BACKUP_FILE="$(awk -F': ' '/  Archivo:/ {print $2}' "$TMP_BACKUP_OUTPUT" | tail -1)"

if [[ -z "$BACKUP_FILE" ]]; then
  BACKUP_FILE="unknown"
fi

echo
echo "7. Actualizando código..."
git pull --ff-only origin main
echo

echo "8. Validando Docker Compose..."
$COMPOSE config >/dev/null
echo "✓ Compose válido"
echo

echo "9. Descargando imágenes..."
$COMPOSE pull
echo

echo "10. Recreando servicios..."
$COMPOSE up -d --force-recreate
echo

echo "11. Esperando servicios..."
sleep 10

echo "12. Comprobando estado..."
$COMPOSE ps
echo

API_STATUS="$($COMPOSE ps --format '{{.Service}} {{.Health}}' | awk '$1 == "api" {print $2}')"
WEB_STATUS="$($COMPOSE ps --format '{{.Service}} {{.Health}}' | awk '$1 == "web" {print $2}')"

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
