#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────
# ClawRouter Installer — Linux & macOS
# Usage: curl -fsSL https://get.clawrouter.qzz.io/install.sh | bash
# ────────────────────────────────────────────────────────────
set -e
set -o pipefail

# ─── Config ───
# ⚠️  UPDATE THESE before distributing:
DOWNLOAD_URL="https://github.com/malek2662/cp-dist/releases/latest/download/clawrouter.tgz.enc"
DIST_PASSWORD='Cl@wPr0xy$2026!SecureDist#K9x'

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1"; }
heading() { echo -e "\n${BOLD}${CYAN}$1${NC}\n"; }

# ─── Banner ───
echo ""
echo -e "${BOLD}ClawRouter Installer${NC}"
echo -e "${DIM}   AI Routing Gateway — Multi-provider, Key Rotation, Dashboard${NC}"
echo ""

# ─── Step 1: Detect OS & Package Manager ───
heading "Checking prerequisites..."

IS_MACOS=false
PKG_MANAGER=""
PKG_INSTALL=""
NEEDS_SUDO=true

if [ "$(uname -s)" = "Darwin" ]; then
    IS_MACOS=true
    if command -v brew &> /dev/null; then
        PKG_MANAGER="brew"
        PKG_INSTALL="brew install"
        NEEDS_SUDO=false
    else
        warn "Homebrew not found. Will attempt to install it if needed."
    fi
else
    # Linux: detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt-get install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="pacman -S --noconfirm"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="zypper install -y"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
        PKG_INSTALL="apk add"
    fi
fi

# Helper: install a package using detected package manager
install_pkg() {
    local pkg_name="$1"
    if [ -z "$PKG_MANAGER" ]; then
        error "Cannot auto-install ${pkg_name}: no supported package manager found."
        echo "  Please install ${pkg_name} manually and re-run this script."
        exit 1
    fi
    warn "Installing ${pkg_name}..."
    if [ "$NEEDS_SUDO" = true ]; then
        if command -v sudo &> /dev/null; then
            # Update package index for apt
            if [ "$PKG_MANAGER" = "apt" ]; then
                sudo apt-get update -qq 2>/dev/null
            fi
            sudo $PKG_INSTALL "$pkg_name"
        else
            # Try without sudo (e.g., running as root in a container)
            if [ "$PKG_MANAGER" = "apt" ]; then
                apt-get update -qq 2>/dev/null
            fi
            $PKG_INSTALL "$pkg_name"
        fi
    else
        $PKG_INSTALL "$pkg_name"
    fi
}

# ─── Check / Install curl ───
if ! command -v curl &> /dev/null; then
    warn "curl is not installed."
    install_pkg "curl"
    if ! command -v curl &> /dev/null; then
        error "Failed to install curl. Please install it manually."
        exit 1
    fi
fi
info "curl detected"

# ─── Check / Install openssl ───
if ! command -v openssl &> /dev/null; then
    warn "openssl is not installed."
    if [ "$PKG_MANAGER" = "pacman" ]; then
        install_pkg "openssl"
    elif [ "$PKG_MANAGER" = "apk" ]; then
        install_pkg "openssl"
    else
        install_pkg "openssl"
    fi
    if ! command -v openssl &> /dev/null; then
        error "Failed to install openssl. Please install it manually."
        exit 1
    fi
fi
info "openssl detected"

# ─── Check / Install Node.js ───
NEED_NODE_INSTALL=false

if ! command -v node &> /dev/null; then
    NEED_NODE_INSTALL=true
else
    NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
    # >= 20: better-sqlite3 12.x dropped EOL Node 18, and its prebuilt binaries
    # start at Node 20 (ABI 115). On Node 18 there is no prebuilt binary, so npm
    # would fall back to compiling SQLite from source — slow, needs a toolchain,
    # and needs sizeable scratch space in TMPDIR.
    if [ "$NODE_VERSION" -lt 20 ]; then
        warn "Node.js version ${NODE_VERSION} is too old. Required: >= 20"
        NEED_NODE_INSTALL=true
    fi
fi

if [ "$NEED_NODE_INSTALL" = true ]; then
    warn "Node.js 22 is required. Attempting to install..."

    if [ "$IS_MACOS" = true ]; then
        if command -v brew &> /dev/null; then
            brew install node@22
            brew link --overwrite node@22 2>/dev/null || true
        else
            # Install Homebrew first, then Node.js
            warn "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
            # Try to source brew for this session
            if [ -f "/opt/homebrew/bin/brew" ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [ -f "/usr/local/bin/brew" ]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            brew install node@22
            brew link --overwrite node@22 2>/dev/null || true
        fi
    else
        # Linux: Use NodeSource setup script
        if command -v curl &> /dev/null; then
            warn "Setting up NodeSource repository..."
            if command -v sudo &> /dev/null; then
                curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
                sudo $PKG_INSTALL nodejs 2>/dev/null || true
            else
                curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
                $PKG_INSTALL nodejs 2>/dev/null || true
            fi
        fi

        # If NodeSource didn't work, try nvm as fallback
        if ! command -v node &> /dev/null; then
            warn "Trying nvm as fallback..."
            export NVM_DIR="$HOME/.nvm"
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
            [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            nvm install 22
            nvm use 22
        fi
    fi

    if ! command -v node &> /dev/null; then
        error "Failed to install Node.js. Please install Node.js 22 manually:"
        echo "  https://nodejs.org"
        echo ""
        echo "  Or using nvm:"
        echo "    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
        echo "    nvm install 22"
        exit 1
    fi
fi
info "Node.js v$(node -v | sed 's/v//') detected"

if ! command -v npm &> /dev/null; then
    error "npm is not found. This usually comes with Node.js. Please reinstall Node.js from https://nodejs.org"
    exit 1
fi
info "npm v$(npm -v) detected"

# ─── Step 2: Ask for PORT ───
heading "Configuration"

DEFAULT_PORT=3030

# Read from /dev/tty to work with curl | bash
if [ -t 0 ]; then
    TTY_INPUT="/dev/stdin"
else
    TTY_INPUT="/dev/tty"
fi

echo -ne "  Enter port for ClawRouter ${DIM}(default: ${DEFAULT_PORT})${NC}: "
read -r USER_PORT < "$TTY_INPUT" 2>/dev/null || USER_PORT=""

PORT="${USER_PORT:-$DEFAULT_PORT}"

if [ "$PORT" != "$DEFAULT_PORT" ]; then
    warn "Using custom port: ${PORT}"
    # Write to env file for persistence
    ENV_FILE="$HOME/.clawrouter.env"
    echo "PORT=${PORT}" > "$ENV_FILE"
    export PORT="$PORT"
    info "Port saved to ${ENV_FILE}"
else
    info "Using default port: ${PORT}"
fi

# ─── Step 3: Download & Decrypt ClawRouter Package ───
heading "Downloading ClawRouter..."

TEMP_DIR=$(mktemp -d)
ENCRYPTED_FILE="$TEMP_DIR/clawrouter.tgz.enc"
DECRYPTED_FILE="$TEMP_DIR/clawrouter.tgz"

# Download + decrypt are one user-visible step: "downloading" is what the user
# asked for, and the encryption is an internal delivery detail. Only failures
# distinguish the two phases, so only failures name them.
# `step` rewrites a single line in place when stdout is a TTY (\r + clear-to-EOL),
# and falls back to plain sequential lines when piped/redirected — a progress
# animation written into a log file would otherwise emit control characters.
step() {
    if [ -t 1 ]; then
        printf "\r\033[K  ${DIM}%s${NC}" "$1"
    else
        echo -e "  ${DIM}$1${NC}"
    fi
}
# Clear the in-place line before printing a final status.
step_done() { [ -t 1 ] && printf "\r\033[K"; return 0; }

step "Downloading package..."
curl -fsSL -o "$ENCRYPTED_FILE" "$DOWNLOAD_URL"
if [ ! -f "$ENCRYPTED_FILE" ]; then
    step_done
    error "Download failed. Please check your internet connection."
    rm -rf "$TEMP_DIR"
    exit 1
fi

step "Preparing package..."
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
    -pass "pass:${DIST_PASSWORD}" \
    -in "$ENCRYPTED_FILE" \
    -out "$DECRYPTED_FILE" 2>/dev/null

if [ ! -f "$DECRYPTED_FILE" ]; then
    step_done
    error "Could not unpack the downloaded package."
    rm -rf "$TEMP_DIR"
    exit 1
fi
step_done
info "Package ready"

# ─── Step 4: Install ClawRouter ───
heading "Installing ClawRouter..."

# Backup existing database before npm install (npm replaces the entire package directory)
NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "")
CLAWROUTER_DIR="${NPM_PREFIX}/lib/node_modules/clawrouter"
DB_BACKUP=""

# ─── Backup safety helpers ───
# The database is IRREPLACEABLE (providers, API keys, logs) and `npm install -g`
# deletes the package directory outright, so the backup is the only copy that
# survives. Two failure modes made this dangerous:
#   1. `cp ... 2>/dev/null` hid a FAILED copy, so the install proceeded and
#      destroyed the original — silent, total data loss.
#   2. mktemp lands in TMPDIR (/tmp), which on modern systemd (>= v256) is a
#      tmpfs in RAM with a per-user QUOTA (~50% of the tmpfs). A large database
#      can exceed the quota, which is EDQUOT, not ENOSPC — so a plain free-space
#      check is not sufficient on its own.
# Therefore: warn if space looks short, then VERIFY the copy byte-for-byte and
# abort BEFORE npm runs if it did not land intact.
file_size_bytes() {
    # Portable across GNU coreutils and BSD/macOS stat.
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}

# Copy one file and prove it arrived complete. Returns non-zero on any mismatch.
copy_verified() {
    local src="$1" dst="$2"
    [ -f "$src" ] || return 0   # nothing to copy is not a failure
    local src_size dst_size
    src_size=$(file_size_bytes "$src")
    if ! cp "$src" "$dst" 2>/dev/null; then
        return 1
    fi
    dst_size=$(file_size_bytes "$dst")
    [ "$src_size" = "$dst_size" ]
}

# Abort with an actionable message rather than proceeding into data loss.
backup_failed() {
    local what="$1" need_bytes="$2"
    error "Could not back up ${what} — aborting BEFORE any changes are made."
    echo ""
    echo "  Your existing installation and database are UNTOUCHED."
    echo ""
    echo "  The backup is written to a temporary directory:"
    echo "    ${TMPDIR:-/tmp}"
    if [ -n "$need_bytes" ] && [ "$need_bytes" -gt 0 ] 2>/dev/null; then
        echo "    required: ~$(( need_bytes / 1024 / 1024 )) MB"
    fi
    echo "    available: $(df -Pk "${TMPDIR:-/tmp}" 2>/dev/null | awk 'NR==2{printf "%d MB", $4/1024}')"
    echo ""
    echo "  Note: /tmp may be a RAM disk with a per-user quota, so it can refuse"
    echo "  a write even when the disk itself has plenty of free space."
    echo ""
    echo "  Fix it by either freeing space in /tmp:"
    echo "    df -h /tmp && du -sh /tmp/* 2>/dev/null | sort -rh | head"
    echo ""
    echo "  ...or pointing the backup at a directory with more room:"
    echo "    TMPDIR=\"\$HOME/.cache\" bash -c \"\$(curl -fsSL https://get.clawrouter.qzz.io/install.sh)\""
    echo ""
    exit 1
}

if [ -n "$NPM_PREFIX" ] && [ -f "${CLAWROUTER_DIR}/clawrouter.db" ]; then
    # Preflight: compare the backup footprint against free space, and warn early.
    DB_BYTES=$(file_size_bytes "${CLAWROUTER_DIR}/clawrouter.db")
    WAL_BYTES=$(file_size_bytes "${CLAWROUTER_DIR}/clawrouter.db-wal")
    NEED_BYTES=$(( DB_BYTES + WAL_BYTES ))
    AVAIL_BYTES=$(( $(df -Pk "${TMPDIR:-/tmp}" 2>/dev/null | awk 'NR==2{print $4}' || echo 0) * 1024 ))
    if [ "$NEED_BYTES" -gt 0 ] && [ "$AVAIL_BYTES" -gt 0 ] && [ "$NEED_BYTES" -gt "$AVAIL_BYTES" ]; then
        warn "Database is $(( NEED_BYTES / 1024 / 1024 )) MB but ${TMPDIR:-/tmp} has only $(( AVAIL_BYTES / 1024 / 1024 )) MB free."
    fi

    DB_BACKUP=$(mktemp -d)/clawrouter_backup
    mkdir -p "$DB_BACKUP"
    # The main database MUST be backed up intact — this one is fatal.
    if copy_verified "${CLAWROUTER_DIR}/clawrouter.db" "$DB_BACKUP/clawrouter.db"; then
        info "Backed up existing database ($(( DB_BYTES / 1024 / 1024 )) MB)"
    else
        rm -rf "$(dirname "$DB_BACKUP")" 2>/dev/null || true
        backup_failed "your database" "$NEED_BYTES"
    fi
    # WAL must also be intact: a truncated WAL alongside a valid DB can lose the
    # most recent committed transactions on recovery.
    if ! copy_verified "${CLAWROUTER_DIR}/clawrouter.db-wal" "$DB_BACKUP/clawrouter.db-wal"; then
        rm -rf "$(dirname "$DB_BACKUP")" 2>/dev/null || true
        backup_failed "your database write-ahead log" "$NEED_BYTES"
    fi
    # SHM is a rebuildable shared-memory index — safe to skip if it can't be copied.
    copy_verified "${CLAWROUTER_DIR}/clawrouter.db-shm" "$DB_BACKUP/clawrouter.db-shm" || true
    # Backup state file (activation/version tracking)
    copy_verified "${CLAWROUTER_DIR}/.clawrouter-state" "$DB_BACKUP/.clawrouter-state" || true
fi
# Also check backend directory
if [ -n "$NPM_PREFIX" ] && [ -f "${CLAWROUTER_DIR}/backend/clawrouter.db" ]; then
    if [ -z "$DB_BACKUP" ]; then
        DB_BACKUP=$(mktemp -d)/clawrouter_backup
        mkdir -p "$DB_BACKUP"
    fi
    BE_BYTES=$(file_size_bytes "${CLAWROUTER_DIR}/backend/clawrouter.db")
    if copy_verified "${CLAWROUTER_DIR}/backend/clawrouter.db" "$DB_BACKUP/backend_clawrouter.db"; then
        info "Backed up existing backend database"
    else
        rm -rf "$(dirname "$DB_BACKUP")" 2>/dev/null || true
        backup_failed "your backend database" "$BE_BYTES"
    fi
    if ! copy_verified "${CLAWROUTER_DIR}/backend/clawrouter.db-wal" "$DB_BACKUP/backend_clawrouter.db-wal"; then
        rm -rf "$(dirname "$DB_BACKUP")" 2>/dev/null || true
        backup_failed "your backend database write-ahead log" "$BE_BYTES"
    fi
    copy_verified "${CLAWROUTER_DIR}/backend/clawrouter.db-shm" "$DB_BACKUP/backend_clawrouter.db-shm" || true
fi

npm install -g "$DECRYPTED_FILE"

# Clean up temp files
rm -rf "$TEMP_DIR"

# Restore database after install
if [ -n "$DB_BACKUP" ]; then
    # The restore is verified too, and the backup is KEPT unless every restore
    # succeeded. Previously the "Restored" message printed unconditionally and
    # the backup was deleted regardless — so a failed restore looked like a
    # success and destroyed the only remaining copy.
    RESTORE_OK=true
    if [ -f "$DB_BACKUP/clawrouter.db" ]; then
        if copy_verified "$DB_BACKUP/clawrouter.db" "${CLAWROUTER_DIR}/clawrouter.db"; then
            copy_verified "$DB_BACKUP/clawrouter.db-wal" "${CLAWROUTER_DIR}/clawrouter.db-wal" || RESTORE_OK=false
            copy_verified "$DB_BACKUP/clawrouter.db-shm" "${CLAWROUTER_DIR}/clawrouter.db-shm" || true
            [ "$RESTORE_OK" = true ] && info "Restored existing database"
        else
            RESTORE_OK=false
        fi
    fi
    # Restore state file silently (activation/version tracking — internal, not shown to user)
    copy_verified "$DB_BACKUP/.clawrouter-state" "${CLAWROUTER_DIR}/.clawrouter-state" || true
    if [ -f "$DB_BACKUP/backend_clawrouter.db" ]; then
        if copy_verified "$DB_BACKUP/backend_clawrouter.db" "${CLAWROUTER_DIR}/backend/clawrouter.db"; then
            copy_verified "$DB_BACKUP/backend_clawrouter.db-wal" "${CLAWROUTER_DIR}/backend/clawrouter.db-wal" || RESTORE_OK=false
            copy_verified "$DB_BACKUP/backend_clawrouter.db-shm" "${CLAWROUTER_DIR}/backend/clawrouter.db-shm" || true
            [ "$RESTORE_OK" = true ] && info "Restored existing backend database"
        else
            RESTORE_OK=false
        fi
    fi

    if [ "$RESTORE_OK" = true ]; then
        # Clean up backup
        rm -rf "$(dirname "$DB_BACKUP")"
    else
        error "Database restore did not complete — your backup has been KEPT."
        echo ""
        echo "  Backup location (copy it somewhere safe now):"
        echo "    $DB_BACKUP"
        echo ""
        echo "  Restore it manually with:"
        echo "    cp \"$DB_BACKUP/clawrouter.db\" \"${CLAWROUTER_DIR}/clawrouter.db\""
        echo ""
        echo "  NOTE: /tmp is cleared on reboot — move the backup before restarting."
        echo ""
        exit 1
    fi
fi

if ! command -v clawrouter &> /dev/null; then
    # npm global bin might not be in PATH
    NPM_PREFIX=$(npm config get prefix)
    export PATH="$NPM_PREFIX/bin:$PATH"

    if ! command -v clawrouter &> /dev/null; then
        error "clawrouter command not found after install."
        echo ""
        echo "  Make sure npm global bin is in your PATH:"
        echo "    export PATH=\"${NPM_PREFIX}/bin:\$PATH\""
        echo ""
        echo "  Then re-run:"
        echo "    clawrouter install --port ${PORT}"
        exit 1
    fi
fi

info "ClawRouter installed globally"

# ─── Step 4.5: Copy Documentation to User Documents ───
heading "Setting up Documentation..."

DOCS_DIR="$HOME/Documents/ClawRouter-Documentation"
if [ ! -d "$HOME/Documents" ]; then
    DOCS_DIR="$HOME/ClawRouter-Documentation"
fi
mkdir -p "$DOCS_DIR"

if [ -n "$NPM_PREFIX" ]; then
    CLAWROUTER_DIR="${NPM_PREFIX}/lib/node_modules/clawrouter"
    if [ -d "$CLAWROUTER_DIR/Docs" ]; then
        # Copy md documentation (contents of Docs/md → Documentation folder root)
        cp -r "$CLAWROUTER_DIR/Docs/md/." "$DOCS_DIR/" 2>/dev/null || true
        cp "$CLAWROUTER_DIR/README.md" "$DOCS_DIR/" 2>/dev/null || true
        info "Documentation copied to ${DOCS_DIR}"

        # Remove docs from install directory (keep only in Documentation folder)
        rm -rf "$CLAWROUTER_DIR/Docs" 2>/dev/null || true
        rm -f "$CLAWROUTER_DIR/README.md" 2>/dev/null || true
    else
        warn "Could not find ClawRouter documentation directory."
    fi
fi

# ─── Step 5: Install as service ───
heading "Setting up background service..."

# --quiet: this script prints its own richer summary below. Without it the CLI
# prints the identical "installed and running / Dashboard / Manage with" block
# and the user sees the whole thing twice.
if [ "$PORT" != "$DEFAULT_PORT" ]; then
    clawrouter install --port "$PORT" --no-open --quiet
else
    clawrouter install --no-open --quiet
fi

# ─── Done ───
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ClawRouter is installed and running!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Dashboard:${NC}  ${CYAN}http://localhost:${PORT}${NC}"
echo -e "  ${BOLD}Proxy:${NC}      ${CYAN}http://localhost:${PORT}/proxy/{provider}/v1${NC}"
echo ""
echo -e "  ${BOLD}Knowledge Base:${NC} ${GREEN}We created a 'ClawRouter-Documentation' folder in your Documents!${NC}"
echo ""
echo -e "  ${DIM}Manage with:${NC}"
echo -e "    clawrouter status"
echo -e "    clawrouter stop"
echo -e "    clawrouter restart"
echo -e "    clawrouter logs"
echo -e "    clawrouter uninstall"
echo ""
