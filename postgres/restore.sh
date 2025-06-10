#!/bin/bash

# Enforces strict mode
set -euo pipefail


# Load environment variables from .env file
if [ -f "/.env" ]; then
  set -a
  source <(grep -v '^#' /.env | xargs -d '\n')
  set +a
else
  echo "Error: .env file not found." >&2
  exit 1
fi

# Constants
readonly WORKING_DIR="/tmp/odoo_restore_$$"
readonly LOCAL_BACKUP_DIR="/mnt/backup"
readonly BASE_FILESTORE_PATH="${DATA_DIR}/filestore"


# Setup trap for cleaning up on error
cleanup() {
  echo "Cleaning up..."
  rm -rf "${WORKING_DIR}"
}
trap cleanup ERR


# Parse arguments
VERBOSE=true
RESTORE_FILESTORE=false
RESTORE_DB=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--db)
      RESTORE_DB=true
      shift
      ;;
    -f|--filestore)
      RESTORE_FILESTORE=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -*)
      echo "Invalid option: $1" >&2
      echo "Usage: $0 [-f|--filestore] [-v|--verbose] <database_name>" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [-f|--filestore] [-v|--verbose] <database_name>" >&2
    echo " -f, --filestore : restore filestore in the backup" >&2
    echo " -v, --verbose   : enable verbose output for pg_dump" >&2
    exit 1
fi


# Exit if both RESTORE_DB and INCLUDE_FILESTORE are false
if [[ "${RESTORE_DB}" = false && "${RESTORE_FILESTORE}" = false ]]; then
  echo "Nothing to restore: both database and filestore restore are disabled. Use -d and/or -f." >&2
  exit 1
fi

readonly DATABASE="$1"
if [[ -z "${DATABASE}" ]]; then
  echo "Database name is not provided."
  exit 1
fi
echo "DATABASE ${DATABASE}."

# Allow restore if APP_ENV is not set or is not 'production'
if [[ "${APP_ENV:-}" == "production" ]]; then
  echo "Restore is not allowed in production environment. Exiting."
  exit 1
fi

# Export PGPASSWORD for non-interactive postgres operations
export PGPASSWORD="${DB_PASSWORD}"

# Find the most recent backup file
readonly LATEST_BACKUP=$(find "${LOCAL_BACKUP_DIR}" -name "${DATABASE}_*.tar.gz" -print | sort -r | head -1)


# Prepare working directory
mkdir -p "${WORKING_DIR}"

# Check if the backup file is a valid tar.gz file
if [[ -z "${LATEST_BACKUP}" || ! -f "${LATEST_BACKUP}" || ! "${LATEST_BACKUP}" =~ \.tar\.gz$ ]]; then
  echo "Backup file ${LATEST_BACKUP} is not a valid tar.gz file."
  exit 1
fi

# Extract backup
echo "Extracting ${LATEST_BACKUP}..."
tar -xzf "${LATEST_BACKUP}" -C "${WORKING_DIR}"

if [[ "${RESTORE_DB}" = true ]]; then
  #-----------------------------------------------------------------------------

  if [[ -z "${DB_USER}" || -z "${DB_HOST}" || -z "${DB_PASSWORD}" ]]; then
    echo "Database connection variables are not set properly in the .env file."
    exit 1
  fi
  echo "Restoring database ${DATABASE}..."


  if [[ ! -f "${WORKING_DIR}/${DATABASE}.sql" ]]; then
    echo "SQL dump file ${WORKING_DIR}/${DATABASE}.sql not found in the backup."
    exit 1
  fi

  # Drop the existing database if it exists
  # dropdb --if-exists --force -h "${DB_HOST}" -U "${DB_USER}" "${DATABASE}"

  # Create the database
  # createdb -h "${DB_HOST}" -U "${DB_USER}" "${DATABASE}"


  # Terminate all active connections to the target database before dropping
  echo "Terminating all active connections to ${DATABASE}..."
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $POSTGRES_DB -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DATABASE}' AND pid <> pg_backend_pid();"
  if [[ $? -ne 0 ]]; then
    echo "Failed to terminate active connections to the database ${DATABASE}."
    exit 1
  fi

  echo
  echo "Dropping existing databases $DB_TEMPLATE, $DATABASE and user $DB_USER (if exists)..."
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $POSTGRES_DB -c "DROP DATABASE IF EXISTS $DB_TEMPLATE;"
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $POSTGRES_DB -c "DROP DATABASE IF EXISTS $DATABASE;"
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $POSTGRES_DB -c "DROP USER IF EXISTS $DB_USER;"
  echo
  echo "Create the $DB_TEMPLATE database and $DB_USER user..."
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $POSTGRES_DB -c "CREATE DATABASE $DB_TEMPLATE WITH TEMPLATE = template0;"
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $POSTGRES_DB -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $POSTGRES_DB -c "ALTER USER $DB_USER CREATEDB;"
  echo
  echo "Give Odoo user access to copy $DB_TEMPLATE..."
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $POSTGRES_DB -c "GRANT ALL PRIVILEGES ON DATABASE $DB_TEMPLATE TO $DB_USER;"
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $DB_TEMPLATE -c "ALTER DATABASE $DB_TEMPLATE OWNER TO $DB_USER;"
  echo
  echo "Create the $DATABASE database from $DB_TEMPLATE..."
  psql -p $POSTGRES_PORT -U $DB_USER -d $POSTGRES_DB -c "CREATE DATABASE $DATABASE WITH TEMPLATE $DB_TEMPLATE OWNER $DB_USER;"
  psql -p $POSTGRES_PORT -U $DB_USER -d $DATABASE -c "CREATE EXTENSION IF NOT EXISTS unaccent;"
  psql -p $POSTGRES_PORT -U $POSTGRES_MAIN_USER -d $DATABASE -c "ALTER FUNCTION unaccent(text) IMMUTABLE;"
  if [[ $? -ne 0 ]]; then
    echo "Failed to mark the unaccent function as IMMUTABLE."
    exit 1
  fi

  # Set verbosity flag for pg_dump
  if [ "$VERBOSE" = true ]; then
      PGRESTORE_VERBOSE="--verbose"
  else
      PGRESTORE_VERBOSE=""
  fi

  # Restore database from the sql dump file
  echo "Restoring the database, this might take a while depending on the size of the database. Please wait..."
  pg_restore --exit-on-error ${PGRESTORE_VERBOSE} -h "${DB_HOST}" -U "${DB_USER}" -d "${DATABASE}" "${WORKING_DIR}/${DATABASE}.sql"
  #>/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "Failed to restore the database ${DATABASE}."
    exit 1
  fi

fi

if [[ "${RESTORE_FILESTORE}" = true ]]; then
  #-----------------------------------------------------------------------------

  # Check if the filestore directory exists
  if [[ -d "${WORKING_DIR}/filestore/${DATABASE}" ]]; then
    echo "Filestore directory ${WORKING_DIR}/filestore/${DATABASE} is found in the backup."

    # Check if the filestore path is writable
    if [[ ! -w "${BASE_FILESTORE_PATH}" ]]; then
      echo "Filestore path ${BASE_FILESTORE_PATH} is not writable. Please check permissions."
      exit 1
    fi

  fi

  # Restore filestore
  if [[ -d "${WORKING_DIR}/filestore/${DATABASE}" ]]; then
    # Remove existing filestore if it exists
    if [[ -d "${BASE_FILESTORE_PATH}/${DATABASE}" ]]; then
      echo "Removing existing filestore..."
      rm -rf "${BASE_FILESTORE_PATH}/${DATABASE}"
    fi
    echo "Restoring the filestore..."
    cp -r "${WORKING_DIR}/filestore/${DATABASE}" "${BASE_FILESTORE_PATH}"
  else
    echo "No filestore found in backup, skipping filestore restore."
  fi

fi

# Cleanup after successful execution
cleanup

echo "Restore completed successfully."