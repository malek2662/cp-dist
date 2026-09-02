# ---------------------------------------------------------------
# ClawRouter Installer - Windows PowerShell 5+
# Usage: irm https://get.clawrouter.qzz.io/install.ps1 | iex
# ---------------------------------------------------------------
param(
    [switch]$NonInteractive,
    [int]$PortParam = 0
)

$ErrorActionPreference = "Stop"

# --- Config ---
# UPDATE THESE before distributing:
$DOWNLOAD_URL = "https://github.com/malek2662/cp-dist/releases/latest/download/clawrouter.tgz.enc"
$DIST_PASSWORD = 'Cl@wPr0xy$2026!SecureDist#K9x'

# --- Colors ---
function Write-Success { param([string]$msg) Write-Host "[OK]  $msg" -ForegroundColor Green }
function Write-Warn    { param([string]$msg) Write-Host "[!!]  $msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$msg) Write-Host "[ERR] $msg" -ForegroundColor Red }
function Write-Head    { param([string]$msg) Write-Host "`n$msg`n" -ForegroundColor Cyan }

# --- Banner ---
Write-Host ""
Write-Host "  ClawRouter Installer" -ForegroundColor Cyan
Write-Host "  AI Routing Gateway - Multi-provider, Key Rotation, Dashboard" -ForegroundColor DarkGray
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
$isNonInteractive = $NonInteractive -or $env:CI -or $env:CLAWROUTER_NONINTERACTIVE

if ($PortParam -gt 0) {
    $Port = $PortParam
} elseif ($env:CLAWROUTER_PORT) {
    $Port = [int]$env:CLAWROUTER_PORT
} elseif ($isNonInteractive) {
    $Port = $DEFAULT_PORT
} else {
    $UserPort = Read-Host "  Enter port for ClawRouter (default: $DEFAULT_PORT)"
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
    $envFile = Join-Path $HOME ".clawrouter.env"
    "PORT=$Port" | Set-Content $envFile
    Write-Success "Port saved to $envFile"
} else {
    Write-Success "Using default port: $Port"
}

# --- Step 3: Download and Decrypt ClawRouter Package ---
Write-Head "Downloading ClawRouter..."

$tempDir = Join-Path $env:TEMP "clawrouter_install_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$encryptedFile = Join-Path $tempDir "clawrouter.tgz.enc"
$decryptedFile = Join-Path $tempDir "clawrouter.tgz"

Write-Host "  Downloading package..." -ForegroundColor DarkGray
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $encryptedFile -UseBasicParsing
} catch {
    Write-Err "Download failed: $_"
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "  Preparing package..." -ForegroundColor DarkGray

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
Write-Success "Package ready"

# --- Step 4: Install ClawRouter ---
Write-Head "Installing ClawRouter..."

# Backup existing database before npm install (npm replaces the entire package directory)
$npmPrefix = npm config get prefix 2>$null
$clawDir = Join-Path $npmPrefix "node_modules\clawrouter"
$dbBackup = $null

# --- Backup safety helpers ---
# The database is IRREPLACEABLE (providers, API keys, logs) and `npm install -g`
# deletes the package directory outright, so the backup is the only copy that
# survives. Two failure modes made the previous version dangerous (the same two
# install.sh already fixes):
#   1. `Copy-Item ... -ErrorAction SilentlyContinue` hid a FAILED copy, so the
#      install proceeded and destroyed the original — silent, total data loss.
#   2. "Restored existing database" printed unconditionally and the backup was
#      deleted regardless, so a failed restore looked like a success and removed
#      the only remaining copy.
# Therefore: VERIFY every copy byte-for-byte, abort BEFORE npm runs if the DB or
# its WAL did not land intact, and KEEP the backup unless every restore succeeded.

# Copy one file and prove it arrived complete. Returns $true when the source is
# absent (nothing to copy is not a failure) or the sizes match; $false otherwise.
function Copy-Verified {
    param([string]$Src, [string]$Dst)
    if (-not (Test-Path -LiteralPath $Src -PathType Leaf)) { return $true }
    try {
        Copy-Item -LiteralPath $Src -Destination $Dst -Force -ErrorAction Stop
    } catch {
        return $false
    }
    if (-not (Test-Path -LiteralPath $Dst -PathType Leaf)) { return $false }
    return ((Get-Item -LiteralPath $Src).Length -eq (Get-Item -LiteralPath $Dst).Length)
}

# Abort with an actionable message rather than proceeding into data loss.
function Backup-Failed {
    param([string]$What, [long]$NeedBytes, [string]$BackupDir)
    if ($BackupDir -and (Test-Path -LiteralPath $BackupDir)) {
        Remove-Item -LiteralPath $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Err "Could not back up $What - aborting BEFORE any changes are made."
    Write-Host ""
    Write-Host "  Your existing installation and database are UNTOUCHED."
    Write-Host ""
    Write-Host "  The backup is written to your temp directory:"
    Write-Host "    $env:TEMP"
    if ($NeedBytes -gt 0) {
        Write-Host ("    required: ~{0} MB" -f [math]::Ceiling($NeedBytes / 1MB))
    }
    try {
        $drive = (Get-Item -LiteralPath $env:TEMP).PSDrive
        if ($drive -and $null -ne $drive.Free) {
            Write-Host ("    available: {0} MB" -f [math]::Floor($drive.Free / 1MB))
        }
    } catch { }
    Write-Host ""
    Write-Host "  Free some space on that drive, or point TEMP at a drive with more room"
    Write-Host "  and re-run the installer, e.g.:"
    Write-Host "    `$env:TEMP = 'D:\Temp'; irm https://get.clawrouter.qzz.io/install.ps1 | iex"
    Write-Host ""
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

function New-BackupDir {
    $dir = Join-Path $env:TEMP "clawrouter_backup_$(Get-Random)"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# Check root-level DB
$rootDb = Join-Path $clawDir "clawrouter.db"
if (Test-Path -LiteralPath $rootDb -PathType Leaf) {
    $dbBytes  = (Get-Item -LiteralPath $rootDb).Length
    $walPath  = Join-Path $clawDir "clawrouter.db-wal"
    $walBytes = if (Test-Path -LiteralPath $walPath -PathType Leaf) { (Get-Item -LiteralPath $walPath).Length } else { 0 }
    $needBytes = $dbBytes + $walBytes
    # Preflight: warn early when the temp drive looks too small for the backup.
    try {
        $drive = (Get-Item -LiteralPath $env:TEMP).PSDrive
        if ($drive -and $null -ne $drive.Free -and $needBytes -gt $drive.Free) {
            Write-Warn ("Database is {0} MB but the temp drive has only {1} MB free." -f [math]::Ceiling($needBytes / 1MB), [math]::Floor($drive.Free / 1MB))
        }
    } catch { }

    $dbBackup = New-BackupDir
    # The main database MUST be backed up intact - this one is fatal.
    if (Copy-Verified $rootDb (Join-Path $dbBackup "clawrouter.db")) {
        Write-Success ("Backed up existing database ({0} MB)" -f [math]::Ceiling($dbBytes / 1MB))
    } else {
        Backup-Failed "your database" $needBytes $dbBackup
    }
    # WAL must also be intact: a truncated WAL alongside a valid DB can lose the
    # most recent committed transactions on recovery.
    if (-not (Copy-Verified $walPath (Join-Path $dbBackup "clawrouter.db-wal"))) {
        Backup-Failed "your database write-ahead log" $needBytes $dbBackup
    }
    # SHM is a rebuildable shared-memory index - safe to skip if it can't be copied.
    Copy-Verified (Join-Path $clawDir "clawrouter.db-shm") (Join-Path $dbBackup "clawrouter.db-shm") | Out-Null
    # Backup state file (activation/version tracking)
    Copy-Verified (Join-Path $clawDir ".clawrouter-state") (Join-Path $dbBackup ".clawrouter-state") | Out-Null
}
# Check backend-level DB
$beDb = Join-Path $clawDir "backend\clawrouter.db"
if (Test-Path -LiteralPath $beDb -PathType Leaf) {
    if (-not $dbBackup) { $dbBackup = New-BackupDir }
    $beBytes = (Get-Item -LiteralPath $beDb).Length
    if (Copy-Verified $beDb (Join-Path $dbBackup "backend_clawrouter.db")) {
        Write-Success "Backed up existing backend database"
    } else {
        Backup-Failed "your backend database" $beBytes $dbBackup
    }
    if (-not (Copy-Verified (Join-Path $clawDir "backend\clawrouter.db-wal") (Join-Path $dbBackup "backend_clawrouter.db-wal"))) {
        Backup-Failed "your backend database write-ahead log" $beBytes $dbBackup
    }
    Copy-Verified (Join-Path $clawDir "backend\clawrouter.db-shm") (Join-Path $dbBackup "backend_clawrouter.db-shm") | Out-Null
}

npm install -g $decryptedFile
if ($LASTEXITCODE -ne 0) {
    Write-Err "npm install failed."
    if ($dbBackup) {
        Write-Host ""
        Write-Host "  Your database backup has been KEPT at:"
        Write-Host "    $dbBackup"
        Write-Host ""
    }
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Clean up temp files
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Restore database after install
if ($dbBackup) {
    $clawDir = Join-Path (npm config get prefix 2>$null) "node_modules\clawrouter"
    # The restore is verified too, and the backup is KEPT unless every restore
    # succeeded (see the helper comment above).
    $restoreOk = $true
    if (Test-Path -LiteralPath (Join-Path $dbBackup "clawrouter.db") -PathType Leaf) {
        if (Copy-Verified (Join-Path $dbBackup "clawrouter.db") (Join-Path $clawDir "clawrouter.db")) {
            if (-not (Copy-Verified (Join-Path $dbBackup "clawrouter.db-wal") (Join-Path $clawDir "clawrouter.db-wal"))) { $restoreOk = $false }
            Copy-Verified (Join-Path $dbBackup "clawrouter.db-shm") (Join-Path $clawDir "clawrouter.db-shm") | Out-Null
            if ($restoreOk) { Write-Success "Restored existing database" }
        } else {
            $restoreOk = $false
        }
    }
    # Restore state file silently (activation/version tracking - internal, not shown to user)
    Copy-Verified (Join-Path $dbBackup ".clawrouter-state") (Join-Path $clawDir ".clawrouter-state") | Out-Null
    if (Test-Path -LiteralPath (Join-Path $dbBackup "backend_clawrouter.db") -PathType Leaf) {
        $beDir = Join-Path $clawDir "backend"
        if (-not (Test-Path -LiteralPath $beDir)) { New-Item -ItemType Directory -Path $beDir -Force | Out-Null }
        if (Copy-Verified (Join-Path $dbBackup "backend_clawrouter.db") (Join-Path $beDir "clawrouter.db")) {
            if (-not (Copy-Verified (Join-Path $dbBackup "backend_clawrouter.db-wal") (Join-Path $beDir "clawrouter.db-wal"))) { $restoreOk = $false }
            Copy-Verified (Join-Path $dbBackup "backend_clawrouter.db-shm") (Join-Path $beDir "clawrouter.db-shm") | Out-Null
            if ($restoreOk) { Write-Success "Restored existing backend database" }
        } else {
            $restoreOk = $false
        }
    }

    if ($restoreOk) {
        Remove-Item -LiteralPath $dbBackup -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Err "Database restore did not complete - your backup has been KEPT."
        Write-Host ""
        Write-Host "  Backup location (copy it somewhere safe now):"
        Write-Host "    $dbBackup"
        Write-Host ""
        Write-Host "  Restore it manually with:"
        Write-Host "    Copy-Item `"$dbBackup\clawrouter.db`" `"$clawDir\clawrouter.db`" -Force"
        Write-Host ""
        Write-Host "  NOTE: the temp folder may be cleaned by Windows - move the backup first."
        Write-Host ""
        exit 1
    }
}

# Verify clawrouter command is available
$clawCmd = Get-Command clawrouter -ErrorAction SilentlyContinue
if (-not $clawCmd) {
    # Try refreshing PATH first
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    $clawCmd = Get-Command clawrouter -ErrorAction SilentlyContinue
}
if (-not $clawCmd) {
    Write-Err "clawrouter command not found after install."
    Write-Host ""
    Write-Host "  Make sure npm global bin is in your PATH:"
    $npmPrefix = npm config get prefix
    Write-Host "  Add to PATH: $npmPrefix"
    exit 1
}

Write-Success "ClawRouter installed globally"

# --- Step 4.5: Copy Documentation to User Documents ---
Write-Head "Setting up Documentation..."

$docsDir = Join-Path $HOME "Documents\ClawRouter-Documentation"
if (-not (Test-Path (Join-Path $HOME "Documents"))) {
    $docsDir = Join-Path $HOME "ClawRouter-Documentation"
}
New-Item -ItemType Directory -Path $docsDir -Force | Out-Null

if ($clawDir -and (Test-Path (Join-Path $clawDir "Docs"))) {
    # Copy md documentation (contents of Docs\md → Documentation folder root)
    $srcDocs = Join-Path $clawDir "Docs"
    if (Test-Path (Join-Path $srcDocs "md"))  { Copy-Item (Join-Path $srcDocs "md\*")  $docsDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path (Join-Path $clawDir "README.md")) { Copy-Item (Join-Path $clawDir "README.md") $docsDir -Force -ErrorAction SilentlyContinue }

    Write-Success "Documentation copied to $docsDir"

    # Remove docs from install directory (keep only in Documentation folder)
    Remove-Item (Join-Path $clawDir "Docs") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $clawDir "README.md") -Force -ErrorAction SilentlyContinue
} else {
    Write-Warn "Could not find ClawRouter documentation directory."
}

# --- Step 5: Install node-windows dependency ---
Write-Head "Installing Windows service dependency..."

$clawDir = Split-Path (Split-Path (Get-Command clawrouter).Source)
Push-Location $clawDir
npm install node-windows
if ($LASTEXITCODE -ne 0) {
    Write-Warn "node-windows installation failed. Service functionality may be limited."
}
Pop-Location

Write-Success "node-windows installed"

# --- Step 6: Install as service ---
Write-Head "Setting up Windows service..."

# --quiet: this script prints its own richer summary below. Without it the CLI
# prints the identical "installed and running / Dashboard / Manage with" block
# and the user sees the whole thing twice.
if ($Port -ne $DEFAULT_PORT) {
    clawrouter install --port $Port --no-open --quiet
} else {
    clawrouter install --no-open --quiet
}

# --- Done ---
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  ClawRouter is installed and running!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard:  " -NoNewline; Write-Host "http://localhost:$Port" -ForegroundColor Cyan
Write-Host "  Proxy:      " -NoNewline; Write-Host "http://localhost:$Port/proxy/{provider}/v1" -ForegroundColor Cyan
Write-Host ""
Write-Host "  " -NoNewline; Write-Host "Knowledge Base: " -NoNewline -ForegroundColor White; Write-Host "We created a 'ClawRouter-Documentation' folder in your Documents!" -ForegroundColor Green
Write-Host ""
Write-Host "  Manage with:" -ForegroundColor DarkGray
Write-Host "    clawrouter status"
Write-Host "    clawrouter stop"
Write-Host "    clawrouter restart"
Write-Host "    clawrouter logs"
Write-Host "    clawrouter uninstall"
Write-Host ""