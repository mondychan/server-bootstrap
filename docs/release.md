# Release and Quality Guide

## CI

GitHub Actions workflow: `.github/workflows/ci.yml`

Checks:

- `shfmt`
- `shellcheck`
- `bats`

## Local test commands

```bash
shellcheck main.sh lib/common.sh modules/*.sh gui/start.sh
shfmt -d -i 2 main.sh lib/common.sh modules/*.sh gui/start.sh
bats tests
```

## Versioning

- Project version is stored in `VERSION`.
- Bootstrap pinned release version is stored in `main.sh` as `BOOTSTRAP_VERSION`.
- Changes are recorded in `CHANGELOG.md`.
- Tags use `v<semver>`.

## Release script

Use:

```bash
bash scripts/release.sh
```

Optional explicit version:

```bash
bash scripts/release.sh 0.2.1
```

What it does:

1. Validates semver.
2. Updates `VERSION`.
3. Commits `main.sh` + `VERSION` + `CHANGELOG.md`.
4. Creates annotated git tag.

After script completes:

```bash
git push origin main --tags
```

## Recommended release checklist

1. CI is green on `main`.
2. `CHANGELOG.md` is updated.
3. `main.sh` `BOOTSTRAP_VERSION` matches intended release.
4. `VERSION` matches intended release.
5. Tag `v<version>` created and pushed.
6. `refs/tags/v<version>^{}` matches released commit.
7. Optional: publish signed release artifacts.

## Why main.sh version sync is critical

Short bootstrap (`https://bootstrap.cocoit.cz`) resolves a pinned tarball URL from:

- `main.sh` -> `PINNED_REPO_TARBALL_URL` -> `v${BOOTSTRAP_VERSION}`

If `BOOTSTRAP_VERSION` is stale, users running the short command will fetch older code even if `main` is newer.
