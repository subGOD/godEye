#!/bin/bash

# Print cyberpunk header
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

# Enable strict error handling
set -eE
set -o pipefail

# Core variables
LOG_FILE="/var/log/godeye/install.log"
ERROR_LOG_FILE="/var/log/godeye/error.log"
INSTALL_DIR="/opt/godeye"
DATA_DIR="/var/lib/godeye"
BACKUP_DIR="/var/backups/godeye"
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

# Enhanced logging and error handling
log() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${!level}[${level}]${NC} $msg"
    echo "[$timestamp] [${level}] $msg" >> "$LOG_FILE"
}

cleanup() {
    log "INFO" "Cleaning up on failure..."
    # Stop and disable services
    systemctl stop godeye 2>/dev/null || true
    systemctl disable godeye 2>/dev/null || true
    systemctl stop redis-server 2>/dev/null || true
    
    # Remove service files
    rm -f /etc/systemd/system/godeye.service
    
    # Remove nginx configs
    rm -f /etc/nginx/sites-enabled/godeye
    rm -f /etc/nginx/sites-available/godeye
    systemctl reload nginx 2>/dev/null || true
    
    # Remove installation directory
    [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
    
    # Backup data directory if it exists
    if [ -d "$DATA_DIR" ]; then
        backup_name="godeye-data-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        mv "$DATA_DIR" "$BACKUP_DIR/$backup_name"
        log "INFO" "Data directory backed up to $BACKUP_DIR/$backup_name"
    fi
    
    log "INFO" "Cleanup completed"
}

error_handler() {
    local line_no=$1
    local error_code=$2
    log "ERROR" "Error occurred in script at line: $line_no (Exit code: $error_code)"
    echo "Check $ERROR_LOG_FILE and $LOG_FILE for details."
    cleanup
    exit 1
}

# Trap errors and interrupts
trap 'error_handler ${LINENO} $?' ERR
trap cleanup SIGINT SIGTERM

# System preparation functions
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
    # Create log directories with proper permissions
    mkdir -p /var/log/godeye
    touch "$LOG_FILE" "$ERROR_LOG_FILE"
    chmod 755 /var/log/godeye
    chmod 644 "$LOG_FILE" "$ERROR_LOG_FILE"
    
    # Rotate old logs if they exist
    if [ -s "$LOG_FILE" ]; then
        mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d-%H%M%S)"
    fi
    if [ -s "$ERROR_LOG_FILE" ]; then
        mv "$ERROR_LOG_FILE" "$ERROR_LOG_FILE.$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Clean old logs (keep last 5)
    find /var/log/godeye -name "*.log.*" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
    
    log "INFO" "Installation started at $(date)"
}

check_internet() {
    log "INFO" "Checking internet connectivity..."
    
    # Backup existing resolv.conf
    [ -f /etc/resolv.conf ] && cp /etc/resolv.conf /etc/resolv.conf.backup
    
    # Fix potential DNS issues
    log "INFO" "Configuring DNS resolution..."
    cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    
    # Try multiple DNS servers with timeout
    local dns_servers=("8.8.8.8" "8.8.4.4" "1.1.1.1")
    local connected=false
    
    for dns in "${dns_servers[@]}"; do
        if ping -c 1 -W 5 "$dns" >/dev/null 2>&1; then
            connected=true
            log "SUCCESS" "Internet connection verified using DNS server: $dns"
            break
        fi
    done
    
    # Restore original resolv.conf if connection failed
    if [ "$connected" = false ]; then
        [ -f /etc/resolv.conf.backup ] && mv /etc/resolv.conf.backup /etc/resolv.conf
        log "ERROR" "No internet connection available"
        return 1
    fi
    
    # Test package repository connectivity
    if ! curl -sL --connect-timeout 5 https://deb.nodesource.com >/dev/null; then
        log "ERROR" "Cannot reach package repositories"
        return 1
    fi
    
    rm -f /etc/resolv.conf.backup
    return 0
}

check_requirements() {
    log "INFO" "Checking system requirements..."
    
    [ "$EUID" -ne 0 ] && {
        log "ERROR" "Please run as root or with sudo"
        exit 1
    }

    # Get the actual architecture
    ARCH=$(dpkg --print-architecture)
    [[ ! "$ARCH" =~ ^(arm64|armhf)$ ]] && {
        log "ERROR" "Unsupported architecture: $ARCH. This script is designed for Raspberry Pi."
        exit 1
    }

    # Check RAM with buffer/cache consideration
    local total_ram available_ram
    total_ram=$(free -m | awk '/^Mem:/{print $2}')
    available_ram=$(free -m | awk '/^Mem:/{print $7}')
    
    [ "$total_ram" -lt 1024 ] && {
        log "ERROR" "Insufficient RAM. Minimum 1GB required."
        exit 1
    }

    [ "$available_ram" -lt 512 ] && {
        log "WARN" "Low available memory. This might affect performance."
    }

    # Check disk space with more detail
    local available_space root_space
    available_space=$(df -m /opt | awk "NR==2 {print \$4}")
    root_space=$(df -m / | awk "NR==2 {print \$4}")
    
    [ "$available_space" -lt 1024 ] && {
        log "ERROR" "Insufficient disk space in /opt. Minimum 1GB required."
        exit 1
    }

    [ "$root_space" -lt 512 ] && {
        log "ERROR" "Insufficient disk space in root partition. Minimum 512MB required."
        exit 1
    }

    # Check existing installation with service status
    systemctl is-active --quiet godeye && {
        log "WARN" "godEye is already installed and running"
        echo -e "${YELLOW}Would you like to reinstall? This will backup existing data. [y/N]${NC} "
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && {
            log "INFO" "Installation cancelled by user"
            exit 0
        }
        cleanup
    }

    # Check required ports availability
    for port in $APP_PORT $FRONTEND_PORT $NGINX_PORT; do
        if netstat -tln | grep -q ":$port "; then
            log "ERROR" "Port $port is already in use"
            exit 1
        fi
    done

    log "SUCCESS" "System requirements verified"
}

install_dependencies() {
    log "INFO" "Installing dependencies..."
    
    # Update package list with retry mechanism
    if ! fix_package_manager; then
        log "ERROR" "Failed to fix package manager"
        return 1
    }

    # Verify required commands
    local required_commands=(curl wget git nginx)
    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || {
            log "ERROR" "Required command '$cmd' not found"
            return 1
        }
    done

    # Install prerequisites with better error handling
    log "INFO" "Installing prerequisites..."
    local PACKAGES=(
        curl
        wget
        gnupg2
        ca-certificates
        build-essential
        git
        apt-transport-https
        redis-server
        nginx
        ufw
        fail2ban
        logrotate
    )

    DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing "${PACKAGES[@]}" || {
        log "ERROR" "Failed to install prerequisites"
        error_msg=$(apt-get install -y "${PACKAGES[@]}" 2>&1)
        log "ERROR" "Installation error details: $error_msg"
        apt-get --fix-broken install -y
        return 1
    }

    # Configure Redis security
    log "INFO" "Configuring Redis..."
    local redis_conf="/etc/redis/redis.conf"
    local redis_password
    redis_password=$(openssl rand -hex 16)

    # Backup original Redis config
    cp "$redis_conf" "${redis_conf}.backup"

    # Configure Redis with security settings
    cat > "$redis_conf" << EOF
bind 127.0.0.1
port 6379
requirepass $redis_password
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
EOF

    # Restart Redis with new configuration
    systemctl restart redis-server
    
    # Verify Redis is running with new config
    systemctl is-active --quiet redis-server || {
        log "ERROR" "Redis failed to start with new configuration"
        mv "${redis_conf}.backup" "$redis_conf"
        systemctl restart redis-server
        return 1
    }

    # Configure basic firewall
    log "INFO" "Configuring firewall..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow "$NGINX_PORT/tcp"
    echo "y" | ufw enable
    
    # Configure fail2ban
    log "INFO" "Configuring fail2ban..."
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
                NODE_ARCH=$([ "$ARCH" = "armhf" ] && echo "armv7l" || echo "arm64")
                
                curl -o /tmp/node.tar.xz "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" || {
                    log "ERROR" "Failed to download Node.js binary"
                    return 1
                }
                
                cd /tmp || return 1
                tar -xf node.tar.xz
                cd "node-${NODE_VERSION}-linux-${NODE_ARCH}" || return 1
                cp -R * /usr/local/
                cd .. || return 1
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

        # Create and set permissions for npm directory
        mkdir -p /usr/local/lib/node_modules
        chown -R "$APP_USER:$APP_GROUP" /usr/local/lib/node_modules
        
        local installed_version
        installed_version=$(node -v)
        log "SUCCESS" "Node.js installed successfully (Version: $installed_version)"

        # Configure npm
        npm config set unsafe-perm true
        npm config set cache-min 3600
        npm config set registry "https://registry.npmjs.org/"
        
    else
        local current_version
        current_version=$(node -v)
        log "INFO" "Node.js is already installed (Version: $current_version)"
    fi
}

setup_environment() {
    log "INFO" "Setting up environment..."

    # Create data directory structure
    mkdir -p "$DATA_DIR"
    mkdir -p "$BACKUP_DIR"

    # Create application user and group if they don't exist
    if ! getent group "$APP_GROUP" >/dev/null; then
        groupadd "$APP_GROUP"
    fi
    
    if ! getent passwd "$APP_USER" >/dev/null; then
        useradd -m -g "$APP_GROUP" -s /bin/bash "$APP_USER"
        # Set secure permissions on user home
        chmod 750 "/home/$APP_USER"
    fi

    # Create and set permissions for directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p /var/log/godeye
    
    # Set proper ownership and permissions
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR" "$DATA_DIR" "$BACKUP_DIR"
    chown -R "$APP_USER:$APP_GROUP" /var/log/godeye
    chmod 755 "$INSTALL_DIR"
    chmod 750 "$DATA_DIR" "$BACKUP_DIR"
    chmod 755 /var/log/godeye

    # Setup logrotate configuration
    cat > /etc/logrotate.d/godeye << EOF
/var/log/godeye/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 $APP_USER $APP_GROUP
    postrotate
        systemctl reload godeye >/dev/null 2>&1 || true
    endscript
}
EOF

    # Setup nginx configuration with security headers
    cat > /etc/nginx/sites-available/godeye << EOF
server {
    listen $NGINX_PORT default_server;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';";

    # Performance optimizations
    client_max_body_size 10M;
    client_body_buffer_size 128k;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # Proxy settings
    proxy_http_version 1.1;
    proxy_cache_bypass \$http_upgrade;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_buffering off;

    location / {
        proxy_pass http://localhost:$FRONTEND_PORT;
    }

    location /api {
        proxy_pass http://localhost:$APP_PORT;
    }

    # Security: deny access to sensitive files
    location ~ /\.(?!well-known) {
        deny all;
    }
}
EOF

    # Verify nginx configuration
    if ! nginx -t; then
        log "ERROR" "Invalid nginx configuration"
        return 1
    fi

    # Enable nginx site and reload
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    systemctl reload nginx

    log "SUCCESS" "Environment setup completed"
}

install_global_packages() {
    log "INFO" "Installing required global npm packages..."
    
    # Install PM2 globally with retry mechanism and version lock
    local MAX_RETRIES=3
    local attempt=1
    local PM2_VERSION="5.3.0"  # Specify version for stability
    
    until npm install -g "pm2@$PM2_VERSION" || [ $attempt -eq $MAX_RETRIES ]; do
        log "WARN" "PM2 installation attempt $attempt failed, retrying..."
        npm cache clean --force
        sleep 5
        ((attempt++))
    done

    [ $attempt -eq $MAX_RETRIES ] && {
        log "ERROR" "Failed to install PM2"
        return 1
    }

    # Save PM2 path for systemd
    PM2_PATH=$(which pm2)
    [ -z "$PM2_PATH" ] && {
        log "ERROR" "PM2 binary not found"
        return 1
    }

    # Configure PM2
    mkdir -p "/home/$APP_USER/.pm2"
    chown -R "$APP_USER:$APP_GROUP" "/home/$APP_USER/.pm2"
    
    # Setup PM2 startup with proper user and logging
    su "$APP_USER" -c "$PM2_PATH startup systemd -u $APP_USER --hp /home/$APP_USER"
    
    # Configure PM2 defaults for better performance
    cat > "/home/$APP_USER/.pm2/ecosystem.config.js" << EOF
module.exports = {
  apps: [{
    name: 'godeye',
    script: 'server.js',
    instances: 1,
    exec_mode: 'fork',
    max_memory_restart: '256M',
    kill_timeout: 3000,
    wait_ready: true,
    listen_timeout: 8000,
    max_restarts: 10,
    restart_delay: 4000,
    error_file: '/var/log/godeye/pm2.error.log',
    out_file: '/var/log/godeye/pm2.out.log',
    merge_logs: true,
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    env: {
      NODE_ENV: 'production',
      NODE_OPTIONS: '--max-old-space-size=256'
    }
  }]
}
EOF

    chown "$APP_USER:$APP_GROUP" "/home/$APP_USER/.pm2/ecosystem.config.js"
    
    log "SUCCESS" "Global packages installed successfully"
}

clone_repository() {
    log "INFO" "Cloning godEye repository..."
    
    # Ensure git is installed
    command -v git &> /dev/null || {
        log "ERROR" "Git is not installed"
        return 1
    }

    # Remove existing directory if it exists
    [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"

    # Configure git for better security
    git config --system http.sslVerify true
    git config --system core.askPass ""
    
    # Clone the repository with retry mechanism and progress tracking
    local MAX_RETRIES=3
    local attempt=1
    
    until git clone --depth 1 --single-branch --branch main https://github.com/subGOD/godEye.git "$INSTALL_DIR" || [ $attempt -eq $MAX_RETRIES ]; do
        log "WARN" "Clone attempt $attempt failed, retrying..."
        rm -rf "$INSTALL_DIR"
        sleep 5
        ((attempt++))
    done

    [ $attempt -eq $MAX_RETRIES ] && {
        log "ERROR" "Failed to clone repository"
        return 1
    }

    cd "$INSTALL_DIR" || return 1
    
    # Verify repository content
    [ -f "package.json" ] || {
        log "ERROR" "Invalid repository: missing package.json"
        return 1
    }

    # Set proper permissions
    chown -R "$APP_USER:$APP_GROUP" .
    chmod -R 750 .
    find . -type f -name "*.js" -exec chmod 640 {} \;
    find . -type f -name "*.json" -exec chmod 640 {} \;
    find . -type d -exec chmod 750 {} \;

    log "SUCCESS" "Repository cloned successfully"
}

setup_environment_variables() {
    log "INFO" "Setting up environment variables..."
    
    # Generate random secure strings for secrets
    local jwt_secret redis_password
    jwt_secret=$(openssl rand -base64 48)
    redis_password=$(grep "^requirepass" /etc/redis/redis.conf | cut -d " " -f2)
    
    # Create secure temporary file
    local temp_env
    temp_env=$(mktemp)
    
    # Create .env file with secure permissions
    cat > "$temp_env" << EOF
NODE_ENV=production
PORT=$APP_PORT
FRONTEND_PORT=$FRONTEND_PORT
NGINX_PORT=$NGINX_PORT
JWT_SECRET=$jwt_secret
REDIS_PASSWORD=$redis_password

# Performance tuning
NODE_OPTIONS=--max-old-space-size=256
UV_THREADPOOL_SIZE=4

# Security settings
RATE_LIMIT_WINDOW=900000
RATE_LIMIT_MAX=100
SESSION_TIMEOUT=3600000
COOKIE_SECRET=$(openssl rand -hex 32)

# Logging
LOG_LEVEL=info
LOG_FILE=/var/log/godeye/app.log
ERROR_LOG_FILE=/var/log/godeye/error.log

# Data paths
DATA_DIR=$DATA_DIR
BACKUP_DIR=$BACKUP_DIR
EOF

    # Move to final location with proper permissions
    mv "$temp_env" "$INSTALL_DIR/.env"
    chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    
    # Create data directories
    mkdir -p "$DATA_DIR" "$BACKUP_DIR"
    chown "$APP_USER:$APP_GROUP" "$DATA_DIR" "$BACKUP_DIR"
    chmod 750 "$DATA_DIR" "$BACKUP_DIR"
    
    log "SUCCESS" "Environment variables configured"
}

install_application() {
    log "INFO" "Installing application dependencies..."
    
    cd "$INSTALL_DIR" || return 1
    
    # Clear npm cache and temporary files
    su "$APP_USER" -c "npm cache clean --force"
    rm -rf node_modules package-lock.json

    # Install dependencies with retry mechanism and progress tracking
    local MAX_RETRIES=3
    local attempt=1
    
    until su "$APP_USER" -c "npm install --production --no-optional --no-audit --no-fund --no-progress" || [ $attempt -eq $MAX_RETRIES ]; do
        log "WARN" "Dependency installation attempt $attempt failed, retrying..."
        rm -rf node_modules package-lock.json
        sleep 5
        ((attempt++))
    done

    [ $attempt -eq $MAX_RETRIES ] && {
        log "ERROR" "Failed to install dependencies"
        return 1
    }

    # Verify critical dependencies
    local required_modules=("express" "react" "redis" "pm2")
    for module in "${required_modules[@]}"; do
        [ -d "node_modules/$module" ] || {
            log "ERROR" "Critical dependency missing: $module"
            return 1
        }
    done

    # Build the application
    log "INFO" "Building application..."
    if ! su "$APP_USER" -c "NODE_ENV=production npm run build"; then
        log "ERROR" "Failed to build application"
        return 1
    fi

    # Verify build output
    [ -d "$INSTALL_DIR/dist" ] || {
        log "ERROR" "Build directory not found"
        return 1
    }

    # Optimize production build
    su "$APP_USER" -c "npm prune --production"
    
    # Remove development files
    rm -rf .git .github test tests
    
    # Set final permissions
    find . -type f -name "*.js" -exec chmod 640 {} \;
    find . -type f -name "*.json" -exec chmod 640 {} \;
    find . -type d -exec chmod 750 {} \;
    chmod 640 .env
    
    log "SUCCESS" "Application installation completed"
}

configure_systemd() {
    log "INFO" "Configuring systemd service..."
    
    # Create systemd service file with improved configuration
    cat > /etc/systemd/system/godeye.service << EOF
[Unit]
Description=godEye - PiVPN Management System
Documentation=https://github.com/subGOD/godEye
After=network-online.target redis-server.service nginx.service
Requires=redis-server.service nginx.service
Wants=network-online.target

[Service]
Type=forking
User=$APP_USER
Group=$APP_GROUP
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PM2_HOME=/home/$APP_USER/.pm2
Environment=NODE_ENV=production
Environment=NODE_OPTIONS=--max-old-space-size=256
WorkingDirectory=$INSTALL_DIR

# Security settings
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
CapabilityBoundingSet=~CAP_SYS_ADMIN
RestrictNamespaces=true

ExecStart=$PM2_PATH start /home/$APP_USER/.pm2/ecosystem.config.js
ExecReload=$PM2_PATH reload godeye
ExecStop=$PM2_PATH stop godeye

Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# Logging
StandardOutput=append:/var/log/godeye/godeye.log
StandardError=append:/var/log/godeye/godeye.error.log

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions
    chmod 644 /etc/systemd/system/godeye.service

    # Create systemd override directory
    mkdir -p /etc/systemd/system/godeye.service.d

    # Create memory limit override
    cat > /etc/systemd/system/godeye.service.d/memory.conf << EOF
[Service]
MemoryHigh=384M
MemoryMax=512M
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable godeye.service
    
    log "SUCCESS" "Systemd service configured"
}

start_services() {
    log "INFO" "Starting services..."
    
    # Function to start and verify service
    start_service() {
        local service=$1
        local max_attempts=${2:-3}
        local sleep_time=${3:-2}
        
        log "INFO" "Starting $service service..."
        
        systemctl start "$service"
        
        for ((i=1; i<=max_attempts; i++)); do
            if systemctl is-active --quiet "$service"; then
                log "SUCCESS" "$service started successfully"
                return 0
            fi
            log "WARN" "$service not running, attempt $i of $max_attempts"
            sleep "$sleep_time"
        done
        
        log "ERROR" "Failed to start $service after $max_attempts attempts"
        return 1
    }

    # Start and verify Redis
    start_service redis-server || return 1
    
    # Verify Redis connection
    timeout 5 redis-cli ping > /dev/null || {
        log "ERROR" "Redis is not responding"
        return 1
    }

    # Start and verify nginx
    start_service nginx || return 1
    
    # Verify nginx configuration
    curl -sf --max-time 5 "http://localhost:$NGINX_PORT/health" > /dev/null || {
        log "WARN" "Nginx health check failed, but service is running"
    }
    
    # Start godEye service
    start_service godeye 5 3 || return 1
    
    # Verify all required ports are listening
    for port in $APP_PORT $FRONTEND_PORT $NGINX_PORT; do
        timeout 5 nc -z localhost "$port" || {
            log "ERROR" "Port $port is not listening"
            return 1
        }
    done

    log "SUCCESS" "All services started successfully"
}

print_completion_message() {
    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}godEye Installation Complete!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    echo -e "Access the management interface at:"
    echo -e "${BLUE}http://$ip_address:$NGINX_PORT${NC}"
    echo -e "${BLUE}http://localhost:$NGINX_PORT${NC}"
    
    echo -e "\nService Information:"
    echo -e "Frontend Port: ${YELLOW}$FRONTEND_PORT${NC}"
    echo -e "Backend Port:  ${YELLOW}$APP_PORT${NC}"
    echo -e "Nginx Port:    ${YELLOW}$NGINX_PORT${NC}"
    
    echo -e "\nSystem Status:"
    echo -e "$(systemctl status redis-server --no-pager | grep "Active:")"
    echo -e "$(systemctl status nginx --no-pager | grep "Active:")"
    echo -e "$(systemctl status godeye --no-pager | grep "Active:")"
    
    echo -e "\nLog Files:"
    echo -e "Application: ${YELLOW}$LOG_FILE${NC}"
    echo -e "Errors:      ${YELLOW}$ERROR_LOG_FILE${NC}"
    
    echo -e "\nData Directories:"
    echo -e "Install Dir: ${YELLOW}$INSTALL_DIR${NC}"
    echo -e "Data Dir:    ${YELLOW}$DATA_DIR${NC}"
    echo -e "Backup Dir:  ${YELLOW}$BACKUP_DIR${NC}"
    
    echo -e "\n${GREEN}Installation Verification:${NC}"
    local verification_failed=false
    
    # Check service status
    for service in redis-server nginx godeye; do
        if ! systemctl is-active --quiet "$service"; then
            echo -e "${RED}✗ $service is not running${NC}"
            verification_failed=true
        else
            echo -e "${GREEN}✓ $service is running${NC}"
        fi
    done
    
    # Check port availability
    for port in $APP_PORT $FRONTEND_PORT $NGINX_PORT; do
        if ! nc -z localhost "$port"; then
            echo -e "${RED}✗ Port $port is not responding${NC}"
            verification_failed=true
        else
            echo -e "${GREEN}✓ Port $port is active${NC}"
        fi
    done
    
    $verification_failed && {
        echo -e "\n${RED}Warning: Some services may not be running correctly${NC}"
        echo -e "Please check the logs for more information"
    }
    
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}