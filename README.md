# TiTaN — پنل مدیریت سرور، کانفیگ و اشتراک

A production-ready, Persian-first (RTL) control panel for managing **Xray/sing-box nodes, users, configurations, subscriptions, domains, traffic and monitoring** — built from scratch, with every button wired to a real backend action.

```
Panel (FastAPI + React)  ──HTTPS/HMAC──▶  Node agent (stdlib Python)  ──▶  Xray · nginx
        │                                        │
        ├── PostgreSQL (or SQLite)                ├── /var/lib/titan   (state, backups)
        ├── background jobs (9)                  └── /var/log/titan   (xray, nginx, agent logs)
        └── /sub/<token> subscriptions
```

* **No mock-ups, no dead buttons.** Every screen reads and writes real data through the API.
* **Two-part architecture:** a main panel service plus an independent agent on each node, authenticated with a per-node token **and** an HMAC signature.
* **Config safety:** generate → validate (`xray -test`) → stage → atomic swap → reload, with automatic rollback to the last working config.
* **Self-healing:** bounded retries with exponential backoff, every attempt written to the audit log — never an infinite loop.

---

> **راهنمای فارسی گام‌به‌گام:** [انتشار روی GitHub و دیپلوی روی Railway](docs/DEPLOY-GITHUB-RAILWAY-FA.md)
> — ساخت ریپو، آپلود کد، دیپلوی کامل روی Railway (دیتابیس، volume، متغیرها، دامنه) و افزودن نود.

## Table of contents

1. [Feature map](#feature-map)
2. [Architecture](#architecture)
3. [Local setup (60 seconds)](#local-setup-60-seconds)
4. [Environment variables](#environment-variables)
5. [Database](#database)
6. [Docker](#docker)
7. [Railway](#railway)
8. [Node deployment](#node-deployment)
9. [Node registration](#node-registration)
10. [Domain setup & SSL](#domain-setup--ssl)
11. [Xray core](#xray-core)
12. [Nginx](#nginx)
13. [Subscriptions](#subscriptions)
14. [Security](#security)
15. [Permissions & roles](#permissions--roles)
16. [Background jobs](#background-jobs)
17. [API](#api)
18. [Frontend](#frontend)
19. [Tests](#tests)
20. [Backup & restore](#backup--restore)
21. [Upgrade](#upgrade)
22. [Troubleshooting](#troubleshooting)
23. [Project layout](#project-layout)

---

## Feature map

| Area | What it does |
| --- | --- |
| **Dashboard** | Active users, online nodes, total traffic, active configs, expired users, active subscriptions, node overview, traffic chart, protocol mix, top users, live system health, recent activity and recent errors — refreshed from real data (SSE + polling). |
| **Users** | Create/edit/delete, quota + expiry, device/IP/request limits, per-user usage series, bulk actions, status control, subscription issuance, UUID rotation, traffic reset, extend. |
| **Configurations** | VLESS · VMess · Trojan · Shadowsocks · Hysteria2 · WireGuard where the architecture permits; transports WS · XHTTP · HTTPUpgrade · TCP · gRPC; TLS/Reality/fingerprint/SNI/ALPN/flow; live preview, share link, QR, per-inbound JSON, apply/regenerate/toggle. |
| **Nodes** | Cards (not tables) with live CPU/RAM/Disk/latency/traffic, filters (online/offline/warning/region/country/provider/latency), sorting, quick actions, health, detail tabs (overview, users, configs, traffic, monitoring, logs, health, settings), one-click **detect** (public IP, country, city, flag, ASN, ISP, latency), deploy wizard with visible stages. |
| **Subscriptions** | Opaque, revocable, rotatable tokens at `/sub/<token>`; base64, Clash, sing-box and CSV outputs; per-user info and usage headers; subscription summary. |
| **Domains** | Independent of nodes: add, normalise, verify, DNS check, SSL check, assign to a node, set default, remove — with real resolver/TLS lookups. |
| **Monitoring** | Per-node CPU/RAM/disk/traffic/latency series, uptime, online users, node logs (node/xray/nginx/agent). |
| **Reports** | Traffic, users, nodes, protocols, performance, expired, usage — date/node/user/protocol filters, CSV **and** JSON export. |
| **Logs & activity** | Structured logs with level/source/node filters + stats, activity feed, audit trail, notification centre (node down/recovered, SSL expiring, high CPU/RAM, quota, expiry, deploy errors). |
| **Settings** | 12 grouped sections (general, security, xray, nginx, nodes, domains, database, monitoring, notifications, api, subscription, system) — every value is stored and applied at runtime. |
| **Admins & API keys** | Admin CRUD, role editor with a live permission catalogue, API keys with scopes that are **enforced** on every request, revocation, expiry. |
| **System** | Version/build info, engine status (xray/nginx/sing-box), scheduler with manual job runs, backups (create/download/restore/delete), installer downloads. |

---

## Architecture

```
titan/
├── backend/          FastAPI · SQLAlchemy 2 (async) · Alembic · APScheduler
│   ├── app/api/v1/   14 routers (auth, users, nodes, configs, …) — thin controllers
│   ├── app/services/ business logic (config engine, nodes, subscriptions, geo, dns…)
│   ├── app/jobs/     the 9 background jobs
│   ├── app/db/       models, session, seed
│   └── migrations/   versioned Alembic revisions
├── frontend/         React 18 + TypeScript + Vite + Tailwind (RTL, fa/en)
├── node-agent/       stdlib-only Python agent + installer + build script
├── nginx/            panel and node server-block templates
├── xray/             config template + systemd units
├── docker/           image entrypoints + healthcheck
├── scripts/          dev / build / backup / restore / upgrade / health / demo
└── docs/             architecture, deployment, security, backup, upgrade, API
```

**Request flow (panel):** `React SPA → /api/v1/* → router → service → SQLAlchemy → PostgreSQL`, with a uniform envelope `{success, data|items, meta}` and errors as `{success:false, error:{code, message, details}}`.

**Panel → node:** `agent_gateway` signs the request (`X-Titan-Signature: t=<unix>,v1=<hmac_sha256(secret, "<ts>.<body>")>`) and sends `X-Titan-Node-Token`. If the node is unreachable the command is **queued** and delivered when the agent polls `/api/v1/agent/commands`.

**Node → panel:** the agent pushes heartbeat/metrics/traffic/events to `/api/v1/agent/*`; per-user counters become `TrafficRecord` rows and update quotas, which drives subscription headers and the expiry job.

More detail: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Local setup (60 seconds)

Requirements: Python 3.11+, Node 18+, and (optionally) PostgreSQL. No Docker, no Redis and no external services are required for a local run — SQLite lives in `./.data`.

```bash
git clone <your-repo> titan && cd titan
cp .env.example .env
./scripts/dev.sh setup     # venv + deps + migrations + seed (roles, regions, settings)
./scripts/dev.sh all       # API on :8081 + vite on :5173
```

Open <http://127.0.0.1:5173> (dev, hot reload) or <http://127.0.0.1:8081> (the built SPA served by the API).

The first owner account comes from `BOOTSTRAP_ADMIN_USERNAME` / `BOOTSTRAP_ADMIN_PASSWORD`. In production, if the password is empty the panel generates a strong one and prints it **once** in the logs; it is never stored in the image and never printed again.

### What "seed" creates

Roles + permission catalogue, 7 regions (Amsterdam, Frankfurt, Singapore, California, Virginia, London, Tokyo), and the 12 settings groups with defaults. Idempotent — safe to re-run.

### Demo dataset (optional, all through the real API)

```bash
./scripts/demo-data.sh --users 8 --nodes 2
```

Creates nodes, users with a spread of quota/expiry states, configurations, and subscriptions. Every row goes through the same validation the UI uses.

---

## Environment variables

The full annotated list lives in [`.env.example`](.env.example). The ones that matter:

| Variable | Default | Meaning |
| --- | --- | --- |
| `ENV` | `production` | `production` \| `development` \| `test` |
| `PORT` | `8081` | HTTP port — Railway/Fly inject it, never hardcode |
| `DATABASE_URL` | SQLite in `./.data` | `postgresql+asyncpg://…` recommended, SQLite supported |
| `PUBLIC_URL` | – | Public panel URL used in share links and installers |
| `APP_SECRET`, `SESSION_SECRET`, `API_KEY_PEPPER`, `NODE_API_SECRET` | generated | Secrets; generated on first boot into `${TITAN_STATE_DIR}/secrets.env` (0600) when unset |
| `TITAN_STATE_DIR` | `./.data/state` | Backups, downloads, engine state — **put this on a volume** |
| `BOOTSTRAP_ADMIN_USERNAME` / `_PASSWORD` | `admin` / generated | First owner account |
| `NODE_AGENT_PORT` | `62050` | Default agent port for new nodes |
| `NODE_HEARTBEAT_TIMEOUT` | `180` | Seconds without a heartbeat → node marked stale/offline |
| `SELF_HEAL_MAX_ATTEMPTS` | `5` | Hard cap on automatic recovery attempts per incident |
| `METRIC_INTERVAL_SECONDS` | `60` | Agent push + health-check cadence |
| `METRIC_RETENTION_DAYS` / `LOG_RETENTION_DAYS` | `14` / `60` | Retention windows enforced by the cleanup job |
| `GEOIP_PROVIDER` | `ipwho` | Swappable geo provider (`mock` for offline runs) |
| `SCHEDULER_ENABLED` | `true` | Turn background jobs off (e.g. during a migration) |

Secrets are **never** committed: `.env`, `secrets.env`, `*.db`, `*.pem` are all git-ignored, and the Docker build never bakes a secret into an image layer.

---

## Database

PostgreSQL is the production target (connection pooling, indexed queries, real migrations); SQLite is fully supported for single-node installs and local development. The engine, pool size and driver come from `DATABASE_URL`.

```bash
cd backend
alembic upgrade head          # migrate (never destructive)
alembic current               # what is applied
alembic downgrade -1          # one step back
alembic revision -m "add x"   # new revision
```

* Migrations create **22 tables**: admins, roles, permissions, users, nodes, node_regions, domains, configurations, subscriptions, traffic_records, node_metrics, health_checks, logs, activities, settings, api_keys, deployments, notifications, node_commands, user_ip_records, backups, plus association tables.
* Hot paths are indexed (traffic `(ts, node_id)`, logs `(level, source)`, metrics `(node_id, ts)`, unique subscription tokens and usernames).
* The initial revision was verified with `upgrade head` → `downgrade base` → `upgrade head` and `alembic check` reports no drift.
* All timestamps are stored timezone-aware (UTC) and rendered in the configured locale/timezone.

See [`docs/BACKUP-RESTORE.md`](docs/BACKUP-RESTORE.md) for dump/restore specifics.

---

## Docker

```bash
cp .env.example .env
docker compose up -d --build           # panel + postgres (+ optional redis)
docker compose logs -f panel
```

* `Dockerfile` — multi-stage: builds the SPA with Node, then runs the API on `python:3.12-slim` as a non-root user with `tini` as PID 1.
* `docker/Dockerfile.node` + `docker/entrypoint-node.sh` — a node image (agent + Xray + nginx) for hosts where you prefer a container over the installer.
* `docker/healthcheck.sh` — probes `/healthz`, `/readyz`, `/version` and the SPA; wired into `HEALTHCHECK` and used by CI.
* `docker-compose.yml` — panel, PostgreSQL 16 with a volume, optional Redis, healthchecks and depends-on ordering.
* Volumes: `/data` (database + state + backups). Nothing important lives inside the container filesystem.

Migrations run automatically on start (set `TITAN_SKIP_MIGRATIONS=1` to opt out).
The node-agent binaries are built inside the image and published to `/downloads` on
boot, so a fresh deployment can provision nodes immediately — no manual build step.

Persian walkthrough: [`docs/DEPLOY-GITHUB-RAILWAY-FA.md`](docs/DEPLOY-GITHUB-RAILWAY-FA.md).

---

## Railway

`railway.json` / `railway.toml` are ready:

1. New project → **Deploy from repo**.
2. Add a **PostgreSQL** plugin; Railway injects `DATABASE_URL`.
3. Set `PUBLIC_URL` to the generated domain (or your custom domain) and `BOOTSTRAP_ADMIN_PASSWORD`.
4. Attach a **volume** mounted at `/data` so `TITAN_STATE_DIR=/data/state` survives redeploys.
5. Deploy. The container listens on `$PORT`, the healthcheck path is `/healthz`, and migrations run before the app starts.

Nodes are separate machines/containers — point them at the Railway URL during installation.

---

## Node deployment

A node is any server with Python 3.9+ (plus its own Xray/nginx). Adding a node in the panel gives you a one-liner:

```bash
curl -fsSL "https://panel.example.com/api/v1/nodes/agent/install.sh" | sudo bash -s -- \
  --panel https://panel.example.com --token node_xxxxxxxx --port 62050 --name "Frankfurt-02"
```

`node-agent/install.sh` is idempotent and does exactly this:

1. ensures `python3`, `curl`, `openssl` (apt/yum/dnf/apk aware) and `ca-certificates`;
2. installs the agent — single-file zipapp from `/downloads/titan-agent-linux-<arch>` (built by `scripts/build.sh`), falling back to the packaged source;
3. installs **Xray** if missing (panel mirror or the official release) and enables its service;
4. writes `/etc/titan/agent.env` (mode `0600`) with the panel URL, node token and the signing secret;
5. installs `titan-agent.service` (systemd) or a supervisor fallback on non-systemd hosts;
6. runs `titan-agent doctor` and prints a report (arch, python, xray, nginx, port, panel reachability).

The same file is served by the panel, so the reviewed source and the deployed script are byte-identical (`provisioning.render_installer`).

**Panel → agent API** (`/agent/v1/*`, token + HMAC): `health`, `info`, `detect`, `metrics`, `traffic`, `logs`, `config/apply`, `core/reload`, `core/action`, `nginx/action`, `token/rotate`, `agent/update`, `power`, `self-heal`, `logs/purge`, `command`.

**Agent → panel API** (`/api/v1/agent/*`): `register`, `heartbeat`, `metrics` (per-user traffic + online IPs), `events`, `commands`, `commands/{id}/result`, `config/request`.

**Auto-detection:** the *Detect* button asks the node to resolve its own public IP and geo facts (country, city, region, flag, ASN, ISP) through the swappable GeoIP provider, measures latency with three TCP handshakes, and reports reachability. Nothing is hardcoded.

Details and hardening: [`docs/NODE-DEPLOYMENT.md`](docs/NODE-DEPLOYMENT.md).

---

## Node registration

1. **Panel → سرورها → افزودن نود.** Pick a region, enter a name; use **تشخیص** to auto-fill the address/geo fields.
2. The panel issues a one-time token, stores only its hash plus a display prefix, and shows the installer command (and an equivalent `docker run`).
3. Run the installer on the node. The agent registers itself (`POST /api/v1/agent/register`), pushes hardware facts, and the node moves through `queued → installing → starting → connecting → ready`.
4. The node card turns **online** on the first heartbeat (≤ `METRIC_INTERVAL_SECONDS`) with live latency, CPU, RAM, disk and traffic.

Token lifecycle: rotate from the node page (`POST /nodes/{id}/rotate-token`) or let the agent rotate itself over the signed channel (`POST /agent/v1/token/rotate`); the old token dies immediately. Revoking a node (`is_enabled=false`) cuts off both directions.

---

## Domain setup & SSL

Domains are first-class rows, independent of nodes, and every action performs a real check:

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"hostname":"cdn.example.com"}' https://panel/api/v1/domains
curl -X POST -H "Authorization: Bearer $TOKEN" https://panel/api/v1/domains/3/verify
```

* Hostnames are normalised (scheme/path/port stripped, lower-cased) and validated — wildcards and malformed names are rejected with a Persian error.
* **DNS check** resolves A/AAAA through the configured resolvers; **SSL check** performs a real TLS handshake and reports the issuer and days-to-expiry.
* Statuses: `pending` → `dns_ok`/`dns_error` → `ssl_valid`/`ssl_expired`/`ssl_error` → `active`.
* Assign a domain to a node (`POST /domains/{id}/assign`), mark a default (`POST /domains/{id}/default`); configs that specify a domain use its hostname as their address/SNI.
* The `domain_check` job re-verifies every 6 hours and raises notifications for failing DNS and certificates expiring within 14 days.

Certificate issuance: use the panel's nginx template with your ACME client of choice (certbot or acme.sh) — see [`docs/DOMAINS-AND-SSL.md`](docs/DOMAINS-AND-SSL.md).

---

## Xray core

* **Protocols:** VLESS, VMess, Trojan, Shadowsocks (Xray engine) and Hysteria2, WireGuard (sing-box engine, when installed).
* **Transports:** WS, XHTTP, HTTPUpgrade, TCP, gRPC. **Security:** none, TLS, Reality. Fingerprint, SNI, host, path, flow (VLESS+TCP+TLS/Reality only), ALPN, Reality keys and `service_name` are all first-class fields — and change dynamically with the selected protocol/transport.
* **Pipeline:** `build → validate → stage → test (-test) → atomic replace → reload`, and on any failure the previous config is restored from `<state>/<engine>/backups/` (last 10 kept per engine).
* **Static pre-flight** (`validate_config`) catches duplicate tags, port collisions on overlapping listen addresses, missing users/UUIDs, TLS without SNI/cert, WS without a path, gRPC without a service name — before anything touches a node.
* Applying a config pushes it to every node that uses it; nodes that are unreachable get a queued command instead of a silent failure.

---

## Nginx

* `nginx/panel.conf` — reverse proxy for the panel (TLS, headers, `/sub/` caching disabled, SSE-friendly).
* `nginx/node.conf.template` — per-node server block for subscription/edge traffic.
* The panel renders a config, runs `nginx -t` on the **staged** file, and only then swaps and reloads; a failing test keeps the running configuration (`system/*nginx*` endpoints expose preview/validate/reload).
* Node-side nginx is managed by the agent (`POST /agent/v1/nginx/action` with `start|stop|restart|reload|test`).

---

## Subscriptions

```
GET /sub/<token>              → base64 list (+ profile-title, subscription-userinfo)
GET /sub/<token>/info         → JSON status, usage, expiry
GET /sub/<token>/links        → plain links
GET /sub/<token>/clash        → Clash YAML
GET /sub/<token>/singbox      → sing-box JSON
GET /sub/<token>/csv          → CSV
```

* Tokens are random, opaque, indexed-unique, and **rotatable** (`POST /users/{id}/subscription/rotate`) or revocable; unknown tokens return `404 subscription_not_found`, disabled users `403 subscription_forbidden` — never a 500.
* Titles and headers are `base64:`-encoded when they contain non-latin text, so emoji/Persian brand names never corrupt the HTTP headers.
* `subscription-userinfo: upload=…; download=…; total=…; expire=…` is emitted for client apps that show quota.

---

## Security

* Argon2/bcrypt(12) password hashing, no plaintext passwords anywhere; API keys are stored as peppered SHA-256 hashes and shown once.
* JWT HS256 access tokens (`iss=titan-panel`, `jti`, short TTL) with an httpOnly session cookie option; account lockout after `LOGIN_MAX_ATTEMPTS`; per-IP and per-account rate limits.
* CSRF protection on cookie-authenticated writes (origin/`sec-fetch-site` validation), strict CSP, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, HSTS when `PUBLIC_URL` is HTTPS.
* RBAC on every route (`require("nodes.create")` …) with a **single permission catalogue** shared by backend and frontend; API keys additionally intersect with their scopes.
* Node channel: per-node token (hashed at rest) **plus** HMAC-SHA256 over `timestamp.body` with a ±300 s window, so a captured request cannot be replayed.
* Input validation on every write path (Pydantic + explicit domain/normalisation checks), output encoding in the SPA, parameterised SQL everywhere (no string SQL).
* Audit trail: every write produces an `Activity` row (actor, IP, entity, severity) and important operations a `Log` row; the first-boot owner password is generated (not defaulted) in production.

Report-worthy detail: [`docs/SECURITY.md`](docs/SECURITY.md).

---

## Permissions & roles

| Role | Scope |
| --- | --- |
| **Owner** | `*` — everything, including admins and destructive system actions |
| **Admin** | Full operational access except API-key/owner-level settings |
| **Operator** | Nodes, configs, users, domains, subscriptions — no admin/settings management |
| **Support** | Read users/subscriptions, extend/reset traffic, no infrastructure access |
| **Viewer** | Read-only across the panel |

Granular permissions (`users.*`, `nodes.read/create/deploy/restart/delete`, `configs.*`, `settings.manage`, `admins.manage`, `logs.read`, …) are enforced server-side; the UI hides what a role cannot do instead of showing failing buttons.

---

## Background jobs

| Job | Interval | Purpose |
| --- | --- | --- |
| `node_health_check` | 60 s | Heartbeat freshness → online/offline/recovered + notifications |
| `node_self_heal` | 2 min | Bounded recovery (max `SELF_HEAL_MAX_ATTEMPTS`, exponential backoff) |
| `metrics_retention` | 30 min | Prunes metrics beyond `METRIC_RETENTION_DAYS` |
| `domain_check` | 30 min | DNS + SSL re-verification, expiry warnings |
| `user_expiry` | 5 min | Flips expired/quota-exhausted users, notifies |
| `edge_traffic_sync` | `TRAFFIC_SYNC_SECONDS` | Reads local Xray stats into the DB |
| `backup_job` | 12 h | Scheduled backup + retention |
| `notification_dispatch` | 2 min | Telegram/webhook delivery (opt-in) |
| `traffic_aggregation` | 10 min | Reconciles user counters with traffic records (idempotent) + caches per-node windows |

Jobs are defensive: an exception is logged, the scheduler keeps running, and every run is visible on the System page with a manual “run now” button.

---

## API

REST under `/api/v1` with a uniform envelope, pagination (`page`, `page_size`, `search`, `sort_by`, `sort_dir`) and standard error objects. Interactive docs: `/docs` (Swagger) and `/redoc`.

```
auth      login · refresh · logout · me · password
users     CRUD · bulk · usage · status · extend · reset-traffic · rotate-uuid · subscription
nodes     CRUD · detect · deploy · action · metrics · health · traffic · logs · configs · rotate-token · installer
configs   options · preview · create · link · qr · inbound · apply · toggle · regenerate
subs      list · summary · token · rotate · toggle · ensure · preview   + public /sub/<token>
domains   CRUD · verify · assign · default
traffic   summary · series
metrics   node series · system health
logs      list · stats · activity · audit · notifications (+ SSE /events/stream)
reports   index · 7 kinds · export (csv/json)
system    info · settings · jobs · engines · nginx preview · backups
admins    CRUD · roles · permissions · api-keys
```

Full reference with request/response examples: [`docs/API.md`](docs/API.md).

---

## Frontend

React 18 + TypeScript + Vite + Tailwind, Persian-first with full RTL and an English mode (`fa`/`en`), numbers and dates configurable.

* **Dark, premium visual language:** deep navy surfaces, thin borders, subtle glass, purple/blue glow, soft shadows, restrained animation.
* **Node cards** follow the reference layout exactly (flag, city, status badge, circular latency gauge, CPU/RAM/Disk bars, traffic, metadata, action row) and stay 3 → 2 → 1 per row on desktop/tablet/mobile with the internal structure untouched.
* **Responsive down to 360 px:** the sidebar becomes a drawer, tables become cards, modals become bottom sheets, forms go single-column — no horizontal overflow, no clipped buttons.
* Loading skeletons, empty states, confirmations and human-readable errors everywhere (no stack traces in the UI).
* `Ctrl/⌘+K` global search across users, nodes, configs, domains and logs.

---

## Tests

```bash
cd backend && ../.venv/bin/python -m pytest        # 120 tests, ~40 s
```

| Suite | Covers |
| --- | --- |
| `test_security.py` (8) | hashing, JWT, HMAC signing/verification, API-key format, password strength, rate limiting, hostname validation |
| `test_api_core.py` (21) | health/ready/version, login/lockout/me, envelope + error shape, dashboard, settings, regions, permissions |
| `test_api_users.py` (14) | user CRUD, validation, quota/status changes, bulk actions, usage series, subscriptions |
| `test_api_nodes_agent.py` (18) | node CRUD, agent register/heartbeat/metrics/commands, HMAC enforcement, deployment stages |
| `test_config_engine.py` (22) | protocol/transport/TLS matrix, link generation, preview, apply/regenerate, rollback, sing-box engine |
| `test_api_network.py` (17) | subscriptions + public `/sub` formats, domains (DNS/SSL/validation), regions, RBAC |
| `test_reports_ops.py` (18) | reports + exports, logs/activity/notifications, backups (create/download/restore/delete), jobs, API-key lifecycle and scopes |
| `test_jobs_background.py` (6) | traffic reconciliation, expiry/quota enforcement, retention pruning, notification dispatch, stale-node detection, bounded self-heal |

Tests run against an isolated temporary SQLite database — they never touch your dev data.

---

## Backup & restore

```bash
./scripts/backup.sh                 # through the API (audited, checksummed)
./scripts/backup.sh --offline       # direct dump, panel may be down
./scripts/restore.sh --latest       # SQLite: atomic swap · PostgreSQL: row merge
```

* The panel keeps 7 scheduled backups plus anything you create manually; download or restore from the System page.
* SQLite backups include the backup's own row, so restoring a snapshot is self-consistent.
* A restore copies the current database aside as `*.pre-restore` and rebuilds the connection pool, so the panel keeps serving without a restart.
* PostgreSQL backups are logical JSON dumps of every table (ids preserved) and restore row-by-row with per-row conflict skipping.

---

## Upgrade

```bash
./scripts/upgrade.sh            # backup → pull → migrate → rebuild → restart
./scripts/upgrade.sh --dry-run
```

Upgrades are versioned and non-destructive: a verified backup is taken first, `alembic upgrade head` runs before the new code starts, the SPA and node agent are rebuilt, and the panel restarts. If a step fails the script stops — the previous version keeps running, and `./scripts/restore.sh --latest` rolls the database back.

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Node stays `offline` | `systemctl status titan-agent`; check `TITAN_PANEL_URL` reachability and that the token matches (`titan-agent doctor`). |
| `401` from the agent | Token rotated or node disabled — re-issue from the node page and re-run the installer (idempotent). |
| Config apply fails | The agent returns the failing `-test` output in the response; the previous config stays live. Inspect `عرض خطا` on the node's config tab or `journalctl -u titan-agent`. |
| 502 from nginx | `nginx -t` fails — the panel never swaps a broken config; check `/system/nginx/preview`. |
| Subscription URL 404 | Token rotated/revoked, or the user is disabled (403). Re-issue from the user page. |
| Migration error on start | The entrypoint refuses to boot with an unknown schema: run `alembic upgrade head` manually or `TITAN_SKIP_MIGRATIONS=1` if you know what you are doing. |
| `frontend/dist` missing | The API serves the SPA only if it exists: `cd frontend && npm install && npm run build`. |
| Database locked (SQLite) | Use PostgreSQL for anything beyond a single-node demo; SQLite is single-writer by design. |

More: [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

---

## Project layout

```
backend/app/
  api/deps.py            auth (cookie/bearer/API key), RBAC, pagination, node auth
  api/v1/*.py            14 routers — thin controllers only
  core/                  config, security, permissions, errors, rate limiting, logging
  db/{models,session,seed}  SQLAlchemy models, async engine, idempotent seed
  jobs/scheduler.py      9 documented background jobs
  services/              config engine, node service, agent gateway, subscriptions,
                         domains/DNS, geo, metrics, nginx, provisioning, backups, audit
  schemas/               Pydantic request/response models (validation lives here)
frontend/src/
  pages/                 18 screens (dashboard, users, configs, nodes, node detail, …)
  components/            ui kit, charts, icons, layout, node cards, modals
  lib/                   api client, types, i18n, formatters, store, hooks
node-agent/titan_agent/  server, supervisor, collector, panel client, executor, CLI
```

---

## Documentation

| Document | Contents |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | components, data flow, config engine internals, failure handling |
| [docs/NODE-DEPLOYMENT.md](docs/NODE-DEPLOYMENT.md) | installer internals, agent API, TLS, troubleshooting on nodes |
| [docs/DOMAINS-AND-SSL.md](docs/DOMAINS-AND-SSL.md) | DNS/SSL checks, certificates, nginx wiring |
| [docs/SECURITY.md](docs/SECURITY.md) | threat model, secrets, RBAC, hardening checklist |
| [docs/BACKUP-RESTORE.md](docs/BACKUP-RESTORE.md) | what is backed up, how to restore, disaster recovery |
| [docs/UPGRADE.md](docs/UPGRADE.md) | safe upgrade procedure and rollback |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | symptom → cause → fix for panel, nodes, Xray, nginx, DB |
| [docs/API.md](docs/API.md) | endpoints, envelopes, pagination, examples |
| [docs/TECH-STACK.md](docs/TECH-STACK.md) | why these technologies, and what was deliberately rejected |
| [docs/DEPLOY-GITHUB-RAILWAY-FA.md](docs/DEPLOY-GITHUB-RAILWAY-FA.md) | **فارسی** — انتشار روی GitHub و دیپلوی گام‌به‌گام روی Railway |

---

## License

Proprietary — all rights reserved (see [`LICENSE`](LICENSE)). Built independently; it shares
no code with any other panel. For a commercial license, or to relicense for an open-source
release (MIT/Apache-2.0), replace `LICENSE` and the note above with the terms you want.
