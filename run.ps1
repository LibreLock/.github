# Runs the full LibreLock stack (backend API + Postgres + frontend web) via Docker Compose
# Usage: ./run.ps1 [up|down] (default: up)

param(
    [ValidateSet("up", "down")]
    [string]$Action = "up"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServerDir = Join-Path $ScriptDir "..\librelock-server"
$WebDir = Join-Path $ScriptDir "..\librelock-web"

foreach ($dir in @($ServerDir, $WebDir)) {
    if (-not (Test-Path (Join-Path $dir "docker-compose.yml"))) {
        Write-Error "Error: $dir\docker-compose.yml not found. Expected librelock-server and librelock-web as sibling directories of librelock-readme."
        exit 1
    }
}

$ServerEnv = Join-Path $ServerDir ".env"
if (-not (Test-Path $ServerEnv)) {
    Write-Host "Creating $ServerEnv from .env.example"
    Copy-Item (Join-Path $ServerDir ".env.example") $ServerEnv
    Write-Host "Edit $ServerEnv to set your database credentials (DB_USER, DB_PASSWORD, DB_NAME) before continuing."
}

switch ($Action) {
    "up" {
        Push-Location $ServerDir
        docker compose up -d --build
        Pop-Location

        Push-Location $WebDir
        docker compose up -d --build
        Pop-Location

        Write-Host ""
        Write-Host "LibreLock is running:"
        Write-Host "    Web: http://localhost:1401"
        Write-Host "    API: http://localhost:8000"
    }
    "down" {
        Push-Location $WebDir
        docker compose down
        Pop-Location

        Push-Location $ServerDir
        docker compose down
        Pop-Location
    }
}
