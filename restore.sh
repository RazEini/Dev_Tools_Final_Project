#!/bin/bash
# ==============================================================================
# restore.sh - Full Drupal restoration (Database + Volumes) from a backup
# Usage: ./restore.sh <path-to-backup-dir>   (e.g., ./backups/backup_20260730_120000)
# If no path is provided, it automatically uses the latest backup in ./backups/
# ==============================================================================
set -e

NETWORK_NAME="drupal-net"

DB_CONTAINER="drupal-db"
DB_IMAGE="mysql:8.0"
DB_ROOT_PASSWORD="my-secret-pw"
DB_NAME="drupal"
DB_USER="drupaluser"
DB_PASS="drupalpass"

DRUPAL_CONTAINER="drupal-web"
DRUPAL_IMAGE="drupal:latest"
DRUPAL_PORT="8080"

VOLUMES=("drupal_modules" "drupal_profiles" "drupal_themes" "drupal_sites")

# ---- Step 00: Pull Latest Backups from GitHub ----
echo "==> Fetching latest changes and backups from GitHub..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
git pull origin "${CURRENT_BRANCH}" || echo "⚠️ Git pull failed. Proceeding with local files if available."

# ---- Step 0: Resolve Backup Directory ----
if [ -n "$1" ]; then
  if [[ "$1" == *.tar.gz || "$1" == *.tgz ]]; then
    BACKUP_ARCHIVE="$1"
    if [ ! -f "${BACKUP_ARCHIVE}" ]; then
      echo "❌ Backup archive not found: ${BACKUP_ARCHIVE}"
      exit 1
    fi

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "${TMP_DIR}"' EXIT

    echo "==> Extracting temporary backup archive..."
    tar xzf "${BACKUP_ARCHIVE}" -C "${TMP_DIR}"
    BACKUP_DIR=$(find "${TMP_DIR}" -maxdepth 1 -mindepth 1 -type d | head -1)
    if [ -z "${BACKUP_DIR}" ]; then
      echo "❌ Archive does not contain a valid backup directory."
      exit 1
    fi
  else
    BACKUP_DIR="$1"
  fi
else
  # Clean auto-discovery using find (avoids trailing slashes issues)
  BACKUP_DIR=$(find ./backups -maxdepth 1 -mindepth 1 -type d -name "backup_*" 2>/dev/null | sort -r | head -n 1)
  if [ -z "${BACKUP_DIR}" ]; then
    echo "❌ No backup directory found. Usage: ./restore.sh <path-to-backup-dir> or ./restore.sh <backup-archive.tar.gz>"
    exit 1
  fi
fi

# Strip any trailing slash if present
BACKUP_DIR="${BACKUP_DIR%/}"

BACKUP_FILE="${BACKUP_DIR}/drupal_db_backup.sql.gz"
if [ ! -f "${BACKUP_FILE}" ]; then
  echo "❌ Database backup file not found: ${BACKUP_FILE}"
  exit 1
fi

# Resolve absolute path to backup folder for reliable volume mounts
ABS_BACKUP_DIR=$(cd "${BACKUP_DIR}" && pwd)

echo "=============================================="
echo " Restoring from: ${BACKUP_DIR}"
echo "=============================================="

# ---- Step 1: Ensure Docker Network Exists ----
docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 || docker network create "${NETWORK_NAME}"

# ---- Step 2: Ensure Database Container is Running ----
if [ ! "$(docker ps -q -f name=^${DB_CONTAINER}$)" ]; then
  if [ "$(docker ps -aq -f name=^${DB_CONTAINER}$)" ]; then
    docker start "${DB_CONTAINER}"
  else
    docker run -d \
      --name "${DB_CONTAINER}" \
      --network "${NETWORK_NAME}" \
      --restart always \
      -e MYSQL_ROOT_PASSWORD="${DB_ROOT_PASSWORD}" \
      -e MYSQL_DATABASE="${DB_NAME}" \
      -e MYSQL_USER="${DB_USER}" \
      -e MYSQL_PASSWORD="${DB_PASS}" \
      -p 3306:3306 \
      -v db_data:/var/lib/mysql \
      "${DB_IMAGE}"
  fi
fi

echo "==> Waiting for Database container..."
until docker exec "${DB_CONTAINER}" mysql -u"${DB_USER}" -p"${DB_PASS}" -e "USE ${DB_NAME};" >/dev/null 2>&1; do
  sleep 3
done
echo "✅ Database is ready."

echo "==> Creating database if it does not exist..."
docker exec "${DB_CONTAINER}" sh -c "exec mysqladmin -uroot -p${DB_ROOT_PASSWORD} create ${DB_NAME}" >/dev/null 2>&1 || true

# ---- Step 3: Restore Database Dump ----
echo "==> Restoring MySQL database..."
gunzip < "${BACKUP_FILE}" | docker exec -i "${DB_CONTAINER}" sh -c "exec mysql -h 127.0.0.1 -u${DB_USER} -p${DB_PASS} --force ${DB_NAME}"
echo "✅ Database restored."

# ---- Step 4: Stop Drupal Web Container Before File Restore ----
docker stop "${DRUPAL_CONTAINER}" >/dev/null 2>&1 || true

# ---- Step 5: Restore Volumes ----
echo "==> Restoring Volume files..."
for vol_suffix in "${VOLUMES[@]}"; do
  vol_backup="${BACKUP_DIR}/volumes/${vol_suffix}.tar.gz"
  
  # Dynamic resolution to catch directory/compose prefixes automatically
  ACTUAL_VOL=$(docker volume ls --format '{{.Name}}' | grep -E "(^|_)${vol_suffix}$" | head -n 1)
  
  if [ -z "${ACTUAL_VOL}" ]; then
    ACTUAL_VOL="${vol_suffix}"
    docker volume create "${ACTUAL_VOL}" >/dev/null
  fi

  if [ -f "${vol_backup}" ]; then
    echo "    - Restoring to: ${ACTUAL_VOL}"
    docker run --rm \
      -v "${ACTUAL_VOL}":/data \
      -v "${ABS_BACKUP_DIR}/volumes":/backup \
      drupal:latest sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf /backup/${vol_suffix}.tar.gz -C /data"
  else
    echo "    ⚠️  No backup archive found for ${vol_suffix}, skipping."
  fi
done

# ---- Step 6: Start/Restart Drupal Container ----
if [ "$(docker ps -aq -f name=^${DRUPAL_CONTAINER}$)" ]; then
  docker start "${DRUPAL_CONTAINER}"
else
  docker run -d \
    --name "${DRUPAL_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    --restart always \
    -p ${DRUPAL_PORT}:80 \
    -v drupal_modules:/var/www/html/modules \
    -v drupal_profiles:/var/www/html/profiles \
    -v drupal_themes:/var/www/html/themes \
    -v drupal_sites:/var/www/html/sites \
    "${DRUPAL_IMAGE}"
fi

echo "==> Ensuring Drupal is running and rebuilding cache..."
docker restart "${DRUPAL_CONTAINER}" >/dev/null 2>&1 || true
docker exec -w /opt/drupal "${DRUPAL_CONTAINER}" /opt/drupal/vendor/bin/drush cr >/dev/null 2>&1 || true

echo ""
echo "=============================================="
echo " ✅ Restoration completed successfully!"
echo " Browse to: http://localhost:${DRUPAL_PORT}"
echo " Log in with your restored credentials."
echo "=============================================="