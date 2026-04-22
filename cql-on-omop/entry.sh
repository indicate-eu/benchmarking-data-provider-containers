#!/bin/sh

VERSION=$(java -jar "cql-on-omop-${CQL_ON_OMOP_VERSION}.jar" --version)
/bin/echo -e "\e[36mThis is ${VERSION}\e[0m"
exec /app/supercronic-linux-amd64 -passthrough-logs /app/crontab
