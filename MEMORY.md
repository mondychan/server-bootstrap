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

- `BOOTSTRAP_TUI=auto` (default) uses portable Bash wizard on interactive terminals.
- `BOOTSTRAP_TUI=portable` forces portable Bash wizard.
- `BOOTSTRAP_TUI=0` disables TUI and uses classic prompts.
- CLI flags: `--tui` and `--tui-portable`.

Important expectation:
- Portable mode runs without extra package installation on fresh servers.

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

## Release SOP (Exact Procedure)

Use this exact order every time:

1. Preflight
   - `git status --short` must be clean.
   - decide next version `<x.y.z>` (never reuse existing tag version).
2. Edit release files in one change
   - set `main.sh` `BOOTSTRAP_VERSION="<x.y.z>"`
   - set `VERSION` to `<x.y.z>`
   - add `CHANGELOG.md` section `[<x.y.z>]`
3. Commit release only
   - `git add main.sh VERSION CHANGELOG.md`
   - `git commit -m "release: v<x.y.z>"`
4. Push release commit first
   - `git push origin main`
5. Tag that exact release commit
   - `git tag -a v<x.y.z> -m "Release v<x.y.z>"`
   - `git push origin v<x.y.z>`
6. Verify mapping
   - `git ls-remote https://github.com/mondychan/server-bootstrap.git refs/heads/main refs/tags/v<x.y.z> refs/tags/v<x.y.z>^{}`
   - `refs/tags/v<x.y.z>^{}` must resolve to intended release commit.

Never do:
- do not create a version tag on a feature/docs commit.
- do not tag before version files are bumped.
- do not reuse/move an already published tag; create next patch version instead (e.g. `0.2.8` -> `0.2.9`).

Quick safe command block (after manual file edits):

```bash
git add main.sh VERSION CHANGELOG.md
git commit -m "release: v<x.y.z>"
git push origin main
git tag -a v<x.y.z> -m "Release v<x.y.z>"
git push origin v<x.y.z>
git ls-remote https://github.com/mondychan/server-bootstrap.git refs/heads/main refs/tags/v<x.y.z> refs/tags/v<x.y.z>^{}
```

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
