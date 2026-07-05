# Runs the full LibreLock stack (backend API + frontend web) via Docker Compose
# Usage: ./run.ps1 [up|down] [extra docker compose down args, eg. -v] (default: up)

param(
    [ValidateSet("up", "down")]
    [string]$Action = "up",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (Test-Path (Join-Path $ScriptDir "librelock-server\docker-compose.yml")) {
    $BaseDir = $ScriptDir
} else {
    $BaseDir = Join-Path $ScriptDir ".."
}
$ServerDir = Join-Path $BaseDir "librelock-server"
$WebDir = Join-Path $BaseDir "librelock-web"

foreach ($dir in @($ServerDir, $WebDir)) {
    if (-not (Test-Path (Join-Path $dir "docker-compose.yml"))) {
        Write-Error "Error: $dir\docker-compose.yml not found. Expected librelock-server and librelock-web as siblings of librelock-readme, or alongside run.ps1."
        exit 1
    }
}

$ServerEnv = Join-Path $ServerDir ".env"
if (-not (Test-Path $ServerEnv)) {
    Write-Host "Creating $ServerEnv from .env.example"
    Copy-Item (Join-Path $ServerDir ".env.example") $ServerEnv
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
        Write-Host "Testing API..."
        $apiOk = $false
        for ($i = 0; $i -lt 10; $i++) {
            try {
                Invoke-WebRequest -Uri "http://localhost:8000/" -UseBasicParsing -TimeoutSec 2 *> $null
                $apiOk = $true
                break
            } catch {
                Start-Sleep -Seconds 1
            }
        }

        if ($apiOk) {
            Write-Host "API OK"
        } else {
            Write-Warning "API did not respond at http://localhost:8000 - check 'docker compose logs' in $ServerDir."
        }

        Write-Host ""
        Write-Host "LibreLock is running:"
        Write-Host "    Web: http://localhost:1401"
        Write-Host "    API: http://localhost:8000"

        Start-Process "http://localhost:1401"
    }
    "down" {
        Push-Location $WebDir
        docker compose down @ExtraArgs
        Pop-Location

        Push-Location $ServerDir
        docker compose down @ExtraArgs
        Pop-Location
    }
}
