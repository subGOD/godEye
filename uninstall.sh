#!/bin/bash

# godEye VPN Management Interface Uninstall Script
# Version: 1.0.0
# Author: subGOD
# Repository: https://github.com/subGOD/godeye
# Description: Complete uninstallation script for godEye VPN Management Interface

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
BLUE='\e[34m'
CYAN='\e[38;5;123m'
NC='\e[0m'

# Display banner
echo -e "${CYAN}
╔═════════════════════[SYSTEM_DEACTIVATION_SEQUENCE]═════════════════════╗
║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   ║
║ ▓                    INITIATING CLEANUP PROTOCOL                    ▓   ║
║ ▓                    ========================                       ▓   ║
║ ▓                                                                  ▓   ║
║ ▓                    [ UNINSTALLING godEye ]                       ▓   ║
║ ▓                                                                  ▓   ║
║ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   ║
╚═══════════════════[COMMENCING_SYSTEM_PURGE]═══════════════════════════╝${NC}
"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}[ERROR] Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] Starting godEye uninstallation...${NC}"

# Stop and disable services
services=("godeye" "godeye-api" "redis-server")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo -e "${BLUE}[INFO] Stopping $service...${NC}"
        systemctl stop "$service"
        systemctl disable "$service"
    fi
done

# Remove service files
echo -e "${BLUE}[INFO] Removing service files...${NC}"
rm -f /etc/systemd/system/godeye.service
rm -f /etc/systemd/system/godeye-api.service
systemctl daemon-reload

# Remove nginx configuration
echo -e "${BLUE}[INFO] Removing nginx configuration...${NC}"
rm -f /etc/nginx/sites-enabled/godeye
rm -f /etc/nginx/sites-available/godeye
systemctl restart nginx

# Remove fail2ban configuration
echo -e "${BLUE}[INFO] Removing fail2ban configuration...${NC}"
rm -f /etc/fail2ban/filter.d/godeye.conf
rm -f /etc/fail2ban/jail.d/godeye.conf
systemctl restart fail2ban

# Remove application files
echo -e "${BLUE}[INFO] Removing application files...${NC}"
rm -rf /opt/godeye
rm -rf /var/log/godeye

# Remove system user
echo -e "${BLUE}[INFO] Removing system user...${NC}"
userdel -r godeye 2>/dev/null

# Remove logs
echo -e "${BLUE}[INFO] Removing log files...${NC}"
rm -f /var/log/godeye_install.log
rm -f /var/log/godeye_error.log

# Update firewall rules
echo -e "${BLUE}[INFO] Updating firewall rules...${NC}"
ufw delete allow 1337/tcp
ufw reload

echo -e "${GREEN}[SUCCESS] godEye has been completely uninstalled${NC}"
echo -e "${GREEN}[SUCCESS] System restored to original state${NC}"