#!/bin/bash

set -e

while IFS='=' read -r key value || [[ -n $key ]]; do
    # Skip comments and empty lines
    [[ $key =~ ^#.* ]] || [[ -z $key ]] && continue

    # Removing any quotes around the value
    value=${value%\"}
    value=${value#\"}

    # Declare variable
    eval "$key=\"$value\""
done < .env

# Check the USE_REDIS to add base_attachment_object_storage & session_redis to LOAD variable
if [[ $USE_REDIS == "true" ]]; then
    LOAD+=",session_redis"
fi

# Check the USE_REDIS to add attachment_s3 to LOAD variable
if [[ $USE_S3 == "true" ]]; then
    LOAD+=",base_attachment_object_storage"
    LOAD+=",attachment_s3"
fi

# Check the USE_REDIS to add sentry to LOAD variable
if [[ $USE_SENTRY == "true" ]]; then
    LOAD+=",sentry"
fi

case "$1" in
    shell)
        # Starts a shell in the container.
        echo "Starting the ODOO shell..."
        figlet -f big  "ODOO SHELL"
        exec odoo shell
        ;;

    bash | sh)
        # Display a banner
        figlet -f small "ODOO CONTAINER"

        # Display Odoo version
        echo "`odoo --version`\n"

        # Display environment variables
        echo "Environment Variables:"
        env | grep -E "ODOO|DB|USE|APP_ENV" | sed 's/^/    /'

        # Display container details
        echo "Container Details:"
        echo "    Hostname: $(hostname)"
        echo "    Current User: $(whoami)"
        echo "    Working Directory: $(pwd)"

        # Start a shell
        exec $1
        ;;

    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            # Creates new module.
            exec odoo "$@"
        else
            wait-for-psql.py --db_host ${HOST} --db_port ${PORT} --db_user ${USER} --db_password ${PASSWORD} --timeout=30

            figlet -f big  ${APP_ENV}

            if [ ${APP_ENV} = 'fresh' ] || [ ${APP_ENV} = 'restore' ]; then
                # Ideal for a fresh install or restore a production database.
                # echo odoo --config ${ODOO_RC} --database= --init= --update= --load=${LOAD} --log-level=${LOG_LEVEL} --load-language= --workers=0 --limit-time-cpu=3600 --limit-time-real=7200
                echo odoo --config ${ODOO_RC} --database= --init= --update= --load-language= --workers=0 --limit-time-cpu=3600 --limit-time-real=7200
                exec odoo --config ${ODOO_RC} --database= --init= --update= --load-language= --workers=0 --limit-time-cpu=3600 --limit-time-real=7200
            fi

            if [ ${APP_ENV} = 'staging' ] ; then
                echo "Starting the ODOO staging environment..."

                # exec /clone-addons.sh

                # Automagically upgrade all addons and install new ones.
                # echo odoo --config ${ODOO_RC} --database=${DB_NAME} --init=${INIT} --update=all --load=${LOAD} --log-level=${LOG_LEVEL} --load-language=${LOAD_LANGUAGE} --limit-time-cpu=3600 --limit-time-real=7200 --dev=
                echo odoo --config ${ODOO_RC} --database=${DB_NAME} --init=${INIT} --update=all --without-demo=all --workers=0 --limit-time-cpu=3600 --limit-time-real=7200 --dev=
                exec odoo --config ${ODOO_RC} --database=${DB_NAME} --init=${INIT} --update=all --without-demo=all --workers=0 --limit-time-cpu=3600 --limit-time-real=7200 --dev=
            fi

            if [ ${APP_ENV} = 'dev' ] ||  [ ${APP_ENV} = 'local' ] ; then
                # Listens to all .env variables mapped into odoo.conf file.
                # echo odoo --config ${ODOO_RC} --database=${DB_NAME} --init=${INIT} --update=${UPDATE} --load=${LOAD} --workers=${WORKERS} --log-level=${LOG_LEVEL} --dev=${DEV_MODE}
                echo odoo --config ${ODOO_RC} --init=${INIT} --update=${UPDATE} --dev=${DEV_MODE} --load-language=
                exec odoo --config ${ODOO_RC} --init=${INIT} --update=${UPDATE} --dev=${DEV_MODE} --load-language=
            fi

            if [ ${APP_ENV} = 'production' ] ; then
                # Bring up Odoo ready for production.
                # echo odoo --config ${ODOO_RC} --database= --init=${INIT} --update=${UPDATE} --load=${LOAD} --workers=${WORKERS} --log-level=${LOG_LEVEL} --without-demo=${WITHOUT_DEMO} --load-language= --dev=
                # echo odoo --config ${ODOO_RC} --database= --init=${INIT} --update=${UPDATE} --load-language= --dev=
                # exec odoo --config ${ODOO_RC} --database= --init=${INIT} --update=${UPDATE} --load-language= --dev=
                echo odoo --config ${ODOO_RC} --database=${DB_NAME} --init=${INIT} --update=${UPDATE} --load=${LOAD} --workers=${WORKERS} --log-level=${LOG_LEVEL} --load-language= --dev=
                exec odoo --config ${ODOO_RC} --database=${DB_NAME} --init=${INIT} --update=${UPDATE} --load=${LOAD} --workers=${WORKERS} --log-level=${LOG_LEVEL} --load-language= --dev=
            fi


            if [ ${APP_ENV} = 'debug' ] ; then
                # Same as local but you can debug you custom addons with your code editor (VSCode).
                echo debugpy odoo --config ${ODOO_RC}
                exec /usr/bin/python3 -m debugpy --listen ${DEBUG_INTERFACE}:${DEBUG_PORT} ${DEBUG_PATH} --config ${ODOO_RC}
            fi

            if [ ${APP_ENV} = 'testing' ] ; then
                # Initializies a fresh 'test_*' database, installs the addons to test, and runs tests you specify in the test tags.
                # echo odoo --config ${ODOO_RC} --database=test_${DB_NAME} --test-enable --test-tags ${TEST_TAGS} --init=${ADDONS_TO_TEST} --update=${ADDONS_TO_TEST} --load=${LOAD} --log-level=${LOG_LEVEL} --without-demo= --workers=0 --dev= --stop-after-init
                echo odoo --config ${ODOO_RC} --database=test_${DB_NAME} --test-enable --test-tags ${TEST_TAGS} --init=${ADDONS_TO_TEST} --update=${ADDONS_TO_TEST} --without-demo= --workers=0 --dev= --stop-after-init
                exec odoo --config ${ODOO_RC} --database=test_${DB_NAME} --test-enable --test-tags ${TEST_TAGS} --init=${ADDONS_TO_TEST} --update=${ADDONS_TO_TEST} --without-demo= --workers=0 --dev= --stop-after-init
            fi

        fi
        ;;
    -*)

        wait-for-psql.py --db_host ${HOST} --db_port ${PORT} --db_user ${USER} --db_password ${PASSWORD} --timeout=30
        echo odoo --config ${ODOO_RC}
        exec odoo --config ${ODOO_RC}
        ;;
    *)

        echo "$@"
        exec "$@"
esac

exit 1
