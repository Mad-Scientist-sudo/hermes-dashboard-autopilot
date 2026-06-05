#!/usr/bin/env bash
# hermes-dashboard-autopilot/uninstall.sh
# Stops the dashboard service, removes the service unit, and (optionally)
# deletes the token + env file.

set -euo pipefail

LOG_DIR="$HOME/.hermes/logs"
TOKEN_FILE="$HOME/.hermes/dashboard-session-token"
ENV_FILE="$HOME/.hermes/dashboard-session-token.env"
LOG_FILE="$LOG_DIR/dashboard-remote.log"

KEEP_TOKEN=0
for arg in "$@"; do
  case "$arg" in
    --keep-token) KEEP_TOKEN=1 ;;
    --help|-h)
      echo "Usage: uninstall.sh [--keep-token]"
      echo "  --keep-token  do not delete the session token file"
      exit 0
      ;;
  esac
done

echo "Stopping Hermes dashboard service..."

case "$(uname -s 2>/dev/null)" in
  Linux)
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user stop hermes-dashboard.service 2>/dev/null || true
      systemctl --user disable hermes-dashboard.service 2>/dev/null || true
      rm -f "$HOME/.config/systemd/user/hermes-dashboard.service"
      systemctl --user daemon-reload 2>/dev/null || true
      echo "Removed systemd user unit"
    fi
    ;;
  Darwin)
    PLIST="$HOME/Library/LaunchAgents/ai.hermes.dashboard.plist"
    if [ -f "$PLIST" ]; then
      launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
      rm -f "$PLIST"
      echo "Removed launchd plist"
    fi
    ;;
esac

# Kill any stray dashboard process
for pid in $(pgrep -f "hermes_cli.main dashboard" 2>/dev/null || true); do
  kill "$pid" 2>/dev/null || true
done
sleep 1
for pid in $(pgrep -f "hermes_cli.main dashboard" 2>/dev/null || true); do
  kill -9 "$pid" 2>/dev/null || true
done

if [ "$KEEP_TOKEN" -eq 0 ]; then
  rm -f "$TOKEN_FILE" "$ENV_FILE"
  echo "Removed token and env file"
else
  echo "Kept token at $TOKEN_FILE"
fi

echo "Done."
