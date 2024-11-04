#!/bin/bash

# Basic setup
set -e

# Core variables
LOG_FILE="/var/log/godeye_install.log"
ERROR_LOG_FILE="/var/log/godeye_error.log"

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[38;5;123m'
NC='\e[0m'

# Core functions
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
    echo -e "${GREEN}[SUCCESS]${NC} $1 ✓"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

check_requirements() {
    log "Checking system requirements..."
    
    # Check for root
    if [ "$EUID" -ne 0 ]; then 
        error "Please run as root or with sudo" "exit"
    fi

    # Check architecture
    ARCH=$(uname -m)
    if [[ ! "$ARCH" =~ ^(aarch64|arm64|armv7l)$ ]]; then
        error "Unsupported architecture: $ARCH. This script is designed for Raspberry Pi." "exit"
    fi

    # Check RAM
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 1024 ]; then
        error "Insufficient RAM. Minimum 1GB required." "exit"
    fi

    # Check disk space
    AVAILABLE_SPACE=$(df -m /opt | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1024 ]; then
        error "Insufficient disk space. Minimum 1GB required." "exit"
    fi

    # Check for PiVPN
    if ! command -v pivpn &> /dev/null; then
        error "PiVPN not found. Please install PiVPN first." "exit"
    fi

    # Check internet connection
    if ! ping -c 1 google.com >/dev/null 2>&1; then
        error "No internet connection detected" "exit"
    fi

    success "System requirements verified"
}

detect_wireguard() {
    log "Detecting WireGuard configuration..."
    
    if [ -f "/etc/wireguard/wg0.conf" ]; then
        WG_PORT=$(grep "ListenPort" /etc/wireguard/wg0.conf | awk '{print $3}')
        if [ -z "$WG_PORT" ]; then
            error "WireGuard port not found in config" "exit"
        fi
        log "Detected WireGuard port: $WG_PORT"
        success "WireGuard configuration detected"
    else
        error "WireGuard configuration not found." "exit"
    fi
}

install_dependencies() {
    log "Installing required packages..."
    
    # Update package list
    apt-get update -y || error "Failed to update package list" "exit"

    # Install curl if needed
    if ! command -v curl &> /dev/null; then
        apt-get install -y curl || error "Failed to install curl" "exit"
    fi

    # Setup Node.js repository
    log "Setting up Node.js repository..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - || error "Failed to setup Node.js repository" "exit"
    
    # Install Node.js
    log "Installing Node.js and npm..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs build-essential || error "Failed to install Node.js" "exit"

    # Install other required packages
    PACKAGES=(nginx git redis-server ufw fail2ban python3 make g++)
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            log "Installing $package..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || error "Failed to install $package" "exit"
        fi
    done

    # Update npm
    log "Updating npm..."
    npm install -g npm@latest || error "Failed to update npm" "exit"
    npm install -g node-gyp || error "Failed to install node-gyp" "exit"
    
    success "Required packages installed"
}

setup_user() {
    log "Setting up system user..."
    
    # Create godeye user if it doesn't exist
    if ! id "godeye" &>/dev/null; then
        useradd -r -s /bin/false godeye || error "Failed to create godeye user" "exit"
        usermod -aG sudo godeye
    fi
    
    # Create and set permissions for directories
    mkdir -p /opt/godeye
    mkdir -p /var/log/godeye
    mkdir -p /home/godeye/.npm
    
    chown -R godeye:godeye /opt/godeye
    chown -R godeye:godeye /var/log/godeye
    chown -R godeye:godeye /home/godeye
    
    chmod -R 755 /opt/godeye
    chmod -R 755 /var/log/godeye
    
    success "System user configured"
}

prepare_system() {
    log "Preparing system..."
    
    # Clean up any existing installation
    rm -rf /opt/godeye/*
    
    # Stop and remove existing services
    systemctl stop godeye-api.service 2>/dev/null || true
    systemctl stop godeye-frontend.service 2>/dev/null || true
    rm -f /etc/systemd/system/godeye-api.service
    rm -f /etc/systemd/system/godeye-frontend.service
    systemctl daemon-reload
    
    # Set default credentials
    ADMIN_USER="admin"
    ADMIN_PASS="godEye2024!"
    JWT_SECRET=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -hex 24)
    
    success "System prepared"
}

setup_application() {
    log "Setting up application..."
    
    cd /opt/godeye || error "Failed to access installation directory" "exit"
    
    # Clone repository
    git clone https://github.com/subGOD/godeye.git . || error "Failed to clone repository" "exit"

    # Create npm config
    cat > .npmrc << 'EOF'
unsafe-perm=true
legacy-peer-deps=true
registry=https://registry.npmjs.org/
EOF

    # Create environment file
    cat > .env << EOF
VITE_ADMIN_USERNAME=$ADMIN_USER
VITE_ADMIN_PASSWORD=$ADMIN_PASS
VITE_WIREGUARD_PORT=$WG_PORT
JWT_SECRET=$JWT_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
EOF

    # Install dependencies
    log "Installing Node.js dependencies..."
    npm install --no-audit --no-fund --legacy-peer-deps || error "Failed to install dependencies" "exit"
    
    # Build application
    log "Building application..."
    NODE_ENV=production npm run build || error "Build failed" "exit"
    
    if [ ! -d "dist" ]; then
        error "Build directory not created" "exit"
    fi
    
    # Set permissions
    chown -R godeye:godeye /opt/godeye
    chmod 600 /opt/godeye/.env
    chmod 600 /opt/godeye/.npmrc
    
    success "Application setup complete"
}

setup_services() {
    log "Setting up services..."
    
    # Configure Redis
    sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    systemctl restart redis-server

    # Create API service
    cat > "/etc/systemd/system/godeye-api.service" << 'EOFAPI'
[Unit]
Description=godEye API Server
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=godeye
WorkingDirectory=/opt/godeye
Environment=NODE_ENV=production
Environment=PORT=3001
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=append:/var/log/godeye/api.log
StandardError=append:/var/log/godeye/api-error.log

[Install]
WantedBy=multi-user.target
EOFAPI

    # Create Frontend service
    cat > "/etc/systemd/system/godeye-frontend.service" << 'EOFFRONT'
[Unit]
Description=godEye Frontend
After=network.target godeye-api.service
Wants=godeye-api.service

[Service]
Type=simple
User=godeye
WorkingDirectory=/opt/godeye
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm run preview -- --port 3000
Restart=always
RestartSec=10
StandardOutput=append:/var/log/godeye/frontend.log
StandardError=append:/var/log/godeye/frontend-error.log

[Install]
WantedBy=multi-user.target
EOFFRONT

    # Configure Nginx
    cat > "/etc/nginx/sites-available/godeye" << 'EOFNGINX'
server {
    listen 1337 default_server;
    client_max_body_size 50M;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000" always;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
    
    location /api {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOFNGINX

    # Configure Nginx
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/
    
    # Configure firewall
    log "Configuring firewall..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 1337/tcp
    ufw allow "${WG_PORT}"/udp
    echo "y" | ufw enable

    # Start services
    log "Starting services..."
    systemctl daemon-reload
    
    systemctl enable redis-server
    systemctl restart redis-server
    
    systemctl enable godeye-api.service
    systemctl restart godeye-api.service
    
    systemctl enable godeye-frontend.service
    systemctl restart godeye-frontend.service
    
    systemctl enable nginx
    systemctl restart nginx

    success "Services configured"
}

verify_installation() {
    log "Verifying installation..."
    
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    # Wait for services to start
    sleep 5
    
    # Check if services are running
    if systemctl is-active --quiet godeye-api.service && \
       systemctl is-active --quiet godeye-frontend.service && \
       systemctl is-active --quiet nginx; then
        success "Installation complete"
        
        echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║             godEye Installation Complete                ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        
        echo -e "\n${CYAN}Access your installation at:${NC} http://${IP_ADDRESS}:1337"
        echo -e "\n${CYAN}Default Credentials:${NC}"
        echo -e "Username: admin"
        echo -e "Password: godEye2024!"
        echo -e "\n${RED}IMPORTANT: Change your password after first login!${NC}"
        
        echo -e "\n${CYAN}Useful Commands:${NC}"
        echo -e "View logs: ${NC}sudo journalctl -u godeye-api -f"
        echo -e "View frontend logs: ${NC}sudo journalctl -u godeye-frontend -f"
        echo -e "Restart services: ${NC}sudo systemctl restart godeye-api godeye-frontend"
    else
        error "Services failed to start properly. Check logs for details." "exit"
    fi
}

main() {
    # Initialize log files
    touch "$LOG_FILE" "$ERROR_LOG_FILE"
    chmod 644 "$LOG_FILE" "$ERROR_LOG_FILE"
    
    log "Starting installation..."
    
    # Run installation steps
    check_requirements
    detect_wireguard
    install_dependencies
    setup_user
    prepare_system
    setup_application
    setup_services
    verify_installation
}

# Start installation
main