#!/bin/bash

# godEye VPN Management Interface Installation Script
# Version: 1.0.0
# Author: subGOD
# Repository: https://github.com/subGOD/godeye
# Description: Installation script for godEye VPN Management Interface

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
BLUE='\e[34m'
CYAN='\e[38;5;123m'
GRAY='\e[90m'
NC='\e[0m' # No Color

# Logging setup
LOG_FILE="/var/log/godeye_install.log"
ERROR_LOG_FILE="/var/log/godeye_error.log"

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

# Clear screen and show banner
clear

# Display ASCII art banner
echo -e "${CYAN}
╔════════════════════[NEURAL_INTERFACE_INITIALIZATION]═════════════════════╗
║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ║
║ ▓                                                                     ▓  ║
║ ▓      ▄████  ▒█████  ▓█████▄    ▓█████▓██   ██▓▓█████                ▓  ║
║ ▓     ██▒ ▀█▒██▒  ██▒▒██▀ ██▌   ▓█   ▀ ▒██  ██▒▓█   ▀                 ▓  ║
║ ▓    ▒██░▄▄▄▒██░  ██▒░██   █▌   ▒███   ▒██ ██░▒███                    ▓  ║
║ ▓    ░▓█  ██▓██   ██░░▓█▄   ▌   ▒▓█  ▄ ░ ▐██▓░▒▓█  ▄                  ▓  ║
║ ▓    ░▒▓███▀▒░ ████▓▒░░▒████▓    ░▒████▒░ ██▒▓░░▒████▒                ▓  ║
║ ▓                                                                     ▓  ║
║ ▓         ┌──────────────[NEURAL_LINK_ACTIVE]────────────             ▓  ║
║ ▓         │    CORE.SYS         │     MATRIX.protocol      │          ▓  ║
║ ▓         │    ┌──────┐         │     ╔══════════╗         │          ▓  ║
║ ▓         │    │⚡CPU⚡ │         │     ║ ▓▓▒▒░░▓▓ ║         │          ▓  ║
║ ▓         │    └──────┘         │     ║ ░░▒▒▓▓░░ ║         │          ▓  ║
║ ▓         │                     │     ╚══════════╝         │          ▓  ║
║ ▓         └─────────────────────────────────────────────────          ▓  ║
║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ║
╚════════════════════[INSTALLATION_SEQUENCE_INITIATED]═════════════════════╝${NC}

                        PiVPN Management Interface
                        Version: 1.0.0 | By: subGOD
"

# Initialize log files
sudo touch "$LOG_FILE" "$ERROR_LOG_FILE"
sudo chmod 644 "$LOG_FILE" "$ERROR_LOG_FILE"

log "Installation started at $(date '+%Y-%m-%d %H:%M:%S')"
# System requirements check
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        error "Please run as root or with sudo" "exit"
    }

    # Check system architecture
    ARCH=$(uname -m)
    if [[ ! "$ARCH" =~ ^(aarch64|arm64|armv7l)$ ]]; then
        error "Unsupported architecture: $ARCH. This script is designed for Raspberry Pi." "exit"
    }

    # Check for minimum RAM (1GB)
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 1024 ]; then
        error "Insufficient RAM. Minimum 1GB required." "exit"
    }

    # Check available disk space (minimum 1GB)
    AVAILABLE_SPACE=$(df -m /opt | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1024 ]; then
        error "Insufficient disk space. Minimum 1GB required." "exit"
    }

    # Check for PiVPN
    if ! command -v pivpn &> /dev/null; then
        error "PiVPN not found. Please install PiVPN first." "exit"
    }

    # Check for required ports availability
    check_port_availability() {
        if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null ; then
            error "Port $1 is already in use. Please free this port before continuing." "exit"
        }
    }
    
    check_port_availability 1337
    check_port_availability 3000
    check_port_availability 3001

    # Detect WireGuard port and configuration
    if [ -f "/etc/wireguard/wg0.conf" ]; then
        WG_PORT=$(grep "ListenPort" /etc/wireguard/wg0.conf | awk '{print $3}')
        log "Detected WireGuard port: $WG_PORT"
    else
        error "WireGuard configuration not found." "exit"
    }

    success "System requirements check passed"
}

# Package management
install_dependencies() {
    log "Installing required packages..."
    
    # Update package list
    apt-get update -qq || error "Failed to update package list" "exit"
    
    # Install required packages
    PACKAGES=(
        "nodejs"
        "npm"
        "nginx"
        "git"
        "redis-server"
        "ufw"
        "fail2ban"
    )
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            log "Installing $package..."
            apt-get install -y "$package" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || {
                error "Failed to install $package" "exit"
            }
        else
            log "$package is already installed"
        fi
    done
    
    # Check nodejs version and upgrade if necessary
    NODE_VERSION=$(node -v | cut -d'v' -f2)
    if [ "$(printf '%s\n' "14.0.0" "$NODE_VERSION" | sort -V | head -n1)" = "14.0.0" ]; then
        log "Node.js version is sufficient: $NODE_VERSION"
    else
        log "Upgrading Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
        apt-get install -y nodejs
    fi
    
    success "All dependencies installed successfully"
}

# Create system user and set permissions
setup_system_user() {
    log "Creating system user and setting permissions..."
    
    # Create godeye user if it doesn't exist
    if ! id "godeye" &>/dev/null; then
        useradd -r -s /bin/false godeye || error "Failed to create godeye user" "exit"
        usermod -aG sudo godeye
    fi
    
    # Create required directories
    mkdir -p /opt/godeye
    mkdir -p /var/log/godeye
    
    # Set proper ownership and permissions
    chown -R godeye:godeye /opt/godeye
    chown -R godeye:godeye /var/log/godeye
    chmod -R 755 /opt/godeye
    chmod -R 644 /var/log/godeye
    
    success "System user and permissions configured"
}

# Run initial system setup
check_system_requirements
install_dependencies
setup_system_user
# Application installation
install_application() {
    log "Installing godEye application..."
    
    # Navigate to installation directory
    cd /opt/godeye || error "Failed to access installation directory" "exit"
    
    # Clone repository
    log "Cloning godEye repository..."
    if [ -d ".git" ]; then
        git pull origin main >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
    else
        git clone https://github.com/subGOD/godeye.git . >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
    fi
    
    # Generate secure secrets
    JWT_SECRET=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -hex 24)
    
    # Create environment configuration
    cat > .env << EOL
VITE_ADMIN_USERNAME=admin
VITE_ADMIN_PASSWORD=$(echo -n "$ADMIN_PASSWORD" | sha256sum | awk '{print $1}')
VITE_WIREGUARD_PORT=$WG_PORT
JWT_SECRET=$JWT_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
NODE_ENV=production
EOL
    
    # Install npm packages
    log "Installing Node.js dependencies..."
    npm ci --production >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || error "Failed to install dependencies" "exit"
    
    # Build application
    log "Building application..."
    npm run build >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || error "Failed to build application" "exit"
    
    success "Application installed successfully"
}

# Configure services
configure_services() {
    log "Configuring system services..."
    
    # Configure Redis
    log "Configuring Redis..."
    sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    systemctl restart redis-server
    
    # API Service
    cat > /etc/systemd/system/godeye-api.service << EOL
[Unit]
Description=godEye API Server
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=godeye
WorkingDirectory=/opt/godeye
ExecStart=/usr/bin/node server.js
Restart=always
Environment=NODE_ENV=production
StandardOutput=append:/var/log/godeye/api.log
StandardError=append:/var/log/godeye/api-error.log

[Install]
WantedBy=multi-user.target
EOL
    
    # Frontend Service
    cat > /etc/systemd/system/godeye.service << EOL
[Unit]
Description=godEye Frontend
After=network.target godeye-api.service
Wants=godeye-api.service

[Service]
Type=simple
User=godeye
WorkingDirectory=/opt/godeye
ExecStart=/usr/bin/npm run preview -- --host --port 3000
Restart=always
Environment=NODE_ENV=production
StandardOutput=append:/var/log/godeye/frontend.log
StandardError=append:/var/log/godeye/frontend-error.log

[Install]
WantedBy=multi-user.target
EOL
    
    # Configure Nginx
    log "Configuring Nginx..."
    cat > /etc/nginx/sites-available/godeye << EOL
server {
    listen 1337 ssl http2;
    server_name _;

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/godeye/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/godeye/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';";
    
    # Frontend
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # API endpoints
    location /api {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL
    
    # Enable site and remove default
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/
    
    # Test Nginx configuration
    nginx -t >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || error "Invalid Nginx configuration" "exit"
    
    success "Services configured successfully"
}
# Configure security
setup_security() {
    log "Configuring security measures..."
    
    # Configure UFW
    log "Configuring firewall..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 1337/tcp
    ufw allow "$WG_PORT"/udp
    echo "y" | ufw enable
    
    # Configure fail2ban
    log "Configuring fail2ban..."
    cat > /etc/fail2ban/jail.local << EOL
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 300
bantime = 3600

[godeye]
enabled = true
port = 1337
filter = godeye
logpath = /var/log/godeye/api-error.log
maxretry = 5
findtime = 300
bantime = 3600
EOL
    
    # Create fail2ban filter for godEye
    cat > /etc/fail2ban/filter.d/godeye.conf << EOL
[Definition]
failregex = ^.*Failed login attempt from IP: <HOST>.*$
ignoreregex =
EOL
    
    systemctl restart fail2ban
    
    success "Security measures configured"
}

# Start services
start_services() {
    log "Starting services..."
    
    systemctl daemon-reload
    
    # Enable and start services
    SERVICES=("redis-server" "godeye-api" "godeye" "nginx")
    
    for service in "${SERVICES[@]}"; do
        log "Starting $service..."
        systemctl enable "$service" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
        systemctl start "$service" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
        
        # Check service status
        if ! systemctl is-active --quiet "$service"; then
            error "Failed to start $service" "exit"
        fi
    done
    
    success "All services started successfully"
}

# Final setup and checks
finalize_installation() {
    log "Performing final checks..."
    
    # Get IP address
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    # Test application accessibility
    if curl -s -o /dev/null -w "%{http_code}" "http://$IP_ADDRESS:1337"; then
        success "Installation completed successfully!"
        
        echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║             godEye Installation Complete                ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo -e "\n${CYAN}Access godEye at:${NC} http://$IP_ADDRESS:1337"
        echo -e "\n${CYAN}Credentials:${NC}"
        echo -e "Username: admin"
        echo -e "Password: [your chosen password]"
        echo -e "\n${CYAN}Useful Commands:${NC}"
        echo -e "View logs: ${GRAY}sudo journalctl -u godeye -f${NC}"
        echo -e "View API logs: ${GRAY}sudo journalctl -u godeye-api -f${NC}"
        echo -e "Restart services: ${GRAY}sudo systemctl restart godeye godeye-api${NC}"
        echo -e "\n${CYAN}For issues or updates, visit:${NC} https://github.com/subGOD/godeye\n"
    else
        error "Installation completed but application is not accessible"
    fi
}

# Main installation sequence
main() {
    check_system_requirements
    install_dependencies
    setup_system_user
    install_application
    configure_services
    setup_security
    start_services
    finalize_installation
}

# Execute main installation
main