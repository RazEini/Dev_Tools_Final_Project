#!/bin/bash
# ==============================================================================
# backup.sh - Full backup of the Drupal database and volumes
# ==============================================================================
set -e

DB_CONTAINER="drupal-db"
DB_NAME="drupal"
MYSQL_ROOT_PASSWORD="my-secret-pw"

# Base volume suffixes
VOLUME_SUFFIXES=("drupal_modules" "drupal_profiles" "drupal_themes" "drupal_sites")

BACKUP_ROOT="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/backup_${TIMESTAMP}"

echo "=============================================="
echo " Database and files backup - ${TIMESTAMP}"
echo "=============================================="

mkdir -p "${BACKUP_DIR}/volumes"

# ---- Check that the DB container is running ----
if [ ! "$(docker ps -q -f name=^${DB_CONTAINER}$)" ]; then
  echo "❌ Container ${DB_CONTAINER} is not running. Run setup.sh or start it first."
  exit 1
fi

# ---- Backup the database (MySQL) ----
echo "==> Backing up the database (${DB_NAME})..."
docker exec "${DB_CONTAINER}" sh -c "exec mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} --databases ${DB_NAME}" \
  | gzip > "${BACKUP_DIR}/drupal_db_backup.sql.gz"
echo "✅ DB backup saved to: ${BACKUP_DIR}/drupal_db_backup.sql.gz"

# ---- Backup the Drupal volumes ----
echo "==> Backing up volumes..."
for vol_suffix in "${VOLUME_SUFFIXES[@]}"; do
  # Dynamically resolve full volume name (handles prefixes automatically)
  ACTUAL_VOL=$(docker volume ls --format '{{.Name}}' | grep -E "(^|_)${vol_suffix}$" | head -n 1)

  if [ -n "${ACTUAL_VOL}" ]; then
    echo "    - Found volume: ${ACTUAL_VOL}"
    # Using local drupal:latest image so no new image download is needed
    docker run --rm \
      -v "${ACTUAL_VOL}":/data \
      -v "$(pwd)/${BACKUP_DIR}/volumes":/backup \
      drupal:latest tar czf "/backup/${vol_suffix}.tar.gz" -C /data .
  else
    echo "    ⚠️  Volume matching '${vol_suffix}' not found, skipping."
  fi
done

echo "✅ Backup complete: ${BACKUP_DIR}"