# Changelog

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
