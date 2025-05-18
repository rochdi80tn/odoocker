#------------------------#
#     Odoo Community     #
#------------------------#
ARG ODOO_TAG
FROM odoo:${ODOO_TAG}

# Switch to root user
USER root

# Receive ARGs from docker-compose.yml & convert them into ENVs
ARG ODOO_TAG
ARG ROOT_PATH
ARG LOG_PATH
ARG ENTERPRISE_USER
ARG ENTERPRISE_ACCESS_TOKEN
ARG ENTERPRISE_ADDONS
ARG EXTRA_ADDONS
ARG CUSTOM_ADDONS
ARG GITHUB_USER
ARG GITHUB_ACCESS_TOKEN
ARG THIRD_PARTY_ADDONS
ARG ODOO_RC
ARG USE_REDIS
ARG USE_S3
ARG USE_SENTRY

ENV ODOO_TAG=${ODOO_TAG} \
    LOG_PATH=${LOG_PATH} \
    ENTERPRISE_USER=${ENTERPRISE_USER} \
    ENTERPRISE_ACCESS_TOKEN=${ENTERPRISE_ACCESS_TOKEN} \
    ENTERPRISE_ADDONS=${ENTERPRISE_ADDONS} \
    EXTRA_ADDONS=${EXTRA_ADDONS} \
    CUSTOM_ADDONS=${CUSTOM_ADDONS} \
    GITHUB_USER=${GITHUB_USER} \
    GITHUB_ACCESS_TOKEN=${GITHUB_ACCESS_TOKEN} \
    THIRD_PARTY_ADDONS=${THIRD_PARTY_ADDONS} \
    ODOO_RC=${ODOO_RC} \
    USE_REDIS=${USE_REDIS} \
    USE_S3=${USE_S3} \
    USE_SENTRY=${USE_SENTRY}


#-------------------------------------------------------#
# Create directories for addons and set ownership       #
#-------------------------------------------------------#
RUN mkdir -p ${ENTERPRISE_ADDONS} ${THIRD_PARTY_ADDONS} ${EXTRA_ADDONS} ${CUSTOM_ADDONS} && \
    chown odoo:odoo ${ENTERPRISE_ADDONS} ${THIRD_PARTY_ADDONS} ${EXTRA_ADDONS} ${CUSTOM_ADDONS}

#---------------------#
#       Logging       #
#---------------------#
# Create odoo.log file
RUN touch ${LOG_PATH} && chown odoo:odoo ${LOG_PATH}

#------------------------#
#    APT Dependencies    #
#------------------------#
# Install Odoocker image dependencies
RUN apt-get update && apt-get install -y \
    # `zip` and `unzip` for filestore management
    zip \
    unzip \
    # `git` required packages
    git \
    git-man \
    less \
    libcurl3-gnutls \
    libedit2 \
    liberror-perl \
    libfido2-1 \
    libxmuu1 \
    openssh-client \
    patch \
    xauth \
    # banner display
    figlet \
    # Remove apt lists
    && rm -rf /var/lib/apt/lists/*

#---------------------#
#   PIP Dependecies   #
#---------------------#
# Copy & Install PIP requirements
COPY --chown=odoo:odoo ./odoo/requirements.txt /tmp/requirements.txt

RUN python3 -m pip install -r /tmp/requirements.txt --break-system-packages && \
    rm /tmp/requirements.txt

#--------------------------------------------#
#    Odoo Enterprise + Third Party Addons    #
#--------------------------------------------#
# Create third-party-addons directory and clone them
COPY --chown=odoo:odoo ./odoo/clone-addons.sh /
COPY --chown=odoo:odoo ./odoo/third-party-addons.txt /

#-----------------------#
#       Odoo Conf       #
#-----------------------#
# Copy environment variables & script to generate odoo.conf
COPY --chown=odoo:odoo ./.env /
COPY --chown=odoo:odoo ./odoo/odoo.conf /
COPY --chown=odoo:odoo ./odoo/odoorc.sh /

# Generate odoo.conf
RUN /odoorc.sh && chown odoo:odoo ${ODOO_RC}

# Switch back to odoo user
USER odoo
