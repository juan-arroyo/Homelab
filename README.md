# homelab

Personal homelab running on a **Raspberry Pi 5** — 25+ Docker containers serving self-hosted services, accessible via subdomain routing through a reverse proxy.

All services run at `*.jmarroyo.es` · Personal site: [jmarroyo.es](https://www.jmarroyo.es)

---

## About

I'm Juan Manuel, a self-taught infrastructure enthusiast from Spain, actively learning DevOps and SysAdmin by doing things for real rather than in sandboxes. Everything in this repo is running live on my home server — not a local dev environment, not a tutorial project.

I built this homelab to understand how production infrastructure actually works — backup pipelines, credential management, monitoring, automated deployments, service recovery. The goal is always to make things work reliably, not just to make them work.

---

## Own projects running here

These are applications I built and deployed myself, not tutorials or forks:

| Project | Stack | Description |
|---|---|---|
| bombas-iot | Django · PostgreSQL · MQTT · Nginx | IoT monitoring system for water pumps. Reads sensor data via MQTT, stores it in PostgreSQL, exposes a Django web interface. Fully containerized with Docker. |
| clinica-solaz | Django · PostgreSQL · Nginx | Clinic management app — patient records and appointments. Fully containerized with Docker. |
| cv-web | Custom | Personal CV — [jmarroyo.es](https://www.jmarroyo.es) |
| django-cicd | Django · GitHub Actions | CI/CD learning project — auto-deploys to the Pi on every push. |

---

## Stack overview

| Category | Technologies |
|---|---|
| Containerization | Docker, Docker Compose |
| Reverse proxy | Nginx Proxy Manager |
| Authentication | Authelia (SSO) |
| Databases | PostgreSQL 16, MariaDB 10.6 |
| Monitoring | Prometheus, Grafana, Node Exporter, Uptime Kuma |
| Networking | WireGuard VPN (wg-easy), Pi-hole (DNS blocker) |
| Messaging | Eclipse Mosquitto (MQTT broker) |
| Backups | cron + pg_dump/mysqldump + Duplicati → Google Drive |
| Notifications | Telegram (backup alerts, uptime alerts, Docker updates) |
| Updates | Watchtower (automatic Docker image updates) |

---

## Running services

| Service | Description | Image |
|---|---|---|
| Nginx Proxy Manager | Reverse proxy + SSL (Let's Encrypt) | `jc21/nginx-proxy-manager` |
| Authelia | SSO + 2FA for protected services | `authelia/authelia` |
| Vaultwarden | Self-hosted password manager (Bitwarden-compatible) | `vaultwarden/server` |
| Nextcloud | Personal cloud storage | `nextcloud:28` |
| Wiki.js | Internal knowledge base | `ghcr.io/requarks/wiki:2` |
| Grafana | Metrics dashboards | `grafana/grafana` |
| Prometheus | Metrics collection | `prom/prometheus` |
| Node Exporter | System metrics | `prom/node-exporter` |
| Uptime Kuma | Uptime monitoring + Telegram alerts | `louislam/uptime-kuma` |
| Homepage | Service dashboard | `ghcr.io/gethomepage/homepage:latest` |
| Pi-hole | DNS-level ad/tracker blocking | `pihole/pihole` |
| Mosquitto | MQTT broker | `eclipse-mosquitto` |
| WireGuard (wg-easy) | VPN server | `ghcr.io/wg-easy/wg-easy:13` |
| Portainer | Docker management UI | `portainer/portainer-ce` |
| Duplicati | Encrypted cloud backups | `lscr.io/linuxserver/duplicati:latest` |
| Watchtower | Automatic container updates | `containrrr/watchtower` |
| Speedtest Tracker | Periodic internet speed logging | `lscr.io/linuxserver/speedtest-tracker:latest` |

---

## Infrastructure design decisions

### Bind mounts over Docker Volumes
All persistent data lives under `/srv/docker/<project>/` as bind mounts. This makes data location explicit and predictable — no hunting through `/var/lib/docker/volumes/` when something breaks. It also simplifies backup targeting significantly.

```
/srv/
├── backups/          ← SQL dumps + backup scripts
├── wireguard/        ← WireGuard config
└── docker/
    ├── bombas-iot/
    │   ├── app/
    │   └── postgres_data/    ← PostgreSQL data
    ├── clinica-solaz/
    │   ├── backend/
    │   ├── postgres_data/
    │   ├── static/
    │   └── media/
    ├── grafana/
    │   ├── grafana_data/
    │   └── prometheus_data/
    ├── nextcloud/
    │   ├── data/
    │   └── db/               ← MariaDB data
    ├── wikijs/
    │   └── db/               ← PostgreSQL data
    └── ...
```

### Credentials management
Every project has its own `.env` file, never tracked by git. Compose files only reference variables (`${POSTGRES_PASSWORD}`), never hardcoded values. The backup script loads its own `.env` (chmod 600) separately from project credentials.

---

## Backup system

Automated daily pipeline — no manual steps required:

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

**Why `pg_dump` and not just copying files:**
PostgreSQL writes data asynchronously — copying raw data files from a running container can produce a corrupt backup. `pg_dump` asks the engine for a consistent snapshot. Same reasoning applies to `mysqldump` for MariaDB.

**Integrity verification:**
After each dump, the script checks for `COPY` or `INSERT` lines in the `.sql` file. An empty or truncated dump triggers an immediate Telegram alert — not discovered the next morning in a log file.

**Retention:** 7 daily · 4 weekly · 12 monthly (Duplicati smart retention)

See [`backups/pre-backup.sh`](backups/pre-backup.sh) for the full script.

---

## Notifications

| System | Trigger | Channel |
|---|---|---|
| `pre-backup.sh` | Dump success / failure / empty file | Telegram |
| Uptime Kuma | Service down / recovered | Telegram |
| Watchtower | Docker image updated | Telegram (via shoutrrr) |
| bombas-iot | Custom IoT business logic alerts | Telegram |

---

## Restoration tested

A full destroy-and-restore cycle was performed on a Django + PostgreSQL project:

1. Inserted real data into the database
2. Ran `pg_dump` → synced to Google Drive via Duplicati
3. `docker compose down -v` + `rm -rf` — project completely gone
4. Restored files from Google Drive with Duplicati
5. `docker compose up --build -d` — containers rebuilt from scratch
6. Restored database from SQL dump
7. ✅ Application running, all data intact

---

## Security

- All public services behind Nginx Proxy Manager with Let's Encrypt SSL
- Homepage dashboard protected by Authelia (SSO)
- WireGuard VPN for secure remote access
- Pi-hole for DNS-level blocking across the local network and VPN tunnel
- Vaultwarden for self-hosted password management
- All credentials in `.env` files, never in version control

---

## License

MIT — feel free to use anything here as reference for your own homelab.
