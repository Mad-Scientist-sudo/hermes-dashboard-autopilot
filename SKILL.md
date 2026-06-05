---
name: hermes-dashboard-autopilot
description: One-shot installer for the Hermes Agent dashboard. Detects OS, init system, and firewall; installs a persistent service; prints the URL and session token at the end. Use this whenever Charles (or any user) needs the Hermes dashboard exposed on a remote box for the Hermes Desktop app.
---

# hermes-dashboard-autopilot

Auto-installs the Hermes Agent dashboard as a persistent background service on any host. Auto-detects the environment, opens the firewall, and prints the URL and session token at the end.

## When to use this skill

Use this skill when:

- Charles says "install the dashboard", "set up the dashboard", "expose the dashboard", or "connect Hermes Desktop to the box"
- A new VPS or Mac Mini needs the dashboard running so the Hermes Desktop app can connect
- The dashboard is running but unreachable from outside (firewall blocked, bound to localhost, no persistent service)

Do NOT use this skill for:

- Starting the dashboard on the local dev machine (just run `hermes dashboard` directly)
- Configuring the dashboard in the Hermes Desktop app (that's a different workflow)
- Anything that isn't about getting the dashboard URL + token to a remote box

## What the installer does

1. Detects OS (Linux / macOS) and init system (systemd --user / launchd / none)
2. Detects firewall (ufw / firewalld / pf / none)
3. Locates the Hermes Python interpreter (checks 4 common install paths)
4. Verifies the `hermes dashboard` subcommand supports `--insecure` (and `--tui` if available)
5. Generates a 32-byte session token (or reuses an existing one)
6. Stops any pre-existing dashboard process on port 9119
7. Opens port 9119 in the detected firewall (with a hint if it can't)
8. Installs a service unit (systemd --user unit on Linux, LaunchAgent on macOS, plain background process if no init system)
9. Waits up to 15s for the dashboard API to answer, fails loudly if it doesn't
10. Detects the public IP via `hostname -I` then `api.ipify.org` as fallback
11. Prints the final URL + token + service-control commands

## How to use this skill

For an AI agent running on a host that needs the dashboard installed:

1. Confirm the Hermes install is present (`which hermes` or check `~/.hermes/`)
2. Run the install script:
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/Mad-Scientist-sudo/hermes-dashboard-autopilot/main/scripts/install.sh)
   ```
3. Read the URL and token from the script's output
4. Save the token securely for later use
5. If the user has a Traefik reverse proxy (look for a Traefik container with sslip.io hostnames), re-run with the URL set:
   ```bash
   HERMES_TRAEFIK_URL="https://hermes.187-77-23-118.sslip.io" bash <(curl -fsSL https://raw.githubusercontent.com/Mad-Scientist-sudo/hermes-dashboard-autopilot/main/scripts/install.sh)
   ```

The install is idempotent. Re-running will reuse the existing token, restart the service, and re-print the URL.

## Service management

After install:

- **systemd --user** (Linux): `systemctl --user {start|stop|restart|status} hermes-dashboard.service`
- **launchd** (macOS): `launchctl {start|stop} gui/$(id -u)/ai.hermes.dashboard`
- **No init**: kill the process manually; it isn't persistent across reboots

Logs land in `~/.hermes/logs/dashboard-remote.log`.

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mad-Scientist-sudo/hermes-dashboard-autopilot/main/scripts/uninstall.sh)
```

Removes the service unit, kills the dashboard process, and (optionally) deletes the token file.

## Pitfalls

- **Hermes v0.15.x dropped `--tui`** from the `dashboard` subcommand. The installer detects this and omits the flag. If you see "unrecognized arguments: --tui", the installer is out of date.
- **Two dashboards on the same port** will fight. The installer kills any existing `hermes dashboard` process by PID, but if you have a stray process on 9119 owned by something else, you'll get an "address already in use" error. Check with `ss -ltnp | grep 9119` (Linux) or `lsof -iTCP:9119 -sTCP:LISTEN` (macOS).
- **Token rotation**: changing the token requires restarting the service. The installer does this automatically when re-run.
- **Traefik basicAuth is separate** from the dashboard session token. The Traefik `basicAuth.users` hash in your dynamic config (e.g. `/dynamic/hermes-dashboard.yml`) controls the Traefik layer. The session token is for the dashboard itself.
- **macOS pf firewall**: the installer prints a hint but doesn't auto-open pf. Use System Settings -> Network -> Firewall.

## Files created

- `~/.hermes/dashboard-session-token` — the 32-byte hex token, mode 0600
- `~/.hermes/dashboard-session-token.env` — env file for systemd, mode 0600
- `~/.hermes/logs/dashboard-remote.log` — service stdout+stderr
- `~/.config/systemd/user/hermes-dashboard.service` — Linux service unit
- `~/Library/LaunchAgents/ai.hermes.dashboard.plist` — macOS LaunchAgent
