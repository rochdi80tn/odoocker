#!/bin/bash

# Enforces strict mode
set -euo pipefail

# Function definitions
cleanup() {
  echo "Cleaning up..."
  rm -rf "${WORKING_DIR}"
}

# Constants
readonly BACKUP_DIR="/mnt/backup"
readonly BASE_FILESTORE_PATH="/mnt/filestore"

# Validates input parameters
if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 <database_name>"
  exit 1
fi

readonly DATABASE="$1"
readonly FILESTORE_PATH="${BASE_FILESTORE_PATH}/${DATABASE}"
readonly WORKING_DIR="/tmp/odoo_restore_${DATABASE}_$(date +%Y%m%d%H%M%S)"

# Setup trap for cleaning up on error
trap cleanup ERR

# Export PGPASSWORD for non-interactive postgres operations
export PGPASSWORD="${PASSWORD}"

# Find the most recent backup file
readonly LATEST_BACKUP=$(find "${BACKUP_DIR}" -name "${DATABASE}_*.tar.gz" -print | sort -r | head -1)

if [[ -z "${LATEST_BACKUP}" ]]; then
  echo "No backup found for database ${DATABASE}."
  exit 1
fi

# Prepare working directory
mkdir -p "${WORKING_DIR}"

echo "Restoring from ${LATEST_BACKUP}..."

# Extract backup
tar -xzf "${LATEST_BACKUP}" -C "${WORKING_DIR}"

# Drop the existing database if it exists
echo "Dropping existing database (if it exists)..."
dropdb --if-exists --force -h "${HOST}" -U "${USER}" "${DATABASE}"

# Create the database
echo "Creating the database..."
createdb -h "${HOST}" -U "${USER}" "${DATABASE}"

# Restore database from the sql dump file
echo "Restoring the database..."
pg_restore --exit-on-error --verbose -h "${HOST}" -U "${USER}" -d "${DATABASE}" "${WORKING_DIR}/${DATABASE}.sql"

# Remove existing filestore if it exists
if [[ -d "${FILESTORE_PATH}" ]]; then
  echo "Removing existing filestore..."
  rm -rf "${FILESTORE_PATH}"
fi

# Restore filestore
echo "Restoring the filestore..."
cp -r "${WORKING_DIR}/filestore" "${FILESTORE_PATH}"

# Cleanup after successful execution
cleanup

echo "Restore completed successfully."