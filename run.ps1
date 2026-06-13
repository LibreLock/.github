# Runs the full LibreLock stack (backend API + Postgres + frontend web) via Docker Compose
# Usage: ./run.ps1 [up|down] [extra docker compose down args, eg. -v] (default: up)

param(
    [ValidateSet("up", "down")]
    [string]$Action = "up",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
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

    $passwordBytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($passwordBytes)
    $DbPassword = ($passwordBytes | ForEach-Object { $_.ToString("x2") }) -join ''
    (Get-Content $ServerEnv) -replace '^DB_PASSWORD=.*', "DB_PASSWORD=$DbPassword" | Set-Content $ServerEnv
    Write-Host "Generated a random database password in $ServerEnv"
}

switch ($Action) {
    "up" {
        Push-Location $ServerDir
        docker compose up -d --build
        Pop-Location

        Push-Location $WebDir
        docker compose up -d --build
        Pop-Location

        $envContent = Get-Content $ServerEnv
        $DbUser = (($envContent | Where-Object { $_ -match '^DB_USER=' }) -replace '^DB_USER=', '').Trim()
        $DbName = (($envContent | Where-Object { $_ -match '^DB_NAME=' }) -replace '^DB_NAME=', '').Trim()
        if (-not $DbUser) { $DbUser = "librelock" }
        if (-not $DbName) { $DbName = "librelock" }

        Write-Host ""
        Write-Host "Testing database connection..."
        Push-Location $ServerDir
        try {
            docker compose exec -T db psql -U $DbUser -d $DbName -c "SELECT 1;" *> $null
            $dbOk = $LASTEXITCODE -eq 0
        } catch {
            $dbOk = $false
        }
        Pop-Location

        if ($dbOk) {
            Write-Host "Database connection OK"
        } else {
            Write-Warning "Could not connect to the database with DB_USER/DB_NAME from $ServerEnv."
            Write-Warning "If you changed these after the first run, the Postgres data volume still has the old credentials - update .env to match or remove the volume to reinitialize."
        }

        Write-Host ""
        Write-Host "LibreLock is running:"
        Write-Host "    Web: http://localhost:1401"
        Write-Host "    API: http://localhost:8000"
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
