#!/usr/bin/env bash
# =============================================================================
# OBTrack — Ubuntu server setup
#
# Installs Python, creates a venv with the dashboard's dependencies, registers
# systemd services for the FreeD bridge and the dashboard, opens the relevant
# UDP/TCP ports, and starts both services.
#
# Tested on Ubuntu 22.04 and 24.04. Run on the gateway machine:
#
#     sudo bash setup_ubuntu.sh
#
# Override defaults inline, e.g.:
#
#     sudo FREED_HOST=192.168.1.50 FREED_PRESET=livefx bash setup_ubuntu.sh
#
# Re-running is safe: services are stopped, files rewritten, services restarted.
# =============================================================================
set -euo pipefail

# -------- Tunables (override via env vars) -----------------------------------
JSON_LISTEN_PORT="${JSON_LISTEN_PORT:-5005}"     # UDP port the iPhone sends to
FREED_HOST="${FREED_HOST:-127.0.0.1}"            # Unreal / LiveFX host
FREED_PORT="${FREED_PORT:-6301}"                 # Unreal / LiveFX FreeD port
FREED_PRESET="${FREED_PRESET:-unreal}"           # unreal | livefx | generic
DASHBOARD_PORT="${DASHBOARD_PORT:-8050}"         # web dashboard TCP port
DASHBOARD_HOST="${DASHBOARD_HOST:-0.0.0.0}"      # bind address
SERVICE_USER="${SERVICE_USER:-$(logname 2>/dev/null || echo "$SUDO_USER")}"

# -------- Sanity -------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: run with sudo (sudo bash setup_ubuntu.sh)" >&2
    exit 1
fi
if [[ -z "${SERVICE_USER:-}" || "$SERVICE_USER" == "root" ]]; then
    SERVICE_USER="obtrack"
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd --system --create-home --shell /usr/sbin/nologin "$SERVICE_USER"
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

echo "──────────────────────────────────────────────────────────"
echo "  OBTrack server setup"
echo "──────────────────────────────────────────────────────────"
echo "  Install dir       : $SCRIPT_DIR"
echo "  Service user      : $SERVICE_USER"
echo "  Bridge listens on : UDP $JSON_LISTEN_PORT (from iPhone)"
echo "  FreeD sent to     : $FREED_HOST:$FREED_PORT  (preset: $FREED_PRESET)"
echo "  Dashboard         : http://$DASHBOARD_HOST:$DASHBOARD_PORT"
echo "──────────────────────────────────────────────────────────"

# -------- 1. APT packages ----------------------------------------------------
echo "[1/6] Installing system packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3 python3-venv python3-pip ufw curl >/dev/null

# -------- 2. Python virtualenv + deps ---------------------------------------
echo "[2/6] Creating Python virtualenv at $VENV_DIR ..."
if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt"
chown -R "$SERVICE_USER":"$SERVICE_USER" "$SCRIPT_DIR"

# -------- 3. Firewall --------------------------------------------------------
echo "[3/6] Configuring firewall (ufw)..."
if ufw status | grep -qi "Status: active"; then
    ufw allow "$JSON_LISTEN_PORT"/udp comment 'OBTrack JSON in'   >/dev/null
    ufw allow "$DASHBOARD_PORT"/tcp comment 'OBTrack dashboard'   >/dev/null
    echo "      → ufw rules added"
else
    echo "      → ufw is inactive; skipping (no rules needed)"
fi

# -------- 4. systemd: FreeD bridge ------------------------------------------
echo "[4/6] Writing systemd unit: obtrack-bridge.service ..."
cat > /etc/systemd/system/obtrack-bridge.service <<EOF
[Unit]
Description=OBTrack FreeD bridge (iPhone JSON → Unreal/LiveFX FreeD)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$VENV_DIR/bin/python $SCRIPT_DIR/freed_bridge.py \\
    --preset $FREED_PRESET \\
    --listen-port $JSON_LISTEN_PORT \\
    --out-host $FREED_HOST \\
    --out-port $FREED_PORT \\
    --forward-port 5006
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# -------- 5. systemd: Dashboard ---------------------------------------------
echo "[5/6] Writing systemd unit: obtrack-dashboard.service ..."
cat > /etc/systemd/system/obtrack-dashboard.service <<EOF
[Unit]
Description=OBTrack live dashboard (Dash/Plotly)
After=network-online.target obtrack-bridge.service
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$VENV_DIR/bin/python $SCRIPT_DIR/dashboard.py \\
    --web-port $DASHBOARD_PORT \\
    --host $DASHBOARD_HOST \\
    --udp-port 5006
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# -------- 6. Enable + start --------------------------------------------------
echo "[6/6] Enabling and (re)starting services ..."
systemctl daemon-reload
systemctl enable --now obtrack-bridge.service
systemctl enable --now obtrack-dashboard.service
systemctl restart obtrack-bridge.service obtrack-dashboard.service

sleep 1
IP_ADDR="$(hostname -I | awk '{print $1}')"

echo ""
echo "──────────────────────────────────────────────────────────"
echo "  ✓ OBTrack is running."
echo "──────────────────────────────────────────────────────────"
echo "  iPhone → point the app at :    $IP_ADDR  port $JSON_LISTEN_PORT"
echo "  Dashboard URL                : http://$IP_ADDR:$DASHBOARD_PORT"
echo "  FreeD output going to        : $FREED_HOST:$FREED_PORT"
echo ""
echo "  Live logs:"
echo "    sudo journalctl -u obtrack-bridge    -f"
echo "    sudo journalctl -u obtrack-dashboard -f"
echo ""
echo "  Restart after editing a setting:"
echo "    sudo systemctl restart obtrack-bridge obtrack-dashboard"
echo ""
echo "  To change FreeD target / preset / ports later, edit:"
echo "    /etc/systemd/system/obtrack-bridge.service"
echo "    /etc/systemd/system/obtrack-dashboard.service"
echo "  then run:  sudo systemctl daemon-reload && sudo systemctl restart obtrack-bridge obtrack-dashboard"
echo "──────────────────────────────────────────────────────────"
