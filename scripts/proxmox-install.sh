#!/usr/bin/env bash
# openHop Glass - Proxmox LXC Installer
# Creates an LXC container and installs openHop Glass with Docker Compose.
#
# Usage (run on the Proxmox host):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/pyMC-dev/pyMC-Glass/main/scripts/proxmox-install.sh)"
#
# License: MIT
# Source: https://github.com/pyMC-dev/pyMC-Glass

set -euo pipefail

# ── Defaults ───────────────────────────────────────────────────────────────
REPO="https://github.com/pyMC-dev/pyMC-Glass.git"
BRANCH="main"
CT_TEMPLATE="debian-12-standard"
CT_RAM=4096
CT_SWAP=1024
CT_DISK=10
CT_CORES=4
CT_HOSTNAME="openhop-glass"
CT_BRIDGE="vmbr0"
CT_STORAGE="local-lvm"
CT_TEMPLATE_STORAGE="local"
APP_DIR="/opt/openhop-glass"
APP_ADMIN_EMAIL="admin@openhop.glass"
APP_ADMIN_PASSWORD="admin12345678"
APP_FRONTEND_PORT=5173
APP_BACKEND_PORT=8080
# Reused Compose command for predictable invocation in container context.
STACK_COMPOSE_CMD="docker compose --env-file .env.production -f docker-compose.yml -f docker-compose.prod.yml"

# ── Colors ─────────────────────────────────────────────────────────────────
RD="\033[01;31m" GN="\033[1;92m" YW="\033[33m" BL="\033[36m" BLD="\033[1m" CL="\033[m"

msg_info()  { echo -e " ${BL}ℹ${CL}  ${1}"; }
msg_ok()    { echo -e " ${GN}✓${CL}  ${1}"; }
msg_warn()  { echo -e " ${YW}⚠${CL}  ${1}"; }
msg_error() { echo -e " ${RD}✗${CL}  ${1}"; }

header() {
    clear
    echo -e "${BLD}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "           openHop Glass - Proxmox LXC Installer"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${CL}"
}

cleanup() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ] && [ -n "${CTID:-}" ] && pct status "$CTID" &>/dev/null; then
        echo ""
        read -p "  Delete the failed container ${CTID}? [y/N]: " -r
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            pct stop "$CTID" 2>/dev/null || true
            pct destroy "$CTID" 2>/dev/null || true
            msg_ok "Container ${CTID} removed"
        fi
    fi
}
trap cleanup EXIT

container_exec() {
    # Ensure container is running before executing inside it.
    local status
    status=$(pct status "$CTID" 2>/dev/null || true)
    if [[ "$status" != *"status: running" ]]; then
        msg_info "Starting container ${CTID} before running command..."
        if ! pct start "$CTID"; then
            pct status "$CTID"
            msg_error "Failed to start container ${CTID}."
            exit 1
        fi

        local attempt
        for attempt in $(seq 1 45); do
            sleep 1
            status=$(pct status "$CTID" 2>/dev/null || true)
            if [[ "$status" == *"status: running" ]]; then
                break
            fi
        done

        status=$(pct status "$CTID" 2>/dev/null || true)
        if [[ "$status" != *"status: running" ]]; then
            msg_error "Container ${CTID} did not reach running state (status: ${status:-unknown})."
            exit 1
        fi
        msg_ok "Container ${CTID} is running"
    fi

    pct exec "$CTID" -- "$@"
}

container_bash() {
    container_exec bash -c "$1"
}

# ── Preflight checks ───────────────────────────────────────────────────────
header

if ! command -v pct &>/dev/null; then
    msg_error "This script must be run on a Proxmox VE host."
    exit 1
fi

if ! command -v pvesh &>/dev/null; then
    msg_error "pvesh was not found. This script must run from the Proxmox VE shell."
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    msg_error "Please run as root."
    exit 1
fi

msg_ok "Running on Proxmox host as root"

if [ ! -t 0 ]; then
    msg_error "Do not run this installer with: curl ... | bash"
    echo ""
    echo "  Interactive prompts need terminal stdin. Use:"
    echo "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/pyMC-dev/pyMC-Glass/main/scripts/proxmox-install.sh)\""
    exit 1
fi

DEFAULT_CTID=$(pvesh get /cluster/nextid)

# ── Interactive settings ───────────────────────────────────────────────────
echo ""
echo -e "${BLD}Container Settings${CL} (press Enter for defaults):"
echo ""

while true; do
    read -p "  Container ID [${DEFAULT_CTID}]: " -r input
    CTID="${input:-$DEFAULT_CTID}"
    if [[ ! "$CTID" =~ ^[0-9]+$ ]]; then
        msg_warn "Container ID must be a number"
        continue
    fi
    if pct status "$CTID" &>/dev/null; then
        msg_warn "Container ID ${CTID} already exists"
        continue
    fi
    break
done

read -p "  Hostname [${CT_HOSTNAME}]: " -r input; CT_HOSTNAME="${input:-$CT_HOSTNAME}"
read -p "  RAM in MB [${CT_RAM}]: " -r input; CT_RAM="${input:-$CT_RAM}"
read -p "  Disk in GB [${CT_DISK}]: " -r input; CT_DISK="${input:-$CT_DISK}"
read -p "  CPU cores [${CT_CORES}]: " -r input; CT_CORES="${input:-$CT_CORES}"
read -p "  Bridge [${CT_BRIDGE}]: " -r input; CT_BRIDGE="${input:-$CT_BRIDGE}"

AVAILABLE_STORAGES=$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}' || echo "local-lvm")
echo "  Available storages: ${AVAILABLE_STORAGES}"
read -p "  Storage [${CT_STORAGE}]: " -r input; CT_STORAGE="${input:-$CT_STORAGE}"
read -p "  Git branch [${BRANCH}]: " -r input; BRANCH="${input:-$BRANCH}"
read -sp "  Root password [openhop-glass]: " CT_PASSWORD; echo
CT_PASSWORD="${CT_PASSWORD:-openhop-glass}"

# ── Confirmation ───────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}Summary:${CL}"
echo "  CTID: ${CTID}  Host: ${CT_HOSTNAME}  RAM: ${CT_RAM}MB  Disk: ${CT_DISK}GB"
echo "  Cores: ${CT_CORES}  Storage: ${CT_STORAGE}  Bridge: ${CT_BRIDGE}  Branch: ${BRANCH}"
echo "  Mode: privileged (required for Docker Compose in LXC)"
echo "  Tailscale: manual-ready (no auto-install)"

echo ""
read -p "  Proceed? [Y/n]: " -r
[[ "${REPLY:-Y}" =~ ^[Nn]$ ]] && { msg_warn "Aborted"; exit 0; }

# ── Download template ──────────────────────────────────────────────────────
echo ""
msg_info "Downloading Debian 12 template..."
TEMPLATE_FILE=$(pveam available -section system 2>/dev/null | grep "${CT_TEMPLATE}" | sort -t- -k4 -V | tail -1 | awk '{print $2}')
[ -z "$TEMPLATE_FILE" ] && { msg_error "Template not found. Run: pveam update"; exit 1; }

pveam list "$CT_TEMPLATE_STORAGE" 2>/dev/null | grep -q "$TEMPLATE_FILE" || \
    pveam download "$CT_TEMPLATE_STORAGE" "$TEMPLATE_FILE"
msg_ok "Template ready"

# ── Create container ───────────────────────────────────────────────────────
msg_info "Creating LXC container ${CTID}..."
pct create "$CTID" "${CT_TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_FILE}" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_RAM" \
    --swap "$CT_SWAP" \
    --cores "$CT_CORES" \
    --rootfs "${CT_STORAGE}:${CT_DISK}" \
    --net0 "name=eth0,bridge=${CT_BRIDGE},ip=dhcp" \
    --unprivileged 0 \
    --features nesting=1 \
    --onboot 1 \
    --start 0 \
    --password "$CT_PASSWORD" \
    --ostype debian
msg_ok "Container created"

# Docker-in-LXC compatibility knobs. Keep this scoped to the new CT only.
msg_info "Configuring LXC nesting for Docker..."
cat >> "/etc/pve/lxc/${CTID}.conf" <<'EOF'

# Docker support for openHop Glass
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
EOF
msg_ok "LXC Docker compatibility configured"

msg_info "Preconfiguring LXC for manual Tailscale support (if desired)..."
if ! grep -q '^lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' "/etc/pve/lxc/${CTID}.conf"; then
  echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> "/etc/pve/lxc/${CTID}.conf"
fi
if ! grep -q '^lxc.cgroup2.devices.allow: c 10:200 rwm' "/etc/pve/lxc/${CTID}.conf"; then
  echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> "/etc/pve/lxc/${CTID}.conf"
fi
msg_ok "Tailscale support preconfiguration applied"


# ── Start container & wait for network ───────────────────────────────────────
msg_info "Starting container..."
pct start "$CTID"
sleep 3

msg_info "Waiting for container network..."
for _ in $(seq 1 45); do
    if container_exec ping -c1 -W1 8.8.8.8 &>/dev/null; then
        break
    fi
    sleep 2
done

if ! container_exec ping -c1 -W1 8.8.8.8 &>/dev/null; then
    msg_warn "Container did not reach 8.8.8.8 yet; continuing anyway in case DNS/routing is restricted."
else
    msg_ok "Container running with network"
fi

# ── Bootstrap container ────────────────────────────────────────────────────
msg_info "Installing Docker, Compose, git, and supporting packages inside container..."
container_bash "
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get install -y locales ca-certificates curl git make openssl whiptail >/dev/null 2>&1
    sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
    locale-gen >/dev/null 2>&1
    echo 'LANG=en_US.UTF-8' > /etc/default/locale

    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | sh >/dev/null
    fi
    systemctl enable --now docker >/dev/null 2>&1

    # Enable auto-login on console (no password prompt in Proxmox web console).
    mkdir -p /etc/systemd/system/container-getty@1.service.d
    cat > /etc/systemd/system/container-getty@1.service.d/override.conf <<'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
AUTOLOGIN
    systemctl daemon-reload
"
msg_ok "Container packages installed"

msg_info "Cloning openHop Glass (branch: ${BRANCH})..."
container_bash "
    set -euo pipefail
    rm -rf '${APP_DIR}'
    git clone --branch '${BRANCH}' '${REPO}' '${APP_DIR}'
"
msg_ok "Repository cloned"

msg_info "Configuring openHop Glass environment..."
POSTGRES_PASSWORD=$(openssl rand -base64 30 | tr -d '=+/[:space:]' | cut -c1-32)
container_bash "
    set -euo pipefail
    cd '${APP_DIR}'
    make init-prod-env
    printf 'POSTGRES_PASSWORD=%s\n' '${POSTGRES_PASSWORD}' > .env.production
    sed -i 's/^BOOTSTRAP_SEED_ADMIN_EMAIL=.*/BOOTSTRAP_SEED_ADMIN_EMAIL=${APP_ADMIN_EMAIL}/' backend/.env.production
    sed -i 's/^BOOTSTRAP_SEED_ADMIN_PASSWORD=.*/BOOTSTRAP_SEED_ADMIN_PASSWORD=${APP_ADMIN_PASSWORD}/' backend/.env.production
    sed -i 's/^BOOTSTRAP_SEED_ADMIN_ENABLED=.*/BOOTSTRAP_SEED_ADMIN_ENABLED=true/' backend/.env.production
    sed -i 's/^APP_ENV=.*/APP_ENV=production/' backend/.env.production
    cp backend/.env.production backend/.env
"
msg_ok "Environment configured"

msg_info "Installing login banner inside container..."
container_bash "cat > /etc/profile.d/openhop-glass-motd.sh <<'MOTD'
#!/bin/sh
HOSTNAME=\$(hostname)
IP=\$(hostname -I | awk '{print \$1}')
OS=\$(. /etc/os-release && echo \"\$NAME\")
VER=\$(. /etc/os-release && echo \"\$VERSION_ID\")
echo \"\"
echo \"    openHop Glass LXC Container\"
echo \"    🌐  GitHub: https://github.com/pyMC-dev/pyMC-Glass\"
echo \"\"
echo \"    🖥️   OS: \$OS - Version: \$VER\"
echo \"    🏠  Hostname: \$HOSTNAME\"
echo \"    💡  IP Address: \$IP\"
echo \"    🪟  Glass UI: http://\$IP:5173\"
echo \"    🩺  Backend health: http://\$IP:8080/healthz\"
echo \"\"
echo \"    Default login: ${APP_ADMIN_EMAIL} / ${APP_ADMIN_PASSWORD}\"
echo \"    Management: cd ${APP_DIR} && ${STACK_COMPOSE_CMD} ps\"
echo \"    Update: update\"
echo \"\"
MOTD
chmod +x /etc/profile.d/openhop-glass-motd.sh"
msg_ok "Login banner installed"

# Pre-seed branch variables so this heredoc is safe under set -u.
CURRENT_BRANCH=main
CHOSEN_BRANCH=main

msg_info "Installing container update helper and command aliases..."
container_bash "
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/openhop-glass-update <<'UPDATE'
#!/usr/bin/env bash

set -euo pipefail

APP_DIR='/opt/openhop-glass'

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: openHop Glass directory not found at $APP_DIR"
    exit 1
fi

if ! git -C "$APP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Not a git repository at $APP_DIR"
    echo "Run this from inside the container where openHop Glass was installed."
    exit 1
fi

CURRENT_BRANCH="$(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
CHOSEN_BRANCH="${CURRENT_BRANCH}"

if [ -t 0 ]; then
    read -r -p "Current branch is ${CURRENT_BRANCH}. Branch to update [${CURRENT_BRANCH}]: " INPUT_BRANCH || INPUT_BRANCH=""
    CHOSEN_BRANCH="${INPUT_BRANCH:-$CURRENT_BRANCH}"
fi

git -C "$APP_DIR" fetch --all --prune

if git -C "$APP_DIR" show-ref --verify --quiet "refs/heads/${CHOSEN_BRANCH}"; then
    git -C "$APP_DIR" switch "$CHOSEN_BRANCH"
else
    git -C "$APP_DIR" switch -c "$CHOSEN_BRANCH" "origin/$CHOSEN_BRANCH"
fi

git -C "$APP_DIR" pull --ff-only

cd "$APP_DIR"
${STACK_COMPOSE_CMD} down

${STACK_COMPOSE_CMD} up -d --build

echo "Updated ${CHOSEN_BRANCH} and restarted services."
UPDATE
chmod +x /usr/local/bin/openhop-glass-update
ln -sf /usr/local/bin/openhop-glass-update /usr/local/bin/update
cat > /etc/profile.d/openhop-glass-update-alias.sh <<'ALIAS'
alias update='/usr/local/bin/openhop-glass-update'
alias openhop-glass-update='/usr/local/bin/openhop-glass-update'
ALIAS
"
msg_ok "Update helper and aliases installed"

# ── Start openHop Glass ───────────────────────────────────────────────────────
msg_info "Starting openHop Glass production stack (this can take several minutes)..."
container_bash "
    set -euo pipefail
    cd '${APP_DIR}'
    ${STACK_COMPOSE_CMD} up -d --build
"
msg_ok "Docker Compose stack started"

msg_info "Waiting for backend health endpoint..."
for attempt in $(seq 1 90); do
    if container_exec curl -fsS "http://127.0.0.1:${APP_BACKEND_PORT}/healthz" >/dev/null 2>&1; then
        break
    fi

    if (( attempt % 12 == 0 )); then
        msg_info "Still waiting (${attempt}/90), dumping service state and recent logs..."
        container_exec bash -lc "cd '${APP_DIR}' && ${STACK_COMPOSE_CMD} ps"
        container_exec bash -lc "cd '${APP_DIR}' && ${STACK_COMPOSE_CMD} logs --no-color --tail=60 postgres mosquitto backend pki-init"
    fi

    sleep 5
done

if container_exec curl -fsS "http://127.0.0.1:${APP_BACKEND_PORT}/healthz" >/dev/null 2>&1; then
    msg_ok "Backend is healthy"
else
    msg_warn "Backend health endpoint is not ready yet. Check logs with:"
    echo "    pct exec ${CTID} -- bash -lc 'cd ${APP_DIR} && ${STACK_COMPOSE_CMD} logs --tail=200 postgres mosquitto backend pki-init frontend'"
    echo "    pct exec ${CTID} -- bash -lc 'cd ${APP_DIR} && ${STACK_COMPOSE_CMD} ps'"
    echo "    pct exec ${CTID} -- bash -lc 'cd ${APP_DIR} && ${STACK_COMPOSE_CMD} ps --services | xargs -r docker inspect -f '\''name={{.Name}} status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} pid={{.State.Pid}}'\'''"
fi

# ── Get container IP ───────────────────────────────────────────────────────
sleep 2
CT_IP=$(container_exec hostname -I 2>/dev/null | awk '{print $1}')

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}"
echo "═══════════════════════════════════════════════════════════════"
echo "          ✓ openHop Glass Installation Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo -e "${CL}"
echo -e "  Container:       ${GN}${CTID}${CL} (${CT_HOSTNAME})"
echo -e "  IP Address:      ${GN}${CT_IP:-unknown}${CL}"
echo -e "  Glass UI:        ${GN}http://${CT_IP:-<ip>}:${APP_FRONTEND_PORT}${CL}"
echo -e "  Backend health:  ${GN}http://${CT_IP:-<ip>}:${APP_BACKEND_PORT}/healthz${CL}"
echo ""
echo -e "  Default app username:  ${GN}${APP_ADMIN_EMAIL}${CL}"
echo -e "  Default app password:  ${GN}${APP_ADMIN_PASSWORD}${CL}"
echo -e "  Container root login:  ${GN}root${CL} / ${GN}${CT_PASSWORD}${CL}"
echo ""
echo "  Next: open the Glass UI and change the default admin password after login."
echo "  Manage: pct enter ${CTID}, then: cd ${APP_DIR}"
echo "    Logs:   ${STACK_COMPOSE_CMD} logs -f"
echo "  Tailscale: ready-for-manual-install; use: add tailscale in this container when desired"
echo ""
echo "═══════════════════════════════════════════════════════════════"
