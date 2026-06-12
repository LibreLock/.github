#!/usr/bin/env bash
# Runs the full LibreLock stack (backend API + Postgres + frontend web) via Docker Compose
# Usage: ./run.sh [up|down] (default: up)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/../librelock-server"
WEB_DIR="$SCRIPT_DIR/../librelock-web"
ACTION="${1:-up}"

for dir in "$SERVER_DIR" "$WEB_DIR"; do
    if [ ! -f "$dir/docker-compose.yml" ]; then
        echo "Error: $dir/docker-compose.yml not found. Expected librelock-server and librelock-web as sibling directories of librelock-readme." >&2
        exit 1
    fi
done

if [ ! -f "$SERVER_DIR/.env" ]; then
    echo "Creating $SERVER_DIR/.env from .env.example"
    cp "$SERVER_DIR/.env.example" "$SERVER_DIR/.env"
    echo "Edit $SERVER_DIR/.env to set your database credentials (DB_USER, DB_PASSWORD, DB_NAME) before continuing."
fi

case "$ACTION" in
    up)
        (cd "$SERVER_DIR" && docker compose up -d --build)
        (cd "$WEB_DIR" && docker compose up -d --build)
        echo
        echo "LibreLock is running:"
        echo "    Web: http://localhost:1401"
        echo "    API: http://localhost:8000"
        ;;
    down)
        (cd "$WEB_DIR" && docker compose down)
        (cd "$SERVER_DIR" && docker compose down)
        ;;
    *)
        echo "Usage: $0 [up|down]" >&2
        exit 1
        ;;
esac
