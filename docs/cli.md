# CLI Guide

## Command model

`main.sh` now executes modules using lifecycle stages:

- `plan`: print intended actions.
- `apply`: perform changes.
- `verify`: run post-checks.

Default action is `apply`.

## Basic usage

```bash
sudo ./main.sh --plan --modules docker,wireguard
sudo ./main.sh --apply --profile prod --modules ssh-keys,webmin
sudo ./main.sh --verify --modules docker
```

## Module selection

You can select modules in three ways:

- Positional args: `sudo ./main.sh docker wireguard`
- CSV: `sudo ./main.sh --modules docker,wireguard`
- Interactive picker (default when no modules passed and interactive mode enabled)

## Profiles

Profiles are env files in `profiles/*.env`.

```bash
sudo ./main.sh --profile dev --modules docker
./main.sh --list-profiles
./main.sh --list-profiles-json
```

Profile file naming rules are validated (`[a-zA-Z0-9._-]+`).

## Listing and machine-readable output

```bash
./main.sh --list
./main.sh --list-json
./main.sh --list-profiles
./main.sh --list-profiles-json
```

## Important options

- `--apply` / `--plan` / `--verify`
- `--modules <csv>`
- `--profile <name>`
- `--tui`
- `--no-interactive`
- `--help`

## Global environment variables

- `BOOTSTRAP_DRY_RUN=1`
- `BOOTSTRAP_VERBOSE=1`
- `BOOTSTRAP_INTERACTIVE=0`
- `BOOTSTRAP_TUI=1`
- `BOOTSTRAP_LOG_DIR=<path>`
- `BOOTSTRAP_STATE_DIR=<path>`
- `BOOTSTRAP_LOCK_FILE=<path>`
- `BOOTSTRAP_CONTINUE_ON_ERROR=1`

## Root requirements

- `apply`: requires root unless `BOOTSTRAP_DRY_RUN=1`.
- `verify`: requires root.
- `plan`: no root required.

## Remote bootstrap behavior

When run via stdin (`curl ... | bash`), `main.sh`:

1. Tries pinned tag tarball (`v<VERSION>`).
2. Falls back to `main` tarball if pinned download fails.
3. Re-execs from extracted path.

You can override source tarball:

```bash
REPO_TARBALL_URL=https://.../archive/refs/tags/v0.2.0.tar.gz \
  curl -fsSL https://raw.githubusercontent.com/mondychan/server-bootstrap/main/main.sh | sudo bash -s --
```
