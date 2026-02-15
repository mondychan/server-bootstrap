# Project Memory

## Goal and Product Direction

- Project is a CLI-first server bootstrap framework for fresh Linux servers.
- Primary operator path is terminal/TUI (headless-friendly, remote-console friendly).
- Web GUI exists as optional helper; it is not the primary UX.

## Architecture Snapshot

- Entry point: `main.sh`
- Shared helpers: `lib/common.sh`
- Modules: `modules/*.sh`
- Profiles: `profiles/*.env`
- Tests: `tests/main.bats`
- CI: `.github/workflows/ci.yml`

Main runtime model:

1. Parse args/env.
2. Discover and load modules.
3. Resolve dependencies (topological order).
4. Execute lifecycle `plan -> apply -> verify` per module.
5. Write logs/events/state.
6. Use lock to prevent concurrent runs.

## Module Contract (Important)

Each module should provide metadata and lifecycle functions:

- `module_id`
- `module_desc`
- `module_apply()` or legacy `module_run()`
- optional: `module_plan()`, `module_verify()`, `module_env`, `module_deps=()`

`main.sh` injects defaults for missing `module_plan/module_verify`.

Shellcheck note:
- module metadata is read dynamically by `main.sh`, so module files use
  `# shellcheck disable=SC2034` at file header.

## TUI Strategy (Current)

- `BOOTSTRAP_TUI=auto` (default) prefers `whiptail` for compatibility.
- `BOOTSTRAP_TUI=gum` forces modern wizard UI.
- `BOOTSTRAP_TUI=whiptail` forces compatibility wizard.
- `BOOTSTRAP_TUI=0` disables TUI and uses classic prompts.
- CLI flags: `--tui-gum`, `--tui-whiptail`.

Important expectation:
- `whiptail` is intentionally retro (ncurses); improvements there are text/context only.
- For "modern/wow" CLI experience, use `gum`.

## Remote Bootstrap Mechanics

Short command:
- `sudo bash -c "$(curl -fsSL https://bootstrap.cocoit.cz)"`

Behavior:
- bootstrap script resolves `PINNED_REPO_TARBALL_URL` from
  `main.sh -> BOOTSTRAP_VERSION -> tag vX.Y.Z`.
- if pinned tarball fails download, it falls back to `main` tarball.

Debug override:
- set `REPO_TARBALL_URL=...` to force exact tarball source (main/tag/commit tarball).

Do not do:
- `BOOTSTRAP_EXTRACTED=1` with piped raw script; that skips extraction and breaks path resolution.

## Release Discipline (Do Not Skip)

For every release meant to be reachable via short bootstrap, always synchronize:

1. `main.sh` -> `BOOTSTRAP_VERSION="<x.y.z>"`
2. `VERSION` -> `<x.y.z>`
3. `CHANGELOG.md` -> `[<x.y.z>]` section
4. Git tag -> `v<x.y.z>` (annotated + pushed)

If one is missing, users can receive older code despite newer `main`.

## CI and Quality Gates

CI job `lint-test` runs:

1. `shfmt -d -i 2 main.sh lib/common.sh modules/*.sh gui/start.sh`
2. `shellcheck main.sh lib/common.sh modules/*.sh gui/start.sh`
3. `bats tests`

Local parity tips:
- On PowerShell, expand `modules/*.sh` manually when running `shfmt`.
- Keep shell formatting at 2-space indent to match CI.

## Known Pitfalls From Recent Work

- `apply` dry-run should work without root; lock handling must not chmod/chown existing `/tmp`.
- Dynamic functions and trap handlers in `main.sh` may trigger shellcheck false positives;
  suppress only with targeted rule disables.
- Annotated tag hash differs from commit hash; compare with `refs/tags/vX.Y.Z^{}`.
- Proxy/cache layers can serve stale bootstrap script; verify source content and use
  `REPO_TARBALL_URL` override when needed.

## Final Verification Checklist

1. `git ls-remote origin refs/heads/main refs/tags/v<x.y.z> refs/tags/v<x.y.z>^{}`
2. CI green on `main`
3. Release docs updated when process changed:
   - `README.md`
   - `docs/release.md`
   - this `MEMORY.md`
