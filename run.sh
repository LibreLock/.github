#!/usr/bin/env bash
# Runs the full LibreLock stack (backend API + Postgres + frontend web) via Docker Compose
# Usage: ./run.sh [up|down] [extra docker compose down args, eg. -v] (default: up)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/../librelock-server"
WEB_DIR="$SCRIPT_DIR/../librelock-web"
ACTION="${1:-up}"
shift || true

for dir in "$SERVER_DIR" "$WEB_DIR"; do
    if [ ! -f "$dir/docker-compose.yml" ]; then
        echo "Error: $dir/docker-compose.yml not found. Expected librelock-server and librelock-web as sibling directories of librelock-readme." >&2
        exit 1
    fi
done

if [ ! -f "$SERVER_DIR/.env" ]; then
    echo "Creating $SERVER_DIR/.env from .env.example"
    cp "$SERVER_DIR/.env.example" "$SERVER_DIR/.env"

    DB_PASSWORD="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    sed -i.bak "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" "$SERVER_DIR/.env"
    rm -f "$SERVER_DIR/.env.bak"
    echo "Generated a random database password in $SERVER_DIR/.env"
fi

case "$ACTION" in
    up)
        (cd "$SERVER_DIR" && docker compose up -d --build)
        (cd "$WEB_DIR" && docker compose up -d --build)

        DB_USER="$(grep -E '^DB_USER=' "$SERVER_DIR/.env" | cut -d= -f2-)" || true
        DB_NAME="$(grep -E '^DB_NAME=' "$SERVER_DIR/.env" | cut -d= -f2-)" || true
        echo
        echo "Testing database connection..."
        if (cd "$SERVER_DIR" && docker compose exec -T db psql -U "${DB_USER:-librelock}" -d "${DB_NAME:-librelock}" -c "SELECT 1;" >/dev/null 2>&1); then
            echo "Database connection OK"
        else
            echo "Warning: could not connect to the database with DB_USER/DB_NAME from $SERVER_DIR/.env." >&2
            echo "If you changed these after the first run, the Postgres data volume still has the old credentials - update .env to match or remove the volume to reinitialize." >&2
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
