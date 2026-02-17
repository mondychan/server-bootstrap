# server-bootstrap

Need to onboard many servers and do not want to repeat the same setup steps manually?

`server-bootstrap` gives you a profile-driven, module-based bootstrap flow that can be executed in one command.
It is built for fast, repeatable server provisioning: SSH keys, Docker runtime, WireGuard client, unattended updates, time sync, and more.

You pick a profile, pick modules, run one command, and let the script handle the rest (`plan -> apply -> verify`).

## What You Get

- Lifecycle execution model per module: `module_plan`, `module_apply`, `module_verify`
- Dependency-aware module orchestration
- Profile support via `profiles/*.env`
- Portable TUI wizard (no extra dependencies)
- Optional local Web UI (Phase B)
- Structured logging + JSON event log + state file
- Safe lockfile handling to avoid parallel bootstrap runs
- Release pinning for remote bootstrap through `BOOTSTRAP_VERSION`

## Typical Use Cases

- New server onboarding with a consistent baseline
- Repeated deployment across VPS fleets
- Profile-driven setup (dev/prod/tenant-specific profiles)
- Fast remote rollout over SSH with one-line commands
- Controlled post-install verification

## Quick Start

### 1) Short proxy one-liner (recommended)

Interactive wizard:

```bash
sudo bash -c "$(curl -fsSL https://bootstrap.cocoit.cz)"
```

If cache is suspected, force fresh fetch:

```bash
sudo bash -c "$(curl -fsSL https://bootstrap.cocoit.cz?nocache=$(date +%s))"
```

### 2) Raw GitHub one-liner (no proxy)

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s --
```

### 3) Non-interactive one-liner (direct rollout)

```bash
curl -fsSL https://bootstrap.cocoit.cz | sudo BOOTSTRAP_INTERACTIVE=0 bash -s -- \
  --apply --profile prod \
  --modules ssh-keys,docker,wireguard,unattended-upgrades,time-sync
```

Short proxy with explicit action/modules:

```bash
curl -fsSL https://bootstrap.cocoit.cz | sudo bash -s -- --plan --modules docker,wireguard
```

## Command Structure

General form:

```bash
./main.sh --<action> [--profile <name>] [--modules <csv>] [--no-interactive]
```

Actions:

- `--plan`: print what would be done (no changes)
- `--apply`: run `plan`, then apply changes, then verify
- `--verify`: run checks only (plus plan output for context)

Examples:

```bash
sudo ./main.sh --plan --profile prod --modules ssh-keys,wireguard
sudo ./main.sh --apply --profile prod --modules ssh-keys,webmin,docker
sudo ./main.sh --verify --modules docker,time-sync
```

List metadata:

```bash
./main.sh --list
./main.sh --list-json
./main.sh --list-profiles
./main.sh --list-profiles-json
```

## Profile-Driven Workflow

Profiles are plain env files in `profiles/*.env`.

Included examples:

- `profiles/dev.env`
- `profiles/prod.env`

Add your own profile (for example `profiles/forte.env`) and run:

```bash
sudo ./main.sh --apply --profile forte --modules ssh-keys,wireguard,docker
```

You can also override any profile value at runtime:

```bash
sudo WG_ENDPOINT_HOST=vpn.example.net WG_ENDPOINT_PORT=3232 \
  ./main.sh --apply --profile prod --modules wireguard
```

## TUI (Phase A)

CLI/TUI is the primary operator path (headless-friendly).

- Default mode is portable Bash wizard (`BOOTSTRAP_TUI=auto`)
- Force portable wizard: `BOOTSTRAP_TUI=portable` or `--tui-portable`
- Disable TUI and use classic prompts: `BOOTSTRAP_TUI=0`

Examples:

```bash
sudo ./main.sh
sudo BOOTSTRAP_TUI=portable ./main.sh
sudo BOOTSTRAP_TUI=0 ./main.sh
```

## Web GUI (Phase B)

Optional local ops panel backed by the same `main.sh` actions.

```bash
python3 gui/server.py --host 127.0.0.1 --port 8089
# then open http://127.0.0.1:8089
```

or:

```bash
bash gui/start.sh
```

## Module Overview

| Module ID | Purpose | Key env vars |
| --- | --- | --- |
| `ssh-keys` | Sync `authorized_keys` from GitHub via systemd timer + SSH hardening. | `GH_USER`, `USERNAME`, `INTERVAL_MIN`, `SSH_REQUIRE_SERVER`, `SSH_AUTO_INSTALL` |
| `webmin` | Install Webmin from official repository, verify service. | `WEBMIN_PORT`, `WEBMIN_VERSION`, `WEBMIN_KEY_SHA256`, `WEBMIN_STRICT_KEY_CHECK` |
| `docker` | Install Docker Engine + Compose plugin from official repo. | `DOCKER_HELLO` |
| `wireguard` | WireGuard client setup to configurable endpoint. | `WG_ADDRESS`, `WG_INTERFACE`, `WG_CONFIRM`, `WG_TEST`, `WG_BACKEND`, `WG_ENDPOINT_HOST`, `WG_ENDPOINT_PORT`, `WG_PEER_PUBLIC_KEY`, `WG_ALLOWED_IPS`, `WG_PERSISTENT_KEEPALIVE`, `WG_DNS` |
| `unattended-upgrades` | Enable automatic security updates via APT unattended-upgrades. | `UAU_AUTO_REBOOT`, `UAU_AUTO_REBOOT_TIME`, `UAU_REMOVE_UNUSED`, `UAU_UPDATE_PACKAGE_LISTS`, `UAU_UNATTENDED_UPGRADE` |
| `time-sync` | Configure timezone and NTP sync via systemd-timesyncd. | `TS_TIMEZONE`, `TS_NTP_SERVERS`, `TS_FALLBACK_NTP`, `TS_STRICT_SYNC`, `TS_SYNC_TIMEOUT_SEC` |

## Global Environment Variables

- `BOOTSTRAP_DRY_RUN=1` skip apply stage (plan still runs)
- `BOOTSTRAP_VERBOSE=1` verbose logs
- `BOOTSTRAP_INTERACTIVE=0` disable prompts
- `BOOTSTRAP_TUI=auto|portable|1|0` auto/portable/disabled TUI mode
- `BOOTSTRAP_COLOR=auto|always|never` default `always`; colored console output
- `BOOTSTRAP_LOG_DIR=/path` override log directory
- `BOOTSTRAP_STATE_DIR=/path` override state directory
- `BOOTSTRAP_LOCK_FILE=/path` override lock file location
- `BOOTSTRAP_CONTINUE_ON_ERROR=1` continue when a module fails

## State and Logging

- Text log: `<log_dir>/server-bootstrap.log`
- Event log: `<log_dir>/events.jsonl`
- State file: `<state_dir>/state.json`

Default locations:

- root: `/var/log/server-bootstrap`, `/var/lib/server-bootstrap`
- non-root fallback: `/tmp/server-bootstrap`, `/tmp/server-bootstrap-state`

## Security Notes

- `ssh-keys` hardening uses backup + `sshd -t` validation before reload/restart.
- `webmin` supports strict key checksum pinning:
  - `WEBMIN_STRICT_KEY_CHECK=1`
  - `WEBMIN_KEY_SHA256=<expected_sha256>`
- `wireguard` supports non-interactive automation (`WG_CONFIRM=1`, `WG_TEST=0|1`).

## Development Quality Gates

CI runs:

- `shellcheck`
- `shfmt` (2-space shell format)
- `bats` tests

## Release Version Sync (Mandatory)

When releasing a new version, always keep these synchronized:

1. `main.sh` -> `BOOTSTRAP_VERSION="<x.y.z>"`
2. `VERSION` -> `<x.y.z>`
3. `CHANGELOG.md` -> add section `[<x.y.z>]`
4. Git tag -> `v<x.y.z>` (annotated tag)

Why this matters:

- The short bootstrap URL (`https://bootstrap.cocoit.cz`) resolves script logic that pins tarball download by `BOOTSTRAP_VERSION`.
- If version points are out of sync, users can receive older code.

Release command template:

```bash
git add main.sh VERSION CHANGELOG.md
git commit -m "release: v<x.y.z>"
git push origin main
git tag -a v<x.y.z> -m "Release v<x.y.z>"
git push origin v<x.y.z>
```

Verify:

```bash
git ls-remote origin refs/heads/main refs/tags/v<x.y.z> refs/tags/v<x.y.z>^{}
```

## Script References

- Web GUI launcher: `bash gui/start.sh`
- Release helper: `bash scripts/release.sh`
- Tests: `bats tests`

## Documentation Map

- Docs index: `docs/README.md`
- CLI/lifecycle: `docs/cli.md`
- Modules/env vars: `docs/modules.md`
- TUI/Web UI: `docs/gui.md`
- Logging/state/locks: `docs/operations.md`
- Release process: `docs/release.md`

## Notes

- `apply` and `verify` require root (`sudo`) unless `BOOTSTRAP_DRY_RUN=1`.
- Modules are built for Ubuntu + systemd.
- Remote bootstrap prefers pinned tag tarball and falls back to `main` if needed.
