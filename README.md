# Medblocks faasd

These are scripts to install medblocks with [openFaaS](https://www.openfaas.com/) using [faasd](https://github.com/openfaas/faasd/)

This distribution is meant to be run on a single server. The `faasd-docker-compose.yml` is tightly integrated with faasd and may not run on a normal docker-compose environment. Use the `docker-compose.yml` file for experimentation using docker. This distribution uses HAPI FHIR for the FHIR Server, EHRbase for the openEHR CDR and NATS for eventing. openFaaS functions can be triggered in response to the events using annotations in the function deployment. See the [NATS connector example](https://github.com/openfaas/nats-connector) for more info.

## Events from HAPI FHIR:

The `prestorage` events directly correspond to HAPI JPA FHIR server's [STORAGE_PRESTORAGE_RESOURCE_X Pointcut](https://hapifhir.io/hapi-fhir//apidocs/hapi-fhir-base/ca/uhn/fhir/interceptor/api/Pointcut.html#STORAGE_PRESTORAGE_RESOURCE_CREATED).

- fhir.prestorage.created.<resourceType>
- fhir.prestorage.updated.<resourceType>
- fhir.prestorage.deleted.<resourceType>

The `poststorage` events corresponds directly to HAPI JPA FHIR server's [STORAGE_PRECOMMIT_RESOURCE_X Pointcut](https://hapifhir.io/hapi-fhir//apidocs/hapi-fhir-base/ca/uhn/fhir/interceptor/api/Pointcut.html#STORAGE_PRECOMMIT_RESOURCE_CREATED)

- fhir.poststorage.created.<resourceType>
- fhir.poststorage.updated.<resourceType>
- fhir.poststorage.deleted.<resourceType>

For more details on HAPI JPA server pointcuts, reference [this diagram](https://hapifhir.io/hapi-fhir/docs/images/interceptors-server-jpa-pipeline.svg).

## Events from EHRbase:

The events from EHRbase are sourced from the [wal-listner](https://github.com/medblocks/wal-listener) running on the PostgreSQL database. The following are supported by default:

- openehr.template_store.insert
- openehr.template_store.update
- openehr.template_store.delete
- openehr.composition.insert
- openehr.composition.update
- openehr.composition.delete
- openehr.ehr.insert
- openehr.ehr.update
- openehr.ehr.delete
- openehr.folder.insert
- openehr.folder.update
- openehr.folder.delete
- openehr.stored_query.insert
- openehr.stored_query.update
- openehr.stored_query.delete

You can change this by configuring the `database.filter.tables` property in the wal.yml file. If you're using a cloud database, you'll have to enable a [few settings](https://github.com/medblocks/wal-listener#db-setting). Although this is well-supported by most cloud providers like AWS RDS and Azure Database, there are some (DigitalOcean Managed Postgres) that don't support enabling logical replication yet. This is a temporary fix, and will be removed once EHRbase supports eventing natively.

