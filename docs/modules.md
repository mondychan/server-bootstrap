# Module Guide

## Module contract

Each module file in `modules/*.sh` must define:

- `module_id`
- `module_desc`
- `module_apply()` (or legacy `module_run()`)

Optional but recommended:

- `module_plan()`
- `module_verify()`
- `module_env` (comma-separated env var list)
- `module_deps=()` (array of module IDs)

If `module_plan`/`module_verify` are missing, defaults are injected by `main.sh`.

## Dependency behavior

- Dependencies are resolved automatically.
- Order is topologically sorted.
- Cycles fail fast.
- Unknown dependency IDs fail fast.

## Current modules

### `ssh-keys`

Purpose:
- Sync `authorized_keys` from GitHub via systemd timer.
- Harden SSH auth settings.

Key env vars:
- `GH_USER` (default `mondychan`)
- `USERNAME` (default `root`)
- `INTERVAL_MIN` (default `15`)

Security behavior:
- Backs up `sshd_config` before edits.
- Validates with `sshd -t`.
- Restores backup on validation failure.

### `webmin`

Purpose:
- Install and configure Webmin.

Key env vars:
- `WEBMIN_PORT` (default `10000`)
- `WEBMIN_VERSION` (optional pin)
- `WEBMIN_KEY_SHA256` (optional expected key checksum)
- `WEBMIN_STRICT_KEY_CHECK=1` (enforce checksum pinning)

Security behavior:
- No remote setup script execution.
- Repository key can be checksum-pinned.

### `docker`

Purpose:
- Install Docker Engine and Compose plugin from official repo.

Key env vars:
- `DOCKER_HELLO` (`1` by default, run hello-world)

### `wireguard`

Purpose:
- Configure WireGuard client.

Key env vars:
- `WG_INTERFACE` (default `wg0`)
- `WG_ADDRESS` (required unless interactive prompt)
- `WG_CONFIRM` (`0` default, `1` for non-interactive approval)
- `WG_TEST` (`ask`, `0`, `1`)

Automation behavior:
- CI/non-interactive runs should set `WG_CONFIRM=1`.

## Writing new modules

Minimal template:

```bash
#!/usr/bin/env bash
set -euo pipefail

module_id="example"
module_desc="Example module"
module_env="EXAMPLE_FLAG"
module_deps=()

module_plan() {
  echo "Plan: ..."
}

module_apply() {
  echo "Apply: ..."
}

module_verify() {
  echo "Verify: ..."
}
```
