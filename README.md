# Medblocks faasd

These are scripts to install medblocks with [openFaaS](https://www.openfaas.com/) using [faasd](https://github.com/openfaas/faasd/)

## 
This distribution is meant to be run on a single server. The `faasd-docker-compose.yml` is tightly integrated with faasd and may not run on a normal docker-compose environment. Use the `docker-compose.yml` file for experimentation using docker. This distribution uses HAPI FHIR for the FHIR Server, EHRbase for the openEHR CDR and NATS for eventing. openFaaS functions can be triggered in response to the events using annotations in the function deployment. See the [NATS connector example](https://github.com/openfaas/nats-connector) for more info.

### Events from HAPI FHIR:
 - 