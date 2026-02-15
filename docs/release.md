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
3. Commits `VERSION` + `CHANGELOG.md`.
4. Creates annotated git tag.

After script completes:

```bash
git push origin main --tags
```

## Recommended release checklist

1. CI is green on `main`.
2. `CHANGELOG.md` is updated.
3. `VERSION` matches intended tag.
4. Tag created and pushed.
5. Optional: publish signed release artifacts.
