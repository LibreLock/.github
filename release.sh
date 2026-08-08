#!/usr/bin/env bash

# Tags a LibreLock release in both code repositories at once
# One version number covers the app and the API - they are built from the same tag, published under the same image tag, and run together via LIBRELOCK_VERSION
# Usage: ./release.sh 0.1.0

set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "Usage: $0 <version>   eg. $0 0.1.0" >&2
    exit 1
fi
TAG="v$VERSION"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/librelock-server/.git" ]; then
    BASE_DIR="$SCRIPT_DIR"
else
    BASE_DIR="$SCRIPT_DIR/.."
fi
REPOS=("$BASE_DIR/librelock-server" "$BASE_DIR/librelock-web")

# Every check runs against both repositories before anything is tagged
# A release that exists in one repository and not the other is the exact failure this script prevents
for repo in "${REPOS[@]}"; do
    name="$(basename "$repo")"

    [ -d "$repo/.git" ] || { echo "Error: $repo is not a git repository." >&2; exit 1; }

    branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
    [ "$branch" = "main" ] || { echo "Error: $name is on '$branch', not main." >&2; exit 1; }

    if [ -n "$(git -C "$repo" status --porcelain)" ]; then
        echo "Error: $name has uncommitted changes." >&2
        exit 1
    fi

    git -C "$repo" fetch --quiet origin main --tags

    if [ "$(git -C "$repo" rev-parse HEAD)" != "$(git -C "$repo" rev-parse origin/main)" ]; then
        echo "Error: $name is not in sync with origin/main - push or pull first." >&2
        exit 1
    fi

    if git -C "$repo" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        echo "Error: $name already has tag $TAG." >&2
        exit 1
    fi
done

echo "Releasing LibreLock $TAG"
for repo in "${REPOS[@]}"; do
    printf '    %-18s %s\n' "$(basename "$repo")" "$(git -C "$repo" log -1 --format='%h %s')"
done
echo
echo "This pushes $TAG to both repositories, which publishes ghcr.io images. Tags are hard to retract once pulled."
read -r -p "Continue? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

for repo in "${REPOS[@]}"; do
    git -C "$repo" tag -a "$TAG" -m "LibreLock $TAG"
    git -C "$repo" push --quiet origin "$TAG"
    echo "Tagged and pushed $(basename "$repo") $TAG"
done

echo
echo "Done. The publish workflows are now building:"
echo "    https://github.com/LibreLock/librelock-server/actions"
echo "    https://github.com/LibreLock/librelock-web/actions"
echo
echo "When both are green, ghcr.io/librelock/librelock-{server,web}:$VERSION exist,"
echo "and instances on LIBRELOCK_VERSION=latest pick it up on the next 'docker compose pull'."
