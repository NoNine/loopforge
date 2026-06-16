ARG HARNESS_LDAP_IMAGE=osixia/openldap:1.5.0
FROM ${HARNESS_LDAP_IMAGE}

COPY ldap/50-harness-seed.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/50-harness-seed.ldif
