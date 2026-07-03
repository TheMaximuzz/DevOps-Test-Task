#!/bin/bash
set -euo pipefail
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  "host=$POSTGRES_HOST port=5432 dbname=$POSTGRES_DB user=$POSTGRES_USER sslmode=require" \
  -F c -f "$BACKUP_DIR/postgresql_${TIMESTAMP}.dump"

LDAPTLS_REQCERT=never ldapsearch -x -H "ldaps://$LDAP_HOST:636" \
  -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD" \
  -b "dc=example,dc=org" > "$BACKUP_DIR/openldap_${TIMESTAMP}.ldif"

find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete
echo "Backup completed: $TIMESTAMP"
