#!/bin/bash
# Napi pg_dump backup — cron-ból futtatva a backup konténerben.
# Minden pm_central + pm_tenant_* DB-t ment, gzip-pelve.
set -euo pipefail

BACKUP_DIR="/backups"
RETENTION_DAYS=14
DATE=$(date +%Y-%m-%d_%H-%M)
PGHOST="postgres"
PGUSER="app"

export PGPASSWORD="${POSTGRES_PASSWORD}"

echo "[$(date)] Starting backup..."

# Central DB
pg_dump -h "$PGHOST" -U "$PGUSER" pm_central | gzip > "$BACKUP_DIR/pm_central_$DATE.sql.gz"
echo "  OK pm_central"

# Tenant DB-k — automatikus felderítés
psql -h "$PGHOST" -U "$PGUSER" -d pm_central -t -A -c \
    "SELECT datname FROM pg_database WHERE datname LIKE 'pm_tenant_%'" | \
while read -r db; do
    [ -z "$db" ] && continue
    pg_dump -h "$PGHOST" -U "$PGUSER" "$db" | gzip > "$BACKUP_DIR/${db}_$DATE.sql.gz"
    echo "  OK $db"
done

# Régi backup-ok törlése
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

TOTAL=$(find "$BACKUP_DIR" -name "*_$DATE.sql.gz" | wc -l)
echo "[$(date)] Backup complete: $TOTAL databases backed up"
