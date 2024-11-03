#!/bin/bash

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
BLUE='\e[34m'
CYAN='\e[38;5;123m'
GRAY='\e[90m'
YELLOW='\e[33m'
NC='\e[0m'
CHECK_MARK="\u2714"
PROCESSING_MARK="⟳"

# Logging setup
LOG_FILE="/var/log/godeye_install.log"
ERROR_LOG_FILE="/var/log/godeye_error.log"

# Progress bar function
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

# Initialize log files
sudo touch "$LOG_FILE" "$ERROR_LOG_FILE"
sudo chmod 644 "$LOG_FILE" "$ERROR_LOG_FILE"

log "Installation started at $(date '+%Y-%m-%d %H:%M:%S')"
# Clear screen and show banner
clear

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

    for ((i=0; i<${#banner[@]}; i++)); do
        echo -e "${banner[$i]}"
        sleep 0.05
    done
    echo -e "${NC}"
    echo -e "\n                        ${CYAN}PiVPN Management Interface"
    echo -e "                        Version: 1.0.0 | By: subGOD${NC}\n"

    echo -e "${GREEN}[SYSTEM]: Neural interface detected...${NC}"
    sleep 0.5
    echo -e "${CYAN}[CORE]: Initializing neural handshake...${NC}"
    sleep 0.5
    echo -e "${YELLOW}[ALERT]: Bio-digital patterns synchronized${NC}"
    sleep 0.5
    echo -e "${GREEN}[SYSTEM]: Connection established to the Matrix${NC}"
    sleep 0.5
    echo -e "\n${CYAN}[CORE]: Beginning installation sequence...${NC}\n"
    sleep 1
}

check_system_requirements() {
    log "Checking system requirements..."
    echo -e "${CYAN}[CORE]: Analyzing system compatibility...${NC}"
    
    if [ "$EUID" -ne 0 ]; then 
        error "Please run as root or with sudo" "exit"
    fi

    ARCH=$(uname -m)
    if [[ ! "$ARCH" =~ ^(aarch64|arm64|armv7l)$ ]]; then
        error "Unsupported architecture: $ARCH. This script is designed for Raspberry Pi." "exit"
    fi

    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 1024 ]; then
        error "Insufficient RAM. Minimum 1GB required." "exit"
    fi

    AVAILABLE_SPACE=$(df -m /opt | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1024 ]; then
        error "Insufficient disk space. Minimum 1GB required." "exit"
    fi

    if ! command -v pivpn &> /dev/null; then
        error "PiVPN not found. Please install PiVPN first." "exit"
    fi

    success "System requirements verified"
}
install_dependencies() {
    log "Installing required packages..."
    echo -e "${CYAN}[CORE]: Downloading neural enhancement modules...${NC}"
    
    log "Updating system packages..."
    apt-get update -y || error "Failed to update package list" "exit"

    if ! command -v curl &> /dev/null; then
        apt-get install -y curl || error "Failed to install curl" "exit"
    fi
install_dependencies() {
    log "Installing required packages..."
    echo -e "${CYAN}[CORE]: Downloading neural enhancement modules...${NC}"
    
    log "Updating system packages..."
    apt-get update -y || error "Failed to update package list" "exit"

    if ! command -v curl &> /dev/null; then
        apt-get install -y curl || error "Failed to install curl" "exit"
    fi

    log "Setting up Node.js repository..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - || error "Failed to setup Node.js repository" "exit"
    
    log "Installing Node.js and npm..."
    apt-get install -y nodejs build-essential || error "Failed to install Node.js and npm" "exit"

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

    # Install development tools
    apt-get install -y python3 make g++ || error "Failed to install development tools" "exit"

    # Verify installations
    if ! command -v node &> /dev/null; then
        error "Node.js installation failed" "exit"
    fi
    
    if ! command -v npm &> /dev/null; then
        error "npm installation failed" "exit"
    fi

    log "Node.js version: $(node -v)"
    log "npm version: $(npm -v)"
    
    # Install global npm packages
    npm install -g npm@latest || error "Failed to update npm" "exit"
    npm install -g node-gyp || error "Failed to install node-gyp" "exit"
    
    success "Neural enhancement modules installed"
}

setup_system_user() {
    log "Creating system user and setting permissions..."
    echo -e "${CYAN}[CORE]: Configuring neural interface permissions...${NC}"
    show_progress 2
    
    if ! id "godeye" &>/dev/null; then
        useradd -r -s /bin/false godeye || error "Failed to create godeye user" "exit"
        usermod -aG sudo godeye
    fi
    
    # Create and set permissions for directories
    rm -rf /opt/godeye
    mkdir -p /opt/godeye
    mkdir -p /var/log/godeye
    
    chown -R godeye:godeye /opt/godeye
    chown -R godeye:godeye /var/log/godeye
    chmod -R 755 /opt/godeye
    chmod -R 644 /var/log/godeye

    # Create npm configuration directory for godeye user
    mkdir -p /home/godeye/.npm
    chown -R godeye:godeye /home/godeye
    
    success "Neural interface permissions configured"
}

create_admin_credentials() {
    echo -e "\n${CYAN}[CORE]: Initializing administrator neural implant...${NC}"
    echo -e "${YELLOW}[ALERT]: Security protocols require authentication setup${NC}\n"
    
    # Set default credentials for initial setup
    ADMIN_USER="admin"
    ADMIN_PASS="godEye2024!"
    
    log "Using default credentials for initial setup"
    echo -e "${YELLOW}[ALERT]: Default credentials set - please change after initial login${NC}"
    echo -e "${CYAN}Username: ${NC}${ADMIN_USER}"
    echo -e "${CYAN}Password: ${NC}${ADMIN_PASS}"
    
    success "Administrator neural implant configured with default credentials"
}

setup_system_user() {
    log "Creating system user and setting permissions..."
    echo -e "${CYAN}[CORE]: Configuring neural interface permissions...${NC}"
    show_progress 2
    
    if ! id "godeye" &>/dev/null; then
        useradd -r -s /bin/false godeye || error "Failed to create godeye user" "exit"
        usermod -aG sudo godeye
    fi
    
    # Create and set permissions for directories
    rm -rf /opt/godeye
    mkdir -p /opt/godeye
    mkdir -p /var/log/godeye
    
    chown -R godeye:godeye /opt/godeye
    chown -R godeye:godeye /var/log/godeye
    chmod -R 755 /opt/godeye
    chmod -R 644 /var/log/godeye

    # Create npm configuration directory for godeye user
    mkdir -p /home/godeye/.npm
    chown -R godeye:godeye /home/godeye
    
    success "Neural interface permissions configured"
}

create_admin_credentials() {
    echo -e "\n${CYAN}[CORE]: Initializing administrator neural implant...${NC}"
    echo -e "${YELLOW}[ALERT]: Security protocols require authentication setup${NC}\n"
    
    read -p "$(echo -e ${CYAN}"Enter desired admin username [default: admin]: "${NC})" ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}
    
    while true; do
        read -s -p "$(echo -e ${CYAN}"Enter admin password: "${NC})" ADMIN_PASS
        echo
        read -s -p "$(echo -e ${CYAN}"Confirm admin password: "${NC})" ADMIN_PASS_CONFIRM
        echo
        
        if [ "$ADMIN_PASS" = "$ADMIN_PASS_CONFIRM" ]; then
            if [ ${#ADMIN_PASS} -ge 8 ]; then
                break
            else
                echo -e "${RED}[ERROR]: Password must be at least 8 characters long${NC}"
            fi
        else
            echo -e "${RED}[ERROR]: Passwords do not match. Please try again${NC}"
        fi
    done
    
    success "Administrator neural implant configured"
}
install_application() {
    log "Installing godEye application..."
    echo -e "${CYAN}[CORE]: Integrating neural matrix components...${NC}"
    
    # Clean and prepare directory
    rm -rf /opt/godeye/*
    cd /opt/godeye || error "Failed to access installation directory" "exit"
    
    # Initialize npm project
    log "Initializing npm project..."
    cat > package.json << EOL
{
  "name": "godeye",
  "version": "1.0.0",
  "description": "PiVPN Management Interface",
  "main": "server.js",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --host --port 3000"
  },
  "dependencies": {
    "@heroicons/react": "^2.0.18",
    "axios": "^1.6.0",
    "bcryptjs": "^2.4.3",
    "express": "^4.18.2",
    "jsonwebtoken": "^9.0.2",
    "lucide-react": "^0.292.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "recharts": "^2.9.0",
    "redis": "^4.6.10"
  },
  "devDependencies": {
    "@types/react": "^18.2.15",
    "@types/react-dom": "^18.2.7",
    "@vitejs/plugin-react": "^4.0.3",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.31",
    "tailwindcss": "^3.3.5",
    "vite": "^4.4.5"
  }
}
EOL

    # Create npm config
    cat > .npmrc << EOL
unsafe-perm=true
legacy-peer-deps=true
EOL

    # Set correct permissions
    chown -R godeye:godeye /opt/godeye
    chmod -R 755 /opt/godeye

    # Install dependencies
    log "Installing Node.js dependencies..."
    npm install --no-audit --no-fund >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || {
        cat "$ERROR_LOG_FILE"
        error "Failed to install dependencies" "exit"
    }

    log "Cloning godEye repository..."
    git clone https://github.com/subGOD/godeye.git temp >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE"
    cp -r temp/* . && rm -rf temp

    # Create environment file
    JWT_SECRET=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -hex 24)
    
    cat > .env << EOL
VITE_ADMIN_USERNAME=$ADMIN_USER
VITE_ADMIN_PASSWORD=$ADMIN_PASS
VITE_WIREGUARD_PORT=$WG_PORT
JWT_SECRET=$JWT_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
NODE_ENV=production
EOL

    # Create Vite config
    cat > vite.config.js << EOL
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 3000
  },
  build: {
    outDir: 'dist',
    chunkSizeWarningLimit: 1000
  }
})
EOL

    log "Building application..."
    npm run build 2>&1 | tee -a "$LOG_FILE" || {
        cat "$LOG_FILE"
        error "Failed to build application" "exit"
    }
    
    if [ ! -d "dist" ]; then
        error "Build directory not created. Build failed." "exit"
    fi

    # Final permission adjustment
    chown -R godeye:godeye /opt/godeye
    chmod -R 755 /opt/godeye
    
    success "Neural matrix components integrated"
}
configure_services() {
    log "Configuring system services..."
    echo -e "${CYAN}[CORE]: Establishing neural network protocols...${NC}"
    show_progress 4
    
    log "Configuring Redis..."
    sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    systemctl restart redis-server

    # Create log directories with correct permissions
    mkdir -p /var/log/godeye
    chown -R godeye:godeye /var/log/godeye
    chmod -R 755 /var/log/godeye
    
    cat > /etc/systemd/system/godeye-api.service << EOL
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
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm run preview -- --port 3000
Restart=always
RestartSec=10
StandardOutput=append:/var/log/godeye/frontend.log
StandardError=append:/var/log/godeye/frontend-error.log

[Install]
WantedBy=multi-user.target
EOL
    
    log "Configuring Nginx..."
    cat > /etc/nginx/sites-available/godeye << EOL
server {
    listen 1337 default_server;
    server_name _;

    client_max_body_size 50M;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # CORS headers
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range' always;
    }

    location /api {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /socket.io {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOL
    
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/
    
    nginx -t >> "$LOG_FILE" 2>> "$ERROR_LOG_FILE" || error "Invalid Nginx configuration" "exit"
    
    success "Neural network protocols established"
}
setup_security() {
    log "Configuring security measures..."
    echo -e "${CYAN}[CORE]: Deploying neural defense systems...${NC}"
    show_progress 4
    
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
    
    # Set secure permissions on sensitive files
    chmod 600 /opt/godeye/.env
    chmod 600 /opt/godeye/.npmrc
    
    success "Neural defense systems activated"
}

start_services() {
    log "Starting services..."
    echo -e "${CYAN}[CORE]: Activating neural interface services...${NC}"
    show_progress 5
    
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
    
    success "Neural interface services activated"
}

detect_wireguard_port() {
    log "Detecting WireGuard configuration..."
    echo -e "${CYAN}[CORE]: Scanning for quantum tunneling protocols...${NC}"
    show_progress 2
    
    if [ -f "/etc/wireguard/wg0.conf" ]; then
        WG_PORT=$(grep "ListenPort" /etc/wireguard/wg0.conf | awk '{print $3}')
        log "Detected WireGuard port: $WG_PORT"
        success "Quantum tunneling protocols detected"
    else
        error "WireGuard configuration not found." "exit"
    fi
}

finalize_installation() {
    log "Performing final checks..."
    echo -e "${CYAN}[CORE]: Verifying neural interface stability...${NC}"
    show_progress 3
    
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    if curl -s -o /dev/null -w "%{http_code}" "http://$IP_ADDRESS:1337"; then
        success "Neural interface initialization complete"
        
        echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║             godEye Installation Complete                ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo -e "\n${CYAN}Access neural interface at:${NC} http://$IP_ADDRESS:1337"
        echo -e "\n${CYAN}Authentication credentials:${NC}"
        echo -e "Username: $ADMIN_USER"
        echo -e "Password: [REDACTED]"
        echo -e "\n${CYAN}Neural command protocols:${NC}"
        echo -e "View logs: ${GRAY}sudo journalctl -u godeye -f${NC}"
        echo -e "View API logs: ${GRAY}sudo journalctl -u godeye-api -f${NC}"
        echo -e "Restart services: ${GRAY}sudo systemctl restart godeye godeye-api${NC}"
        echo -e "\n${CYAN}Neural support protocols:${NC} https://github.com/subGOD/godeye\n"
    else
        error "Installation completed but neural interface is not accessible"
    fi
}

main() {
    display_banner
    check_system_requirements
    detect_wireguard_port
    create_admin_credentials
    install_dependencies
    setup_system_user
    install_application
    configure_services
    setup_security
    start_services
    finalize_installation
}

main