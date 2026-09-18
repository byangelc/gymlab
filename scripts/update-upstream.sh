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

echo "1. Consultando upstream de Duarte..."
git fetch upstream --tags
echo

DEVELOP="$(git rev-parse develop)"
UPSTREAM="$(git rev-parse upstream/main)"
BASE="$(git merge-base develop upstream/main)"

echo "2. Estado actual:"
echo "  develop:      $DEVELOP"
echo "  upstream/main: $UPSTREAM"
echo "  punto común:   $BASE"
echo

echo "3. Último commit de develop:"
git log -1 --oneline develop
echo

echo "4. Último commit de upstream:"
git log -1 --oneline upstream/main
echo

if [[ "$DEVELOP" == "$UPSTREAM" ]]; then
  echo "✓ develop está exactamente alineado con upstream."
  echo
  echo "=== FIN ==="
  echo "No se modificó ningún archivo."
  echo "No se modificó producción."
  echo "No se hizo ningún merge."
  exit 0
fi

if [[ "$BASE" == "$UPSTREAM" ]]; then
  echo "✓ No hay cambios nuevos de Duarte respecto al punto común."
  echo
  echo "Commits propios de Gymlab pendientes:"
  git log --oneline "$BASE..develop"
  echo
  echo "=== FIN ==="
  echo "No se modificó ningún archivo."
  echo "No se modificó producción."
  echo "No se hizo ningún merge."
  exit 0
fi

echo "5. Cambios nuevos publicados por Duarte:"
git log --oneline --decorate "$BASE..$UPSTREAM"
echo

echo "6. Archivos afectados por los cambios de Duarte:"
git diff --stat "$BASE..$UPSTREAM"
echo

echo "7. Commits propios de Gymlab desde el punto común:"
if [[ "$BASE" == "$DEVELOP" ]]; then
  echo "  (ninguno)"
else
  git log --oneline --decorate "$BASE..$DEVELOP"
fi
echo

echo "=== FIN ==="
echo "No se modificó ningún archivo."
echo "No se modificó producción."
echo "No se hizo ningún merge."
