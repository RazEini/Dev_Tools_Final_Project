#!/bin/bash
# ==============================================================================
# cleanup.sh - Complete cleanup of project resources (containers, volumes, network, images)
# ==============================================================================
set -e

NETWORK_NAME="drupal-net"
DB_CONTAINER="drupal-db"
DRUPAL_CONTAINER="drupal-web"
DB_IMAGE="mysql:latest"
DRUPAL_IMAGE="drupal:latest"
VOLUMES=("db_data" "drupal_modules" "drupal_profiles" "drupal_themes" "drupal_sites")

echo "=============================================="
echo " Cleaning up all project resources"
echo "=============================================="

read -p "⚠️  This action will permanently delete all unbacked data. Continue? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Cancelled."
  exit 0
fi

echo "==> Removing containers..."
docker rm -f "${DRUPAL_CONTAINER}" >/dev/null 2>&1 && echo "    - ${DRUPAL_CONTAINER} removed" || echo "    - ${DRUPAL_CONTAINER} not found"
docker rm -f "${DB_CONTAINER}" >/dev/null 2>&1 && echo "    - ${DB_CONTAINER} removed" || echo "    - ${DB_CONTAINER} not found"

echo "==> Removing volumes..."
for vol in "${VOLUMES[@]}"; do
  # Exact names only (the ones setup.sh creates) - no suffix/pattern matching,
  # so volumes that belong to other projects are never removed.
  if docker volume inspect "${vol}" >/dev/null 2>&1; then
    docker volume rm "${vol}" >/dev/null 2>&1 && echo "    - Volume ${vol} removed" || echo "    - Failed to remove volume ${vol}"
  else
    echo "    - Volume ${vol} not found"
  fi
done

echo "==> Removing network..."
docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 && echo "    - Network ${NETWORK_NAME} removed" || echo "    - Network ${NETWORK_NAME} not found"

echo "==> Removing Docker images..."
docker rmi "${DRUPAL_IMAGE}" >/dev/null 2>&1 && echo "    - Image ${DRUPAL_IMAGE} removed" || echo "    - Image ${DRUPAL_IMAGE} not found"
docker rmi "${DB_IMAGE}" >/dev/null 2>&1 && echo "    - Image ${DB_IMAGE} removed" || echo "    - Image ${DB_IMAGE} not found"

echo ""
echo "=============================================="
echo " ✅ Cleanup complete! Environment restored to initial state."
echo "=============================================="
