#!/bin/bash

# Obtain or generate unique id for data provider.
ID_DIRECTORY=/run/provider-id
ID_FILE="${ID_DIRECTORY}/id"
if ! [ -d "${ID_DIRECTORY}" ] ; then
    echo "The directory ${ID_DIRECTORY} which will contain the provider id does not exist"
    exit 1
fi
if ! [ -r "${ID_DIRECTORY}" ] || ! [ -w "${ID_DIRECTORY}" ] || ! [ -x "${ID_DIRECTORY}" ] ; then
    echo "The directory ${ID_DIRECTORY} which will contain the provider id must permit rwx for this user"
    exit 1
fi

if [ -f "${ID_FILE}" ] ; then
    ID=$(cat "${ID_FILE}")
    echo -e "\e[1mFound provider id ${ID} in ${ID_FILE}\e[0m"
else
    echo "Did not find provider id; generating a new one into ${ID_FILE}"
    uuid > "${ID_FILE}"
    ID=$(cat "${ID_FILE}")
    echo -e "Generated provider id \e[31m${ID}\e[0m into ${ID_FILE}"
    echo -e "\e[1mPlease make a backup of that id\e[0m"
    echo -e "\e[1mThe id is available as ./provider-id/id in the compose project directory\e[0m"
fi

# Run data exchange client with provider id and database access
# variables.
export DATABASE_PASSWORD=$(cat /run/secrets/database-password)
PROVIDER_ID=${ID}               \
DATABASE_HOST=${TARGET_DB_HOST} \
DATABASE_PORT=${TARGET_DB_PORT} \
DATABASE_USER=${TARGET_DB_USER} \
DATABASE_NAME=${TARGET_DB_DATABASE} \
DATA_EXCHANGE_ENDPOINT=${DATA_EXCHANGE_ENDPOINT} \
  python3 indicate_data_exchange_client/main.py
