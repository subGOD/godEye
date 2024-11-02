#!/bin/bash

# Clear screen for dramatic effect
clear

# Cybernetic Demon ASCII Art
echo -e "\e[31m
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║     ▄▄█████▓▓██   ██▓ ▄▄▄       ███▄    █  ███▄    █     ║
║     ▓  ██▒ ▓▒ ▒██  ██▒▒████▄     ██ ▀█   █  ██ ▀█   █     ║
║     ▒ ▓██░ ▒░  ▒██ ██░▒██  ▀█▄  ▓██  ▀█ ██▒▓██  ▀█ ██▒    ║
║     ░ ▓██▓ ░   ░ ▐██▓░░██▄▄▄▄██ ▓██▒  ▐▌██▒▓██▒  ▐▌██▒    ║
║       ▒██▒ ░   ░ ██▒▓░ ▓█   ▓██▒▒██░   ▓██░▒██░   ▓██░    ║
║       ▒ ░░      ██▒▒▒  ▒▒   ▓▒█░░ ▒░   ▒ ▒ ░ ▒░   ▒ ▒     ║
║         ░     ▓██ ░▒░   ▒   ▒▒ ░░ ░░   ░ ▒░░ ░░   ░ ▒░    ║
║       ░       ▒ ▒ ░░    ░   ▒      ░   ░ ░    ░   ░ ░     ║
║               ░ ░           ░  ░         ░          ░     ║
║               ░ ░                                          ║
║              ▒█████   █     █░ ███▄    █                 ║
║             ▒██▒  ██▒▓█░ █ ░█░ ██ ▀█   █                 ║
║             ▒██░  ██▒▒█░ █ ░█ ▓██  ▀█ ██▒                ║
║             ▒██   ██░░█░ █ ░█ ▓██▒  ▐▌██▒                ║
║             ░ ████▓▒░░░██▒██▓ ▒██░   ▓██░                ║
║             ░ ▒░▒░▒░ ░ ▓░▒ ▒  ░ ▒░   ▒ ▒                 ║
║               ░ ▒ ▒░   ▒ ░ ░  ░ ░░   ░ ▒░                ║
║             ░ ░ ░ ▒    ░   ░     ░   ░ ░                 ║
║                 ░ ░      ░             ░                 ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝\e[0m"

echo -e "\n\e[34mInitializing godEye Installation...\e[0m\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "\e[31m⚠️  Please run as root or with sudo\e[0m"
    exit 1
fi

# Check for PiVPN
if ! command -v pivpn &> /dev/null; then
    echo -e "\e[31m❌ PiVPN not found. Please install PiVPN first.\e[0m"
    exit 1
fi

echo -e "\e[32m✓ PiVPN detected\e[0m"

# Detect WireGuard port
DETECTED_PORT=""
if [ -f "/etc/wireguard/wg0.conf" ]; then
    DETECTED_PORT=$(grep "ListenPort" /etc/wireguard/wg0.conf | awk '{print $3}')
fi

if [ ! -z "$DETECTED_PORT" ]; then
    echo -e "\n\e[34mDetected WireGuard port: $DETECTED_PORT\e[0m"
    read -p "Is this correct? [Y/n] " -n 1 -r PORT_CONFIRM
    echo
    if [[ $PORT_CONFIRM =~ ^[Nn]$ ]]; then
        DETECTED_PORT=""
    fi
fi

if [ -z "$DETECTED_PORT" ]; then
    while true; do
        read -p "Enter your WireGuard port: " WG_PORT
        # Validate port number
        if [[ "$WG_PORT" =~ ^[0-9]+$ ]] && [ "$WG_PORT" -ge 1 ] && [ "$WG_PORT" -le 65535 ]; then
            DETECTED_PORT=$WG_PORT
            break
        else
            echo -e "\e[31m❌ Invalid port number. Please enter a number between 1 and 65535.\e[0m"
        fi
    done
fi

# Create admin password
echo -e "\n\e[34mSetting up admin credentials...\e[0m"
while true; do
    read -s -p "Enter admin password for godEye: " ADMIN_PASSWORD
    echo
    read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
    echo
    
    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        echo -e "\e[31m❌ Passwords do not match. Try again.\e[0m"
    elif [ ${#ADMIN_PASSWORD} -lt 8 ]; then
        echo -e "\e[31m❌ Password must be at least 8 characters long. Try again.\e[0m"
    else
        break
    fi
done

echo -e "\e[32m✓ Password confirmed\e[0m"

# Install dependencies
echo -e "\n\e[34m📦 Installing dependencies...\e[0m"
apt-get update &> /dev/null
apt-get install -y nodejs npm nginx git &> /dev/null

echo -e "\e[32m✓ Dependencies installed\e[0m"

# Setup directory
echo -e "\n\e[34m📁 Creating installation directory...\e[0m"
mkdir -p /var/www/godeye
cd /var/www/godeye

# Clone repository
echo -e "\e[34m📥 Cloning godEye...\e[0m"
git clone https://github.com/subGOD/godeye.git . &> /dev/null

# Create .env file
cat > .env << EOL
VITE_ADMIN_USERNAME=admin
VITE_ADMIN_PASSWORD=$(echo -n "$ADMIN_PASSWORD" | sha256sum | awk '{print $1}')
VITE_WIREGUARD_PORT=$DETECTED_PORT
EOL

# Install npm packages
echo -e "\e[34m📦 Installing node packages...\e[0m"
npm install &> /dev/null
npm run build &> /dev/null

# Create service file
echo -e "\e[34m🔧 Configuring system service...\e[0m"
cat > /etc/systemd/system/godeye.service << EOL
[Unit]
Description=godEye PiVPN Management Interface
After=network.target

[Service]
Type=simple
User=$SUDO_USER
WorkingDirectory=/var/www/godeye
ExecStart=/usr/bin/npm run preview -- --port 1337 --host
Restart=always
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOL

# Configure Nginx
cat > /etc/nginx/sites-available/godeye << EOL
server {
    listen 1337;
    server_name _;

    location / {
        root /var/www/godeye/dist;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }

    location /api {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

# Enable site
ln -sf /etc/nginx/sites-available/godeye /etc/nginx/sites-enabled/

# Start services
echo -e "\e[34m🚀 Starting services...\e[0m"
systemctl daemon-reload
systemctl enable godeye &> /dev/null
systemctl start godeye
systemctl restart nginx

# Get IP address
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo -e "\n\e[32m✨ Installation complete! ✨\e[0m

\e[34mAccess godEye at:\e[0m http://$IP_ADDRESS:1337

\e[34mCredentials:\e[0m
Username: admin
Password: [your chosen password]

\e[34mUseful commands:\e[0m
To view logs: \e[33msudo journalctl -u godeye -f\e[0m
To restart: \e[33msudo systemctl restart godeye\e[0m

\e[31m🔮 Your PiVPN has been assimilated. Welcome to the future. 🔮\e[0m\n"
