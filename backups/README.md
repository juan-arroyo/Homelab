# Backup system

Automated daily backup pipeline for all databases running in the homelab.

## How it works

```
02:00 AM  cron → pre-backup.sh
              ├── pg_dump   clinica-solaz  → integrity check → /srv/backups/dumps/
              ├── pg_dump   bombas-iot     → integrity check → /srv/backups/dumps/
              ├── pg_dump   wikijs         → integrity check → /srv/backups/dumps/
              ├── mysqldump nextcloud      → integrity check → /srv/backups/dumps/
              ├── auto-cleanup: dumps older than 7 days deleted
              └── Telegram notification (✅ all good / ⚠️ N errors)

02:30 AM  Duplicati → Google Drive (account 1)  AES-256 encrypted
02:30 AM  Duplicati → Google Drive (account 2)  redundant offsite copy
              both upload: /srv/docker + /srv/backups
```

> `cv-web` uses SQLite — no dump needed, Duplicati backs up the `.db` file directly.

## Setup

### 1. Credentials

```bash
cp .env.example .env
# Edit .env with your Telegram bot token and chat ID
chmod 600 .env
```

Each project also needs its own `.env` with database credentials — the script reads them at runtime using `source`.

### 2. Script permissions

```bash
chmod +x pre-backup.sh
```

### 3. Cron

```bash
crontab -e
# Add:
0 2 * * * /srv/backups/pre-backup.sh >> /srv/backups/pre-backup.log 2>&1
```

## Integrity verification

After each dump, the script counts `COPY` or `INSERT` lines in the `.sql` file. If zero are found, the dump is considered empty and a Telegram alert is sent immediately — not discovered later in a log file.

## Restoration

```bash
# PostgreSQL
docker exec -i <container> psql -U <user> <database> < dumps/<file>.sql

# MariaDB
docker exec -i <container> mysql -u <user> -p<password> <database> < dumps/<file>.sql
```

Full restoration procedure (including file recovery via Duplicati) is documented in the main [README](../README.md).
