#!/bin/bash
# pre-backup.sh
# Automated backup script for Raspberry Pi 5 homelab
# Runs daily at 2:00 AM via cron
# Generates SQL dumps for all databases and sends Telegram notifications
#
# Setup:
#   1. Copy .env.example to .env and fill in your values
#   2. chmod 600 .env
#   3. chmod +x pre-backup.sh
#   4. Add to crontab: 0 2 * * * /srv/backups/pre-backup.sh >> /srv/backups/pre-backup.log 2>&1
 
DATE=$(date +%Y%m%d_%H%M%S)
DUMPS_DIR=/srv/backups/dumps
ERRORS=0
 
# Load sensitive credentials from .env file (not tracked by git)
source /srv/backups/.env
 
echo "=== Starting pre-backup: $DATE ==="
 
# --- TELEGRAM NOTIFICATIONS ---
# Sends a message to the configured Telegram chat
telegram_notify() {
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$1" > /dev/null
}
 
# --- DUMP INTEGRITY VERIFICATION ---
# Checks that the generated .sql file contains real data (COPY or INSERT lines)
# If the file is empty or has no data, it reports an error and sends a Telegram alert
verify_dump() {
  local FILE=$1
  local NAME=$2
  local COUNT=$(grep -c "COPY\|INSERT" $FILE 2>/dev/null || echo 0)
  if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: $NAME dump is empty"
    telegram_notify "❌ ERROR [$NAME] Dump is empty: $(date '+%d/%m/%Y %H:%M')"
    ERRORS=$((ERRORS+1))
  else
    echo "OK: $NAME dump verified ($COUNT data lines)"
  fi
}
 
# Create dumps directory if it doesn't exist
mkdir -p $DUMPS_DIR
 
# --- CLINICA SOLAZ (PostgreSQL 16) ---
echo "Dumping clinica-solaz..."
source /srv/docker/clinica-solaz/.env
docker exec clinica-solaz-db-1 pg_dump -U $POSTGRES_USER $POSTGRES_DB > $DUMPS_DIR/clinica-solaz_$DATE.sql \
  && verify_dump $DUMPS_DIR/clinica-solaz_$DATE.sql "clinica-solaz" \
  || { echo "ERROR: clinica-solaz dump failed"; telegram_notify "❌ ERROR [clinica-solaz] Dump failed: $(date '+%d/%m/%Y %H:%M')"; ERRORS=$((ERRORS+1)); }
 
# --- BOMBAS IOT (PostgreSQL 16 Alpine) ---
echo "Dumping bombas-iot..."
source /srv/docker/bombas-iot/.env
docker exec bombas-iot-db pg_dump -U $POSTGRES_USER $POSTGRES_DB > $DUMPS_DIR/bombas-iot_$DATE.sql \
  && verify_dump $DUMPS_DIR/bombas-iot_$DATE.sql "bombas-iot" \
  || { echo "ERROR: bombas-iot dump failed"; telegram_notify "❌ ERROR [bombas-iot] Dump failed: $(date '+%d/%m/%Y %H:%M')"; ERRORS=$((ERRORS+1)); }
 
# --- WIKIJS (PostgreSQL 15 Alpine) ---
echo "Dumping wikijs..."
source /srv/docker/wikijs/.env
docker exec wikijs_db pg_dump -U $POSTGRES_USER $POSTGRES_DB > $DUMPS_DIR/wikijs_$DATE.sql \
  && verify_dump $DUMPS_DIR/wikijs_$DATE.sql "wikijs" \
  || { echo "ERROR: wikijs dump failed"; telegram_notify "❌ ERROR [wikijs] Dump failed: $(date '+%d/%m/%Y %H:%M')"; ERRORS=$((ERRORS+1)); }
 
# --- NEXTCLOUD (MariaDB 10.6) ---
echo "Dumping nextcloud..."
source /srv/docker/nextcloud/.env
docker exec nextcloud_db mysqldump -u nextcloud -p${MYSQL_PASSWORD} nextcloud > $DUMPS_DIR/nextcloud_$DATE.sql \
  && verify_dump $DUMPS_DIR/nextcloud_$DATE.sql "nextcloud" \
  || { echo "ERROR: nextcloud dump failed"; telegram_notify "❌ ERROR [nextcloud] Dump failed: $(date '+%d/%m/%Y %H:%M')"; ERRORS=$((ERRORS+1)); }
 
# --- CLEANUP ---
# Removes SQL dumps older than 7 days to save disk space
echo "Cleaning up old dumps..."
find $DUMPS_DIR -name "*.sql" -mtime +7 -delete
echo "OK: cleanup completed"
 
# --- FINAL NOTIFICATION ---
if [ $ERRORS -eq 0 ]; then
  telegram_notify "✅ Backup completed successfully: $(date '+%d/%m/%Y %H:%M')"
else
  telegram_notify "⚠️ Backup completed with $ERRORS error(s): $(date '+%d/%m/%Y %H:%M')"
fi
 
echo "=== Pre-backup completed: $(date) ==="