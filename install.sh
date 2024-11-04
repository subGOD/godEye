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

    log "SUCCESS" "System requirements verified"
}

install_nginx() {
    log "INFO" "Installing and configuring Nginx..."

    # Stop any existing web servers
    local web_servers=(apache2 nginx)
    for service in "${web_servers[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log "INFO" "Stopping $service..."
            systemctl stop "$service"
            systemctl disable "$service"
        fi
    done

    # Check for and kill any processes using port 80
    if netstat -tuln | grep -q ":80 "; then
        log "WARN" "Port 80 is in use. Attempting to free it..."
        local pid=$(lsof -t -i:80)
        if [ ! -z "$pid" ]; then
            kill -9 $pid
            sleep 2
        fi
    fi

    # Remove existing Nginx completely
    log "INFO" "Removing existing Nginx installation..."
    apt-get remove --purge -y nginx nginx-common nginx-full >/dev/null 2>&1 || true
    apt-get autoremove -y >/dev/null 2>&1 || true
    
    # Clean up Nginx directories
    rm -rf /etc/nginx
    rm -rf /var/log/nginx
    rm -rf /var/lib/nginx
    
    # Create fresh directories
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /var/log/nginx
    
    # Fresh install of Nginx
    log "INFO" "Installing Nginx..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx || {
        log "ERROR" "Failed to install Nginx. Checking apt logs..."
        cat /var/log/apt/term.log >> "$ERROR_LOG_FILE"
        return 1
    }

    # Configure Nginx
    cat > "/etc/nginx/sites-available/godeye" << EOF
server {
    listen $NGINX_PORT default_server;
    listen [::]:$NGINX_PORT default_server;
    server_name _;
    
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

    access_log /var/log/nginx/godeye.access.log;
    error_log /var/log/nginx/godeye.error.log;
}
EOF

    # Configure main nginx.conf
    cat > "/etc/nginx/nginx.conf" << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

    # Remove default site and enable godEye site
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/

    # Set permissions
    chown -R www-data:www-data /var/log/nginx
    chmod -R 755 /var/log/nginx

    # Test Nginx configuration
    nginx -t || {
        log "ERROR" "Nginx configuration test failed"
        cat /var/log/nginx/error.log >> "$ERROR_LOG_FILE"
        return 1
    }

    # Start Nginx
    systemctl start nginx || {
        log "ERROR" "Failed to start Nginx"
        journalctl -u nginx --no-pager -n 50 >> "$ERROR_LOG_FILE"
        return 1
    }

    log "SUCCESS" "Nginx installed and configured successfully"
    return 0
}

install_dependencies() {
    log "INFO" "Installing dependencies..."
    
    # Update package list with retry mechanism
    log "INFO" "Updating package lists..."
    for i in {1..3}; do
        if apt-get update -y; then
            break
        else
            log "WARN" "Attempt $i to update package lists failed, retrying..."
            sleep 5
        fi
    done

    # Install prerequisites
    log "INFO" "Installing prerequisites..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg2 ca-certificates build-essential || {
        log "ERROR" "Failed to install prerequisites"
        return 1
    }

    # Node.js installation
    if ! command -v node &> /dev/null; then
        log "INFO" "Installing Node.js..."
        
        # Remove any existing Node.js installations
        apt-get remove -y nodejs npm &>/dev/null || true
        rm -rf /etc/apt/sources.list.d/nodesource* &>/dev/null || true
        
        # Add Node.js repository manually with proper error handling
        log "INFO" "Adding NodeSource repository..."
        if ! curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg; then
            log "ERROR" "Failed to download and import NodeSource GPG key"
            return 1
        fi
        
        echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x buster main" > /etc/apt/sources.list.d/nodesource.list
        echo "deb-src [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x buster main" >> /etc/apt/sources.list.d/nodesource.list
        
        # Update package list after adding repository
        log "INFO" "Updating package list with Node.js repository..."
        apt-get update -y || {
            log "ERROR" "Failed to update package list after adding Node.js repository"
            return 1
        }
        
        # Install Node.js with fallback method
        log "INFO" "Installing Node.js packages..."
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs; then
            log "WARN" "Standard Node.js installation failed. Trying alternative method..."
            
            # Alternative installation using n
            if ! curl -L https://raw.githubusercontent.com/tj/n/master/bin/n -o /usr/local/bin/n; then
                log "ERROR" "Failed to download n"
                return 1
            fi
            chmod +x /usr/local/bin/n
            if ! n 18; then
                log "ERROR" "Alternative Node.js installation failed"
                return 1
            fi
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

    # Install Redis Server
    log "INFO" "Installing Redis..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server || {
        log "ERROR" "Failed to install Redis"
        return 1
    }

    # Configure Redis for better security
    sed -i 's/^# requirepass.*/requirepass/' /etc/redis/redis.conf
    sed -i 's/^bind 127.0.0.1.*/bind 127.0.0.1/' /etc/redis/redis.conf
    systemctl restart redis-server

    # Install remaining required packages
    local packages=(ufw fail2ban python3 git)
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            log "INFO" "Installing $package..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" || {
                log "ERROR" "Failed to install $package"
                return 1
            }
        fi
    done

    # Install and configure Nginx
    install_nginx || {
        log "ERROR" "Nginx installation failed"
        return 1
    }

    # Update npm and install global packages
    log "INFO" "Updating npm..."
    npm install -g npm@latest || {
        log "ERROR" "Failed to update npm"
        return 1
    }

    log "INFO" "Installing required global npm packages..."
    npm install -g bcrypt winston express-rate-limit helmet || {
        log "ERROR" "Failed to install required npm packages"
        return 1
    }

    log "SUCCESS" "All dependencies installed successfully"
    return 0
}

setup_user() {
    log "INFO" "Setting up system user..."
    
    # Create group if it doesn't exist
    if ! getent group "$APP_GROUP" >/dev/null; then
        groupadd "$APP_GROUP" || {
            log "ERROR" "Failed to create group $APP_GROUP"
            return 1
        }
        log "INFO" "Created group $APP_GROUP"
    fi

    # Create user if it doesn't exist
    if ! id "$APP_USER" &>/dev/null; then
        useradd -r -g "$APP_GROUP" -d "/home/$APP_USER" -s /bin/false "$APP_USER" || {
            log "ERROR" "Failed to create user $APP_USER"
            return 1
        }
        log "INFO" "Created user $APP_USER"
    fi

    # Create required directories
    local directories=(
        "$INSTALL_DIR"
        "/var/log/godeye"
        "/home/$APP_USER"
        "/home/$APP_USER/.npm"
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$dir" || {
            log "ERROR" "Failed to create directory $dir"
            return 1
        }
        log "INFO" "Created directory $dir"
    done

    # Set ownership
    local owned_paths=(
        "$INSTALL_DIR"
        "/var/log/godeye"
        "/home/$APP_USER"
    )

    for path in "${owned_paths[@]}"; do
        chown -R "$APP_USER:$APP_GROUP" "$path" || {
            log "ERROR" "Failed to set ownership for $path"
            return 1
        }
        chmod -R 755 "$path" || {
            log "ERROR" "Failed to set permissions for $path"
            return 1
        }
        log "INFO" "Set permissions for $path"
    done

    log "SUCCESS" "System user configured"
    return 0
}

setup_application() {
    log "INFO" "Setting up application..."
    
    # Change to installation directory
    cd "$INSTALL_DIR" || {
        log "ERROR" "Failed to access installation directory"
        return 1
    }
    
    # Clean any existing installation
    log "INFO" "Cleaning existing installation..."
    rm -rf "$INSTALL_DIR"/* || {
        log "ERROR" "Failed to clean installation directory"
        return 1
    }
    
    # Clone repository
    log "INFO" "Cloning repository..."
    git clone https://github.com/subGOD/godeye.git . || {
        log "ERROR" "Failed to clone repository"
        return 1
    }

    # Configure npm
    log "INFO" "Configuring npm..."
    cat > .npmrc << 'EOF'
unsafe-perm=true
legacy-peer-deps=true
registry=https://registry.npmjs.org/
EOF

    # Generate secure secrets
    log "INFO" "Generating security credentials..."
    local jwt_secret=$(openssl rand -base64 32)
    local redis_pass=$(openssl rand -base64 24)

    # Create environment file
    log "INFO" "Creating environment configuration..."
    cat > .env << EOF
JWT_SECRET="$jwt_secret"
REDIS_PASSWORD="$redis_pass"
PORT=$APP_PORT
NODE_ENV=production
EOF

    # Install project dependencies
    log "INFO" "Installing project dependencies..."
    npm install --no-audit --no-fund --legacy-peer-deps \
        bcrypt \
        winston \
        express-rate-limit \
        helmet \
        cors \
        express \
        jsonwebtoken \
        ioredis || {
        log "ERROR" "Failed to install project dependencies"
        return 1
    }
    
    # Build application
    log "INFO" "Building application..."
    NODE_ENV=production npm run build || {
        log "ERROR" "Build failed"
        cat npm-debug.log >> "$ERROR_LOG_FILE"
        return 1
    }
    
    # Verify build
    if [ ! -d "dist" ]; then
        log "ERROR" "Build directory not created"
        return 1
    fi
    
    # Set permissions
    log "INFO" "Setting application permissions..."
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"
    chmod 600 "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.npmrc"
    chmod -R 755 "$INSTALL_DIR/dist"
    
    # Store Redis password for service configuration
    REDIS_PASSWORD="$redis_pass"
    
    log "SUCCESS" "Application setup complete"
    return 0
}

setup_services() {
    log "INFO" "Configuring services..."

    # Configure Redis
    log "INFO" "Configuring Redis..."
    if [ -f "/etc/redis/redis.conf" ]; then
        sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
        systemctl restart redis-server || {
            log "ERROR" "Failed to restart Redis"
            journalctl -u redis-server --no-pager -n 50 >> "$ERROR_LOG_FILE"
            return 1
        }
    else
        log "ERROR" "Redis configuration file not found"
        return 1
    fi

    # API Service
    log "INFO" "Creating API service..."
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
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target
EOF

    # Frontend Service
    log "INFO" "Creating frontend service..."
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
ExecStart=/usr/bin/npm run preview -- --port $FRONTEND_PORT --host
Restart=always
RestartSec=10
StandardOutput=append:/var/log/godeye/frontend.log
StandardError=append:/var/log/godeye/frontend-error.log
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions for service files
    chmod 644 /etc/systemd/system/godeye-api.service
    chmod 644 /etc/systemd/system/godeye-frontend.service

    # Configure firewall
    log "INFO" "Configuring firewall..."
    if command -v ufw >/dev/null 2>&1; then
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow $NGINX_PORT/tcp
        ufw --force enable
    else
        log "WARN" "UFW not found, skipping firewall configuration"
    fi

    # Reload systemd and start services
    log "INFO" "Starting services..."
    systemctl daemon-reload

    local services=(redis-server godeye-api godeye-frontend nginx)
    for service in "${services[@]}"; do
        log "INFO" "Enabling and starting $service..."
        systemctl enable "$service"
        systemctl restart "$service" || {
            log "ERROR" "Failed to start $service"
            journalctl -u "$service" --no-pager -n 50 >> "$ERROR_LOG_FILE"
            return 1
        }
        log "SUCCESS" "Service $service started"
    done

    # Verify all services are running
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log "ERROR" "Service $service failed to start"
            return 1
        fi
    done

    log "SUCCESS" "All services configured and started"
    return 0
}

verify_installation() {
    log "INFO" "Verifying installation..."
    
    local failed=0
    
    # Verify system user and group
    if ! id "$APP_USER" >/dev/null 2>&1; then
        log "ERROR" "System user $APP_USER does not exist"
        failed=1
    fi

    if ! getent group "$APP_GROUP" >/dev/null 2>&1; then
        log "ERROR" "System group $APP_GROUP does not exist"
        failed=1
    fi
    
    # Verify services
    local services=(redis-server godeye-api godeye-frontend nginx)
    for service in "${services[@]}"; do
        log "INFO" "Checking service: $service"
        if ! systemctl is-active --quiet "$service"; then
            log "ERROR" "Service $service is not running"
            journalctl -u "$service" --no-pager -n 50 >> "$ERROR_LOG_FILE"
            failed=1
        else
            log "SUCCESS" "Service $service is running"
        fi
    done

    # Verify ports
    local ports=($APP_PORT $FRONTEND_PORT $NGINX_PORT)
    for port in "${ports[@]}"; do
        log "INFO" "Checking port: $port"
        if ! netstat -tuln | grep -q ":$port "; then
            log "ERROR" "Port $port is not listening"
            failed=1
        else
            log "SUCCESS" "Port $port is listening"
        fi
    done

    # Verify Redis connection
    log "INFO" "Verifying Redis connection..."
    if ! redis-cli ping > /dev/null 2>&1; then
        log "ERROR" "Redis connection failed"
        failed=1
    else
        log "SUCCESS" "Redis connection verified"
    fi

    # Verify Nginx configuration
    log "INFO" "Verifying Nginx configuration..."
    if ! nginx -t >/dev/null 2>&1; then
        log "ERROR" "Nginx configuration test failed"
        nginx -t >> "$ERROR_LOG_FILE" 2>&1
        failed=1
    else
        log "SUCCESS" "Nginx configuration verified"
    fi

    # Verify API health
    log "INFO" "Verifying API health..."
    if ! curl -s "http://localhost:$APP_PORT/api/setup/status" >/dev/null; then
        log "ERROR" "API health check failed"
        failed=1
    else
        log "SUCCESS" "API health verified"
    fi

    # Final verification result
    if [ $failed -eq 1 ]; then
        log "ERROR" "Installation verification failed"
        return 1
    fi

    local ip_address=$(hostname -I | awk '{print $1}')
    
    log "SUCCESS" "Installation verified successfully"
    
    # Display completion banner
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║             godEye Installation Complete                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}Access your installation at:${NC} http://${ip_address}:${NGINX_PORT}"
    echo -e "\n${CYAN}Complete the setup:${NC}"
    echo -e "1. Visit the URL above"
    echo -e "2. Create your administrator account"
    echo -e "3. Make sure to use a strong password"
    
    echo -e "\n${CYAN}Useful Commands:${NC}"
    echo -e "View API logs: ${NC}sudo journalctl -u godeye-api -f"
    echo -e "View frontend logs: ${NC}sudo journalctl -u godeye-frontend -f"
    echo -e "Restart services: ${NC}sudo systemctl restart godeye-api godeye-frontend"
    
    return 0
}

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Installation failed with exit code: $exit_code"
        
        # Stop any running services
        local services=(godeye-api godeye-frontend nginx redis-server)
        for service in "${services[@]}"; do
            if systemctl is-active --quiet "$service"; then
                log "INFO" "Stopping $service..."
                systemctl stop "$service"
            fi
        done
        
        # Log final error status
        echo -e "\n${RED}Installation failed. Please check the logs:${NC}"
        echo "Error log: $ERROR_LOG_FILE"
        echo "Install log: $LOG_FILE"
    fi
}

main() {
    # Register cleanup handler
    trap cleanup EXIT
    
    # Display welcome banner
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                   godEye Installer                     ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Initialize logging
    init_logging
    
    # Run installation steps with proper error handling
    check_requirements || {
        log "ERROR" "System requirements check failed"
        exit 1
    }
    
    check_internet || {
        log "ERROR" "Internet connectivity check failed"
        exit 1
    }
    
    install_dependencies || {
        log "ERROR" "Dependencies installation failed"
        exit 1
    }
    
    setup_user || {
        log "ERROR" "User setup failed"
        exit 1
    }
    
    setup_application || {
        log "ERROR" "Application setup failed"
        exit 1
    }
    
    setup_services || {
        log "ERROR" "Services setup failed"
        exit 1
    }
    
    verify_installation || {
        log "ERROR" "Installation verification failed"
        exit 1
    }
}

# Start installation
main "$@"