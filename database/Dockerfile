FROM docker.io/postgres:18

COPY sql/* /docker-entrypoint-initdb.d/

ENV POSTGRES_USER=postgres
ENV POSTGRES_DB=ohdsi

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD pg_isready -U $POSTGRES_USER -d $POSTGRES_DB || exit 1
