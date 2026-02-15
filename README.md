# server-bootstrap

Bootstrap framework for fresh Ubuntu servers. It is now lifecycle-driven (`plan -> apply -> verify`), profile-aware, dependency-capable, and includes optional TUI + local Web GUI.

## Highlights

- Modular engine with `module_plan`, `module_apply`, `module_verify`
- Dependency graph resolution with automatic ordering
- Profile support via `profiles/*.env`
- State tracking (`state.json`) + text/JSON event logs
- Concurrency lock (`flock`) to prevent parallel runs
- Safer SSH hardening with backup + `sshd -t` validation
- WireGuard automation flags for CI (`WG_CONFIRM`, `WG_TEST`)
- Webmin repo setup without executing remote setup scripts

## Quick start

Interactive run:

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s --
```

Run all (non-interactive):

```bash
curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo BOOTSTRAP_INTERACTIVE=0 bash -s --
```

## CLI actions

```bash
sudo ./main.sh --plan --modules docker,wireguard
sudo ./main.sh --apply --profile prod --modules ssh-keys,webmin
sudo ./main.sh --verify --modules docker
```

## List modules/profiles

```bash
./main.sh --list
./main.sh --list-json
./main.sh --list-profiles
./main.sh --list-profiles-json
```

## Profile usage

Profiles are plain env files in `profiles/*.env`.

Examples included:
- `profiles/dev.env`
- `profiles/prod.env`

Run with profile:

```bash
sudo ./main.sh --profile prod --modules ssh-keys,docker
```

## TUI (Phase A)

Enable TUI selectors with `--tui` or `BOOTSTRAP_TUI=1`.

- Uses `gum` when available
- Falls back to `whiptail`
- Falls back to classic prompt UI

```bash
sudo BOOTSTRAP_TUI=1 ./main.sh
```

## Web GUI (Phase B)

Local ops panel (no external dependencies, Python stdlib only):

```bash
python3 gui/server.py --host 127.0.0.1 --port 8089
# then open http://127.0.0.1:8089
```

or

```bash
bash gui/start.sh
```

The Web GUI calls the same `main.sh` actions (`plan/apply/verify`) underneath.

## Global environment variables

- `BOOTSTRAP_DRY_RUN=1` skip apply stage (plan still runs)
- `BOOTSTRAP_VERBOSE=1` verbose logs
- `BOOTSTRAP_INTERACTIVE=0` disable prompts
- `BOOTSTRAP_TUI=1` prefer TUI selectors
- `BOOTSTRAP_LOG_DIR=/path`
- `BOOTSTRAP_STATE_DIR=/path`
- `BOOTSTRAP_LOCK_FILE=/path`
- `BOOTSTRAP_CONTINUE_ON_ERROR=1` continue when a module fails

## State and logging

- Text log: `<log_dir>/server-bootstrap.log`
- Event log (JSONL): `<log_dir>/events.jsonl`
- State file: `<state_dir>/state.json`

Default paths:
- root: `/var/log/server-bootstrap`, `/var/lib/server-bootstrap`
- non-root fallback: `/tmp/server-bootstrap`, `/tmp/server-bootstrap-state`

## Module overview

| Module ID | Purpose | Key env vars |
| --- | --- | --- |
| `ssh-keys` | Sync `authorized_keys` from GitHub via systemd timer + SSH hardening. | `GH_USER`, `USERNAME`, `INTERVAL_MIN` |
| `webmin` | Install Webmin from official repository, verify service. | `WEBMIN_PORT`, `WEBMIN_VERSION`, `WEBMIN_KEY_SHA256`, `WEBMIN_STRICT_KEY_CHECK` |
| `docker` | Install Docker Engine + Compose plugin from official repo. | `DOCKER_HELLO` |
| `wireguard` | WireGuard client setup to `vpn.cocoit.cz`. | `WG_ADDRESS`, `WG_INTERFACE`, `WG_CONFIRM`, `WG_TEST` |

## Security note (Webmin key pinning)

For strict key pinning, set:

- `WEBMIN_STRICT_KEY_CHECK=1`
- `WEBMIN_KEY_SHA256=<expected_sha256_of_jcameron-key.asc>`

## Development quality gates

CI workflow runs:
- `shellcheck`
- `shfmt`
- `bats` tests

## Documentation

- Docs index: `docs/README.md`
- CLI and lifecycle: `docs/cli.md`
- Module contract and module usage: `docs/modules.md`
- TUI/Web GUI usage: `docs/gui.md`
- Logging/state/lock operations: `docs/operations.md`
- CI/versioning/release process: `docs/release.md`

## Script usage reference

GUI launcher:

```bash
bash gui/start.sh
```

Release helper:

```bash
bash scripts/release.sh
# or explicit version:
bash scripts/release.sh 0.2.1
```

Test suite:

```bash
bats tests
```

## Notes

- `apply` and `verify` require root (`sudo`) unless `BOOTSTRAP_DRY_RUN=1`.
- Modules are designed for Ubuntu + systemd.
- Tarball bootstrap prefers pinned tag URL and falls back to `main` when needed.
