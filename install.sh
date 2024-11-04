#!/bin/bash

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

init_logging() {
    mkdir -p /var/log/godeye
    touch "$LOG_FILE" "$ERROR_LOG_FILE"
    chmod 755 /var/log/godeye
    chmod 644 "$LOG_FILE" "$ERROR_LOG_FILE"
    log "INFO" "Installation started at $(date)"
}

check_requirements() {
    log "INFO" "Checking system requirements..."
    
    if [ "$EUID" -ne 0 ]; then 
        log "ERROR" "Please run as root or with sudo"
        exit 1
    fi

    ARCH=$(uname -m)
    if [[ ! "$ARCH" =~ ^(aarch64|arm64|armv7l)$ ]]; then
        log "ERROR" "Unsupported architecture: $ARCH. This script is designed for Raspberry Pi."
        exit 1
    fi

    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 1024 ]; then
        log "ERROR" "Insufficient RAM. Minimum 1GB required."
        exit 1
    fi

    local available_space=$(df -m /opt | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1024 ]; then
        log "ERROR" "Insufficient disk space. Minimum 1GB required."
        exit 1
    fi

    if ! ping -c 1 -W 5 google.com >/dev/null 2>&1; then
        log "ERROR" "No internet connection detected"
        exit 1
    fi

    log "SUCCESS" "System requirements verified"
}

install_dependencies() {
    log "INFO" "Installing dependencies..."
    
    apt-get update -y || {
        log "ERROR" "Failed to update package list"
        return 1
    }

    if ! command -v node &> /dev/null; then
        log "INFO" "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs build-essential || {
            log "ERROR" "Failed to install Node.js"
            return 1
        }
    fi

    local packages=(nginx redis-server ufw fail2ban python3 git curl)
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            log "INFO" "Installing $package..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || {
                log "ERROR" "Failed to install $package"
                return 1
            }
        fi
    done

    log "INFO" "Updating npm..."
    npm install -g npm@latest || {
        log "ERROR" "Failed to update npm"
        return 1
    }

    npm install -g node-gyp || {
        log "ERROR" "Failed to install node-gyp"
        return 1
    }

    log "SUCCESS" "Dependencies installed"
    return 0
}

setup_user() {
    log "INFO" "Setting up system user..."
    
    if ! getent group "$APP_GROUP" >/dev/null; then
        groupadd "$APP_GROUP"
    fi

    if ! id "$APP_USER" &>/dev/null; then
        useradd -r -g "$APP_GROUP" -d "/home/$APP_USER" -s /bin/false "$APP_USER"
        mkdir -p "/home/$APP_USER"
        chown "$APP_USER:$APP_GROUP" "/home/$APP_USER"
    fi

    mkdir -p "$INSTALL_DIR"
    mkdir -p "/var/log/godeye"
    mkdir -p "/home/$APP_USER/.npm"

    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"
    chown -R "$APP_USER:$APP_GROUP" "/var/log/godeye"
    chown -R "$APP_USER:$APP_GROUP" "/home/$APP_USER"

    chmod -R 755 "$INSTALL_DIR"
    chmod -R 755 "/var/log/godeye"

    log "SUCCESS" "System user configured"
    return 0
}

setup_application() {
    log "INFO" "Setting up application..."
    
    cd "$INSTALL_DIR" || {
        log "ERROR" "Failed to access installation directory"
        return 1
    }
    
    git clone https://github.com/subGOD/godeye.git . || {
        log "ERROR" "Failed to clone repository"
        return 1
    }

    cat > .npmrc << 'EOF'
unsafe-perm=true
legacy-peer-deps=true
registry=https://registry.npmjs.org/
EOF

    local admin_user=${ADMIN_USER:-"admin"}
    local admin_pass=${ADMIN_PASS:-$(openssl rand -base64 12)}
    local jwt_secret=$(openssl rand -base64 32)
    local redis_pass=$(openssl rand -base64 24)

    cat > .env << EOF
VITE_ADMIN_USERNAME=$admin_user
VITE_ADMIN_PASSWORD=$admin_pass
JWT_SECRET=$jwt_secret
REDIS_PASSWORD=$redis_pass
PORT=$APP_PORT
NODE_ENV=production
EOF

    log "INFO" "Installing core dependencies..."
    npm install --no-audit express-rate-limit helmet || {
        log "ERROR" "Failed to install core dependencies"
        return 1
    }

    log "INFO" "Installing project dependencies..."
    npm install --no-audit --no-fund --legacy-peer-deps || {
        log "ERROR" "Failed to install project dependencies"
        return 1
    }
    
    log "INFO" "Building application..."
    NODE_ENV=production npm run build || {
        log "ERROR" "Build failed"
        return 1
    }
    
    if [ ! -d "dist" ]; then
        log "ERROR" "Build directory not created"
        return 1
    fi
    }
    
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"
    chmod 600 "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.npmrc"
    
    # Store Redis password for service configuration
    REDIS_PASSWORD="$redis_pass"
    
    log "SUCCESS" "Application setup complete"
    return 0
}

setup_services() {
    log "INFO" "Configuring services..."

    log "INFO" "Configuring Redis..."
    sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    systemctl restart redis-server || {
        log "ERROR" "Failed to restart Redis"
        return 1
    }

    cat > "/etc/systemd/system/godeye-api.service" << EOF
[Unit]
Description=godEye API Server
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=append:/var/log/godeye/api.log
StandardError=append:/var/log/godeye/api-error.log

[Install]
WantedBy=multi-user.target
EOF

    cat > "/etc/systemd/system/godeye-frontend.service" << EOF
[Unit]
Description=godEye Frontend
After=network.target godeye-api.service
Wants=godeye-api.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=/usr/bin/npm run preview -- --port $FRONTEND_PORT
Restart=always
RestartSec=10
StandardOutput=append:/var/log/godeye/frontend.log
StandardError=append:/var/log/godeye/frontend-error.log

[Install]
WantedBy=multi-user.target
EOF

    cat > "/etc/nginx/sites-available/godeye" << EOF
server {
    listen $NGINX_PORT default_server;
    client_max_body_size 50M;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    location / {
        proxy_pass http://localhost:$FRONTEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
    
    location /api {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/

    log "INFO" "Configuring firewall..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow "$NGINX_PORT"/tcp
    echo "y" | ufw enable

    log "INFO" "Starting services..."
    systemctl daemon-reload

    local services=(redis-server godeye-api godeye-frontend nginx)
    for service in "${services[@]}"; do
        log "INFO" "Starting $service..."
        systemctl enable "$service"
        systemctl restart "$service" || {
            log "ERROR" "Failed to start $service"
            return 1
        }
    done

    log "SUCCESS" "Services configured"
    return 0
}

verify_installation() {
    log "INFO" "Verifying installation..."
    
    local failed=0
    
    local services=(redis-server godeye-api godeye-frontend nginx)
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log "ERROR" "Service $service failed to start"
            journalctl -u "$service" --no-pager -n 50 >> "$ERROR_LOG_FILE"
            failed=1
        fi
    done

    local ports=($APP_PORT $FRONTEND_PORT $NGINX_PORT)
    for port in "${ports[@]}"; do
        if ! netstat -tuln | grep -q ":$port "; then
            log "ERROR" "Port $port is not listening"
            failed=1
        fi
    done

    if ! redis-cli ping > /dev/null 2>&1; then
        log "ERROR" "Redis connection failed"
        failed=1
    fi

    if [ $failed -eq 1 ]; then
        log "ERROR" "Installation verification failed"
        return 1
    fi

    local ip_address=$(hostname -I | awk '{print $1}')
    
    log "SUCCESS" "Installation verified successfully"
    
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║             godEye Installation Complete                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}Access your installation at:${NC} http://${ip_address}:${NGINX_PORT}"
    echo -e "\n${CYAN}Default Credentials:${NC}"
    echo -e "Username: $admin_user"
    echo -e "Password: $admin_pass"
    echo -e "\n${RED}IMPORTANT: Change your password after first login!${NC}"
    
    echo -e "\n${CYAN}Useful Commands:${NC}"
    echo -e "View API logs: ${NC}sudo journalctl -u godeye-api -f"
    echo -e "View frontend logs: ${NC}sudo journalctl -u godeye-frontend -f"
    echo -e "Restart services: ${NC}sudo systemctl restart godeye-api godeye-frontend"
    
    return 0
}

main() {
    init_logging
    check_requirements
    install_dependencies
    setup_user
    setup_application
    setup_services
    verify_installation
}

main