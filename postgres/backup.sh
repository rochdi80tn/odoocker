#!/bin/bash


# Load environment variables from .env file
if [ -f "/.env" ]; then
    export $(grep -v '^#' "/.env" | xargs)
else
    echo "Error: .env file not found." >&2
    exit 1
fi

# Check if a parameter is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <database_name>" >&2
    exit 1
fi

DATABASE=$1
BACKUP_DIR="${BACKUP_DIR:-/mnt/backup}"  # Default to /mnt/backup if not set in .env
FILESTORE_PATH="/var/lib/odoo/filestore/$DATABASE"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BACKUP_NAME="${DATABASE}_${TIMESTAMP}"
WORKING_DIR="/tmp/${BACKUP_NAME}"

# Ensure working directory exists
mkdir -p "${WORKING_DIR}"

# Backup database
echo "Backing up the PostgreSQL database..."
PGPASSWORD=$DB_PASSWORD pg_dump -h $DB_HOST -U $DB_USER -F c -b -v -f "${WORKING_DIR}/${DATABASE}.sql" ${DATABASE} >&2

# Check if the dump was successful
if [ $? -ne 0 ]; then
    echo "Failed to backup the database, exiting." >&2
    exit 2
fi

echo "Backing up the PostgreSQL database to a plain SQL script..."
PGPASSWORD=$DB_PASSWORD pg_dump -h $DB_HOST -U $DB_USER -F p -b -v -f "${WORKING_DIR}/dump.sql" ${DATABASE} >&2

# Check if the plain SQL dump was successful
if [ $? -ne 0 ]; then
    echo "Failed to backup the database to plain SQL script, exiting." >&2
    exit 3
fi

# Backup filestore
echo "Backing up the filestore..."
if [ -d "${FILESTORE_PATH}" ]; then
    cp -r "${FILESTORE_PATH}" "${WORKING_DIR}/filestore" >&2
else
    echo "Filestore directory does not exist, skipping filestore backup." >&2
fi

# Compress backup
echo "Compressing backup..."
tar -czvf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C "${WORKING_DIR}" . >&2

# Check for successful compression
if [ $? -ne 0 ]; then
    echo "Failed to compress backup, exiting." >&2
    exit 4
fi

# Verify backup integrity
echo "Verifying backup integrity..."
tar -tzf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" > /dev/null

if [ $? -ne 0 ]; then
    echo "Backup file is corrupted, exiting." >&2
    exit 5
fi

# Clean up
echo "Cleaning up..."
rm -rf "${WORKING_DIR}"

echo "Backup completed successfully."