## Introduction

This repository contains scripts and data for creating containers that INDICATE data providers can deploy in order to implement the evaluation of quality indicators as well as communication with the central hub for the INDICATE quality benchmarking dashboard.

## Containers

This project creates the following containers:

1. The `database` container contains a PostgreSQL database initialized with OMOP CDM v5.4 tables and a collection of terminology.
   At runtime, the database is used to store the results of evaluating quality indicators.
   The stored results can be used for two purposes:
   1. The data provider can inspect adherence values for the INDICATE quality indicators on a level of individual patients and 24-hour periods.
   2. The stored results are aggregated via views into a hospital-level representation with coarser periods such as weeks.
      This aggregated data is sent (without identifiable information) to the central benchmarking service, also known as INDICATE hub, for distribution to all data providers.

2. The `cql-on-omop` container contains an evaluation engine for CQL libraries.
   This engine applies CQL libraries which implement the INDICATE quality indicators to a database containing clinical data (which is distinct from the database in the `database` container).
   The results computed by the CQL libraries are stored in the `database` container for local inspection, aggregation and distribution as explained above.

3. The `data-exchange` container contains a simple program that uploads aggregated quality indicator results to the INDICATE hub.
   To this end, the program fetches aggregated quality indicator results from the `database` container and uploads them, together with a unique id for the data provider, to the hub node of the INDICATE quality indicator dashboard architecture.

4. The `dashboard` container contains the web-based quality indicator dashboard application that is the main purpose of the whole architecture.
   At the moment, the `dashboard` container communicates with the INDICATE hub to retrieve aggregated quality indicator results from all data providers and present the results in different web-based views.

   Later, the `dashboard` container may be extended to also communicate with the `database` container in order to display patient-level quality indicator results that are specific to the data provider and must not leave the systems of the data provider for privacy and data protection reasons.

## Dependencies

The following software is used by the containers in this compose project.
The list is provided for reference - there is no need to install any software on the host system or within container manually.

* PostgreSQL

* supercronic - A task scheduling engine for containers

  This dependency is downloaded automatically from the GitHub project https://github.com/aptible/supercronic.

* cql-on-omop

  This dependency is obtained automatically from the GitHub Container Registry at https://github.com/umg-minai/cql-on-omop/pkgs/container/cql-on-omop.

* Quality Indicator CQL Libraries

  TODO describe

* INDICATE Data Exchange Client

  This dependency is obtained automatically from the GitHub Container Registry at https://github.com/indicate-eu/benchmarking-data-exchange-client/pkgs/container/benchmarking-data-exchange-client

* INDICATE Dashboard Application

   This dependency is obtained automatically from the GitHub Container Registry at https://github.com/indicate-eu/benchmarking-dashboard/pkgs/container/benchmarking-dashboard

## Configuration and Build

### Set up Database Access

The most important part of the configuration are the options related to accessing the "source" database which contains the clinical data and exists outside of this compose project.

1. Add connection data for the OMOP CDM v5.4-formatted database which provides the clinical data to `source-database.env` in the root directory of this repository.

2. Enter the database password for that database into the file `source-database-password` in the root directory of this repository.
   This option is separate from the remainder of the database configuration so that the password can handle by the "secrets" mechanism of the container runtime.

3. Choose an arbitrary password for the internal database in the `database` container and enter that password into the file `target-database-password` in the root directory of this repository.
   One way to do this is

   ```sh
   echo INDICATE | mkpasswd -m descrypt -s > target-database-password
   ```

### Set up Data Exchange (optional)

If default settings for communication with the INDICATE hub are not appropriate, customize the settings in the `data-exchange.env` in the root directory of this repository.
Concretely, set `DATA_EXCHANGE_ENDPOINT` to the URL under which the data exchange endpoint of the INDICATE Hub can be reached.

### Set a Provider Display Name

Some views of the `dashboard` container display quality indicator results for multiple data providers and highlight the results for the data provider running the dashboard.
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

in the root directory of this repository.
When started for the first time, the `data-exchange` service will generate a data provider-specific unique id which will be used for submitting quality indicator results without identifying information.
A backup of this id should be made immediately since there is no way re-create or restore it if lost.

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
