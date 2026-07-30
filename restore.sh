#!/bin/bash
# ==============================================================================
# restore.sh - שחזור מלא של האתר (בסיס נתונים + volumes) מתוך גיבוי
# שימוש: ./restore.sh <path-to-backup-dir>   (לדוגמה: ./backups/backup_20260730_120000)
# אם לא מציינים נתיב - הסקריפט ישתמש בגיבוי העדכני ביותר בתיקיית backups/
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

# ---- קביעת תיקיית הגיבוי ----
if [ -n "$1" ]; then
  BACKUP_DIR="$1"
else
  BACKUP_DIR=$(ls -td ./backups/backup_*/ 2>/dev/null | head -1)
  if [ -z "${BACKUP_DIR}" ]; then
    echo "❌ לא נמצאה תיקיית גיבוי. שימוש: ./restore.sh <path-to-backup-dir>"
    exit 1
  fi
fi

BACKUP_FILE="${BACKUP_DIR}/my-drupal.backup.sql.gz"
if [ ! -f "${BACKUP_FILE}" ]; then
  echo "❌ קובץ גיבוי לא נמצא: ${BACKUP_FILE}"
  exit 1
fi

echo "=============================================="
echo " משחזר מתוך: ${BACKUP_DIR}"
echo "=============================================="

# ---- שלב 1: רשת ----
docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 || docker network create "${NETWORK_NAME}"

# ---- שלב 2: העלאת בסיס הנתונים ----
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

echo "==> ממתין ל-DB..."
until docker exec "${DB_CONTAINER}" mysqladmin ping -h localhost -uroot -p"${DB_ROOT_PASSWORD}" --silent >/dev/null 2>&1; do
  sleep 3
done
echo "✅ DB מוכן."

# ---- שלב 3: שחזור בסיס הנתונים (הדאמפ מכיל CREATE DATABASE, לכן מספיק לייבא ישירות) ----
echo "==> משחזר את בסיס הנתונים..."
gunzip < "${BACKUP_FILE}" | docker exec -i "${DB_CONTAINER}" sh -c "exec mysql -uroot -p${DB_ROOT_PASSWORD} --force"
echo "✅ בסיס הנתונים שוחזר."

# ---- שלב 4: עצירת drupal לפני שחזור קבצים ----
docker stop "${DRUPAL_CONTAINER}" >/dev/null 2>&1 || true

# ---- שלב 5: שחזור ה-Volumes ----
echo "==> משחזר קבצי Volumes..."
for vol in "${VOLUMES[@]}"; do
  vol_backup="${BACKUP_DIR}/volumes/${vol}.tar.gz"
  if [ -f "${vol_backup}" ]; then
    echo "    - ${vol}"
    docker volume create "${vol}" >/dev/null
    docker run --rm \
      -v "${vol}":/data \
      -v "$(pwd)/${BACKUP_DIR}/volumes":/backup \
      alpine sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf /backup/${vol}.tar.gz -C /data"
  else
    echo "    ⚠️  אין גיבוי עבור ${vol}, מדלג."
  fi
done

# ---- שלב 6: הרצת / הפעלת drupal מחדש ----
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

echo ""
echo "=============================================="
echo " ✅ שחזור הושלם!"
echo " גלשו אל: http://localhost:${DRUPAL_PORT}"
echo " התחברו עם אחד מהמשתמשים הקיימים (demoadmin וכו')."
echo "=============================================="
