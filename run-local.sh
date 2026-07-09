#!/usr/bin/env bash
# Runs the full LibreLock stack (backend API + frontend web) locally without Docker.
# Requires Go and Node.js (npm). Ctrl-C stops both.
# Usage: ./run-local.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "$SCRIPT_DIR/librelock-server" ]; then
    BASE_DIR="$SCRIPT_DIR"
else
    BASE_DIR="$SCRIPT_DIR/.."
fi
SERVER_DIR="$BASE_DIR/librelock-server"
WEB_DIR="$BASE_DIR/librelock-web"

for dir in "$SERVER_DIR" "$WEB_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "Error: $dir not found. Expected librelock-server and librelock-web as siblings of librelock-readme, or alongside run-local.sh." >&2
        exit 1
    fi
done

command -v go >/dev/null 2>&1 || { echo "Error: go not found. Install Go first." >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "Error: npm not found. Install Node.js first." >&2; exit 1; }

if [ ! -f "$SERVER_DIR/.env" ]; then
    echo "Creating $SERVER_DIR/.env from .env.example"
    cp "$SERVER_DIR/.env.example" "$SERVER_DIR/.env"
fi

if [ ! -d "$WEB_DIR/node_modules" ]; then
    echo "Installing frontend dependencies..."
    (cd "$WEB_DIR" && npm install)
fi

SERVER_PID=""
WEB_PID=""
cleanup() {
    echo
    echo "Stopping..."
    [ -n "$WEB_PID" ] && kill "$WEB_PID" 2>/dev/null || true
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Starting API..."
(
    cd "$SERVER_DIR"
    set -a
    . ./.env
    set +a
    exec go run .
) &
SERVER_PID=$!

echo "Starting web..."
(
    cd "$WEB_DIR"
    npm run build
    npm run preview -- --port 1401
) &
WEB_PID=$!

echo
echo "LibreLock is running:"
echo "    Web: http://localhost:1401"
echo "    API: http://localhost:8000"
echo "Press Ctrl-C to stop."

wait
