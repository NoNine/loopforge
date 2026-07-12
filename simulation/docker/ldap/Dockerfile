ARG HARNESS_LDAP_IMAGE=osixia/openldap:1.5.0
FROM ${HARNESS_LDAP_IMAGE}

ARG LOOPFORGE_RESOURCE=docker-simulation
ARG LOOPFORGE_SCHEMA_VERSION=1
ARG LOOPFORGE_PROJECT=unknown
ARG LOOPFORGE_RUN_ID=unknown
ARG LOOPFORGE_SERVICE=unknown
LABEL org.loopforge.resource="${LOOPFORGE_RESOURCE}" \
      org.loopforge.schema-version="${LOOPFORGE_SCHEMA_VERSION}" \
      org.loopforge.project="${LOOPFORGE_PROJECT}" \
      org.loopforge.run-id="${LOOPFORGE_RUN_ID}" \
      org.loopforge.service="${LOOPFORGE_SERVICE}"

COPY ldap/50-harness-seed.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/50-harness-seed.ldif
