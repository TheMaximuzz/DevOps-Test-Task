#!/bin/bash
set -e
mkdir -p files/tls/postgresql files/tls/openldap

# PostgreSQL
openssl req -new -x509 -days 365 -nodes -text \
  -out files/tls/postgresql/server.crt \
  -keyout files/tls/postgresql/server.key \
  -subj "/CN=postgresql.default.svc.cluster.local"
chmod 600 files/tls/postgresql/server.key

# OpenLDAP
openssl req -new -x509 -days 365 -nodes -text \
  -out files/tls/openldap/ldap.crt \
  -keyout files/tls/openldap/ldap.key \
  -subj "/CN=openldap.default.svc.cluster.local"
chmod 600 files/tls/openldap/ldap.key

echo "Certificates generated."
