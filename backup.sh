#!/bin/bash
# ==============================================================================
# backup.sh - גיבוי מלא של בסיס הנתונים וקבצי ה-Volumes של Drupal
# ==============================================================================
set -e

DB_CONTAINER="drupal-db"
MYSQL_ROOT_PASSWORD="my-secret-pw"

VOLUMES=("drupal_modules" "drupal_profiles" "drupal_themes" "drupal_sites")

BACKUP_ROOT="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/backup_${TIMESTAMP}"

echo "=============================================="
echo " גיבוי בסיס נתונים וקבצים - ${TIMESTAMP}"
echo "=============================================="

mkdir -p "${BACKUP_DIR}/volumes"

# ---- בדיקה שהקונטיינר של ה-DB רץ ----
if [ ! "$(docker ps -q -f name=^${DB_CONTAINER}$)" ]; then
  echo "❌ קונטיינר ${DB_CONTAINER} לא רץ. יש להריץ setup.sh או להעלות אותו קודם."
  exit 1
fi

# ---- גיבוי בסיס הנתונים (MySQL) ----
echo "==> מגבה את בסיס הנתונים (mysqldump --all-databases)..."
docker exec "${DB_CONTAINER}" sh -c "exec mysqldump --all-databases -uroot -p${MYSQL_ROOT_PASSWORD}" \
  | gzip > "${BACKUP_DIR}/my-drupal.backup.sql.gz"
echo "✅ גיבוי DB נשמר ב: ${BACKUP_DIR}/my-drupal.backup.sql.gz"

# ---- גיבוי ה-Volumes של Drupal ----
echo "==> מגבה את קבצי ה-Volumes..."
for vol in "${VOLUMES[@]}"; do
  if docker volume inspect "${vol}" >/dev/null 2>&1; then
    echo "    - ${vol}"
    docker run --rm \
      -v "${vol}":/data \
      -v "$(pwd)/${BACKUP_DIR}/volumes":/backup \
      alpine tar czf "/backup/${vol}.tar.gz" -C /data .
  else
    echo "    ⚠️  volume ${vol} לא נמצא, מדלג."
  fi
done

echo "✅ גיבוי הושלם: ${BACKUP_DIR}"
echo ""
echo "כדי לשמור את הגיבוי ב-Git, הריצו:"
echo "  git add ${BACKUP_DIR}"
echo "  git commit -m \"backup ${TIMESTAMP}\""
echo "  git push"
