#!/bin/bash
set -euo pipefail

APP_DIR="/root/opengym"
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.prod.yml"

cd "$APP_DIR"

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
CURRENT="$(git rev-parse HEAD)"
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

echo "Nueva versión detectada:"
echo "  Actual:   $CURRENT"
echo "  Nueva:    $TARGET"
echo

echo "Cambios que se desplegarán:"
git log --oneline "$CURRENT..$TARGET"
echo

echo "6. Ejecutando backup antes del despliegue..."
./scripts/backup-production.sh
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
  exit 1
fi

if [[ "$WEB_STATUS" != "healthy" ]]; then
  echo "ERROR: Web no está healthy."
  exit 1
fi

echo "✓ API healthy"
echo "✓ Web healthy"
echo

echo "=== FIN ==="
echo "✓ Deploy completado correctamente."
