#!/bin/bash

# Core variables and functions
LOG_FILE="/var/log/godeye_install.log"
ERROR_LOG_FILE="/var/log/godeye_error.log"
COLOR_RED='\e[31m'
COLOR_GREEN='\e[32m'
COLOR_YELLOW='\e[33m'
COLOR_BLUE='\e[34m'
COLOR_CYAN='\e[38;5;123m'
COLOR_NC='\e[0m'

log() { echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $1"; }
error() { echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1" && [[ "$2" == "exit" ]] && exit 1; }
success() { echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $1 ✓"; }
warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $1"; }

# Pre-installation checks
check_prerequisites() {
    [[ $EUID -ne 0 ]] && error "Please run as root" "exit"
    [[ ! $(uname -m) =~ ^(aarch64|arm64|armv7l)$ ]] && error "Unsupported architecture" "exit"
    [[ $(free -m | awk '/^Mem:/{print $2}') -lt 1024 ]] && error "Insufficient RAM" "exit"
    [[ $(df -m /opt | awk 'NR==2 {print $4}') -lt 1024 ]] && error "Insufficient disk space" "exit"
    command -v pivpn >/dev/null || error "PiVPN not found" "exit"
    ping -c 1 google.com >/dev/null 2>&1 || error "No internet connection" "exit"
    
    # Detect WireGuard port
    WG_PORT=$(grep "ListenPort" /etc/wireguard/wg0.conf | awk '{print $3}') || error "WireGuard config not found" "exit"
}

# Quick package installation
install_packages() {
    local packages=(curl nginx git redis-server ufw fail2ban python3 make g++)
    
    apt-get update -y || error "Failed to update package list" "exit"
    
    # Install Node.js first (most time-consuming)
    log "Installing Node.js (this may take several minutes)..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs build-essential || \
    error "Failed to install Node.js" "exit"
    
    # Install other packages in parallel
    log "Installing required packages..."
    for pkg in "${packages[@]}"; do
        dpkg -l | grep -q "^ii  $pkg" || {
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" &
        }
    done
    wait
    
    # Update npm
    npm install -g npm@latest node-gyp || error "Failed to update npm" "exit"
}

# Setup system user and directories
setup_environment() {
    # Create system user
    id godeye &>/dev/null || useradd -r -s /bin/false godeye
    usermod -aG sudo godeye
    
    # Setup directories
    local dirs=("/opt/godeye" "/var/log/godeye" "/home/godeye/.npm")
    for dir in "${dirs[@]}"; do
        rm -rf "$dir"
        mkdir -p "$dir"
        chown -R godeye:godeye "$dir"
        chmod -R 755 "$dir"
    done
    
    # Set credentials
    ADMIN_USER="admin"
    ADMIN_PASS="godEye2024!"
    JWT_SECRET=$(openssl rand -hex 32)
    REDIS_PASSWORD=$(openssl rand -hex 24)
}

# Install and configure application
setup_application() {
    cd /opt/godeye || error "Failed to access installation directory" "exit"
    
    # Clone and setup repository
    git clone https://github.com/subGOD/godeye.git . || error "Failed to clone repository" "exit"

    # Create npmrc file
    cat > .npmrc << EOL
unsafe-perm=true
legacy-peer-deps=true
registry=https://registry.npmjs.org/
EOL
    
    # Create configuration files
    cat > .env << EOL
VITE_ADMIN_USERNAME=$ADMIN_USER
VITE_ADMIN_PASSWORD=$ADMIN_PASS
VITE_WIREGUARD_PORT=$WG_PORT
JWT_SECRET=$JWT_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
EOL

    # Create package.json if not in repo
    if [ ! -f "package.json" ]; then
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
    "@tailwindcss/forms": "^0.5.7",
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
    fi

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
  },
  define: {
    'process.env.NODE_ENV': '"production"'
  }
})
EOL

    # Create Tailwind config
    cat > tailwind.config.js << EOL
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [
    require('@tailwindcss/forms'),
  ],
}
EOL
    
    # Install dependencies and build
    log "Installing dependencies (this may take 10-15 minutes)..."
    npm install --no-audit --no-fund --legacy-peer-deps || error "Failed to install dependencies" "exit"
    
    log "Building application..."
    NODE_ENV=production npm run build || error "Build failed" "exit"
    
    [[ ! -d "dist" ]] && error "Build directory not created" "exit"
    
    # Set permissions
    chown -R godeye:godeye /opt/godeye
    chmod 600 /opt/godeye/.env
}

# Configure services and security
setup_services() {
    # Configure Redis
    sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    systemctl restart redis-server
    
    # Create service files
    local services=(api frontend)
    for svc in "${services[@]}"; do
        cat > "/etc/systemd/system/godeye-${svc}.service" << EOL
[Unit]
Description=godEye ${svc^}
After=network.target
Wants=redis-server.service

[Service]
Type=simple
User=godeye
WorkingDirectory=/opt/godeye
Environment=NODE_ENV=production
Environment=PORT=${svc == "api" && echo "3001" || echo "3000"}
ExecStart=/usr/bin/${svc == "api" && echo "node server.js" || echo "npm run preview -- --port 3000"}
Restart=always
StandardOutput=append:/var/log/godeye/${svc}.log
StandardError=append:/var/log/godeye/${svc}-error.log

[Install]
WantedBy=multi-user.target
EOL
    done
    
    # Configure Nginx
    cat > /etc/nginx/sites-available/godeye << EOL
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
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
    
    location /api {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL
    
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/
    
    # Configure security
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 1337/tcp
    ufw allow "$WG_PORT"/udp
    echo "y" | ufw enable
    
    # Start services
    systemctl daemon-reload
    local services=(redis-server godeye-api godeye-frontend nginx)
    for svc in "${services[@]}"; do
        systemctl enable "$svc"
        systemctl restart "$svc"
    done
}

# Main installation sequence
main() {
    log "Starting installation..."
    
    check_prerequisites
    install_packages
    setup_environment
    setup_application
    setup_services
    
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    if curl -s -o /dev/null -w "%{http_code}" "http://$IP_ADDRESS:1337"; then
        success "Installation complete! Access at http://$IP_ADDRESS:1337"
        log "Default credentials: admin / godEye2024!"
        warn "IMPORTANT: Change your password after first login!"
    else
        error "Installation completed but service is not accessible"
    fi
}

main "$@"