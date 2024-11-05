#!/bin/bash

# Print cyberpunk header
echo -e "\e[38;5;51m"
cat << "EOF"
 ▄▄ •       ·▄▄▄▄  ▄▄▄ . ▄· ▄▌▄▄▄ .
▐█ ▀ ▪▪     ██▪ ██ ▀▄.▀·▐█▪██▌▀▄.▀·
▄█ ▀█▄ ▄█▀▄ ▐█· ▐█▌▐▀▀▪▄▐█▌▐█▪▐▀▀▪▄
▐█▄▪▐█▐█▌.▐▌██. ██ ▐█▄▄▌ ▐█▀·.▐█▄▄▌
·▀▀▀▀  ▀█▄▀▪▀▀▀▀▀•  ▀▀▀   ▀ •  ▀▀▀ 
EOF
echo -e "\e[38;5;39m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e "\e[38;5;51m      PiVPN Management & Monitoring System\e[0m"
echo -e "\e[38;5;39m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo ""

# Enable error tracing and exit on error
set -eE

# Core variables
LOG_FILE="/var/log/godeye/install.log"
ERROR_LOG_FILE="/var/log/godeye/error.log"
INSTALL_DIR="/opt/godeye"
APP_USER="godeye"
APP_GROUP="godeye"
APP_PORT="3001"
FRONTEND_PORT="3000"
NGINX_PORT="1337"

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[38;5;123m'
NC='\e[0m'

# Enhanced logging
log() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${!level}[${level}]${NC} $msg"
    echo "[$timestamp] [${level}] $msg" >> "$LOG_FILE"
}

error_handler() {
    local line_no=$1
    local error_code=$2
    log "ERROR" "Error occurred in script at line: $line_no (Exit code: $error_code)"
    echo "Check $ERROR_LOG_FILE and $LOG_FILE for details."
    exit 1
}

trap 'error_handler ${LINENO} $?' ERR

# Function to fix package manager issues
fix_package_manager() {
    log "INFO" "Checking and fixing package manager..."
    
    # Kill any stuck package manager processes
    pkill -9 apt-get >/dev/null 2>&1 || true
    pkill -9 dpkg >/dev/null 2>&1 || true
    
    # Remove locks
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock*
    
    # Fix potentially broken installations
    dpkg --configure -a
    
    # Clean package manager
    apt-get clean
    apt-get autoclean
    
    # Update sources list for both Buster and Bullseye compatibility
    cat > /etc/apt/sources.list << 'EOFAPT'
deb http://archive.raspberrypi.org/debian/ bullseye main
deb http://raspbian.raspberrypi.org/raspbian/ bullseye main contrib non-free rpi
EOFAPT

    # Update package lists with multiple retries and error checking
    for i in {1..3}; do
        if apt-get update -y 2>/tmp/apt-error.log; then
            # Force update the package cache
            apt-get update --fix-missing -y
            apt-get install -f -y
            log "SUCCESS" "Package manager fixed successfully"
            return 0
        else
            error_msg=$(cat /tmp/apt-error.log)
            log "WARN" "Package update attempt $i failed: $error_msg"
            
            # Try to fix common issues
            if echo "$error_msg" | grep -q "NO_PUBKEY"; then
                key=$(echo "$error_msg" | grep -o '[A-F0-9]\{16\}')
                apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$key" || true
            fi
            
            sleep 5
        fi
    done
    
    log "ERROR" "Failed to fix package manager"
    return 1
}

init_logging() {
    mkdir -p /var/log/godeye
    touch "$LOG_FILE" "$ERROR_LOG_FILE"
    chmod 755 /var/log/godeye
    chmod 644 "$LOG_FILE" "$ERROR_LOG_FILE"
    log "INFO" "Installation started at $(date)"
}

check_internet() {
    log "INFO" "Checking internet connectivity..."
    
    # Fix potential DNS issues
    log "INFO" "Configuring DNS resolution..."
    cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    
    # Try multiple DNS servers
    local dns_servers=("8.8.8.8" "8.8.4.4" "1.1.1.1")
    local connected=false
    
    for dns in "${dns_servers[@]}"; do
        if ping -c 1 -W 5 "$dns" >/dev/null 2>&1; then
            connected=true
            log "SUCCESS" "Internet connection verified using DNS server: $dns"
            break
        fi
    done
    
    if ! $connected; then
        log "ERROR" "No internet connection available"
        return 1
    fi
    
    return 0
}

check_requirements() {
    log "INFO" "Checking system requirements..."
    
    if [ "$EUID" -ne 0 ]; then 
        log "ERROR" "Please run as root or with sudo"
        exit 1
    fi

    # Get the actual architecture
    ARCH=$(dpkg --print-architecture)
    if [[ ! "$ARCH" =~ ^(arm64|armhf)$ ]]; then
        log "ERROR" "Unsupported architecture: $ARCH. This script is designed for Raspberry Pi."
        exit 1
    fi

    local total_ram=$(free -m | awk "/^Mem:/{print \$2}")
    if [ "$total_ram" -lt 1024 ]; then
        log "ERROR" "Insufficient RAM. Minimum 1GB required."
        exit 1
    fi

    local available_space=$(df -m /opt | awk "NR==2 {print \$4}")
    if [ "$available_space" -lt 1024 ]; then
        log "ERROR" "Insufficient disk space. Minimum 1GB required."
        exit 1
    fi

    log "SUCCESS" "System requirements verified"
}

install_dependencies() {
    log "INFO" "Installing dependencies..."
    
    # Update package list with retry mechanism
    if ! fix_package_manager; then
        log "ERROR" "Failed to fix package manager"
        return 1
    }

    # Install prerequisites with better error handling
    log "INFO" "Installing prerequisites..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing \
        curl \
        gnupg2 \
        ca-certificates \
        build-essential \
        git \
        apt-transport-https || {
        log "ERROR" "Failed to install prerequisites"
        error_msg=$(apt-get install -y curl gnupg2 ca-certificates build-essential git 2>&1)
        log "ERROR" "Installation error details: $error_msg"
        # Try to fix broken packages
        apt-get --fix-broken install -y
        return 1
    }

    # Node.js installation with fallback methods
    if ! command -v node &> /dev/null; then
        log "INFO" "Installing Node.js..."
        
        # Method 1: NodeSource repository
        if curl -fsSL https://deb.nodesource.com/setup_18.x | bash - ; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs || {
                log "WARN" "Standard Node.js installation failed, trying alternative method..."
                # Method 2: Direct binary installation
                NODE_VERSION="v18.18.2"
                ARCH=$(dpkg --print-architecture)
                if [[ "$ARCH" == "armhf" ]]; then
                    NODE_ARCH="armv7l"
                else
                    NODE_ARCH="arm64"
                fi
                
                curl -o /tmp/node.tar.xz "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" || {
                    log "ERROR" "Failed to download Node.js binary"
                    return 1
                }
                
                cd /tmp
                tar -xf node.tar.xz
                cd "node-${NODE_VERSION}-linux-${NODE_ARCH}"
                cp -R * /usr/local/
                cd ..
                rm -rf "node-${NODE_VERSION}-linux-${NODE_ARCH}" node.tar.xz
            }
        else
            log "ERROR" "Failed to setup Node.js repository"
            return 1
        fi
        
        # Verify Node.js installation
        if ! command -v node &> /dev/null; then
            log "ERROR" "Node.js installation failed verification"
            return 1
        fi
        
        local installed_version=$(node -v)
        log "SUCCESS" "Node.js installed successfully (Version: $installed_version)"
    else
        local current_version=$(node -v)
        log "INFO" "Node.js is already installed (Version: $current_version)"
    fi
}

setup_environment() {
    log "INFO" "Setting up environment..."

    # Create application user and group if they don't exist
    if ! getent group "$APP_GROUP" >/dev/null; then
        groupadd "$APP_GROUP"
    fi
    
    if ! getent passwd "$APP_USER" >/dev/null; then
        useradd -m -g "$APP_GROUP" -s /bin/bash "$APP_USER"
    fi

    # Create and set permissions for installation directory
    mkdir -p "$INSTALL_DIR"
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"

    # Create logs directory if it doesn't exist
    mkdir -p /var/log/godeye
    chown -R "$APP_USER:$APP_GROUP" /var/log/godeye
    chmod 755 /var/log/godeye

    log "SUCCESS" "Environment setup completed"
}

install_global_packages() {
    log "INFO" "Installing required global npm packages..."
    
    # Install PM2 globally with retry mechanism
    for i in {1..3}; do
        if npm install -g pm2@latest; then
            log "SUCCESS" "PM2 installed successfully"
            break
        else
            log "WARN" "PM2 installation attempt $i failed, retrying..."
            sleep 5
            if [ $i -eq 3 ]; then
                log "ERROR" "Failed to install PM2"
                return 1
            fi
        fi
    done

    # Save PM2 path for systemd
    PM2_PATH=$(which pm2)
    if [ -z "$PM2_PATH" ]; then
        log "ERROR" "PM2 binary not found"
        return 1
    fi

    log "SUCCESS" "Global packages installed successfully"
}

clone_repository() {
    log "INFO" "Cloning godEye repository..."
    
    # Ensure git is installed
    if ! command -v git &> /dev/null; then
        log "ERROR" "Git is not installed"
        return 1
    }

    # Remove existing directory if it exists
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
    fi

    # Clone the repository
    if git clone https://github.com/subGOD/godEye.git "$INSTALL_DIR"; then
        cd "$INSTALL_DIR"
        chown -R "$APP_USER:$APP_GROUP" .
        log "SUCCESS" "Repository cloned successfully"
    else
        log "ERROR" "Failed to clone repository"
        return 1
    fi
}

setup_environment_variables() {
    log "INFO" "Setting up environment variables..."
    
    # Generate random secure strings for secrets
    JWT_SECRET=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -hex 16)
    
    # Create .env file
    cat > "$INSTALL_DIR/.env" << EOF
NODE_ENV=production
PORT=$APP_PORT
FRONTEND_PORT=$FRONTEND_PORT
NGINX_PORT=$NGINX_PORT
JWT_SECRET=$JWT_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
EOF

    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    
    log "SUCCESS" "Environment variables configured"
}

install_application() {
    log "INFO" "Installing application dependencies..."
    
    cd "$INSTALL_DIR"
    
    # Install dependencies with retry mechanism
    for i in {1..3}; do
        if su "$APP_USER" -c "npm install --production"; then
            log "SUCCESS" "Application dependencies installed"
            break
        else
            log "WARN" "Dependency installation attempt $i failed, retrying..."
            sleep 5
            if [ $i -eq 3 ]; then
                log "ERROR" "Failed to install dependencies"
                return 1
            fi
        fi
    done

    # Build the application
    if su "$APP_USER" -c "npm run build"; then
        log "SUCCESS" "Application built successfully"
    else
        log "ERROR" "Failed to build application"
        return 1
    fi
}

configure_systemd() {
    log "INFO" "Configuring systemd service..."
    
    # Create systemd service file
    cat > /etc/systemd/system/godeye.service << EOF
[Unit]
Description=godEye - PiVPN Management System
After=network.target redis-server.service

[Service]
Type=forking
User=$APP_USER
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PM2_HOME=/home/$APP_USER/.pm2
WorkingDirectory=$INSTALL_DIR
ExecStart=$PM2_PATH start server.js --name godeye
ExecReload=$PM2_PATH reload godeye
ExecStop=$PM2_PATH stop godeye
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable godeye.service
    
    log "SUCCESS" "Systemd service configured"
}

start_services() {
    log "INFO" "Starting services..."
    
    # Start Redis if not running
    if ! systemctl is-active --quiet redis-server; then
        systemctl start redis-server
    fi
    
    # Start godEye service
    if systemctl start godeye; then
        log "SUCCESS" "godEye service started successfully"
    else
        log "ERROR" "Failed to start godEye service"
        return 1
    fi
}

print_completion_message() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}godEye Installation Complete!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "Access the management interface at:"
    echo -e "${BLUE}http://localhost:$NGINX_PORT${NC}"
    echo -e "\nDefault ports:"
    echo -e "Frontend: ${YELLOW}$FRONTEND_PORT${NC}"
    echo -e "Backend:  ${YELLOW}$APP_PORT${NC}"
    echo -e "Nginx:    ${YELLOW}$NGINX_PORT${NC}\n"
    echo -e "Installation logs can be found at:"
    echo -e "${YELLOW}$LOG_FILE${NC}"
    echo -e "${YELLOW}$ERROR_LOG_FILE${NC}\n"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main installation flow
main() {
    echo -e "${CYAN}Starting godEye installation...${NC}\n"
    
    # Initialize logging
    init_logging
    
    # Check system requirements
    check_requirements
    
    # Check internet connectivity
    check_internet
    
    # Install dependencies
    if ! install_dependencies; then
        log "ERROR" "Dependencies installation failed"
        exit 1
    fi
    
    # Setup environment
    if ! setup_environment; then
        log "ERROR" "Environment setup failed"
        exit 1
    fi
    
    # Install global packages
    if ! install_global_packages; then
        log "ERROR" "Global packages installation failed"
        exit 1
    fi
    
    # Clone repository
    if ! clone_repository; then
        log "ERROR" "Repository cloning failed"
        exit 1
    fi
    
    # Setup environment variables
    if ! setup_environment_variables; then
        log "ERROR" "Environment variables setup failed"
        exit 1
    fi
    
    # Install application
    if ! install_application; then
        log "ERROR" "Application installation failed"
        exit 1
    fi
    
    # Configure systemd
    if ! configure_systemd; then
        log "ERROR" "Systemd configuration failed"
        exit 1
    fi
    
    # Start services
    if ! start_services; then
        log "ERROR" "Service startup failed"
        exit 1
    fi
    
    # Print completion message
    print_completion_message
}

# Start installation
main "$@"