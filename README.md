# hermes-dashboard-autopilot

**One-shot installer for the Hermes Agent dashboard. Auto-detects the host environment and exposes the dashboard as a persistent background service. Prints the URL and session token at the end.**

## What is this

A small, portable install script for the [Hermes Agent](https://hermes-agent.nousresearch.com) `dashboard` subcommand. The dashboard is a web UI for managing config, API keys, and sessions. The Hermes Desktop app talks to it over HTTP + a session token.

This skill automates the boring parts: detecting the OS, init system, and firewall; finding the Hermes install; opening port 9119; installing a persistent service; and printing the connection details.

## Who this is for

Two audiences:

1. **AI agents** running on a fresh VPS or Mac Mini, told by their user to "expose the dashboard" or "connect Hermes Desktop". The agent runs the install command, reads the output, and reports the URL + token to the user.
2. **Humans** who just want a one-line way to get the dashboard running and reachable.

## How to use it

### As an AI agent

If you're an AI agent (any framework — Hermes, Claude Code, Codex, OpenCode, etc.) and your user asks you to set up the Hermes dashboard on a host:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mad-Scientist-sudo/hermes-dashboard-autopilot/main/scripts/install.sh)
```

The script will:
1. Print what it detected (OS, init system, firewall)
2. Locate the Hermes install
3. Generate a session token
4. Install and start the dashboard as a background service
5. Print the final URL and token

Read the output. Save the token. Tell the user the URL.

If the host has a Traefik reverse proxy with a public hostname (e.g. `hermes.187-77-23-118.sslip.io`), re-run with:

```bash
HERMES_TRAEFIK_URL="https://your-hostname.sslip.io" bash <(curl -fsSL https://raw.githubusercontent.com/Mad-Scientist-sudo/hermes-dashboard-autopilot/main/scripts/install.sh)
```

The script is **idempotent**. Re-running it is safe and will reuse the existing token.

### As a human

Same one-liner. Copy-paste into a terminal on a host where Hermes is installed:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mad-Scientist-sudo/hermes-dashboard-autopilot/main/scripts/install.sh)
```

You'll see a final block like:

```
========================================
  HERMES DASHBOARD READY
========================================

Direct URL (LAN / public IP):
  http://187.77.23.118:9119

Session token (paste into Hermes Desktop):
  22e939f248284727da8c26e62a038393510add17216d18d2e038a01370c91e3e

Token file:  /root/.hermes/dashboard-session-token
Log file:    /root/.hermes/logs/dashboard-remote.log

Service manager: systemd-user
Control:         systemctl --user {start|stop|restart|status} hermes-dashboard.service
========================================
```

Paste the URL and token into Hermes Desktop's connection settings.

## What it detects

| Component | Detected values |
|---|---|
| OS | Linux, macOS |
| Init system | systemd --user, launchd, none |
| Firewall | ufw, firewalld, pf, none (and a hint if none) |
| Hermes | looks in 4 common install paths |

If the host doesn't match a known pattern, the script will print a clear error explaining what to do.

## Files it creates

- `~/.hermes/dashboard-session-token` — the 32-byte hex token, mode 0600
- `~/.hermes/dashboard-session-token.env` — env file for systemd, mode 0600
- `~/.hermes/logs/dashboard-remote.log` — service stdout+stderr
- `~/.config/systemd/user/hermes-dashboard.service` — Linux service unit
- `~/Library/LaunchAgents/ai.hermes.dashboard.plist` — macOS LaunchAgent

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mad-Scientist-sudo/hermes-dashboard-autopilot/main/scripts/uninstall.sh)
```

Removes the service unit, kills the dashboard process, optionally deletes the token file.

## Repository layout

```
.
├── README.md           # this file
├── SKILL.md            # agent-facing instructions (loaded by skill_view)
└── scripts/
    ├── install.sh      # the installer
    └── uninstall.sh    # the uninstaller
```

## How this was built

This was extracted from a real Charles Blair (Mad Scientist) setup. The dashboard install flow was originally a one-off bash session. After hitting the same edge cases (port conflicts, missing ufw rules, `--tui` flag removed in Hermes v0.15, port-in-use from a stale process) enough times, it was packaged into this skill so any agent can run it without re-deriving the steps.

## Compatibility

Tested with:

- Hermes Agent v0.15.1 on Ubuntu 24.04 (systemd --user, ufw)
- Hermes Agent v0.15.x on macOS (launchd, pf hint)

Other Linux distros and macOS versions should work as long as they have one of the supported init systems / firewalls.

## License

MIT.
