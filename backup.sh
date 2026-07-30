#!/bin/bash
# ==============================================================================
# backup.sh - Full backup of the Drupal database and volumes
# ==============================================================================
set -e

DB_CONTAINER="drupal-db"
DB_NAME="drupal"
MYSQL_ROOT_PASSWORD="my-secret-pw"

VOLUMES=("dev_tools_final_project_drupal_modules" "dev_tools_final_project_drupal_profiles" "dev_tools_final_project_drupal_themes" "dev_tools_final_project_drupal_sites")

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
echo "==> Backing up the database (mysqldump --all-databases)..."
docker exec "${DB_CONTAINER}" sh -c "exec mysqldump --all-databases -uroot -p${MYSQL_ROOT_PASSWORD}" \
  | gzip > "${BACKUP_DIR}/drupal_db_backup.sql.gz"
echo "✅ DB backup saved to: ${BACKUP_DIR}/drupal_db_backup.sql.gz"

# ---- Backup the Drupal volumes ----
echo "==> Backing up volumes..."
for vol in "${VOLUMES[@]}"; do
  if docker volume inspect "${vol}" >/dev/null 2>&1; then
    echo "    - ${vol}"
    docker run --rm \
      -v "${vol}":/data \
      -v "$(pwd)/${BACKUP_DIR}/volumes":/backup \
      alpine tar czf "/backup/${vol}.tar.gz" -C /data .
  else
    echo "    ⚠️  Volume ${vol} not found, skipping."
  fi
done

echo "✅ Backup complete: ${BACKUP_DIR}"
echo ""
echo "To save the backup in Git, run:"
echo "  git add ${BACKUP_DIR}"
echo "  git commit -m \"backup ${TIMESTAMP}\""
echo "  git push"