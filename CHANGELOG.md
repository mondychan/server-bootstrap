# Changelog

## [0.2.2] - 2026-02-15

### Changed
- Bumped pinned bootstrap version to `0.2.2` to align remote tarball resolution with latest release tag.
- Improved interactive profile prompt handling (`none`/`default` is treated as no profile).
- Reduced noisy download output in stdin bootstrap fallback path.
- WireGuard interactive output ordering improved so public key prints cleanly around prompts.

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
