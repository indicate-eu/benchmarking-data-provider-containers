#!/bin/bash

if [ -n "${SOURCE_DB_DRIVER}" ] ; then
    SOURCE_DB_DRIVER_ARG="--connection-string ${SOURCE_DB_DRIVER}"
fi
if [ -n "${SOURCE_DB_CONNECTION_STRING}" ] ; then
    SOURCE_DB_CONNECTION_STRING_ARG="--connection-string ${SOURCE_DB_CONNECTION_STRING}"
fi

if [ -n "${TARGET_DB_DRIVER}" ] ; then
    TARGET_DB_DRIVER_ARG="--connection-string ${TARGET_DB_DRIVER}"
fi
if [ -n "${TARGET_DB_CONNECTION_STRING}" ] ; then
    TARGET_DB_CONNECTION_STRING_ARG="--connection-string ${TARGET_DB_CONNECTION_STRING}"
fi

function sql_in_target_db() {
    EXPRESSION="$1"
    #
    PGPASS_FILE="${HOME}/.pgpass"
    touch "${PGPASS_FILE}"
    chmod 600 "${PGPASS_FILE}"
    echo -n "${TARGET_DB_HOST}:${TARGET_DB_PORT}:${TARGET_DB_DATABASE}:${TARGET_DB_USER}:" > "${PGPASS_FILE}"
    cat /run/secrets/target-database-password >> "${PGPASS_FILE}"
    psql -h "${TARGET_DB_HOST}" -p "${TARGET_DB_PORT}" \
         -U "${TARGET_DB_USER}"                        \
         -d "${TARGET_DB_DATABASE}"                    \
         -t -c "${EXPRESSION}"
    rm -f "${PGPASS_FILE}"
}

MARKER_CONCEPT_ID=2_000_000_091

PREVIOUS_RUN=$(sql_in_target_db \
"SELECT max(observation_datetime) FROM ${TARGET_DB_SCHEMA}.observation
 WHERE observation_concept_id = ${MARKER_CONCEPT_ID};")

if [ -n "$(echo ${PREVIOUS_RUN} | sed -e 's/ //')" ] ; then
    PREVIOUS_RUN_TIMESTAMP="@$(echo ${PREVIOUS_RUN} | sed -e 's/ /T/')"
else
    PREVIOUS_RUN_TIMESTAMP="@2026-01-01T00:00:00"
fi
echo "Using previous run time ${PREVIOUS_RUN_TIMESTAMP}"

# The cronjob calls this script daily and we would ideally compute the
# indicators for the 24-hour period of "yesterday 6:00" to "today
# 5:59" and be done. However, for multiple indicators, the result for
# a given 24-hour period depends on data before or even after that
# period. To accommodate such indicators, include data in generous
# window around the 24-hour period of interest.
#TODAY=$(date +'@%Y-%m-%dT06:00:00')
NOW=$(date +'@%Y-%m-%dT%H:%M:%S')
REVIEW_PERIOD="Interval[${PREVIOUS_RUN_TIMESTAMP}, ${NOW})"

# TODO(moringenj): should not use --password for target db
# TODO(moringenj): MIMIC is temporary
CQL_ON_OMOP_DATABASE_PASSWORD=$(cat /run/secrets/source-database-password) \
  java -Xmx24000000000                                                     \
    -jar cql-on-omop-${CQL_ON_OMOP_VERSION}.jar                            \
    batch                                                                  \
    --omop-version=v5.4.MIMIC \
      ${SOURCE_DB_CONNECTION_STRING_ARG}                                   \
      ${SOURCE_DB_DRIVER_ARG}                                              \
      --host="${SOURCE_DB_HOST}"                                           \
      --port="${SOURCE_DB_PORT}"                                           \
      --user="${SOURCE_DB_USER}"                                           \
      --database="${SOURCE_DB_DATABASE}"                                   \
      --schema="${SOURCE_DB_SCHEMA}"                                       \
      -I cql/                                                              \
      --context-value "${CQL_CONTEXT}"                                     \
      -D"IndicateQiElements.Review Period=${REVIEW_PERIOD}"                \
      --result-name='Results'                                              \
      Main                                                                 \
      dbwrite                                                              \
        ${TARGET_DB_CONNECTION_STRING_ARG}                                 \
        ${TARGET_DB_DRIVER_ARG}                                            \
        --host="${TARGET_DB_HOST}"                                         \
        --port="${TARGET_DB_PORT}"                                         \
        --user="${TARGET_DB_USER}"                                         \
        --password="$(cat /run/secrets/target-database-password)"          \
        --database="${TARGET_DB_DATABASE}"                                 \
        --schema="${TARGET_DB_SCHEMA}"                                     \
        --no-print-notes

# Insert marker for this run
sql_in_target_db \
"INSERT INTO ${TARGET_DB_SCHEMA}.observation
        (observation_concept_id, observation_type_concept_id, observation_datetime, observation_date, person_id)
 VALUES (${MARKER_CONCEPT_ID},   0,                           localtimestamp,       current_date,     0);"
