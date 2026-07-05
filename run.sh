#!/usr/bin/env bash
# Runs the full LibreLock stack (backend API + frontend web) via Docker Compose
# Usage: ./run.sh [up|down] [extra docker compose down args, eg. -v] (default: up)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-up}"
shift || true

if [ -f "$SCRIPT_DIR/librelock-server/docker-compose.yml" ]; then
    BASE_DIR="$SCRIPT_DIR"
else
    BASE_DIR="$SCRIPT_DIR/.."
fi
SERVER_DIR="$BASE_DIR/librelock-server"
WEB_DIR="$BASE_DIR/librelock-web"

for dir in "$SERVER_DIR" "$WEB_DIR"; do
    if [ ! -f "$dir/docker-compose.yml" ]; then
        echo "Error: $dir/docker-compose.yml not found. Expected librelock-server and librelock-web as siblings of librelock-readme, or alongside run.sh." >&2
        exit 1
    fi
done

if [ ! -f "$SERVER_DIR/.env" ]; then
    echo "Creating $SERVER_DIR/.env from .env.example"
    cp "$SERVER_DIR/.env.example" "$SERVER_DIR/.env"
fi

case "$ACTION" in
    up)
        (cd "$SERVER_DIR" && docker compose up -d --build)
        (cd "$WEB_DIR" && docker compose up -d --build)

        echo
        echo "Testing API..."
        API_OK=""
        for _ in $(seq 1 10); do
            if curl -fsS http://localhost:8000/ >/dev/null 2>&1; then
                API_OK=1
                break
            fi
            sleep 1
        done
        if [ -n "$API_OK" ]; then
            echo "API OK"
        else
            echo "Warning: API did not respond at http://localhost:8000 - check 'docker compose logs' in $SERVER_DIR." >&2
        fi

        echo
        echo "LibreLock is running:"
        echo "    Web: http://localhost:1401"
        echo "    API: http://localhost:8000"

        if command -v xdg-open >/dev/null 2>&1; then
            xdg-open "http://localhost:1401" >/dev/null 2>&1 &
        elif command -v open >/dev/null 2>&1; then
            open "http://localhost:1401" >/dev/null 2>&1 &
        fi
        ;;
    down)
        (cd "$WEB_DIR" && docker compose down "$@")
        (cd "$SERVER_DIR" && docker compose down "$@")
        ;;
    *)
        echo "Usage: $0 [up|down] [extra docker compose down args, eg. -v]" >&2
        exit 1
        ;;
esac
