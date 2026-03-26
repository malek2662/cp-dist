#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────
# ClawProxy Installer — Linux & macOS
# Usage: curl -fsSL https://get.clawproxy.qzz.io/install.sh | bash
# ────────────────────────────────────────────────────────────
set -e
set -o pipefail

# ─── Config ───
# ⚠️  UPDATE THESE before distributing:
DOWNLOAD_URL="https://github.com/malek2662/cp-dist/releases/latest/download/clawproxy.tgz.enc"
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
echo -e "${BOLD}🐾 ClawProxy Installer${NC}"
echo -e "${DIM}   AI Routing Proxy — Multi-provider, Key Rotation, Dashboard${NC}"
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
    if [ "$NODE_VERSION" -lt 18 ]; then
        warn "Node.js version ${NODE_VERSION} is too old. Required: >= 18"
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

echo -ne "  Enter port for ClawProxy ${DIM}(default: ${DEFAULT_PORT})${NC}: "
read -r USER_PORT < "$TTY_INPUT" 2>/dev/null || USER_PORT=""

PORT="${USER_PORT:-$DEFAULT_PORT}"

if [ "$PORT" != "$DEFAULT_PORT" ]; then
    warn "Using custom port: ${PORT}"
    # Write to env file for persistence
    ENV_FILE="$HOME/.clawproxy.env"
    echo "PORT=${PORT}" > "$ENV_FILE"
    export PORT="$PORT"
    info "Port saved to ${ENV_FILE}"
else
    info "Using default port: ${PORT}"
fi

# ─── Step 3: Download & Decrypt ClawProxy Package ───
heading "Downloading ClawProxy..."

TEMP_DIR=$(mktemp -d)
ENCRYPTED_FILE="$TEMP_DIR/clawproxy.tgz.enc"
DECRYPTED_FILE="$TEMP_DIR/clawproxy.tgz"

echo -e "  ${DIM}Downloading encrypted package...${NC}"
curl -fsSL -o "$ENCRYPTED_FILE" "$DOWNLOAD_URL"
if [ ! -f "$ENCRYPTED_FILE" ]; then
    error "Download failed. Please check your internet connection."
    rm -rf "$TEMP_DIR"
    exit 1
fi
info "Package downloaded"

echo -e "  ${DIM}Decrypting package...${NC}"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
    -pass "pass:${DIST_PASSWORD}" \
    -in "$ENCRYPTED_FILE" \
    -out "$DECRYPTED_FILE" 2>/dev/null

if [ ! -f "$DECRYPTED_FILE" ]; then
    error "Decryption failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi
info "Package decrypted"

# ─── Step 4: Install ClawProxy ───
heading "Installing ClawProxy..."

# Backup existing database before npm install (npm replaces the entire package directory)
NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "")
CLAWPROXY_DIR="${NPM_PREFIX}/lib/node_modules/clawproxy"
DB_BACKUP=""

if [ -n "$NPM_PREFIX" ] && [ -f "${CLAWPROXY_DIR}/clawproxy.db" ]; then
    DB_BACKUP=$(mktemp -d)/clawproxy_backup
    mkdir -p "$DB_BACKUP"
    cp "${CLAWPROXY_DIR}/clawproxy.db" "$DB_BACKUP/clawproxy.db" 2>/dev/null && \
        info "Backed up existing database"
    # Also backup WAL/SHM files if they exist
    cp "${CLAWPROXY_DIR}/clawproxy.db-wal" "$DB_BACKUP/" 2>/dev/null || true
    cp "${CLAWPROXY_DIR}/clawproxy.db-shm" "$DB_BACKUP/" 2>/dev/null || true
fi
# Also check backend directory
if [ -n "$NPM_PREFIX" ] && [ -f "${CLAWPROXY_DIR}/backend/clawproxy.db" ]; then
    if [ -z "$DB_BACKUP" ]; then
        DB_BACKUP=$(mktemp -d)/clawproxy_backup
        mkdir -p "$DB_BACKUP"
    fi
    cp "${CLAWPROXY_DIR}/backend/clawproxy.db" "$DB_BACKUP/backend_clawproxy.db" 2>/dev/null && \
        info "Backed up existing backend database"
    cp "${CLAWPROXY_DIR}/backend/clawproxy.db-wal" "$DB_BACKUP/backend_clawproxy.db-wal" 2>/dev/null || true
    cp "${CLAWPROXY_DIR}/backend/clawproxy.db-shm" "$DB_BACKUP/backend_clawproxy.db-shm" 2>/dev/null || true
fi

npm install -g "$DECRYPTED_FILE"

# Clean up temp files
rm -rf "$TEMP_DIR"

# Restore database after install
if [ -n "$DB_BACKUP" ]; then
    if [ -f "$DB_BACKUP/clawproxy.db" ]; then
        cp "$DB_BACKUP/clawproxy.db" "${CLAWPROXY_DIR}/clawproxy.db" 2>/dev/null
        cp "$DB_BACKUP/clawproxy.db-wal" "${CLAWPROXY_DIR}/clawproxy.db-wal" 2>/dev/null || true
        cp "$DB_BACKUP/clawproxy.db-shm" "${CLAWPROXY_DIR}/clawproxy.db-shm" 2>/dev/null || true
        info "Restored existing database"
    fi
    if [ -f "$DB_BACKUP/backend_clawproxy.db" ]; then
        cp "$DB_BACKUP/backend_clawproxy.db" "${CLAWPROXY_DIR}/backend/clawproxy.db" 2>/dev/null
        cp "$DB_BACKUP/backend_clawproxy.db-wal" "${CLAWPROXY_DIR}/backend/clawproxy.db-wal" 2>/dev/null || true
        cp "$DB_BACKUP/backend_clawproxy.db-shm" "${CLAWPROXY_DIR}/backend/clawproxy.db-shm" 2>/dev/null || true
        info "Restored existing backend database"
    fi
    # Clean up backup
    rm -rf "$(dirname "$DB_BACKUP")"
fi

if ! command -v clawproxy &> /dev/null; then
    # npm global bin might not be in PATH
    NPM_PREFIX=$(npm config get prefix)
    export PATH="$NPM_PREFIX/bin:$PATH"

    if ! command -v clawproxy &> /dev/null; then
        error "clawproxy command not found after install."
        echo ""
        echo "  Make sure npm global bin is in your PATH:"
        echo "    export PATH=\"${NPM_PREFIX}/bin:\$PATH\""
        echo ""
        echo "  Then re-run:"
        echo "    clawproxy install --port ${PORT}"
        exit 1
    fi
fi

info "ClawProxy installed globally"

# ─── Step 4.5: Copy Documentation to User Documents ───
heading "Setting up Documentation..."

DOCS_DIR="$HOME/Documents/ClawProxy-Documentation"
if [ ! -d "$HOME/Documents" ]; then
    DOCS_DIR="$HOME/ClawProxy-Documentation"
fi
mkdir -p "$DOCS_DIR"

if [ -n "$NPM_PREFIX" ]; then
    CLAWPROXY_DIR="${NPM_PREFIX}/lib/node_modules/clawproxy"
    if [ -d "$CLAWPROXY_DIR" ]; then
        # Documentation files to copy
        DOC_FILES=(
            "README.md"
            "QUICKSTART.md"
            "QUICKSTART.pdf"
            "OPENCLAW_PROVIDERS.md"
            "OPENCLAW_PROVIDERS.pdf"
            "ClawProxy-Knowledge-Base.md"
            "TROUBLESHOOTING.md"
            "SETTINGS_REFERENCE.md"
            "HOW_TO_GUIDES.md"
            "FAQ.md"
            "COMMANDS.md"
        )
        for f in "${DOC_FILES[@]}"; do
            cp "$CLAWPROXY_DIR/$f" "$DOCS_DIR/" 2>/dev/null || true
        done
        if [ -d "$CLAWPROXY_DIR/assets" ]; then
            cp -r "$CLAWPROXY_DIR/assets" "$DOCS_DIR/" 2>/dev/null || true
        fi
        info "Documentation copied to ${DOCS_DIR}"

        # Remove doc files from install directory (keep only in Documentation folder)
        for f in "${DOC_FILES[@]}"; do
            rm -f "$CLAWPROXY_DIR/$f" 2>/dev/null || true
        done
        rm -rf "$CLAWPROXY_DIR/assets" 2>/dev/null || true
    else
        warn "Could not find ClawProxy directory to copy documentation."
    fi
fi

# ─── Step 5: Install as service ───
heading "Setting up background service..."

if [ "$PORT" != "$DEFAULT_PORT" ]; then
    clawproxy install --port "$PORT" --no-open
else
    clawproxy install --no-open
fi

# ─── Done ───
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ✅ ClawProxy is installed and running!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Dashboard:${NC}  ${CYAN}http://localhost:${PORT}${NC}"
echo -e "  ${BOLD}Proxy:${NC}      ${CYAN}http://localhost:${PORT}/proxy/{provider}/v1${NC}"
echo ""
echo -e "  ${BOLD}📔 Knowledge Base:${NC} ${GREEN}We created a 'ClawProxy-Documentation' folder in your Documents!${NC}"
echo ""
echo -e "  ${DIM}Manage with:${NC}"
echo -e "    clawproxy status"
echo -e "    clawproxy stop"
echo -e "    clawproxy restart"
echo -e "    clawproxy logs"
echo -e "    clawproxy uninstall"
echo ""
