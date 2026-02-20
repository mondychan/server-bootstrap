# Changelog

## [0.2.18] - 2026-02-20

### Fixed
- Updated `forte` WireGuard profile values so release tarball uses intended peer settings:
  - `WG_PEER_PUBLIC_KEY=qIvVJXHqQuYT2XMdqGiMrwO5DA7F0MCSk/bmbj1tolM=`
  - `WG_ALLOWED_IPS="192.168.80.0/24"`
- Hardened SSH service detection in `ssh-keys` module to recognize both `ssh.service` and `sshd.service` reliably across distributions.
- Fixed `ssh-keys` verify stage to return non-zero when SSH server prerequisites are missing (prevents false `Completed successfully`).

## [0.2.17] - 2026-02-15

### Changed
- Expanded WireGuard profile-driven configuration:
  - added endpoint host/port override support (`WG_ENDPOINT_HOST`, `WG_ENDPOINT_PORT`)
  - added peer and tunnel options (`WG_PEER_PUBLIC_KEY`, `WG_ALLOWED_IPS`, `WG_PERSISTENT_KEEPALIVE`, `WG_DNS`)
- Clarified WireGuard `WG_ADDRESS` wording as local interface address of this peer.
- Updated profile examples (`dev`, `prod`, `forte`) with extended WireGuard settings.
- Restructured `README.md` for clearer onboarding flow, one-liner usage, command structure, and release guidance.

## [0.2.16] - 2026-02-15

### Changed
- Improved `ssh-keys` module behavior when SSH server is missing:
  - added `SSH_AUTO_INSTALL=1` default to auto-install `openssh-server` (or distro equivalent)
  - added stricter SSH server presence checks with clearer failure messages
  - kept opt-out path for key-sync-only mode via `SSH_REQUIRE_SERVER=0`
- Extended profile and docs coverage for new SSH options:
  - added `SSH_AUTO_INSTALL=1` to `profiles/dev.env` and `profiles/prod.env`
  - updated module environment docs in `README.md` and `docs/modules.md`

## [0.2.15] - 2026-02-15

### Fixed
- Fixed module stage failure propagation in `main.sh` so non-zero module exits are no longer masked by output piping.
- Hardened `webmin` module failure handling:
  - cleanup of stale Webmin APT repository/key files before and after failed install attempts
  - failed install now exits with error instead of printing false-positive success
  - safe APT refresh after cleanup to prevent cross-module repo breakage

## [0.2.14] - 2026-02-15

### Changed
- Added colored console logs for clearer output readability (`ERROR`, `WARN`, `OK` highlighting).
- Made colored console logs default behavior (`BOOTSTRAP_COLOR=always` by default).
- Added `BOOTSTRAP_COLOR=auto|always|never` documentation in CLI/README.

## [0.2.13] - 2026-02-15

### Changed
- Made portable Bash TUI the single supported interactive UI mode and removed whiptail mode/flags.
- Added two new modules:
  - `unattended-upgrades` for automatic APT security updates.
  - `time-sync` for timezone + NTP configuration via `systemd-timesyncd`.
- Set `time-sync` default timezone to `CET`.
- Extended `dev` and `prod` profiles with `time-sync` NTP defaults.
- Added inline explanatory comments for all profile variables in `profiles/dev.env` and `profiles/prod.env`.
- Updated module docs/README and tests for newly added modules.

## [0.2.12] - 2026-02-15

### Fixed
- Fixed portable TUI crash caused by `status_line` being uninitialized under `set -u`.
- Portable profile/module selection now proceeds correctly after profile confirmation.

## [0.2.11] - 2026-02-15

### Changed
- Replaced optional `gum` runtime dependency with a portable Bash TUI mode.
- Added portable interactive navigation (`arrows`, `space`, `enter`) for profile and module selection.
- Added explicit `BOOTSTRAP_TUI=portable` and `--tui-portable` mode.
- Kept `--tui-gum` as a compatibility alias mapped to portable mode.
- Updated CLI/TUI docs and project memory for dependency-free first-run UX.
- Fixed shellcheck issues in portable TUI array indexing and kept CI green.
- Synchronized release version points for short bootstrap pinning consistency.

## [0.2.8] - 2026-02-15

### Changed
- Added explicit TUI selection modes for CLI-first operation:
  - `BOOTSTRAP_TUI=gum` / `--tui-gum` for modern wizard
  - `BOOTSTRAP_TUI=whiptail` / `--tui-whiptail` for compatibility mode
- Updated documentation to emphasize CLI/TUI-first usage for headless and remote environments.
- Added and expanded `MEMORY.md` to preserve architecture, release process, and troubleshooting context for future development continuity.
- Synchronized release version points (`main.sh`, `VERSION`, changelog) to keep short bootstrap pinned tag behavior correct.

## [0.2.6] - 2026-02-15

### Changed
- Bumped pinned bootstrap version to `0.2.6` so stdin/short bootstrap resolves current release tag instead of older `v0.2.4`.
- Improved whiptail wizard UX with runtime backtitle (version/action/profile/run id), onboarding intro dialog, and clearer profile/module selection text.
- Fixed lock directory handling for non-root apply/dry-run flows to avoid permission errors on existing lock parent directories.
- Stabilized CI checks (`shfmt`, `shellcheck`, `bats`) after dynamic module framework hardening.

## [0.2.4] - 2026-02-15

### Changed
- Fixed interactive TUI compatibility in problematic terminals by preferring `whiptail` in `auto` mode.
- Stabilized `gum` menu invocation by passing choices as arguments instead of piped stdin.
- Added explicit docs note and fallback for broken terminal rendering (`BOOTSTRAP_TUI=0`).

## [0.2.3] - 2026-02-15

### Changed
- Improved TUI compatibility in interactive mode: `auto` now prefers `whiptail` before `gum`.
- Hardened gum picker invocation by passing choices as arguments (instead of stdin pipes) to avoid broken key handling in some terminals.
- Added clearer fallback behavior from advanced TUI to classic prompt mode when needed.
- Updated docs with troubleshooting for garbled/broken terminal UI (`BOOTSTRAP_TUI=0`).

## [0.2.2] - 2026-02-15

### Changed
- Bumped pinned bootstrap version to `0.2.2` to align remote tarball resolution with latest release tag.
- Improved interactive profile prompt handling (`none`/`default` is treated as no profile).
- Reduced noisy download output in stdin bootstrap fallback path.
- WireGuard interactive output ordering improved so public key prints cleanly around prompts.
- Improved interactive CLI with modern gum wizard flow (profile picker, module detail browser, richer multi-select, clearer progress output).
- Improved TUI compatibility: `auto` mode now prefers `whiptail`, with safer gum invocation and prompt fallback.

## [0.2.0] - 2026-02-15

### Added
- Lifecycle engine: `module_plan`, `module_apply`, `module_verify`.
- Profile support via `profiles/*.env` and `--profile`.
- Dependency resolver with automatic module ordering.
- Locking with `flock` and state output to `state.json`.
- Structured logging (`server-bootstrap.log`, `events.jsonl`).
- TUI mode support (`gum`/`whiptail` fallback chain).
- Local Web GUI (`gui/server.py`, `gui/static/index.html`).
- CI workflow with `shellcheck`, `shfmt`, `bats`.
- Extended documentation set in `docs/` (CLI, modules, GUI, operations, release).

### Changed
- Fixed root handling for `--list`/`--list-json`.
- Replaced fragile `for path in $(...)` loops with robust path handling.
- Improved remote bootstrap tarball strategy with pinned tag preference and fallback.
- `ssh-keys` module now validates sshd config and restores from backup on error.
- `wireguard` module now supports non-interactive automation via `WG_CONFIRM` and `WG_TEST`.
- `webmin` module no longer executes remote setup scripts directly.

### Notes
- Strict Webmin key pinning is available via `WEBMIN_STRICT_KEY_CHECK=1` + `WEBMIN_KEY_SHA256`.
