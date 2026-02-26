## Introduction

This repository contains scripts and data for creating containers that
INDICATE data providers can deploy in order to implement the
evaluation of quality indicators as well as communication with the
central hub for the INDICATE quality benchmarking dashboard.

## Containers

This project creates the following container images:

1. The `database` container contains a PostgreSQL database initialized with OMOP CDM tables and a collection of terminology.
   At runtime, the database is used to store the results of evaluating quality indicators.
   The stored results can be used for two purposes:
   1. The data provider can inspect conformance to the INDICATE quality indicators on a per-patient level.
   2. The stored results are aggregated via views or stored procedures into a ward-level representation.
      This aggregated data is sent (without identifiable information) to the central benchmarking service for distribution to all data providers.

2. The `cql-on-omop` container contains an evaluation engine for CQL libraries.
   This engine applies CQL libraries which implement the INDICATE quality indicators to a database containing clinical data (which is distinct from the database in the `database` container).
   The results computed by the CQL libraries are stored in the `database` container for local inspection, aggregation and distribution as explained above.

3. The `data-exchange` container contains a simple program that uploads aggregated quality indicator results to the INDICATE central hub..
   To this end, the program fetches aggregated quality indicator results from the `database` container and uploads them, together with a unique id for the data provider, to the hub node of the INDICATE quality indicator dashboard architecture.

4. The `dashboard` container contains the web-based quality indicator dashboard application that is the main purpose of the whole architecture.
   At the moment, the `dashboard` container communicates with the INDICATE central hub to retrieve aggregated quality indicator results from all data providers and present the results in different web-based views.
   Later, the `dashboard` container may be extended to also communicate with the `database` container in order to display patient-level quality indicator results that are specific to the data provider and must also not leave the systems of the data provider for privacy and data protection reasons.

## Dependencies

* PostgreSQL

* https://github.com/umg-minai/cql-on-omop

* https://github.com/aptible/supercronic

* INDICATE CQL Libraries

## Build

### Obtain Dependencies

1. cql-on-omop

   This dependency will be obtained automatically from the GitHub Container Registry at
   https://github.com/umg-minai/cql-on-omop/pkgs/container/cql-on-omop.

2. INDICATE Quality Indicator CQL Libraries

   TODO

3. INDICATE Data Exchange Client

   This dependency will be obtained automatically from the GitHub
   Container Registry at
   https://github.com/umg-minai/indicate-data-exchange-client/pkgs/container/indicate-data-exchange-client.

4. Dashboard

   This dependency will be obtained automatically from the GitHub
   Container Registry at
   https://github.com/umg-minai/indicate-dashboard/pkgs/container/indicate-dashboard.

### Set up Database Access

1. Add connection data for the OMOP database which provides the
   clinical data to `databases.env` in the root directory of this
   repository.

2. Enter the database password for that database into the file
   `source-database-password` in the root directory of this
   repository.

3. Choose an arbitrary password for the internal database in the
   "database" container and enter that password into the file
   `target-database-password` in the root directory of this
   repository. One way to do this is

   ```sh
   echo INDICATE | mkpasswd -m descrypt -s > target-database-password
   ```

### Set up Data Exchange (optional)

If default settings for communication with the INDICATE data exchange
server are not appropriate, customize the settings as described below.

1. TODO DATA_EXCHANGE_ENDPOINT

### Set a Provider Display Name

Some views of the `dashboard` container display quality indicator results for multiple data provider and highlight the results for the data provider running the dashboard.
This works because the data provider (and only the data provider) can recognize its "own" results based on the unique provider id.
This highlighting can be augmented by specifying a human-readable name that should be displayed alongside the highlighted results.
The chosen name, which is an arbitrary string, should be written into the file `provider-id/name` relative to the root directory of this repository.

### Build the Images

Execute

```sh
docker-compose build
```

in the root directory of this repository.

## Usage

### Create and Start

To create and start the containers, run

```sh
docker-compose run -d
```

in the root directory of this repository.  When started for the first
time, the `data-exchange` service will generate a data
provider-specific unique id which will be used for submitting quality
indicator results without identifying information.  A backup of this
id should be made immediately since there is no way re-create or
restore it if lost.

### Stop

To stop the containers, run

```sh
docker-compose stop
```

in the root directory of this repository.

### Start again after stopping

To start the containers again after stopping, run

```sh
docker-compose start
```

in the root directory of this repository.
