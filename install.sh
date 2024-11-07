#!/bin/bash
# Cyberpunk header preserved for branding
echo -e "\e[38;5;49m"
cat << "EOF"
┌────────────────────────────────────────────────────────┐
│   ┌─━┐  ┌───────┐   ┌───┐  ┌───┐   ┌───┐    ┌─━┐    │
│   │ ◯│  │░░░░░░░│   │▓▓▓│  │░░░│   │▓▓▓│    │◯ │    │
│   └─╥┘  └──╥────┘   └─╥─┘  └─╥─┘   └─╥─┘    └─╥┘    │
│  ═══║══╗═══║════════>║<════>║<═════>║<═══════║══    │
│     ║  ║   ║    ┌────╨────────╨───────╨──┐   ┌╨─┐    │
│   ┌─╨┐ ║ ┌─╨─┐  │  [[[[ god•EYE ]]]]     │   │◯ │    │
│   │◯ │ ║ │░░░│  │  SYSTEM STATUS: ACTIVE  │   │  │    │
│   └─╥┘ ║ └─╥─┘  │  MONITORING: ENABLED    │   └─╥┘    │
│  ═══║══╝══>║<═══│  <<< v1.0.0 >>>        │════║══    │
│     ║      ║    └──────────────────────┘     ║      │
│   ┌─╨┐   ┌─╨─┐     ┌───┐  ┌───┐   ┌───┐    ┌╨─┐    │
│   │◯ │   │▓▓▓│     │▓▓▓│  │░░░│   │▓▓▓│    │◯ │    │
│   └──┘   └───┘     └───┘  └───┘   └───┘    └──┘    │
└────────────────────────────────────────────────────────┘
EOF
echo -e "\e[38;5;39m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e "\e[38;5;51m      PiVPN Management & Monitoring System\e[0m"
echo -e "\e[38;5;39m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo ""

# Essential configuration and error handling
set -eE
set -o pipefail

# Core variables with minimal footprint
export DEBIAN_FRONTEND=noninteractive
APT_OPTIONS="-o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef"
INSTALL_DIR="/opt/godeye"
DATA_DIR="/var/lib/godeye"
APP_USER="godeye"
APP_GROUP="godeye"
APP_PORT="3001"
FRONTEND_PORT="3000"
NGINX_PORT="1337"

# Minimal color definitions
RED='\e[31m'
GREEN='\e[32m'
NC='\e[0m'

# Enhanced error handler with cleanup
error_handler() {
    echo -e "${RED}Error on line $1 (Exit code: $2)${NC}" >&2
    cleanup
    exit 1
}

trap 'error_handler ${LINENO} $?' ERR

# Optimized cleanup function
cleanup() {
    echo "Performing cleanup..."
    systemctl stop godeye nginx redis-server 2>/dev/null || true
    
    # Backup existing data if present
    if [ -d "$DATA_DIR" ]; then
        backup_dir="/var/backups/godeye/backup-$(date +%s)"
        mkdir -p "$backup_dir"
        cp -r "$DATA_DIR" "$backup_dir/"
        echo "Data backed up to $backup_dir"
    fi
    
    # Remove installation files
    rm -rf "$INSTALL_DIR"
    rm -f /etc/systemd/system/godeye.service
    rm -f /etc/nginx/sites-*/godeye
}

# System requirements check
check_system() {
    echo "Checking system requirements..."
    local errors=0

    # Check root with specific error
    [ "$EUID" -ne 0 ] && {
        echo -e "${RED}Error: Please run as root or with sudo${NC}"
        return 1
    }

    # Check architecture with specific error
    local arch=$(dpkg --print-architecture)
    if [[ ! "$arch" =~ ^(arm64|armhf)$ ]]; then
        echo -e "${RED}Error: Unsupported architecture: $arch${NC}"
        echo "This script supports Raspberry Pi architectures (arm64/armhf) only"
        return 1
    fi

    # Check RAM with detailed reporting
    local total_ram mem_available
    total_ram=$(free -m | awk '/^Mem:/{print $2}')
    mem_available=$(free -m | awk '/^Mem:/{print $7}')
    
    echo "Memory check:"
    echo "  Total RAM: ${total_ram}MB"
    echo "  Available: ${mem_available}MB"
    
    if [ "$mem_available" -lt 512 ]; then
        echo -e "${RED}Error: Insufficient memory${NC}"
        echo "Required: 512MB free memory"
        echo "Available: ${mem_available}MB"
        ((errors++))
    fi

    # Check disk space with detailed reporting
    local install_space data_space root_space
    install_space=$(df -m "$INSTALL_DIR" | awk 'NR==2 {print $4}')
    data_space=$(df -m "$DATA_DIR" | awk 'NR==2 {print $4}')
    root_space=$(df -m / | awk 'NR==2 {print $4}')

    echo "Disk space check:"
    echo "  Install directory space: ${install_space}MB"
    echo "  Data directory space: ${data_space}MB"
    echo "  Root partition space: ${root_space}MB"

    if [ "$install_space" -lt 1024 ]; then
        echo -e "${RED}Error: Insufficient space in $INSTALL_DIR${NC}"
        echo "Required: 1024MB"
        echo "Available: ${install_space}MB"
        ((errors++))
    fi

    if [ "$data_space" -lt 512 ]; then
        echo -e "${RED}Error: Insufficient space in $DATA_DIR${NC}"
        echo "Required: 512MB"
        echo "Available: ${data_space}MB"
        ((errors++))
    fi

    # Check for required commands
    echo "Checking required commands..."
    local required_commands=(curl wget systemctl)
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}Error: Required command '$cmd' not found${NC}"
            ((errors++))
        else
            echo "  $cmd: Found"
        fi
    done

    # Check if ports are available
    echo "Checking port availability..."
    for port in $APP_PORT $FRONTEND_PORT $NGINX_PORT; do
        if netstat -tuln | grep -q ":$port "; then
            echo -e "${RED}Error: Port $port is already in use${NC}"
            ((errors++))
        else
            echo "  Port $port: Available"
        fi
    done

    # Create directories if they don't exist
    mkdir -p "$INSTALL_DIR" "$DATA_DIR" || {
        echo -e "${RED}Error: Failed to create required directories${NC}"
        ((errors++))
    }

    # Final check
    if [ $errors -gt 0 ]; then
        echo -e "\n${RED}Found $errors system requirement issue(s)${NC}"
        return 1
    fi

    echo -e "${GREEN}System requirements verified successfully${NC}"
    return 0
}

# Package manager optimization
fix_package_manager() {
    echo "Optimizing package manager..."
    export DEBIAN_FRONTEND=noninteractive
    
    # Kill any stuck processes
    pkill -9 apt apt-get dpkg 2>/dev/null || true
    
    # Clear locks and cache
    rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock
    rm -f /var/cache/apt/*.bin /var/lib/apt/lists/* || true
    
    # Fix interrupted installations
    dpkg --configure -a || true
    apt-get clean
    
    # Update package lists with retry mechanism
    for i in {1..3}; do
        if apt-get update -q -y; then
            return 0
        fi
        sleep 2
    done
    return 1
}

# Core dependency installation with better verification
install_core_dependencies() {
    echo "Installing minimal dependencies..."
    
    # Force clean the package manager state
    rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
    dpkg --configure -a
    apt-get clean
    
    # Update package lists with multiple retries
    for i in {1..3}; do
        if apt-get update -y; then
            break
        fi
        echo "Retry $i updating package lists..."
        sleep 5
    done

    # Upgrade system packages first
    apt-get -y -f install
    apt-get -y --fix-broken install
    
    # Install packages individually with error handling
    local CORE_PACKAGES=(
        "nginx-light"
        "redis-server"
        "curl"
        "ufw"
        "git"
    )

    local install_errors=0
    
    for pkg in "${CORE_PACKAGES[@]}"; do
        echo "Processing $pkg..."
        
        # Check if package is already installed and working
        if dpkg -l | grep -q "^ii.*$pkg"; then
            echo "$pkg is already installed"
            
            # Verify the package's functionality
            case $pkg in
                "nginx-light")
                    # Test nginx installation
                    if nginx -v 2>/dev/null; then
                        echo "$pkg is working correctly"
                        continue
                    fi
                    ;;
                "redis-server")
                    # Test redis installation
                    if systemctl is-active redis-server >/dev/null 2>&1; then
                        echo "$pkg is working correctly"
                        continue
                    fi
                    ;;
                "curl")
                    # Test curl installation
                    if curl --version >/dev/null 2>&1; then
                        echo "$pkg is working correctly"
                        continue
                    fi
                    ;;
                "ufw")
                    # Test ufw installation
                    if ufw version >/dev/null 2>&1; then
                        echo "$pkg is working correctly"
                        continue
                    fi
                    ;;
                "git")
                    # Test git installation
                    if git --version >/dev/null 2>&1; then
                        echo "$pkg is working correctly"
                        continue
                    fi
                    ;;
            esac
        fi
        
        echo "Installing/Reinstalling $pkg..."
        
        # Remove package first if it exists but isn't working
        apt-get remove -y "$pkg" >/dev/null 2>&1 || true
        apt-get autoremove -y >/dev/null 2>&1 || true
        
        # Try installation with different methods
        if ! apt-get install -y --no-install-recommends "$pkg"; then
            echo "Retrying installation of $pkg with fix-broken..."
            apt-get -f install -y
            apt-get update
            if ! apt-get install -y --fix-missing --no-install-recommends "$pkg"; then
                echo "Failed to install $pkg using standard methods. Attempting alternative repository..."
                # Add Debian backports if not already added
                if ! grep -q "deb http://deb.debian.org/debian bullseye-backports main" /etc/apt/sources.list; then
                    echo "deb http://deb.debian.org/debian bullseye-backports main" >> /etc/apt/sources.list
                    apt-get update
                fi
                if ! apt-get install -y -t bullseye-backports "$pkg"; then
                    echo -e "${RED}Failed to install $pkg after all attempts${NC}"
                    ((install_errors++))
                    continue
                fi
            fi
        fi
        
        # Verify installation again
        if ! dpkg -l | grep -q "^ii.*$pkg"; then
            echo -e "${RED}Failed to verify installation of $pkg${NC}"
            ((install_errors++))
            continue
        fi
        
        echo -e "${GREEN}Successfully installed $pkg${NC}"
    done
    
    if [ $install_errors -gt 0 ]; then
        echo -e "${RED}Failed to install/verify $install_errors package(s)${NC}"
        return 1
    fi
    
    echo -e "${GREEN}All core dependencies installed successfully${NC}"
    return 0
}

# Node.js installation
install_nodejs() {
    echo "Installing Node.js..."
    
    if ! command -v node &>/dev/null; then
        # Direct binary installation - faster than package manager
        local NODE_VERSION="v18.18.2"
        local ARCH=$(dpkg --print-architecture)
        local NODE_ARCH=$([ "$ARCH" = "armhf" ] && echo "armv7l" || echo "arm64")
        
        curl -sSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" | tar xJ -C /usr/local --strip-components=1 || {
            echo -e "${RED}Failed to install Node.js${NC}"
            return 1
        }
        
        # Configure npm
        npm config set unsafe-perm true
        npm config set cache-min 3600
    fi
}

# PiHole compatibility configuration
configure_pihole_compatibility() {
    echo "Checking PiHole compatibility..."
    
    if command -v pihole &>/dev/null; then
        echo "PiHole detected, configuring compatibility..."
        
        # Backup PiHole's nginx config if exists
        if [ -f /etc/nginx/sites-enabled/default ]; then
            cp /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.backup
        fi
        
        # Configure nginx to use alternate port
        NGINX_PORT=8080
        
        # Update PiHole's configuration if needed
        if [ -f /etc/pihole/setupVars.conf ]; then
            sed -i 's/WEBSERVER_PORT=80/WEBSERVER_PORT=8080/' /etc/pihole/setupVars.conf
        fi
    fi
}

# Redis setup
configure_redis() {
    echo "Configuring Redis..."
    
    local redis_conf="/etc/redis/redis.conf"
    local redis_password=$(openssl rand -hex 16)
    
    # Backup original config
    cp "$redis_conf" "${redis_conf}.backup"
    
    # Minimal Redis configuration
    cat > "$redis_conf" << EOF
bind 127.0.0.1
port 6379
requirepass $redis_password
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
EOF
    
    # Restart Redis
    systemctl restart redis-server || {
        echo -e "${RED}Failed to start Redis${NC}"
        mv "${redis_conf}.backup" "$redis_conf"
        return 1
    }
    
    # Verify Redis is running
    systemctl is-active --quiet redis-server || return 1
    
    # Save Redis password for later use
    echo "$redis_password" > "$INSTALL_DIR/.redis_password"
    chmod 600 "$INSTALL_DIR/.redis_password"
}

# Security configuration
setup_security() {
    echo "Configuring basic security..."
    
    # Configure UFW
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow "$NGINX_PORT/tcp"
    echo "y" | ufw enable
    
    # Configure fail2ban
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true
EOF

    systemctl restart fail2ban
}

# Environment setup
setup_environment() {
    echo "Setting up environment..."
    
    # Create core directories
    mkdir -p "$INSTALL_DIR" "$DATA_DIR"

    # Create service user
    if ! getent group "$APP_GROUP" >/dev/null; then
        groupadd "$APP_GROUP"
    fi
    if ! getent passwd "$APP_USER" >/dev/null; then
        useradd -m -g "$APP_GROUP" -s /bin/bash "$APP_USER"
        chmod 750 "/home/$APP_USER"
    fi

    # Set permissions
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR" "$DATA_DIR"
    chmod 750 "$INSTALL_DIR" "$DATA_DIR"
}

# Nginx configuration
configure_nginx() {
    echo "Configuring nginx..."
    
    # Minimal nginx configuration
    cat > /etc/nginx/sites-available/godeye << EOF
server {
    listen ${NGINX_PORT} default_server;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    
    # Performance
    gzip on;
    gzip_types text/plain application/json application/javascript text/css;
    client_max_body_size 10M;
    
    # Frontend
    location / {
        proxy_pass http://localhost:${FRONTEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
    }

    # API
    location /api {
        proxy_pass http://localhost:${APP_PORT};
    }

    # Security
    location ~ /\. {
        deny all;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/
    
    # Test configuration
    nginx -t || return 1
}

# Application installation
install_application() {
    echo "Installing godEye application..."
    
    cd "$INSTALL_DIR" || return 1
    
    # Clone repository efficiently
    git clone --depth 1 --single-branch https://github.com/subGOD/godEye.git . || return 1
    
    # Setup environment variables
    cat > .env << EOF
NODE_ENV=production
PORT=$APP_PORT
FRONTEND_PORT=$FRONTEND_PORT
NGINX_PORT=$NGINX_PORT
JWT_SECRET=$(openssl rand -base64 48)
REDIS_PASSWORD=$(cat .redis_password)
NODE_OPTIONS=--max-old-space-size=256
EOF
    
    # Install dependencies
    su "$APP_USER" -c "npm ci --production --no-optional" || return 1
    
    # Install PM2 globally
    npm install -g pm2@latest || return 1
    
    # Build application
    su "$APP_USER" -c "npm run build" || return 1
    
    # Cleanup
    rm -rf .git tests .github
    find . -type f -name "*.js" -exec chmod 640 {} \;
    find . -type f -name "*.json" -exec chmod 640 {} \;
    chmod 600 .env
}

# Systemd service configuration
configure_service() {
    echo "Configuring systemd service..."
    
    cat > /etc/systemd/system/godeye.service << EOF
[Unit]
Description=godEye VPN Management System
After=network.target redis-server.service nginx.service
Requires=redis-server.service nginx.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$INSTALL_DIR
Environment=NODE_ENV=production
Environment=NODE_OPTIONS=--max-old-space-size=256
ExecStart=/usr/local/bin/node server.js
Restart=always
RestartSec=10

# Security
ProtectSystem=full
NoNewPrivileges=true
PrivateTmp=true

# Resource limits
MemoryHigh=384M
MemoryMax=512M
CPUQuota=80%

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/godeye.service
    systemctl daemon-reload
    systemctl enable godeye.service
}

# Service management
start_services() {
    echo "Starting services..."
    
    local services=(redis-server nginx godeye)
    
    for service in "${services[@]}"; do
        systemctl restart "$service" || {
            echo -e "${RED}Failed to start $service${NC}"
            return 1
        }
        
        # Verify service is running
        systemctl is-active --quiet "$service" || {
            echo -e "${RED}$service failed to start${NC}"
            return 1
        }
    done
    
    # Verify ports
    for port in $APP_PORT $FRONTEND_PORT $NGINX_PORT; do
        timeout 5 bash -c ">/dev/tcp/localhost/$port" 2>/dev/null || {
            echo -e "${RED}Port $port is not responding${NC}"
            return 1
        }
    done
}

# Helper function for progress indication
show_progress() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Command success verification
check_command() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# Installation verification
verify_installation() {
    local errors=0
    
    # Check services
    echo -n "Checking Redis... "
    systemctl is-active --quiet redis-server && echo -e "${GREEN}✓${NC}" || { echo -e "${RED}✗${NC}"; ((errors++)); }
    
    echo -n "Checking nginx... "
    systemctl is-active --quiet nginx && echo -e "${GREEN}✓${NC}" || { echo -e "${RED}✗${NC}"; ((errors++)); }
    
    echo -n "Checking godEye... "
    systemctl is-active --quiet godeye && echo -e "${GREEN}✓${NC}" || { echo -e "${RED}✗${NC}"; ((errors++)); }
    
    # Check ports
    for port in $APP_PORT $FRONTEND_PORT $NGINX_PORT; do
        echo -n "Checking port $port... "
        timeout 1 bash -c ">/dev/tcp/localhost/$port" 2>/dev/null && echo -e "${GREEN}✓${NC}" || { echo -e "${RED}✗${NC}"; ((errors++)); }
    done
    
    # Check files
    echo -n "Checking installation files... "
    [ -f "$INSTALL_DIR/server.js" ] && [ -f "$INSTALL_DIR/.env" ] && echo -e "${GREEN}✓${NC}" || { echo -e "${RED}✗${NC}"; ((errors++)); }
    
    return $errors
}

# Installation status display
print_status() {
    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${GREEN}Installation Complete!${NC}"
    echo -e "\nAccess URLs:"
    echo -e "Local:  http://localhost:${NGINX_PORT}"
    echo -e "Remote: http://${ip_address}:${NGINX_PORT}"
    
    echo -e "\nService Status:"
    systemctl status redis-server nginx godeye --no-pager
    
    echo -e "\nInstallation Directory: ${INSTALL_DIR}"
    echo -e "Data Directory: ${DATA_DIR}\n"
}

# Main installation sequence
main() {
    # Print welcome message (header already shown)
    echo "Starting godEye installation..."
    export DEBIAN_FRONTEND=noninteractive

    # Pre-installation checks with better error handling
    if ! check_system; then
        echo -e "${RED}System requirements check failed. Please resolve the issues above and try again.${NC}"
        exit 1
    fi

    # Initialize installation
    mkdir -p "$INSTALL_DIR" || exit 1
    cd "$INSTALL_DIR" || exit 1

    # Step 1: Package Management
    echo "Step 1/7: Preparing system..."
    fix_package_manager || {
        echo -e "${RED}Failed to prepare package manager${NC}"
        exit 1
    }

    # Step 2: Dependencies
    echo "Step 2/7: Installing dependencies..."
    install_core_dependencies || {
        echo -e "${RED}Failed to install core dependencies${NC}"
        cleanup
        exit 1
    }

    # Step 3: Node.js
    echo "Step 3/7: Setting up Node.js..."
    install_nodejs || {
        echo -e "${RED}Failed to install Node.js${NC}"
        cleanup
        exit 1
    }

    # Step 4: Environment
    echo "Step 4/7: Configuring environment..."
    setup_environment || {
        echo -e "${RED}Failed to setup environment${NC}"
        cleanup
        exit 1
    }

    # Step 5: Services
    echo "Step 5/7: Configuring services..."
    configure_pihole_compatibility
    configure_redis || {
        echo -e "${RED}Failed to configure Redis${NC}"
        cleanup
        exit 1
    }
    configure_nginx || {
        echo -e "${RED}Failed to configure nginx${NC}"
        cleanup
        exit 1
    }
    setup_security || {
        echo -e "${RED}Failed to setup security${NC}"
        cleanup
        exit 1
    }

    # Step 6: Application
    echo "Step 6/7: Installing application..."
    install_application || {
        echo -e "${RED}Failed to install application${NC}"
        cleanup
        exit 1
    }
    configure_service || {
        echo -e "${RED}Failed to configure service${NC}"
        cleanup
        exit 1
    }

    # Step 7: Start Services
    echo "Step 7/7: Starting services..."
    start_services || {
        echo -e "${RED}Failed to start services${NC}"
        cleanup
        exit 1
    }

    # Installation complete
    print_status
}

# Function to write runtime configuration
write_runtime_config() {
    cat > "$INSTALL_DIR/runtime.json" << EOF
{
    "version": "1.0.0",
    "installDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "ports": {
        "app": $APP_PORT,
        "frontend": $FRONTEND_PORT,
        "nginx": $NGINX_PORT
    },
    "paths": {
        "install": "$INSTALL_DIR",
        "data": "$DATA_DIR"
    }
}
EOF
    chmod 640 "$INSTALL_DIR/runtime.json"
    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/runtime.json"
}

# Function to handle upgrades
handle_upgrade() {
    if [ -d "$INSTALL_DIR" ]; then
        echo "Existing installation detected"
        echo -n "Would you like to upgrade? [y/N] "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "Creating backup..."
            backup_dir="/var/backups/godeye/backup-$(date +%s)"
            mkdir -p "$backup_dir"
            cp -r "$INSTALL_DIR" "$backup_dir/"
            cp -r "$DATA_DIR" "$backup_dir/" 2>/dev/null || true
            echo "Backup created at $backup_dir"
            cleanup
        else
            echo "Installation cancelled"
            exit 0
        fi
    fi
}

# Add final confirmation before starting
confirm_installation() {
    echo -e "\nReady to install godEye with the following configuration:"
    echo "  Installation Directory: $INSTALL_DIR"
    echo "  Data Directory: $DATA_DIR"
    echo "  Web Interface Port: $NGINX_PORT"
    echo -e "  Memory Limit: 512MB\n"
    
    echo -n "Continue with installation? [Y/n] "
    read -r response
    [[ ! "$response" =~ ^[Nn]$ ]] || exit 0
}

# Main execution
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

confirm_installation
handle_upgrade
(main) & show_progress $!
verify_installation

# Final steps
write_runtime_config
echo -e "\n${GREEN}Installation completed successfully!${NC}"