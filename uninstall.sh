#!/bin/bash

# Enable error tracing
set -eE

# Core variables
LOG_FILE="/var/log/godeye/uninstall.log"
ERROR_LOG_FILE="/var/log/godeye/uninstall_error.log"
INSTALL_DIR="/opt/godeye"
APP_USER="godeye"
APP_GROUP="godeye"
NGINX_PORT="1337"

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
BLUE='\e[34m'
CYAN='\e[38;5;123m'
NC='\e[0m'

# Enhanced logging
log() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${!level}[${level}]${NC} $msg"
    
    # Create log directory if it doesn't exist
    [ ! -d "/var/log/godeye" ] && mkdir -p "/var/log/godeye"
    
    echo "[$timestamp] [${level}] $msg" >> "$LOG_FILE"
}

error_handler() {
    local line_no=$1
    local error_code=$2
    log "ERROR" "Error occurred in script at line: $line_no (Exit code: $error_code)"
    echo "Check $ERROR_LOG_FILE for details."
}

trap 'error_handler ${LINENO} $?' ERR

# Display banner
show_banner() {
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
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log "ERROR" "Please run as root or with sudo"
        exit 1
    fi
}

stop_services() {
    log "INFO" "Stopping services..."
    
    local services=("godeye-api" "godeye-frontend" "redis-server")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log "INFO" "Stopping $service..."
            systemctl stop "$service"
            systemctl disable "$service"
        fi
    done
    
    # Give services time to properly shut down
    sleep 2
}

remove_files() {
    log "INFO" "Removing application files..."
    
    # Remove service files
    local service_files=(
        "/etc/systemd/system/godeye-api.service"
        "/etc/systemd/system/godeye-frontend.service"
    )
    
    for file in "${service_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
        fi
    done
    
    # Reload systemd
    systemctl daemon-reload
    
    # Remove nginx configuration
    if [ -f "/etc/nginx/sites-enabled/godeye" ]; then
        rm -f "/etc/nginx/sites-enabled/godeye"
    fi
    if [ -f "/etc/nginx/sites-available/godeye" ]; then
        rm -f "/etc/nginx/sites-available/godeye"
    fi
    
    # Restart nginx if it's running
    if systemctl is-active --quiet nginx; then
        systemctl restart nginx
    fi
    
    # Remove application directory
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
    fi
    
    # Remove logs
    if [ -d "/var/log/godeye" ]; then
        rm -rf "/var/log/godeye"
    fi
}

remove_user() {
    log "INFO" "Removing system user..."
    
    # Kill any remaining processes owned by the user
    if id "$APP_USER" &>/dev/null; then
        pkill -u "$APP_USER" || true
        
        # Remove user and their home directory
        userdel -r "$APP_USER" 2>/dev/null || true
    fi
    
    # Remove group if it exists
    if getent group "$APP_GROUP" >/dev/null; then
        groupdel "$APP_GROUP" 2>/dev/null || true
    fi
}

update_firewall() {
    log "INFO" "Updating firewall rules..."
    
    if command -v ufw >/dev/null; then
        # Remove the nginx port rule
        ufw delete allow "$NGINX_PORT"/tcp
        
        # Reload firewall
        ufw reload
    fi
}

cleanup_redis() {
    log "INFO" "Cleaning up Redis..."
    
    # Clear Redis configuration
    if [ -f "/etc/redis/redis.conf" ]; then
        # Remove password configuration
        sed -i 's/^requirepass.*/#requirepass foobared/' /etc/redis/redis.conf
        
        # Restart Redis if it's still installed and running
        if systemctl is-active --quiet redis-server; then
            systemctl restart redis-server
        fi
    fi
}

verify_uninstall() {
    log "INFO" "Verifying uninstallation..."
    
    local failed=0
    
    # Check if services are stopped
    local services=("godeye-api" "godeye-frontend")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log "ERROR" "Service $service is still running"
            failed=1
        fi
    done
    
    # Check if files are removed
    if [ -d "$INSTALL_DIR" ]; then
        log "ERROR" "Installation directory still exists"
        failed=1
    fi
    
    # Check if user is removed
    if id "$APP_USER" &>/dev/null; then
        log "ERROR" "Application user still exists"
        failed=1
    fi
    
    if [ $failed -eq 0 ]; then
        log "SUCCESS" "Uninstallation completed successfully"
        echo -e "\n${GREEN}godEye has been completely removed from your system${NC}"
    else
        log "ERROR" "Uninstallation completed with errors"
        echo -e "\n${RED}Some components could not be removed. Check the logs for details.${NC}"
        return 1
    fi
}

main() {
    show_banner
    check_root
    
    # Confirm uninstallation
    read -p "Are you sure you want to uninstall godEye? This will remove all data and configurations. [y/N] " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
    
    stop_services
    remove_files
    remove_user
    update_firewall
    cleanup_redis
    verify_uninstall
}

# Start uninstallation
main