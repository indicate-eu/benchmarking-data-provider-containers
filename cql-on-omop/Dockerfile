FROM ghcr.io/umg-minai/cql-on-omop:1.0.0-SNAPSHOT

RUN DEBIAN_FRONTEND=noninteractive apt-get --assume-yes update     \
    && DEBIAN_FRONTEND=noninteractive apt-get --assume-yes install \
         curl postgresql-client                                    \
    && apt-get clean

WORKDIR /app

# CQL libraries

ADD cql/ cql/

# Cron

RUN curl -fsSLO https://github.com/aptible/supercronic/releases/download/v0.2.41/supercronic-linux-amd64 \
    && chmod +x supercronic-linux-amd64
# The download can be slow. Cache the file locally in that case.
# ADD supercronic-linux-amd64 .
# RUN chmod +x supercronic-linux-amd64

ADD --chmod=750 run-cql-on-omop.sh .

CMD ["/app/supercronic-linux-amd64", "-passthrough-logs", "/app/crontab"]
