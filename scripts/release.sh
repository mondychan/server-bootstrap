#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-$(cat VERSION)}"
TAG="v${VERSION}"

if [[ -z "$VERSION" ]]; then
  echo "ERROR: version is empty" >&2
  exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: version must match semver (e.g. 1.2.3)" >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "ERROR: tag already exists: $TAG" >&2
  exit 1
fi

echo "$VERSION" > VERSION

git add VERSION CHANGELOG.md
git commit -m "release: ${TAG}" || true
git tag -a "$TAG" -m "Release ${TAG}"

echo "Created tag ${TAG}."
echo "Next: git push origin main --tags"
