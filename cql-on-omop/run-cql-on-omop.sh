#!/bin/bash

set -e

# Prepare commandline arguments related to "source" database
# TODO(moringenj): We could perform these checks in entry.sh so that one would not have to wait for the cron job to run
SOURCE_DB_ARGS=()
if [ -n "${SOURCE_DB_DRIVER}" ] || [ -n "${SOURCE_DB_CONNECTION_STRING}" ] ; then
    if [ -z "${SOURCE_DB_CONNECTION_STRING}" ] ; then
        echo -e "\e[1;31mCannot specify SOURCE_DB_DRIVER without SOURCE_DB_CONNECTION_STRING\e[0m"
        exit 1
    fi
    for name in HOST PORT DATABASE USER SCHEMA ; do
        variable_name="SOURCE_DB_${name}"
        if [ -n "${!variable_name}" ] ; then
            echo -e "\e[1;31mThe environment variables SOURCE_DB_DRIVER and SOURCE_DB_CONNECTION_STRING cannot be specified together with SOURCE_DB_${name}\e[0m"
            exit 1
        fi
    done
    if [ -n "${SOURCE_DB_DRIVER}" ] ; then
        SOURCE_DB_ARGS+=("--driver=${SOURCE_DB_DRIVER}")
    fi
    SOURCE_DB_ARGS+=("--connection-string=${SOURCE_DB_CONNECTION_STRING}")
else
    for name in HOST PORT DATABASE USER SCHEMA ; do
        if [ -v SOURCE_DB_${name} ] ; then
            option_name="${name,,}" # downcase
            variable_name="SOURCE_DB_${name}"
            value="${!variable_name}"
            SOURCE_DB_ARGS+=("--${option_name}=${value}")
        fi
    done
fi

# Operations on target database

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

function query_in_target_db() {
    EXPRESSION="$1"
    sql_in_target_db "${EXPRESSION}" | sed -e 's/^ //'
}

START_MARKER_CONCEPT_ID=2_000_100_091
END_MARKER_CONCEPT_ID=2_000_100_092

function insert_marker() {
    MARKER_CONCEPT_ID="$1"
    if [ -n "$2" ] ; then
        MARKER_TIMESTAMP="$(echo $2 | sed -e 's/T/ /')"
    else
        MARKER_TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
    fi
    MARKER_DATE="$(echo ${MARKER_TIMESTAMP} | cut -f 1 -d ' ')"
    #
    if [ ${MARKER_CONCEPT_ID} == ${START_MARKER_CONCEPT_ID} ] ; then
        MARKER_LABEL="start marker"
    else
        MARKER_LABEL="end marker"
    fi
    echo -e "\e[1mInserting ${MARKER_LABEL} at ${MARKER_TIMESTAMP} into database\e[0m"
    #
    sql_in_target_db \
      "INSERT INTO ${TARGET_DB_SCHEMA}.observation
              (observation_concept_id, observation_type_concept_id, observation_datetime,            observation_date,      person_id)
       VALUES (${MARKER_CONCEPT_ID},   0,                           timestamp '${MARKER_TIMESTAMP}', date '${MARKER_DATE}', 0);" \
      > /dev/null
}

PREVIOUS_RUN_START=$(query_in_target_db \
"SELECT max(observation_datetime) FROM ${TARGET_DB_SCHEMA}.observation
 WHERE observation_concept_id = ${START_MARKER_CONCEPT_ID};")
if [ -n "${PREVIOUS_RUN_START}" ] ; then
    PREVIOUS_RUN_END=$(query_in_target_db \
      "SELECT max(observation_datetime) FROM ${TARGET_DB_SCHEMA}.observation
       WHERE observation_concept_id = ${END_MARKER_CONCEPT_ID}
             AND observation_datetime >= timestamp '${PREVIOUS_RUN_START}';")
    if [ -z "${PREVIOUS_RUN_END}" ] ; then
        echo -e "\e[1;31mEnd marker is missing for previous run\e[0m"
        # Get the start marker of the run before the previous run so
        # that the new run can (re-)compute all observations for the
        # whole period for which observations are missing.
        COMPLETE_RUN_END=$(query_in_target_db \
      "SELECT max(observation_datetime) FROM ${TARGET_DB_SCHEMA}.observation
       WHERE observation_concept_id = ${END_MARKER_CONCEPT_ID};")
        if [ -n "${COMPLETE_RUN_END}" ] ; then
            echo -e "\e[1;31mMost recent complete run ended ${COMPLETE_RUN_END}\e[0m"
            PREVIOUS_RUN_START=$(query_in_target_db \
                                   "SELECT max(observation_datetime) FROM ${TARGET_DB_SCHEMA}.observation
                                    WHERE observation_concept_id = ${START_MARKER_CONCEPT_ID}
                                          AND observation_datetime < timestamp '${COMPLETE_RUN_END}';")
            echo -e "\e[1;31mUsing start marker ${PREVIOUS_RUN_START} (from most recent complete run)\e[0m"
            # Delete all observation produced with the incomplete run,
            # including the start marker of the run.
            echo -e "\e[1;31mDeleting incomplete data (between ${PREVIOUS_RUN_START} and now)\e[0m"
            sql_in_target_db \
              "DELETE FROM ${TARGET_DB_SCHEMA}.observation
               WHERE observation_concept_id != ${END_MARKER_CONCEPT_ID}
                     AND observation_datetime > timestamp '${PREVIOUS_RUN_START}';" \
              > /dev/null
        else
            echo -e "\e[1;31mDeleting incomplete data\e[0m"
            sql_in_target_db \
              "DELETE FROM ${TARGET_DB_SCHEMA}.observation ;" \
              > /dev/null
        fi
    fi
fi

# cql-on-omop execution

if [ -n "${PREVIOUS_RUN_START}" ] ; then
    PREVIOUS_RUN_START_TIMESTAMP="$(echo ${PREVIOUS_RUN_START} | sed -e 's/ /T/')"
else
    PREVIOUS_RUN_START_TIMESTAMP="2026-01-01T00:00:00"
fi
echo "Using previous run start time ${PREVIOUS_RUN_START_TIMESTAMP}"

# The cronjob calls this script daily and we would ideally compute the
# indicators for the 24-hour period of "yesterday 6:00" to "today
# 5:59" and be done. However, for multiple indicators, the result for
# a given 24-hour period depends on data before or even after that
# period. To accommodate such indicators, include data in generous
# window around the 24-hour period of interest.
#TODAY=$(date +'%Y-%m-%dT06:00:00')
THIS_RUN_START=$(date +'%Y-%m-%dT%H:%M:%S')
REVIEW_PERIOD="Interval[@${PREVIOUS_RUN_START_TIMESTAMP}, @${THIS_RUN_START})"
echo "Using review period ${REVIEW_PERIOD}"

insert_marker ${START_MARKER_CONCEPT_ID} ${THIS_RUN_START}

echo -e "\e[1mComputing quality indicators\e[0m"
# TODO(moringenj): should not use --password for target db
CQL_ON_OMOP_DATABASE_PASSWORD=$(cat /run/secrets/source-database-password) \
  java -Xmx24000000000                                                     \
    -jar cql-on-omop-${CQL_ON_OMOP_VERSION}.jar                            \
    batch                                                                  \
    --omop-version=v5.4                                                    \
      "${SOURCE_DB_ARGS[@]}"                                               \
      -I cql/                                                              \
      --context-value "${CQL_CONTEXT}"                                     \
      -D"IndicateQiElements.Review Period=${REVIEW_PERIOD}"                \
      --result-name='Results'                                              \
      --no-print-messages --no-print-errors --print-progress               \
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

if [ $? -eq 0 ] ; then
    # Mark run as successfully completed
    insert_marker ${END_MARKER_CONCEPT_ID}

    # Notify data exchange service
    DATA_EXCHANGE_CONTAINER=data-exchange
    echo -e "\e[1mNotifying data exchange service\e[0m"
    TRIGGER_URL=http://${DATA_EXCHANGE_CONTAINER}:8080/api/trigger
    if ! curl --silent --fail --data-ascii '' "${TRIGGER_URL}" > /dev/null ; then
        echo -e "\e[1;31mData exchange service reported error; see ${DATA_EXCHANGE_CONTAINER} container\e[0m"
    fi
else
    echo -e "\e[31mFailed to compute quality indicators; not notifying data exchange service\e[0m"
fi
