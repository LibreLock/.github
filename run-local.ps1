# Runs the full LibreLock stack (backend API + frontend web) locally without Docker.
# Requires Go and Node.js (npm). Ctrl-C stops both.
# Usage: ./run-local.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (Test-Path (Join-Path $ScriptDir "librelock-server")) {
    $BaseDir = $ScriptDir
} else {
    $BaseDir = Join-Path $ScriptDir ".."
}
$ServerDir = Join-Path $BaseDir "librelock-server"
$WebDir = Join-Path $BaseDir "librelock-web"

foreach ($dir in @($ServerDir, $WebDir)) {
    if (-not (Test-Path $dir)) {
        Write-Error "Error: $dir not found. Expected librelock-server and librelock-web as siblings of librelock-readme, or alongside run-local.ps1."
        exit 1
    }
}

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Error "Error: go not found. Install Go first."
    exit 1
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Error "Error: npm not found. Install Node.js first."
    exit 1
}

$ServerEnv = Join-Path $ServerDir ".env"
if (-not (Test-Path $ServerEnv)) {
    Write-Host "Creating $ServerEnv from .env.example"
    Copy-Item (Join-Path $ServerDir ".env.example") $ServerEnv
}

if (-not (Test-Path (Join-Path $WebDir "node_modules"))) {
    Write-Host "Installing frontend dependencies..."
    Push-Location $WebDir
    npm install
    Pop-Location
}

# Load .env into this process so the Go server inherits it
foreach ($line in Get-Content $ServerEnv) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    $name, $value = $line -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
}

Write-Host "Starting API..."
$Server = Start-Process go -ArgumentList "run", "." -WorkingDirectory $ServerDir -NoNewWindow -PassThru

Write-Host "Starting web..."
$Web = Start-Process npm -ArgumentList "run", "dev" -WorkingDirectory $WebDir -NoNewWindow -PassThru

Write-Host ""
Write-Host "LibreLock is running:"
Write-Host "    Web: http://localhost:1401"
Write-Host "    API: http://localhost:8000"
Write-Host "Press Ctrl-C to stop."

try {
    Wait-Process -Id $Server.Id, $Web.Id
} finally {
    foreach ($proc in @($Web, $Server)) {
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
