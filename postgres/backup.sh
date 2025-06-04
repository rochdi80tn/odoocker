#!/bin/bash


# Load environment variables from .env file
if [ -f "/.env" ]; then
    # export $(grep -v '^#' "/.env" | xargs)
    while IFS='=' read -r key value || [[ -n $key ]]; do
        # Skip comments and empty lines
        [[ $key =~ ^#.* ]] || [[ -z $key ]] && continue

        # Removing any quotes around the value
        value=${value%\"}
        value=${value#\"}

        # Declare variable
        eval "$key=\"$value\""
    done < /.env

else
    echo "Error: .env file not found." >&2
    exit 1
fi


# Parse arguments
INCLUDE_FILESTORE=false
VERBOSE=false
INCLUDE_PLAIN_SQL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--filestore)
      INCLUDE_FILESTORE=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -p|--plain-sql)
      INCLUDE_PLAIN_SQL=true
      shift
      ;;
    -*)
      echo "Invalid option: $1" >&2
      echo "Usage: $0 [-f|--filestore] [-v|--verbose] [-p|--plain-sql] <database_name>" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [-f|--filestore] [-v|--verbose] <database_name>" >&2
    echo " -f, --filestore : include filestore in the backup" >&2
    echo " -v, --verbose   : enable verbose output for pg_dump" >&2
    echo " -p, --plain-sql   : include plain SQL dump in the backup" >&2
    exit 1
fi

DATABASE=$1
BACKUP_DIR="/mnt/backup"
FILESTORE_PATH="/mnt/odoo-data/filestore"
# FILESTORE_PATH="/var/lib/odoo/filestore/$DATABASE"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
WORKING_DIR="/tmp/${BACKUP_NAME}"

BACKUP_NAME="${DATABASE}_${TIMESTAMP}_db"
if [ "$INCLUDE_FILESTORE" = true ]; then
    BACKUP_NAME="${BACKUP_NAME}_filestore"
fi

# Ensure working directory exists
mkdir -p "${WORKING_DIR}"


# Set verbosity flag for pg_dump
if [ "$VERBOSE" = true ]; then
    PGDUMP_VERBOSE="-v"
else
    PGDUMP_VERBOSE=""
fi


# Backup database
echo "Backing up the PostgreSQL database..."
PGPASSWORD=$DB_PASSWORD pg_dump -h $DB_HOST -U $DB_USER -F c -b $PGDUMP_VERBOSE -f "${WORKING_DIR}/${DATABASE}.sql" ${DATABASE} >&2

# Check if the dump was successful
if [ $? -ne 0 ]; then
    echo "Failed to backup the database, exiting." >&2
    exit 2
fi


# Backup plain SQL if -p/--plain-sql is present
if [ "$INCLUDE_PLAIN_SQL" = true ]; then
    echo "Backing up the PostgreSQL database to a plain SQL script..."
    PGPASSWORD=$DB_PASSWORD pg_dump -h $DB_HOST -U $DB_USER -F p -b $PGDUMP_VERBOSE -f "${WORKING_DIR}/dump.sql" ${DATABASE} >&2

    # Check if the plain SQL dump was successful
    if [ $? -ne 0 ]; then
        echo "Failed to backup the database to plain SQL script, exiting." >&2
        exit 3
    fi
else
    echo "Skipping plain SQL dump (use -p to include it)."
fi


# Check if the plain SQL dump was successful
if [ $? -ne 0 ]; then
    echo "Failed to backup the database to plain SQL script, exiting." >&2
    exit 3
fi

# Backup filestore if -f is present
if [ "$INCLUDE_FILESTORE" = true ]; then
    echo "Backing up the filestore..."
    if [ -d "${FILESTORE_PATH}" ]; then
        cp -r "${FILESTORE_PATH}" "${WORKING_DIR}/filestore" >&2
    else
        echo "Filestore directory does not exist, skipping filestore backup." >&2
    fi
else
    echo "Skipping filestore backup (use -f to include it)."
fi


# Compress backup
echo -n "Compressing backup... "
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C "${WORKING_DIR}" . >&2

# Check for successful compression
if [ $? -ne 0 ]; then
    echo "Failed to compress backup, exiting." >&2
    exit 4
fi

# Display full file path and size
BACKUP_FULL_PATH="$(realpath "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz")"
BACKUP_SIZE="$(du -h "${BACKUP_FULL_PATH}" | cut -f1)"
echo " ${BACKUP_FULL_PATH} (${BACKUP_SIZE})"


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