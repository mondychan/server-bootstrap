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
- `SSH_REQUIRE_SERVER` (`1` default, require SSH server presence; set `0` to allow key-sync-only mode)
- `SSH_AUTO_INSTALL` (`1` default, auto-install SSH server when missing if `SSH_REQUIRE_SERVER=1`)

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
- `WG_ADDRESS` (local WireGuard interface address for this peer; required unless interactive prompt)
- `WG_CONFIRM` (`0` default, `1` for non-interactive approval)
- `WG_TEST` (`ask`, `0`, `1`)
- `WG_ENDPOINT_HOST` (default `vpn.cocoit.cz`)
- `WG_ENDPOINT_PORT` (default `13231`)
- `WG_PEER_PUBLIC_KEY` (default bundled peer key)
- `WG_ALLOWED_IPS` (default `192.168.70.0/24`, list of IPv4/CIDR)
- `WG_PERSISTENT_KEEPALIVE` (default `25`, range `0-65535`)
- `WG_DNS` (optional DNS list for interface)

Automation behavior:
- CI/non-interactive runs should set `WG_CONFIRM=1`.

### `unattended-upgrades`

Purpose:
- Enable automatic APT security upgrades for Debian/Ubuntu.

Key env vars:
- `UAU_AUTO_REBOOT` (`0` default, `1` to allow automatic reboot)
- `UAU_AUTO_REBOOT_TIME` (`03:30` default, format `HH:MM`)
- `UAU_REMOVE_UNUSED` (`1` default)
- `UAU_UPDATE_PACKAGE_LISTS` (`1` default)
- `UAU_UNATTENDED_UPGRADE` (`1` default)

Behavior:
- Installs `unattended-upgrades`.
- Writes periodic config in `/etc/apt/apt.conf.d/20auto-upgrades`.
- Writes bootstrap override in `/etc/apt/apt.conf.d/52bootstrap-unattended-upgrades`.

### `time-sync`

Purpose:
- Set server timezone and configure NTP with `systemd-timesyncd`.

Key env vars:
- `TS_TIMEZONE` (`CET` default)
- `TS_NTP_SERVERS` (optional, space/comma separated)
- `TS_FALLBACK_NTP` (optional, space/comma separated)
- `TS_STRICT_SYNC` (`0` default, `1` waits for synchronized state)
- `TS_SYNC_TIMEOUT_SEC` (`60` default)

Behavior:
- Applies timezone via `timedatectl set-timezone`.
- Enables NTP (`timedatectl set-ntp true`) and restarts `systemd-timesyncd`.
- Writes drop-in config `/etc/systemd/timesyncd.conf.d/50-bootstrap.conf`.

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
