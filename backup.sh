#!/bin/bash
# ==============================================================================
# backup.sh - Full backup of the Drupal database and volumes
# ==============================================================================
set -e

DB_CONTAINER="drupal-db"
DB_NAME="drupal"
MYSQL_ROOT_PASSWORD="my-secret-pw"

# Exact volume names (as created by setup.sh)
VOLUMES=("drupal_modules" "drupal_profiles" "drupal_themes" "drupal_sites")

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
for vol in "${VOLUMES[@]}"; do
  if docker volume inspect "${vol}" >/dev/null 2>&1; then
    echo "    - Found volume: ${vol}"
    # Using local drupal:latest image so no new image download is needed
    docker run --rm \
      -v "${vol}":/data \
      -v "$(pwd)/${BACKUP_DIR}/volumes":/backup \
      drupal:latest tar czf "/backup/${vol}.tar.gz" -C /data .
  else
    echo "    ⚠️  Volume '${vol}' not found, skipping."
  fi
done

# ---- Keep only the latest backup in the repository ----
# Runs only after the new backup finished successfully (set -e), so a failed
# backup never deletes the previous good one.
echo "==> Removing older backups (keeping only ${BACKUP_DIR})..."
for old_dir in "${BACKUP_ROOT}"/backup_*/; do
  old_dir="${old_dir%/}"
  [ -d "${old_dir}" ] || continue
  [ "${old_dir}" = "${BACKUP_DIR}" ] && continue
  git rm -r -q -f --ignore-unmatch "${old_dir}" >/dev/null 2>&1 || true
  rm -rf "${old_dir}"
  echo "    - removed ${old_dir}"
done

# ---- Push backup to GitHub ----
echo "==> Pushing backup to GitHub..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

git add "${BACKUP_DIR}"
git commit -m "Automated backup: ${TIMESTAMP}" || echo "⚠️ Nothing to commit or git commit failed."
git pull --rebase origin "${CURRENT_BRANCH}" || echo "⚠️ Git pull failed."
git push origin "${CURRENT_BRANCH}" || echo "⚠️ Git push failed. Ensure SSH/credentials are configured."

echo ""
echo "=============================================="
echo " ✅ Backup complete and pushed: ${BACKUP_DIR}"
echo "=============================================="
