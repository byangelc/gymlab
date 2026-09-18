#!/bin/bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

echo "=== Gymlab · actualización de upstream ==="
echo

if [[ -n "$(git status --short)" ]]; then
  echo "ERROR: tienes cambios locales sin guardar."
  echo "Guárdalos o haz commit antes de continuar."
  exit 1
fi

CURRENT="$(git rev-parse develop)"
echo "Versión actual de develop:"
git log -1 --oneline develop
echo

echo "Consultando upstream de Duarte..."
git fetch upstream --tags

UPSTREAM="$(git rev-parse upstream/main)"

echo "Upstream actual:"
git log -1 --oneline upstream/main
echo

if [[ "$CURRENT" == "$UPSTREAM" ]]; then
  echo "✓ Gymlab ya está actualizado con upstream."
  exit 0
fi

echo "Cambios nuevos de Duarte:"
git log --oneline --decorate "$CURRENT..$UPSTREAM"
echo

echo "Archivos afectados:"
git diff --stat "$CURRENT..$UPSTREAM"
echo

echo "=== FIN ==="
echo "No se modificó ningún archivo."
echo "No se modificó producción."
echo "No se hizo ningún merge."
