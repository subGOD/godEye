#!/bin/bash

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
BLUE='\e[34m'
CYAN='\e[38;5;123m'
GRAY='\e[90m'
YELLOW='\e[33m'
NC='\e[0m' # No Color
CHECK_MARK="\u2714"
PROCESSING_MARK="⟳"

# Logging setup
LOG_FILE="/var/log/godeye_install.log"
ERROR_LOG_FILE="/var/log/godeye_error.log"

# Simplified progress bar function
show_progress() {
    local duration=$1
    echo -e "${CYAN}Processing...${NC}"
    sleep 1
}

# Function definitions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$ERROR_LOG_FILE"
    if [ "$2" = "exit" ]; then
        exit 1
    fi
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1 ${GREEN}${CHECK_MARK}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

# Clear screen and show banner
clear

# Initialize log files with proper permissions
initialize_logs() {
    sudo mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ERROR_LOG_FILE")"
    sudo touch "$LOG_FILE" "$ERROR_LOG_FILE"
    sudo chmod 644 "$LOG_FILE" "$ERROR_LOG_FILE"
    sudo chown "$(whoami)" "$LOG_FILE" "$ERROR_LOG_FILE"
}

# Modified banner display function
display_banner() {
    echo -e "${CYAN}"
    local banner=(
        "╔═══════════════════════[NEURAL_INTERFACE_INITIALIZATION]═══════════════════════╗"
        "║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ║"
        "║ ▓                                                                          ▓  ║"
        "║ ▓      ▄████  ▒█████  ▓█████▄    ▓█████▓██   ██▓▓█████                   ▓  ║"
        "║ ▓     ██▒ ▀█▒██▒  ██▒▒██▀ ██▌   ▓█   ▀ ▒██  ██▒▓█   ▀                   ▓  ║"
        "║ ▓    ▒██░▄▄▄▒██░  ██▒░██   █▌   ▒███   ▒██ ██░▒███                      ▓  ║"
        "║ ▓    ░▓█  ██▓██   ██░░▓█▄   ▌   ▒▓█  ▄ ░ ▐██▓░▒▓█  ▄                    ▓  ║"
        "║ ▓    ░▒▓███▀▒░ ████▓▒░░▒████▓    ░▒████▒░ ██▒▓░░▒████▒                   ▓  ║"
        "║ ▓         ┌──────────────[NEURAL_LINK_ACTIVE]──────────────┐              ▓  ║"
        "║ ▓         │    CORE.SYS         │     MATRIX.protocol      │              ▓  ║"
        "║ ▓         │    ┌──────┐         │     ╔══════════╗        │              ▓  ║"
        "║ ▓         │    │⚡CPU⚡│         │     ║ ▓▓▒▒░░▓▓ ║        │              ▓  ║"
        "║ ▓         │    └──────┘         │     ║ ░░▒▒▓▓░░ ║        │              ▓  ║"
        "║ ▓         │                     │     ╚══════════╝        │              ▓  ║"
        "║ ▓         └─────────────────────────────────────────────────              ▓  ║"
        "║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ║"
        "╚═════════════════════[INSTALLATION_SEQUENCE_INITIATED]════════════════════════╝"
    )

    for line in "${banner[@]}"; do
        echo -e "$line"
        sleep 0.02
    done
    echo -e "${NC}"
    echo -e "\n                        ${CYAN}godEye Management Interface"
    echo -e "                        Version: 1.0.0 | By: subGOD${NC}\n"
}
# System requirements check
check_system_requirements() {
    log "Checking system requirements..."
    echo -e "${CYAN}[CORE]: Analyzing system compatibility...${NC}"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        error "Please run as root or with sudo" "exit"
    fi

    # Check system architecture
    ARCH=$(uname -m)
    if [[ ! "$ARCH" =~ ^(aarch64|arm64|armv7l)$ ]]; then
        error "Unsupported architecture: $ARCH. This script is designed for Raspberry Pi." "exit"
    fi

    # Check for minimum RAM (1GB)
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 1024 ]; then
        error "Insufficient RAM. Minimum 1GB required." "exit"
    fi

    # Check available disk space (minimum 1GB)
    AVAILABLE_SPACE=$(df -m /opt | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1024 ]; then
        error "Insufficient disk space. Minimum 1GB required." "exit"
    fi

    # Check for PiVPN
    if ! command -v pivpn &> /dev/null; then
        error "PiVPN not found. Please install PiVPN first." "exit"
    fi
    
    success "System requirements verified"
}

# Create admin credentials with improved validation
create_admin_credentials() {
    echo -e "\n${CYAN}[CORE]: Initializing administrator credentials...${NC}"
    
    # Username validation
    while true; do
        read -p "$(echo -e ${CYAN}"Enter desired admin username [default: admin]: "${NC})" ADMIN_USER
        ADMIN_USER=${ADMIN_USER:-admin}
        if [[ "$ADMIN_USER" =~ ^[a-zA-Z0-9_-]{3,16}$ ]]; then
            break
        else
            echo -e "${RED}Username must be 3-16 characters and contain only letters, numbers, underscores, and hyphens.${NC}"
        fi
    done
    
    # Password validation
    while true; do
        read -s -p "$(echo -e ${CYAN}"Enter admin password (min 8 chars, must include numbers and letters): "${NC})" ADMIN_PASS
        echo
        if [[ ${#ADMIN_PASS} -ge 8 && "$ADMIN_PASS" =~ [A-Za-z] && "$ADMIN_PASS" =~ [0-9] ]]; then
            read -s -p "$(echo -e ${CYAN}"Confirm admin password: "${NC})" ADMIN_PASS_CONFIRM
            echo
            if [ "$ADMIN_PASS" = "$ADMIN_PASS_CONFIRM" ]; then
                break
            else
                echo -e "${RED}Passwords do not match. Please try again${NC}"
            fi
        else
            echo -e "${RED}Password must be at least 8 characters and contain both letters and numbers${NC}"
        fi
    done
    
    # Hash the password using bcrypt
    HASHED_PASSWORD=$(node -e "const bcrypt = require('bcrypt'); console.log(bcrypt.hashSync('$ADMIN_PASS', 10))")
    if [ -z "$HASHED_PASSWORD" ]; then
        error "Failed to hash password" "exit"
    fi
    
    success "Administrator credentials configured"
}
# Package management with improved error handling
install_dependencies() {
    log "Installing required packages..."
    echo -e "${CYAN}[CORE]: Downloading neural enhancement modules...${NC}"
    
    # Update system first
    log "Updating system packages..."
    apt-get update -y || error "Failed to update package list" "exit"

    # Update package list with timeout
    log "Updating package list..."
    timeout 300 apt-get update -y || error "Failed to update package list. Check your internet connection." "exit"

    # Install packages with proper error handling
    PACKAGES=(
        "nginx"
        "git"
        "redis-server"
        "ufw"
        "fail2ban"
        "bcrypt"
    )
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            log "Installing $package..."
            if ! apt-get install -y "$package" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"; then
                error "Failed to install $package. Check the error log for details." "exit"
            fi
        else
            log "$package is already installed"
        fi
    done

    # Verify Node.js installation
    if ! command -v node &> /dev/null; then
        log "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - || error "Failed to setup Node.js repository" "exit"
        apt-get install -y nodejs || error "Failed to install Node.js" "exit"
    fi
    
    # Verify npm installation
    if ! command -v npm &> /dev/null; then
        error "npm installation failed" "exit"
    fi

    success "Required components installed"
}

# Application installation with improved error handling
install_application() {
    log "Installing godEye application..."
    echo -e "${CYAN}[CORE]: Setting up application...${NC}"
    
    # Ensure directory exists and is clean
    rm -rf /opt/godeye
    mkdir -p /opt/godeye
    cd /opt/godeye || error "Failed to access installation directory" "exit"
    
    # Clone repository with timeout
    log "Cloning godEye repository..."
    if ! timeout 300 git clone https://github.com/subGOD/godeye.git .; then
        error "Failed to clone repository. Check your internet connection." "exit"
    fi
    
    # Generate secure secrets
    JWT_SECRET=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -hex 24)
    
    # Create environment file
    cat > .env << EOL
VITE_ADMIN_USERNAME=$ADMIN_USER
VITE_ADMIN_PASSWORD=$HASHED_PASSWORD
VITE_WIREGUARD_PORT=$WG_PORT
JWT_SECRET=$JWT_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
NODE_ENV=production
EOL

    # Install dependencies with improved error handling
    log "Installing Node.js dependencies..."
    if ! npm install -g vite; then
        error "Failed to install vite globally" "exit"
    fi
    
    if ! npm ci; then
        error "Failed to install dependencies" "exit"
    fi
    
    log "Building application..."
    if ! npm run build; then
        error "Failed to build application" "exit"
    fi
    
    if [ ! -d "dist" ]; then
        error "Build failed - dist directory not created" "exit"
    fi
    
    success "Application setup complete"
}
