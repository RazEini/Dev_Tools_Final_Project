#!/bin/bash
# ==============================================================================
# setup.sh - הקמת תשתית Docker מלאה עבור אתר Drupal + MySQL
# מריץ: network, שני containers, ומתקין את Drupal אוטומטית (drush)
# ==============================================================================
set -e

# ---- משתני סביבה ----
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

SITE_NAME="האתר של Raz"
ADMIN_USER="demoadmin"
ADMIN_PASS="secretpass"
SITE_LANG="he"   # he = עברית, en = אנגלית

echo "=============================================="
echo " שלב 1: יצירת רשת Docker פנימית"
echo "=============================================="
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  docker network create "${NETWORK_NAME}"
  echo "✅ נוצרה רשת: ${NETWORK_NAME}"
else
  echo "ℹ️  הרשת ${NETWORK_NAME} כבר קיימת, ממשיכים."
fi

echo ""
echo "=============================================="
echo " שלב 2: הרצת קונטיינר בסיס הנתונים (MySQL)"
echo "=============================================="
if [ "$(docker ps -aq -f name=^${DB_CONTAINER}$)" ]; then
  echo "ℹ️  קונטיינר ${DB_CONTAINER} כבר קיים, מוודא שהוא רץ..."
  docker start "${DB_CONTAINER}" >/dev/null 2>&1 || true
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
  echo "✅ קונטיינר ${DB_CONTAINER} עלה."
fi

echo "==> ממתין שה-DB יהיה זמין..."
until docker exec "${DB_CONTAINER}" mysqladmin ping -h localhost -uroot -p"${DB_ROOT_PASSWORD}" --silent >/dev/null 2>&1; do
  echo "    ...עדיין לא מוכן"
  sleep 3
done
echo "✅ בסיס הנתונים מוכן."

echo ""
echo "=============================================="
echo " שלב 3: הרצת קונטיינר Drupal"
echo "=============================================="
if [ "$(docker ps -aq -f name=^${DRUPAL_CONTAINER}$)" ]; then
  echo "ℹ️  קונטיינר ${DRUPAL_CONTAINER} כבר קיים, מוודא שהוא רץ..."
  docker start "${DRUPAL_CONTAINER}" >/dev/null 2>&1 || true
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
  echo "✅ קונטיינר ${DRUPAL_CONTAINER} עלה."
fi

echo "==> ממתין שקבצי Drupal יהיו זמינים בתוך הקונטיינר..."
until docker exec "${DRUPAL_CONTAINER}" test -f /opt/drupal/vendor/bin/drush >/dev/null 2>&1; do
  echo "    ...עדיין טוען"
  sleep 3
done
echo "✅ Drupal מוכן."

echo ""
echo "=============================================="
echo " שלב 4: התקנת Drupal אוטומטית (drush site-install)"
echo "=============================================="

# בדיקה אם האתר כבר מותקן (settings.php קיים ומאותחל)
if docker exec "${DRUPAL_CONTAINER}" test -f /opt/drupal/web/sites/default/settings.php 2>/dev/null; then
  echo "ℹ️  נראה שהאתר כבר מותקן, מדלג על ההתקנה."
else
  docker exec "${DRUPAL_CONTAINER}" /opt/drupal/vendor/bin/drush site-install standard \
    --db-url="mysql://${DB_USER}:${DB_PASS}@${DB_CONTAINER}:3306/${DB_NAME}" \
    --site-name="${SITE_NAME}" \
    --account-name="${ADMIN_USER}" \
    --account-pass="${ADMIN_PASS}" \
    --locale="${SITE_LANG}" \
    -y

  echo "✅ Drupal הותקן בהצלחה."
fi

echo ""
echo "=============================================="
echo " ✅ ההתקנה הושלמה!"
echo " גלשו אל: http://localhost:${DRUPAL_PORT}"
echo " משתמש מנהל: ${ADMIN_USER} / ${ADMIN_PASS}"
echo "=============================================="
