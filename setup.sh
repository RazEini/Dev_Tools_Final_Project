#!/bin/bash
# ==============================================================================
# setup.sh - Complete Docker infrastructure setup for Drupal + MySQL
# Runs: network, two containers, and automatically installs Drupal via Drush
# ==============================================================================
set -e

# ---- Environment Variables ----
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

# Fixed: Removed single quote/apostrophe from site name to prevent CLI quote syntax errors
SITE_NAME="האתר של רז עייני, אריאל לוין ורז יעקבי"
ADMIN_USER="demoadmin"
ADMIN_PASS="secretpass"
SITE_LANG="en"   # en = English, he = Hebrew

echo "=============================================="
echo " Step 1: Creating internal Docker network"
echo "=============================================="
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  docker network create "${NETWORK_NAME}"
  echo "✅ Network created: ${NETWORK_NAME}"
else
  echo "ℹ️  Network ${NETWORK_NAME} already exists, continuing."
fi

echo ""
echo "=============================================="
echo " Step 2: Running Database container (MySQL)"
echo "=============================================="
if [ "$(docker ps -aq -f name=^${DB_CONTAINER}$)" ]; then
  echo "ℹ️  Container ${DB_CONTAINER} already exists, ensuring it is running..."
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
    -v db_data:/var/lib/mysql \
    "${DB_IMAGE}"
  echo "✅ Container ${DB_CONTAINER} is up."
fi

echo "==> Waiting for Database and User initialization to complete..."
# Fixed: Checking specific database access with drupaluser instead of root ping
until docker exec "${DB_CONTAINER}" mysql -u"${DB_USER}" -p"${DB_PASS}" -e "USE ${DB_NAME};" >/dev/null 2>&1; do
  echo "    ...Still waiting for MySQL database and user setup"
  sleep 3
done
echo "✅ Database is fully ready."

echo ""
echo "=============================================="
echo " Step 3: Running Drupal container"
echo "=============================================="
if [ "$(docker ps -aq -f name=^${DRUPAL_CONTAINER}$)" ]; then
  echo "ℹ️  Container ${DRUPAL_CONTAINER} already exists, ensuring it is running..."
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
  echo "✅ Container ${DRUPAL_CONTAINER} is up."
fi

echo "==> Ensuring Apache/PHP service inside container is ready..."
until docker exec "${DRUPAL_CONTAINER}" php -v >/dev/null 2>&1; do
  echo "    ...Still loading"
  sleep 3
done

# Install Drush if it does not exist in the container
if ! docker exec "${DRUPAL_CONTAINER}" test -f /opt/drupal/vendor/bin/drush 2>/dev/null; then
  echo "==> Installing Drush inside container..."
  docker exec "${DRUPAL_CONTAINER}" composer require drush/drush --quiet || true
fi

echo "✅ Drupal container is ready."

echo ""
echo "=============================================="
echo " Step 4: Automatic Drupal Installation (drush site-install)"
echo "=============================================="

# Check if Drupal is already installed
if docker exec "${DRUPAL_CONTAINER}" test -f /opt/drupal/web/sites/default/settings.php 2>/dev/null; then
  echo "ℹ️  Site appears to be already installed, skipping installation."
else
  # Fixed: Added working directory parameter (-w /opt/drupal)
  docker exec -w /opt/drupal "${DRUPAL_CONTAINER}" /opt/drupal/vendor/bin/drush site-install standard \
    --db-url="mysql://${DB_USER}:${DB_PASS}@${DB_CONTAINER}:3306/${DB_NAME}" \
    --site-name="${SITE_NAME}" \
    --account-name="${ADMIN_USER}" \
    --account-pass="${ADMIN_PASS}" \
    --locale="${SITE_LANG}" \
    -y

  echo "✅ Drupal installed successfully."
fi

echo ""
echo "=============================================="
echo " ✅ Setup completed!"
echo " Browse to: http://localhost:${DRUPAL_PORT}"
echo " Admin credentials: ${ADMIN_USER} / ${ADMIN_PASS}"
echo "=============================================="