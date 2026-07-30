#!/bin/bash
# ==============================================================================
# cleanup.sh - ניקוי מלא של כל מה שנוצר עבור הפרויקט (containers, images, volumes, network)
# ==============================================================================
set -e

NETWORK_NAME="drupal-net"
DB_CONTAINER="drupal-db"
DRUPAL_CONTAINER="drupal-web"
DB_IMAGE="mysql:8.0"
DRUPAL_IMAGE="drupal:latest"
VOLUMES=("db_data" "drupal_modules" "drupal_profiles" "drupal_themes" "drupal_sites")

echo "=============================================="
echo " מנקה את כל משאבי הפרויקט"
echo "=============================================="

read -p "⚠️  פעולה זו תמחק את כל הנתונים שלא גובו. להמשיך? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "בוטל."
  exit 0
fi

echo "==> מוחק קונטיינרים..."
docker rm -f "${DRUPAL_CONTAINER}" >/dev/null 2>&1 && echo "    - ${DRUPAL_CONTAINER} נמחק" || echo "    - ${DRUPAL_CONTAINER} לא נמצא"
docker rm -f "${DB_CONTAINER}" >/dev/null 2>&1 && echo "    - ${DB_CONTAINER} נמחק" || echo "    - ${DB_CONTAINER} לא נמצא"

echo "==> מוחק Volumes..."
for vol in "${VOLUMES[@]}"; do
  docker volume rm "${vol}" >/dev/null 2>&1 && echo "    - ${vol} נמחק" || echo "    - ${vol} לא נמצא"
done

echo "==> מוחק רשת..."
docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 && echo "    - ${NETWORK_NAME} נמחקה" || echo "    - ${NETWORK_NAME} לא נמצאה"

echo "==> מוחק Images..."
docker rmi "${DRUPAL_IMAGE}" >/dev/null 2>&1 && echo "    - ${DRUPAL_IMAGE} נמחק" || echo "    - ${DRUPAL_IMAGE} לא נמצא"
docker rmi "${DB_IMAGE}" >/dev/null 2>&1 && echo "    - ${DB_IMAGE} נמחק" || echo "    - ${DB_IMAGE} לא נמצא"

echo ""
echo "✅ הניקוי הושלם. הסביבה חזרה למצב שהייתה לפני ההתקנה."
