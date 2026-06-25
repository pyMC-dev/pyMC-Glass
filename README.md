# openHop Glass

openHop Glass is a web management console for openHop Repeater fleets. It provides a control plane for repeater adoption, health monitoring, MQTT telemetry ingest, command dispatch, certificate management, policy distribution, alerting, and encrypted config backups.

The stack is built for self-hosted deployments and runs as Docker Compose services: a FastAPI backend, Vue frontend, Timescale/PostgreSQL database, Mosquitto MQTT broker, and local PKI initializer.

## What it does

- Repeater adoption and inventory
  - discover repeaters from `/inform`
  - approve/reject pending repeaters
  - track firmware, state, location, config hash, certificates, and last inform time

- Live operations dashboard
  - CPU, memory, disk, uptime, radio, counters, airtime, noise floor
  - packet list and packet summaries
  - topology/neighborhood insights
  - MQTT telemetry event stream
  - generic sensor reading display for repeater-provided sensor summaries

- Command and config management
  - queue commands for repeaters through the inform control loop
  - export encrypted config snapshots
  - rotate certificates
  - sync transport keys
  - inspect command results and audit history

- Policy and alert management
  - alert policy templates, assignments, and node groups
  - Repeater Runtime Policy templates
  - visual Repeater policy builder with rules, conditions, actions, and object groups
  - pre-staged policy groups for channel hashes and pubkeys

- Managed MQTT and PKI
  - local CA generation
  - backend MQTT client certificate
  - repeater MQTT client certificate lifecycle
  - Mosquitto mTLS config for the data plane

## Architecture

```text
openHop Repeater(s)
  |  /inform control loop
  v
FastAPI backend  <---->  PostgreSQL / TimescaleDB
  |                         |
  | MQTT mTLS               | stored repeaters, packets,
  v                         | commands, policies, snapshots
Mosquitto broker             |
  ^                         |
  | telemetry/events        |
  +-------------------------+

Vue frontend  --->  FastAPI backend
```

Services:

- `frontend`: Vue 3 + Vite UI. Development uses Vite dev server; production uses nginx serving the built bundle.
- `backend`: FastAPI API and control plane.
- `postgres`: Timescale/PostgreSQL database.
- `mosquitto`: MQTT broker with TLS/mTLS.
- `pki-init`: one-shot service that initializes local PKI material under `./pki`.

## Repository layout

```text
.
├── backend/                  FastAPI backend, contracts, schemas, tests
├── frontend/                 Vue/Vite frontend
├── mosquitto/                Mosquitto broker config
├── scripts/                  installers and release helpers
├── docs/                     implementation handoff notes and design docs
├── docker-compose.yml        local/dev Compose stack
├── docker-compose.prod.yml   production Compose overrides
├── Makefile                  common developer and deployment commands
└── README.md
```

## Requirements

For Docker-based development or production:

- Docker with Compose v2
- GNU Make
- Git

For direct backend/frontend development:

- Python 3.11+
- Node.js 22+
- npm

For Proxmox LXC installation:

- Proxmox VE host
- root shell on the Proxmox node
- working `pct`, `pvesh`, `pveam`, and `pvesm`

## Quick start: local Docker stack

1. Clone the repository.

   ```sh
   git clone https://github.com/pyMC-dev/pyMC-Glass.git openHop-Glass
   cd openHop-Glass
   ```

2. Initialize local environment files.

   ```sh
   make init-env
   ```

3. Start the stack.

   ```sh
   make dev-up
   ```

4. Open the UI.

   ```text
   http://localhost:5173
   ```

5. Check backend health.

   ```text
   http://localhost:8080/healthz
   ```

6. Log in with the seeded development admin account.

   ```text
   Email:    admin@openhop.glass
   Password: admin12345678
   ```

7. View logs or stop the stack.

   ```sh
   make dev-logs
   make dev-down
   ```

The shortcut command below initializes env files and starts the stack:

```sh
make easy-start
```

## Production Docker Compose

1. Create production env files.

   ```sh
   make init-prod-env
   ```

2. Edit production secrets before starting.

   ```text
   .env.production
   backend/.env.production
   ```

   At minimum, change:

   - `POSTGRES_PASSWORD`
   - `BOOTSTRAP_SEED_ADMIN_EMAIL`
   - `BOOTSTRAP_SEED_ADMIN_PASSWORD`
   - any externally reachable host/URL/TLS settings needed for your deployment

3. Start the production stack.

   ```sh
   make prod-up
   ```

4. Open the UI.

   ```text
   http://<host>:5173
   ```

5. View logs or stop the stack.

   ```sh
   make prod-logs
   make prod-down
   ```

Production frontend behavior differs from development: `docker-compose.prod.yml` builds the Vite app and serves the static `dist/` bundle with nginx on port `5173`.

### Docker container timezone

The Compose stack bind-mounts the host `/etc/localtime` into each service so container-level clocks match the host timezone. This is especially important for the frontend container: the development image is based on `node:22-alpine`, where setting `TZ=America/New_York` by itself is not enough because the image does not include the named timezone database.

After changing host timezone settings or updating Compose, recreate the stack and verify each container clock:

```sh
docker compose down
docker compose up -d --build
docker compose exec backend date
docker compose exec frontend date
docker compose exec postgres date
docker compose exec mosquitto date
```

## Proxmox LXC installer

openHop Glass includes an interactive Proxmox installer that creates a Debian 12 LXC container and installs the production Docker Compose stack.

Run from a Proxmox VE root shell:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/pyMC-dev/pyMC-Glass/main/scripts/proxmox-install.sh)"
```

Do not run it as `curl ... | bash`; the installer needs interactive stdin for prompts.

Installer defaults:

- Debian 12 container
- 4096 MB RAM
- 4 CPU cores
- 10 GB disk
- privileged LXC with Docker nesting enabled
- Tailscale device support preconfigured, but Tailscale is not auto-installed

The installer asks for container ID, hostname, RAM, disk, CPU cores, bridge, storage, Git branch, and root password before creating anything.

## Development without Docker containers

Backend:

```sh
make backend-install-dev
make backend-dev
```

Backend tests and lint:

```sh
make backend-test
make backend-lint
make backend-check
```

Frontend:

```sh
make frontend-install
make frontend-dev
make frontend-build
```

The backend dev server listens on `0.0.0.0:8080`. The frontend dev server listens on `0.0.0.0:5173` and proxies API traffic according to `frontend/.env` / Vite config.

## Environment files

Local development templates:

- `.env.example` -> `.env`
- `backend/.env.example` -> `backend/.env`
- `frontend/.env.example` -> `frontend/.env`

Production templates:

- `.env.production.example` -> `.env.production`
- `backend/.env.production.example` -> `backend/.env.production`

Important backend settings:

- `DATABASE_URL`: PostgreSQL connection string.
- `MQTT_BROKER_HOST`, `MQTT_BROKER_PORT`: MQTT broker endpoint.
- `MQTT_TLS_*`: backend MQTT TLS client settings.
- `MQTT_REPEATER_TLS_ENABLED`: controls repeater mTLS expectations.
- `PKI_STATE_DIR`: where CA/client cert material is stored in the backend container.
- `BOOTSTRAP_SEED_ADMIN_*`: initial admin seed account.
- `AUTH_TOKEN_TTL_MINUTES`, `AUTH_TOKEN_BYTES`, `AUTH_PASSWORD_MIN_LENGTH`: auth behavior.
- `CONTRACT_VERSION`: active repeater API contract version.

The seeded admin account is only created when the users table is empty.

## Repeater integration overview

Repeaters communicate with Glass over two paths:

1. Control plane: HTTP `/inform`
   - repeater state and stats
   - certificate renewal responses
   - queued command delivery
   - command result ingestion

2. Data plane: MQTT over TLS/mTLS
   - packet telemetry
   - event telemetry
   - live stream updates in the UI

A repeater usually starts as `pending_adoption` after its first `/inform`. Once approved in Glass, it can receive commands and managed MQTT/certificate settings.

Current `/inform` contract support includes:

- system stats
- radio stats
- packet counters
- settings/config hash
- command results
- optional `sensors` summaries for UPS/battery/environment sensor data

## Runtime policy workflow

Glass can build and store Repeater Runtime Policy templates. A policy contains:

- `enabled`
- `default_action`
- `rules`
- `objects`

The visual builder supports rule conditions, actions, and object groups such as:

```json
{
  "objects": {
    "channel_hash_groups": {
      "blocked_channels": ["0x12"]
    },
    "pubkey_groups": {
      "trusted_relays": ["0xaabbccdd"]
    }
  }
}
```

Rules can reference those groups with values such as:

```text
@channel_hash_groups.blocked_channels
```

Repeater-side implementation notes for policy sync live in:

```text
docs/repeater-policy-sync-implementation.md
```

## Sensor telemetry workflow

Glass is ready to accept repeater sensor summaries in the top-level `/inform` field `sensors`.

Expected shape:

```json
{
  "sensors": {
    "enabled": true,
    "configured": 2,
    "loaded": 2,
    "running": true,
    "readings": [
      {
        "name": "ups-main",
        "type": "waveshare_ups_d",
        "ok": true,
        "timestamp": "2026-06-20T12:00:00Z",
        "data": {
          "battery_percent": 87.5,
          "voltage_v": 4.08,
          "current_ma": 120.0
        }
      }
    ]
  }
}
```

Glass renders unknown sensor data fields generically on the repeater detail page. Repeater-side implementation notes live in:

```text
docs/repeater-sensors-glass-inform-implementation.md
```

## Common commands

```sh
make init-env              # copy local env templates
make easy-start            # initialize and start the local stack
make dev-up                # start local Docker stack
make dev-logs              # follow local stack logs
make dev-down              # stop local stack

make init-prod-env         # copy production env templates
make prod-up               # start production Docker stack
make prod-logs             # follow production logs
make prod-down             # stop production stack

make backend-install-dev   # create backend venv and install dev deps
make backend-dev           # run backend via uvicorn reload
make backend-test          # run backend tests
make backend-lint          # run ruff
make backend-check         # lint + tests

make frontend-install      # npm install in frontend/
make frontend-dev          # run Vite dev server
make frontend-build        # build frontend dist
```

## Troubleshooting

### UI cannot reach API

- Confirm backend health: `http://localhost:8080/healthz`.
- Check frontend env/proxy settings.
- Check backend container logs: `make dev-logs` or `make prod-logs`.

### Repeater appears connected but no MQTT data arrives

- Confirm the repeater was adopted, not only discovered.
- Confirm managed MQTT settings are enabled in Glass.
- Check Mosquitto logs and TLS certificate paths.
- Verify the repeater is connecting to the same broker host/address covered by the cert/SAN expectations.
- Inspect backend MQTT ingest logs and `mqtt_ingest_events` before assuming packet parsing is broken.

### Login does not use the default credentials

The seed admin is only created when the user table is empty. If users already exist, change the password through the app/API or reset the database in a development environment.

### Production stack fails on missing secrets

`docker-compose.prod.yml` requires `POSTGRES_PASSWORD` from `.env.production`. Run `make init-prod-env`, edit the generated file, then start again.

## Security notes

- Change all default passwords before production use.
- Treat `./pki`, database volumes, production env files, and encrypted config snapshot keys as sensitive.
- Use HTTPS/reverse proxy controls when exposing the UI outside a trusted LAN/VPN.
- Prefer mTLS for repeater MQTT data-plane traffic.
- Do not commit generated `.env`, `.env.production`, `backend/.env`, `backend/.env.production`, or PKI material.

## Versioning and changelog

The backend and frontend currently track version `1.1.0`.

Changelog helpers:

```sh
make changelog-preview
make changelog
make changelog-unreleased
```

Patch release helper:

```sh
make patch NOTE="short release note"
make patch-dry-run NOTE="short release note"
```

## License

MIT. See the project source for license details.
