#!/bin/bash

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
╔═══════════════════════[NEURAL_INTERFACE_INITIALIZATION]═══════════════════════╗
║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ║
║ ▓                                                                          ▓  ║
║ ▓      ▄████  ▒█████  ▓█████▄    ▓█████▓██   ██▓▓█████                   ▓  ║
║ ▓     ██▒ ▀█▒██▒  ██▒▒██▀ ██▌   ▓█   ▀ ▒██  ██▒▓█   ▀                   ▓  ║
║ ▓    ▒██░▄▄▄▒██░  ██▒░██   █▌   ▒███   ▒██ ██░▒███                      ▓  ║
║ ▓    ░▓█  ██▓██   ██░░▓█▄   ▌   ▒▓█  ▄ ░ ▐██▓░▒▓█  ▄                    ▓  ║
║ ▓    ░▒▓███▀▒░ ████▓▒░░▒████▓    ░▒████▒░ ██▒▓░░▒████▒                   ▓  ║
║ ▓         ┌──────────────[NEURAL_LINK_ACTIVE]──────────────┐              ▓  ║
║ ▓         │    CORE.SYS         │     MATRIX.protocol      │              ▓  ║
║ ▓         │    ┌──────┐         │     ╔══════════╗        │              ▓  ║
║ ▓         │    │⚡CPU⚡│         │     ║ ▓▓▒▒░░▓▓ ║        │              ▓  ║
║ ▓         │    └──────┘         │     ║ ░░▒▒▓▓░░ ║        │              ▓  ║
║ ▓         │                     │     ╚══════════╝        │              ▓  ║
║ ▓         └─────────────────────────────────────────────────              ▓  ║
║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ║
╚═════════════════════[INSTALLATION_SEQUENCE_INITIATED]════════════════════════╝${NC}

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
}

# Package management
install_dependencies() {
    log "Installing required packages..."
    
    # Update system first
    log "Updating system packages..."
    apt-get update -y || error "Failed to update package list" "exit"

    # Install curl if not present (needed for Node.js installation)
    if ! command -v curl &> /dev/null; then
        apt-get install -y curl || error "Failed to install curl" "exit"
    fi

    # Add Node.js repository and install Node.js properly
    log "Setting up Node.js repository..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - || error "Failed to setup Node.js repository" "exit"
    
    log "Installing Node.js and npm..."
    apt-get install -y nodejs || error "Failed to install Node.js and npm" "exit"

    # Install other required packages
    PACKAGES=(
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
    
    # Verify Node.js and npm installation
    if ! command -v node &> /dev/null; then
        error "Node.js installation failed" "exit"
    fi
    
    if ! command -v npm &> /dev/null; then
        error "npm installation failed" "exit"
    fi

    # Display versions for verification
    log "Node.js version: $(node -v)"
    log "npm version: $(npm -v)"
    
    success "All dependencies installed successfully"
}

# Create system user
setup_system_user() {
    log "Creating system user and setting permissions..."
    
    if ! id "godeye" &>/dev/null; then
        useradd -r -s /bin/false godeye || error "Failed to create godeye user" "exit"
        usermod -aG sudo godeye
    fi
    
    mkdir -p /opt/godeye
    mkdir -p /var/log/godeye
    
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
    
    cd /opt/godeye || error "Failed to access installation directory" "exit"
    
    log "Cloning godEye repository..."
    if [ -d ".git" ]; then
        git pull origin main >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
    else
        git clone https://github.com/subGOD/godeye.git . >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
    fi
    
    JWT_SECRET=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -hex 24)
    
    cat > .env << EOL
VITE_ADMIN_USERNAME=admin
VITE_ADMIN_PASSWORD=test
VITE_WIREGUARD_PORT=$WG_PORT
JWT_SECRET=$JWT_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
NODE_ENV=production
EOL
    
    log "Installing Node.js dependencies..."
    # Install vite globally first
    npm install -g vite >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || error "Failed to install vite" "exit"
    
    # Install all dependencies (including dev dependencies needed for build)
    npm ci >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || error "Failed to install dependencies" "exit"
    
    log "Building application..."
    # Show more detailed build output
    npm run build 2>&1 | tee -a "$LOG_FILE" || error "Failed to build application" "exit"
    
    # Check if build directory exists
    if [ ! -d "dist" ]; then
        error "Build directory not created. Build failed." "exit"
    fi
    
    success "Application installed successfully"
}

# Configure services
configure_services() {
    log "Configuring system services..."
    
    log "Configuring Redis..."
    sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    systemctl restart redis-server
    
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
    
    log "Configuring Nginx..."
    cat > /etc/nginx/sites-available/godeye << EOL
server {
    listen 1337;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
    }

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
    
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/
    
    nginx -t >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || error "Invalid Nginx configuration" "exit"
    
    success "Services configured successfully"
}

# Configure security
setup_security() {
    log "Configuring security measures..."
    
    log "Configuring firewall..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 1337/tcp
    ufw allow "$WG_PORT"/udp
    echo "y" | ufw enable
    
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
    
    SERVICES=("redis-server" "godeye-api" "godeye" "nginx")
    
    for service in "${SERVICES[@]}"; do
        log "Starting $service..."
        systemctl enable "$service" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
        systemctl start "$service" >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
        
        if ! systemctl is-active --quiet "$service"; then
            error "Failed to start $service" "exit"
        fi
    done
    
    success "All services started successfully"
}
# Final setup and checks
finalize_installation() {
    log "Performing final checks..."
    
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    if curl -s -o /dev/null -w "%{http_code}" "http://$IP_ADDRESS:1337"; then
        success "Installation completed successfully!"
        
        echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║             godEye Installation Complete                ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo -e "\n${CYAN}Access godEye at:${NC} http://$IP_ADDRESS:1337"
        echo -e "\n${CYAN}Credentials:${NC}"
        echo -e "Username: admin"
        echo -e "Password: test"
        echo -e "\n${CYAN}Useful Commands:${NC}"
        echo -e "View logs: ${GRAY}sudo journalctl -u godeye -f${NC}"
        echo -e "View API logs: ${GRAY}sudo journalctl -u godeye-api -f${NC}"
        echo -e "Restart services: ${GRAY}sudo systemctl restart godeye godeye-api${NC}"
        echo -e "\n${CYAN}For issues or updates, visit:${NC} https://github.com/subGOD/godeye\n"
    else
        error "Installation completed but application is not accessible"
    fi
}

# Detect WireGuard port
detect_wireguard_port() {
    log "Detecting WireGuard configuration..."
    if [ -f "/etc/wireguard/wg0.conf" ]; then
        WG_PORT=$(grep "ListenPort" /etc/wireguard/wg0.conf | awk '{print $3}')
        log "Detected WireGuard port: $WG_PORT"
    else
        error "WireGuard configuration not found." "exit"
    fi
}

# Main installation sequence
main() {
    check_system_requirements
    detect_wireguard_port
    install_dependencies
    setup_system_user
    install_application
    configure_services
    setup_security
    start_services
    finalize_installation
}

# Start installation
main