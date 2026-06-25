# pyMC to openHop migration guide

This guide helps a human operator or an LLM/code agent migrate pyMC-branded deployments, documentation, and code references to the openHop brand without breaking existing Glass data or repeater integrations.

## Scope

Use `openHop` for the public brand and product names:

- `pyMC` -> `openHop`
- `pyMC Glass` -> `openHop Glass`
- `pyMC Repeater` -> `openHop Repeater`
- `pyMC.dev` -> `openHop` or the current openHop project/org name, depending on context

This repository is the Glass management UI/API. Its current GitHub location may still be under `pyMC-dev/pyMC-Glass` until repository ownership and URLs are moved. Do not assume a GitHub remote has already been renamed just because the product brand changed.

## Brand rules

1. Preferred spelling is exactly `openHop`.
2. Product names are title-style after the brand: `openHop Glass`, `openHop Repeater`.
3. Avoid new user-facing `pyMC` text in UI, docs, logs, page titles, installer prompts, generated examples, and release notes.
4. Keep legacy identifiers only when required for compatibility with an existing database, protocol, path, service, package, or deployment.
5. Do not blindly replace every lowercase `pymc` token. Some are stable machine identifiers and may need compatibility handling.

## Current Glass naming state

The intended user-facing identity is:

- App/UI title: `openHop Glass`
- Backend app name: `openHop Glass API`
- Default development admin email: `admin@openhop.glass`
- Docker container prefix: `openhop_glass_`
- Frontend package name: `openhop-glass-frontend`
- Frontend browser title: `openHop Glass`
- Logo assets: `frontend/src/assets/logo/openhop_*`

Known compatibility identifiers that currently remain:

- GitHub repo URL examples may still point at `https://github.com/pyMC-dev/pyMC-Glass.git` until the repo is actually renamed or moved.
- The database name is currently `pymc_glass` in `DATABASE_URL` and production Compose overrides. Keep it unless you also perform and verify a database rename/migration.
- `docker-compose.yml` creates both `pymc_glass` and `openhop_glass` databases to support compatibility during transition, but the backend currently connects to `pymc_glass` by default.
- Existing persisted users, repeaters, certificates, MQTT state, snapshots, and audit records should be preserved during a brand-only migration.

## Migration checklist for humans

### 1. Back up before changing a live deployment

From the Glass host:

```sh
cd /opt/openhop-glass  # or the existing install directory

docker compose ps

docker compose exec postgres pg_dump -U postgres pymc_glass > glass-before-openhop-migration.sql

tar -czf glass-pki-before-openhop-migration.tgz pki
```

If the install directory is still named `/opt/pymc-glass`, it can remain that way for a brand-only update. Rename the directory only during a separate planned maintenance window.

### 2. Update source and configuration

In a source checkout:

```sh
git pull
make init-env        # local/dev only; does not overwrite existing files
make init-prod-env   # production only; does not overwrite existing files
```

Review generated or existing environment files:

```text
.env
.env.production
backend/.env
backend/.env.production
frontend/.env
```

Expected openHop values include:

```text
APP_NAME=openHop Glass API
PKI_CA_COMMON_NAME=openHop Glass Local CA
BOOTSTRAP_SEED_ADMIN_EMAIL=admin@openhop.glass
MQTT_BASE_TOPIC=glass
```

Do not change `DATABASE_URL` from `pymc_glass` to `openhop_glass` unless you intentionally migrate the database and verify the target database contains the same schema/data.

### 3. Start or restart the stack

Development:

```sh
make dev-up
make dev-logs
```

Production:

```sh
make prod-up
make prod-logs
```

Verify health:

```sh
curl -fsS http://localhost:8080/healthz
```

The service name in the health response should identify openHop Glass.

### 4. Verify UI branding

Open the UI:

```text
http://<host>:5173
```

Confirm:

- Browser title says `openHop Glass`.
- Login screen shows openHop branding and the `Glass` product name.
- Authenticated sidebar/header show openHop Glass branding.
- The browser tab favicon is present.
- There is no new user-facing `pyMC` text on primary screens.

### 5. Verify data preservation

After the stack starts, confirm existing operational data is still present:

- repeaters still appear in inventory
- adoption state is unchanged
- recent packets / MQTT telemetry still arrive
- commands and audit events still render
- PKI/certificate paths still exist under `./pki`

If data disappears immediately after a branding update, first check that `DATABASE_URL` still points to the existing database.

## Migration checklist for LLM/code agents

When asked to rebrand pyMC to openHop:

1. Inspect before editing.
   - Read `README.md`, `docker-compose*.yml`, env examples, frontend `index.html`, package manifests, installer scripts, and affected UI components.
   - Search for `pyMC`, `pymc`, `PYMC`, `openHop`, and `openhop`.

2. Classify every match before changing it.
   - User-facing text: usually rename to openHop.
   - Repo URLs: only rename if the repo actually exists at the new URL.
   - Database names: preserve unless doing a database migration.
   - Protocol fields / API contracts / MQTT topics: preserve unless the counterpart implementation has changed.
   - Filesystem paths and service names: preserve unless the deployment plan includes a rename and restart.

3. Avoid destructive migrations.
   - Do not delete volumes.
   - Do not recreate the database.
   - Do not regenerate PKI unless explicitly requested.
   - Do not change existing admin credentials.

4. Prefer compatibility aliases during transition.
   - Support old names long enough for existing installs to upgrade.
   - Keep legacy DB names or create both old/new databases if needed.
   - Document any remaining legacy machine identifiers.

5. Verify with real commands.
   - Build frontend: `npm --prefix frontend run build` or `make frontend-build`.
   - Check backend tests/lint when backend code changes: `make backend-check`.
   - Start/restart the target stack and check `/healthz`.
   - Use a browser or screenshot to verify the UI branding and favicon.

6. Commit only after live/dev-host verification when requested.

## Suggested find commands

Use these to locate brand references:

```sh
git grep -n -E 'pyMC|pymc|PYMC|openHop|openhop'
```

For likely user-facing frontend text:

```sh
git grep -n -E 'pyMC|pymc|openHop|openhop' -- frontend/src frontend/index.html README.md docs scripts
```

For compatibility-sensitive deployment identifiers:

```sh
git grep -n -E 'pymc_glass|openhop_glass|DATABASE_URL|POSTGRES_DB|COMPOSE_PROJECT_NAME|container_name|volume' -- .
```

## Common mappings

| Old | New | Notes |
| --- | --- | --- |
| pyMC | openHop | Public brand text. |
| pyMC Glass | openHop Glass | Product name. |
| pyMC Repeater | openHop Repeater | Product name. |
| pymc_glass | keep for now | Database compatibility identifier unless explicitly migrated. |
| pyMC-dev/pyMC-Glass | keep until repo moves | Do not invent a new remote URL. |
| admin@pymc.glass | admin@openhop.glass | New default seed account; existing accounts are not automatically renamed. |
| pyMC.dev copyright/org text | openHop project/org text | Update only when ownership/legal text is confirmed. |

## Optional database rename plan

A database rename is not required for a brand-only migration. If a future release intentionally moves from `pymc_glass` to `openhop_glass`, do it as a separate migration with downtime:

1. Stop backend/frontend writers.
2. Back up `pymc_glass`.
3. Create or replace `openhop_glass` from the backup.
4. Update `DATABASE_URL` in all env files and Compose overrides.
5. Start the stack and verify schema, users, repeaters, packets, commands, policies, and audit records.
6. Keep the old backup until the new database has run successfully through an upgrade cycle.

Example outline, not a copy/paste production procedure:

```sh
docker compose stop backend frontend

docker compose exec -T postgres pg_dump -U postgres pymc_glass > pymc_glass.sql

docker compose exec -T postgres createdb -U postgres openhop_glass

docker compose exec -T postgres psql -U postgres openhop_glass < pymc_glass.sql

# edit DATABASE_URL to .../openhop_glass only after restore succeeds

docker compose up -d
```

## Rollback

For a brand-only change, rollback is usually a Git/deployment rollback:

```sh
git revert <branding-commit>
docker compose up -d --build
```

For production, restore the pre-migration database dump and PKI archive only if the change included data/schema/PKI modifications. Do not restore data just to roll back UI text.
