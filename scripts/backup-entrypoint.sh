#!/bin/sh
# Backup konténer entrypoint — cron job beállítás + futtatás.
set -eu

# Cron job: minden nap 03:00 UTC
echo "0 3 * * * /bin/sh /backup.sh >> /backups/backup.log 2>&1" | crontab -

echo "[$(date)] Backup cron scheduled (daily 03:00 UTC)"
echo "[$(date)] Running initial backup..."

# Első backup azonnal (induláskor)
/bin/sh /backup.sh >> /backups/backup.log 2>&1 || echo "[$(date)] Initial backup failed (DB may not be ready yet)"

# Cron daemon foreground-ban
exec crond -f -l 2
