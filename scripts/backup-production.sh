#!/bin/bash
set -euo pipefail

APP_DIR="/root/opengym"
BACKUP_DIR="/root/gymlab-backups"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="${BACKUP_DIR}/gymlab-production-${TIMESTAMP}.tar.gz"

cd "$APP_DIR"

echo "=== Gymlab · backup de producción ==="
echo

mkdir -p "$BACKUP_DIR"

echo "Creando respaldo:"
echo "$BACKUP_FILE"
echo

tar -czf "$BACKUP_FILE" \
  data \
  coach-auth \
  .env \
  docker-compose.yml \
  docker-compose.prod.yml

chmod 600 "$BACKUP_FILE"

SHA256="$(sha256sum "$BACKUP_FILE" | awk '{print $1}')"

echo
echo "✓ Backup creado"
echo "  Archivo: $BACKUP_FILE"
echo "  SHA256:  $SHA256"
echo "  Tamaño:  $(du -h "$BACKUP_FILE" | awk '{print $1}')"
echo

echo "=== FIN ==="
