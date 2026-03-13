# ---------------------------------------------------------------
# ClawProxy Installer - Windows PowerShell 5+
# Usage: irm https://raw.githubusercontent.com/malek2662/cp-dist/main/install.ps1 | iex
# ---------------------------------------------------------------
param(
    [switch]$NonInteractive,
    [int]$PortParam = 0
)

$ErrorActionPreference = "Stop"

# --- Config ---
# UPDATE THESE before distributing:
$DOWNLOAD_URL = "https://github.com/malek2662/cp-dist/releases/download/v1.0.4/clawproxy.tgz.enc"
$DIST_PASSWORD = 'Cl@wPr0xy$2026!SecureDist#K9x'

# --- Colors ---
function Write-Success { param([string]$msg) Write-Host "[OK]  $msg" -ForegroundColor Green }
function Write-Warn    { param([string]$msg) Write-Host "[!!]  $msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$msg) Write-Host "[ERR] $msg" -ForegroundColor Red }
function Write-Head    { param([string]$msg) Write-Host "`n$msg`n" -ForegroundColor Cyan }

# --- Banner ---
Write-Host ""
Write-Host "  ClawProxy Installer" -ForegroundColor Cyan
Write-Host "  AI Routing Proxy - Multi-provider, Key Rotation, Dashboard" -ForegroundColor DarkGray
Write-Host ""

# --- Step 1: Check / Install Node.js ---
Write-Head "Checking prerequisites..."

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
$needNodeInstall = $false

if (-not $nodeCmd) {
    $needNodeInstall = $true
} else {
    $nodeVersion = (node -v) -replace 'v', ''
    $nodeMajor = [int]($nodeVersion.Split('.')[0])
    if ($nodeMajor -lt 18) {
        Write-Warn "Node.js version $nodeVersion is too old. Required: >= 18"
        $needNodeInstall = $true
    }
}

if ($needNodeInstall) {
    Write-Warn "Node.js 22 is required. Attempting to install..."

    # Try winget first (available on Windows 10 1709+)
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "  Installing Node.js 22 via winget..." -ForegroundColor DarkGray
        winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --silent
        # Refresh PATH for this session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } else {
        # Fallback: download and install MSI silently
        Write-Host "  winget not available. Downloading Node.js installer..." -ForegroundColor DarkGray
        $nodeInstallerUrl = "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi"
        $nodeInstallerPath = Join-Path $env:TEMP "node_installer.msi"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $nodeInstallerUrl -OutFile $nodeInstallerPath -UseBasicParsing
            Write-Host "  Installing Node.js (this may take a moment)..." -ForegroundColor DarkGray
            Start-Process msiexec.exe -ArgumentList "/i `"$nodeInstallerPath`" /qn /norestart" -Wait -NoNewWindow
            Remove-Item $nodeInstallerPath -Force -ErrorAction SilentlyContinue
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        } catch {
            Write-Err "Failed to download Node.js installer: $_"
        }
    }

    # Verify Node.js is now available
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) {
        Write-Err "Failed to install Node.js. Please install manually:"
        Write-Host "  https://nodejs.org"
        Write-Host "  Or: winget install OpenJS.NodeJS.LTS"
        exit 1
    }
    $nodeVersion = (node -v) -replace 'v', ''
}
Write-Success "Node.js v$nodeVersion detected"

$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npmCmd) {
    Write-Err "npm is not found. This usually comes with Node.js. Please reinstall Node.js from https://nodejs.org"
    exit 1
}
$npmVersion = npm -v
Write-Success "npm v$npmVersion detected"

# --- Step 2: Ask for PORT ---
Write-Head "Configuration"

$DEFAULT_PORT = 3030

# Determine if we are in non-interactive mode (CI, piped, or explicit flag)
$isNonInteractive = $NonInteractive -or $env:CI -or $env:CLAWPROXY_NONINTERACTIVE

if ($PortParam -gt 0) {
    $Port = $PortParam
} elseif ($env:CLAWPROXY_PORT) {
    $Port = [int]$env:CLAWPROXY_PORT
} elseif ($isNonInteractive) {
    $Port = $DEFAULT_PORT
} else {
    $UserPort = Read-Host "  Enter port for ClawProxy (default: $DEFAULT_PORT)"
    if ([string]::IsNullOrWhiteSpace($UserPort)) {
        $Port = $DEFAULT_PORT
    } else {
        $Port = [int]$UserPort
    }
}

if ($Port -ne $DEFAULT_PORT) {
    Write-Warn "Using custom port: $Port"
    $env:PORT = $Port
    # Save to env file for persistence
    $envFile = Join-Path $HOME ".clawproxy.env"
    "PORT=$Port" | Set-Content $envFile
    Write-Success "Port saved to $envFile"
} else {
    Write-Success "Using default port: $Port"
}

# --- Step 3: Download and Decrypt ClawProxy Package ---
Write-Head "Downloading ClawProxy..."

$tempDir = Join-Path $env:TEMP "clawproxy_install_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$encryptedFile = Join-Path $tempDir "clawproxy.tgz.enc"
$decryptedFile = Join-Path $tempDir "clawproxy.tgz"

Write-Host "  Downloading encrypted package..." -ForegroundColor DarkGray
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $encryptedFile -UseBasicParsing
} catch {
    Write-Err "Download failed: $_"
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Success "Package downloaded"

Write-Host "  Decrypting package..." -ForegroundColor DarkGray

# Build the Node.js decryption script content and write to file
$decryptScriptLines = @(
    "const crypto = require('crypto');"
    "const fs = require('fs');"
    ""
    "const password = process.argv[2];"
    "const inputFile = process.argv[3];"
    "const outputFile = process.argv[4];"
    ""
    "const encData = fs.readFileSync(inputFile);"
    ""
    "// openssl enc format: Salted__<8 bytes salt><encrypted data>"
    "const header = encData.slice(0, 8).toString('utf8');"
    "if (header !== 'Salted__') {"
    "    console.error('Invalid encrypted file format');"
    "    process.exit(1);"
    "}"
    ""
    "const salt = encData.slice(8, 16);"
    "const encrypted = encData.slice(16);"
    ""
    "// Derive key and IV using PBKDF2 (matching openssl enc -pbkdf2 -iter 100000)"
    "const keyIv = crypto.pbkdf2Sync(password, salt, 100000, 48, 'sha256');"
    "const key = keyIv.slice(0, 32);"
    "const iv = keyIv.slice(32, 48);"
    ""
    "const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);"
    "const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);"
    ""
    "fs.writeFileSync(outputFile, decrypted);"
    "console.log('OK');"
)

$decryptScriptFile = Join-Path $tempDir "decrypt.js"
$decryptScriptLines | Set-Content $decryptScriptFile -Encoding UTF8

try {
    $result = node $decryptScriptFile $DIST_PASSWORD $encryptedFile $decryptedFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Decryption failed: $result"
    }
} catch {
    Write-Err "Decryption failed: $_"
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Success "Package decrypted"

# --- Step 4: Install ClawProxy ---
Write-Head "Installing ClawProxy..."

# Backup existing database before npm install (npm replaces the entire package directory)
$npmPrefix = npm config get prefix 2>$null
$clawDir = Join-Path $npmPrefix "node_modules\clawproxy"
$dbBackup = $null

# Check root-level DB
if (Test-Path (Join-Path $clawDir "clawproxy.db")) {
    $dbBackup = Join-Path $env:TEMP "clawproxy_backup_$(Get-Random)"
    New-Item -ItemType Directory -Path $dbBackup -Force | Out-Null
    Copy-Item (Join-Path $clawDir "clawproxy.db") $dbBackup -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $clawDir "clawproxy.db-wal") $dbBackup -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $clawDir "clawproxy.db-shm") $dbBackup -Force -ErrorAction SilentlyContinue
    Write-Success "Backed up existing database"
}
# Check backend-level DB
if (Test-Path (Join-Path $clawDir "backend\clawproxy.db")) {
    if (-not $dbBackup) {
        $dbBackup = Join-Path $env:TEMP "clawproxy_backup_$(Get-Random)"
        New-Item -ItemType Directory -Path $dbBackup -Force | Out-Null
    }
    Copy-Item (Join-Path $clawDir "backend\clawproxy.db") (Join-Path $dbBackup "backend_clawproxy.db") -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $clawDir "backend\clawproxy.db-wal") (Join-Path $dbBackup "backend_clawproxy.db-wal") -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $clawDir "backend\clawproxy.db-shm") (Join-Path $dbBackup "backend_clawproxy.db-shm") -Force -ErrorAction SilentlyContinue
    Write-Success "Backed up existing backend database"
}

npm install -g $decryptedFile
if ($LASTEXITCODE -ne 0) {
    Write-Err "npm install failed."
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Clean up temp files
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Restore database after install
if ($dbBackup) {
    $clawDir = Join-Path (npm config get prefix 2>$null) "node_modules\clawproxy"
    if (Test-Path (Join-Path $dbBackup "clawproxy.db")) {
        Copy-Item (Join-Path $dbBackup "clawproxy.db") (Join-Path $clawDir "clawproxy.db") -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $dbBackup "clawproxy.db-wal") (Join-Path $clawDir "clawproxy.db-wal") -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $dbBackup "clawproxy.db-shm") (Join-Path $clawDir "clawproxy.db-shm") -Force -ErrorAction SilentlyContinue
        Write-Success "Restored existing database"
    }
    if (Test-Path (Join-Path $dbBackup "backend_clawproxy.db")) {
        Copy-Item (Join-Path $dbBackup "backend_clawproxy.db") (Join-Path $clawDir "backend\clawproxy.db") -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $dbBackup "backend_clawproxy.db-wal") (Join-Path $clawDir "backend\clawproxy.db-wal") -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $dbBackup "backend_clawproxy.db-shm") (Join-Path $clawDir "backend\clawproxy.db-shm") -Force -ErrorAction SilentlyContinue
        Write-Success "Restored existing backend database"
    }
    Remove-Item $dbBackup -Recurse -Force -ErrorAction SilentlyContinue
}

# Verify clawproxy command is available
$clawCmd = Get-Command clawproxy -ErrorAction SilentlyContinue
if (-not $clawCmd) {
    # Try refreshing PATH first
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    $clawCmd = Get-Command clawproxy -ErrorAction SilentlyContinue
}
if (-not $clawCmd) {
    Write-Err "clawproxy command not found after install."
    Write-Host ""
    Write-Host "  Make sure npm global bin is in your PATH:"
    $npmPrefix = npm config get prefix
    Write-Host "  Add to PATH: $npmPrefix"
    exit 1
}

Write-Success "ClawProxy installed globally"

# --- Step 4.5: Copy Documentation to User Documents ---
Write-Head "Setting up Documentation..."

$docsDir = Join-Path $HOME "Documents\ClawProxy Documentation"
if (-not (Test-Path (Join-Path $HOME "Documents"))) {
    $docsDir = Join-Path $HOME "ClawProxy-Documentation"
}
New-Item -ItemType Directory -Path $docsDir -Force | Out-Null

if ($clawDir -and (Test-Path $clawDir)) {
    function Copy-Safe {
        param($file, $dest)
        if (Test-Path $file) {
            Copy-Item $file $dest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Copy-Safe (Join-Path $clawDir "README.md") $docsDir
    Copy-Safe (Join-Path $clawDir "QUICKSTART.md") $docsDir
    Copy-Safe (Join-Path $clawDir "QUICKSTART.pdf") $docsDir
    Copy-Safe (Join-Path $clawDir "OPENCLAW_PROVIDERS.md") $docsDir
    Copy-Safe (Join-Path $clawDir "OPENCLAW_PROVIDERS.pdf") $docsDir
    Copy-Safe (Join-Path $clawDir "ClawProxy-Knowledge-Base.md") $docsDir
    Copy-Safe (Join-Path $clawDir "assets") $docsDir

    Write-Success "Documentation copied to $docsDir"
} else {
    Write-Warn "Could not find ClawProxy directory to copy documentation."
}

# --- Step 5: Install node-windows dependency ---
Write-Head "Installing Windows service dependency..."

$clawDir = Split-Path (Split-Path (Get-Command clawproxy).Source)
Push-Location $clawDir
npm install node-windows
if ($LASTEXITCODE -ne 0) {
    Write-Warn "node-windows installation failed. Service functionality may be limited."
}
Pop-Location

Write-Success "node-windows installed"

# --- Step 6: Install as service ---
Write-Head "Setting up Windows service..."

if ($Port -ne $DEFAULT_PORT) {
    clawproxy install --port $Port --no-open
} else {
    clawproxy install --no-open
}

# --- Done ---
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  ClawProxy is installed and running!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard:  " -NoNewline; Write-Host "http://localhost:$Port" -ForegroundColor Cyan
Write-Host "  Proxy:      " -NoNewline; Write-Host "http://localhost:$Port/proxy/{provider}/v1" -ForegroundColor Cyan
Write-Host ""
Write-Host "  " -NoNewline; Write-Host " Knowledge Base: " -NoNewline -ForegroundColor White; Write-Host "We created a 'ClawProxy Documentation' folder in your Documents!" -ForegroundColor Green
Write-Host ""
Write-Host "  Manage with:" -ForegroundColor DarkGray
Write-Host "    clawproxy status"
Write-Host "    clawproxy stop"
Write-Host "    clawproxy restart"
Write-Host "    clawproxy logs"
Write-Host "    clawproxy uninstall"
Write-Host ""
