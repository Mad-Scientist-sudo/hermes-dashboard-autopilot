#!/usr/bin/env bash
# hermes-dashboard-autopilot/install.sh
# Auto-detects host, installs Hermes dashboard as a persistent service,
# and prints the URL + session token at the end. Idempotent.

set -euo pipefail

TOOL_NAME="hermes-dashboard-autopilot"
PORT=9119
LOG_DIR="$HOME/.hermes/logs"
TOKEN_FILE="$HOME/.hermes/dashboard-session-token"
mkdir -p "$LOG_DIR"

echo "hermes-dashboard-autopilot v1.0.0 - auto-detecting environment..."

# === 1. Detect platform ===
OS="unknown"
INIT="none"
FW="none"
case "$(uname -s 2>/dev/null)" in
  Linux)
    OS="linux"
    if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
      INIT="systemd-user"
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
      FW="ufw"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
      FW="firewalld"
    fi
    ;;
  Darwin)
    OS="macos"; INIT="launchd"; FW="pf"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)"; exit 1
    ;;
esac

echo "Detected: OS=$OS  init=$INIT  firewall=$FW"

# === 2. Locate Hermes Python interpreter ===
HERMES_PY=""
CANDIDATES=(
  "$HOME/.hermes/hermes-agent/venv/bin/python"
  "$HOME/.local/bin/hermes"
  "/root/.hermes/hermes-agent/venv/bin/python"
  "/root/.local/bin/hermes"
)
for cand in "${CANDIDATES[@]}"; do
  if [ -x "$cand" ]; then
    if [[ "$cand" == *python ]]; then
      HERMES_PY="$cand"
    else
      HERMES_PY="$(dirname "$cand")/python"
      [ ! -x "$HERMES_PY" ] && HERMES_PY=""
    fi
    break
  fi
done

if [ -z "$HERMES_PY" ] || [ ! -x "$HERMES_PY" ]; then
  echo "ERROR: Could not find a Hermes install. Tried:"
  printf '  %s\n' "${CANDIDATES[@]}"
  exit 1
fi
echo "Hermes Python: $HERMES_PY"

# === 3. Verify dashboard subcommand ===
DASH_HELP_OUT=$("$HERMES_PY" -m hermes_cli.main dashboard --help 2>&1 || true)
if ! echo "$DASH_HELP_OUT" | grep -q -- "--insecure"; then
  echo "ERROR: hermes dashboard does not support --insecure."
  exit 1
fi
DASH_HAS_TUI="0"
echo "$DASH_HELP_OUT" | grep -q -- "--tui" && DASH_HAS_TUI="1"
echo "Dashboard flags: --tui available=$DASH_HAS_TUI"

# === 4. Token ===
if [ ! -s "$TOKEN_FILE" ]; then
  umask 077
  openssl rand -hex 32 > "$TOKEN_FILE"
  echo "Generated new session token"
else
  echo "Using existing session token"
fi
TOKEN=$(cat "$TOKEN_FILE")

# === 5. Stop existing dashboard on the port ===
echo "Stopping any existing dashboard on port ${PORT}..."

# Kill by process name match
for pid in $(pgrep -f "hermes_cli.main dashboard" 2>/dev/null || true); do
  kill "$pid" 2>/dev/null || true
done
sleep 1
for pid in $(pgrep -f "hermes_cli.main dashboard" 2>/dev/null || true); do
  kill -9 "$pid" 2>/dev/null || true
done
sleep 1

# Kill anyone still listening on the port (catches stale processes whose
# command line doesn't match pgrep, e.g. older Hermes versions)
if command -v lsof >/dev/null 2>&1; then
  for pid in $(lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null || true); do
    kill -9 "$pid" 2>/dev/null || true
  done
elif command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}/tcp" 2>/dev/null || true
  sleep 1
fi
sleep 1

# === 6. Firewall ===
case "$FW" in
  ufw)
    if ! ufw status 2>/dev/null | grep -qE "9119/tcp.*ALLOW"; then
      echo "Opening port 9119 in ufw..."
      ufw allow 9119/tcp >/dev/null
    fi
    ;;
  firewalld)
    if ! firewall-cmd --list-ports 2>/dev/null | grep -q "9119/tcp"; then
      echo "Opening port 9119 in firewalld..."
      firewall-cmd --permanent --add-port=9119/tcp >/dev/null
      firewall-cmd --reload >/dev/null
    fi
    ;;
  pf)
    echo "macOS firewall is pf. Allow inbound TCP 9119 in"
    echo "System Settings -> Network -> Firewall if needed."
    ;;
  none)
    echo "No local firewall tool detected. Check your cloud security"
    echo "group if you cant reach the dashboard from another machine."
    ;;
esac

# === 7. Install service unit ===
if [ "$INIT" = "systemd-user" ]; then
  UNIT_DIR="$HOME/.config/systemd/user"
  UNIT_FILE="$UNIT_DIR/hermes-dashboard.service"
  mkdir -p "$UNIT_DIR"

  ENV_FILE="$HOME/.hermes/dashboard-session-token.env"
  umask 077
  echo "HERMES_DASHBOARD_SESSION_TOKEN="$TOKEN"" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  if [ ! -f "$UNIT_FILE" ] || ! grep -q "ExecStart=" "$UNIT_FILE"; then
    DASH_ARGS="--host 0.0.0.0 --port ${PORT} --insecure --no-open"
    [ "$DASH_HAS_TUI" = "1" ] && DASH_ARGS="$DASH_ARGS --tui"
    cat > "$UNIT_FILE" << UNIT_EOF
[Unit]
Description=Hermes Agent Dashboard (remote)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-%h/.hermes/dashboard-session-token.env
Environment=PYTHONUNBUFFERED=1
ExecStart=${HERMES_PY} -m hermes_cli.main dashboard ${DASH_ARGS}
Restart=on-failure
RestartSec=5
StandardOutput=append:%h/.hermes/logs/dashboard-remote.log
StandardError=append:%h/.hermes/logs/dashboard-remote.log

[Install]
WantedBy=default.target
UNIT_EOF
    systemctl --user daemon-reload
    systemctl --user enable hermes-dashboard.service
    echo "Installed systemd unit"
  fi
  echo "Restarting hermes-dashboard.service..."
  systemctl --user restart hermes-dashboard.service

elif [ "$INIT" = "launchd" ]; then
  PLIST_DIR="$HOME/Library/LaunchAgents"
  PLIST_FILE="$PLIST_DIR/ai.hermes.dashboard.plist"
  mkdir -p "$PLIST_DIR"
  cat > "$PLIST_FILE" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>Label</key><string>ai.hermes.dashboard</string>
  <key>ProgramArguments</key>
  <array>
    <string>${HERMES_PY}</string>
    <string>-m</string>
    <string>hermes_cli.main</string>
    <string>dashboard</string>
    <string>--host</string>
    <string>0.0.0.0</string>
    <string>--port</string>
    <string>${PORT}</string>
    <string>--insecure</string>
    <string>--no-open</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HERMES_DASHBOARD_SESSION_TOKEN</key>
    <string>${TOKEN}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${HOME}/.hermes/logs/dashboard-remote.log</string>
  <key>StandardErrorPath</key><string>${HOME}/.hermes/logs/dashboard-remote.log</string>
</dict>
</plist>
PLIST_EOF
  launchctl bootout "gui/$(id -u)" "$PLIST_FILE" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST_FILE" 2>/dev/null || true
  launchctl kickstart -k "gui/$(id -u)/ai.hermes.dashboard" 2>/dev/null || true
  echo "Installed launchd plist"

else
  echo "No service manager detected. Starting dashboard in the background."
  DASH_ARGS="--host 0.0.0.0 --port ${PORT} --insecure --no-open"
  [ "$DASH_HAS_TUI" = "1" ] && DASH_ARGS="$DASH_ARGS --tui"
  HERMES_DASHBOARD_SESSION_TOKEN="$TOKEN" nohup "$HERMES_PY" -m hermes_cli.main \
    dashboard $DASH_ARGS \
    > "$LOG_DIR/dashboard-remote.log" 2>&1 &
  disown 2>/dev/null || true
  echo "Started PID $!"
fi

# === 8. Wait for API ===
READY=0
for _ in $(seq 1 15); do
  if curl -fsS -o /dev/null -H "X-Hermes-Session-Token: $TOKEN" \
       "http://127.0.0.1:${PORT}/api/config" 2>/dev/null; then
    READY=1; break
  fi
  sleep 1
done

if [ "$READY" -ne 1 ]; then
  echo "Dashboard did not respond within 15s."
  echo "--- log tail ---"
  tail -n 30 "$LOG_DIR/dashboard-remote.log" 2>/dev/null | sed 's/^/   /'
  if [ "$INIT" = "systemd-user" ]; then
    echo "--- systemctl status ---"
    systemctl --user status hermes-dashboard.service --no-pager -l | head -20
  fi
  exit 1
fi
echo "Dashboard is up and the token works."

# === 9. Public URL ===
PUBLIC_IP=""
if command -v hostname >/dev/null 2>&1; then
  PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="$(curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
DASHBOARD_URL="http://${PUBLIC_IP:-<YOUR-HOST-IP>}:${PORT}"

# === 10. Traefik sslip.io detection (optional) ===
SSSLIP=""
# === 10. Optional: read TRAEFIK_URL from env or skip ===
TRAEFIK_URL="${HERMES_TRAEFIK_URL:-}"

# === 11. Final print ===
echo
echo "========================================"
echo "  HERMES DASHBOARD READY"
echo "========================================"
echo
echo "Direct URL (LAN / public IP):"
echo "  ${DASHBOARD_URL}"
echo
if [ -n "$TRAEFIK_URL" ]; then
  echo "Reverse-proxy URL (set via HERMES_TRAEFIK_URL env var):"
  echo "  ${TRAEFIK_URL}"
  echo
fi
echo "Session token (paste into Hermes Desktop):"
echo "  ${TOKEN}"
echo
echo "Token file:  ${TOKEN_FILE}"
echo "Log file:    ${LOG_DIR}/dashboard-remote.log"
echo
echo "Service manager: ${INIT}"
if [ "$INIT" = "systemd-user" ]; then
  echo "Control:         systemctl --user {start|stop|restart|status} hermes-dashboard.service"
elif [ "$INIT" = "launchd" ]; then
  echo "Control:         launchctl {start|stop} gui/$(id -u)/ai.hermes.dashboard"
fi
echo "========================================"
