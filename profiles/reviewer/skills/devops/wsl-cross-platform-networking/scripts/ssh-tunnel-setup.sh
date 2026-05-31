#!/bin/bash
# ssh-tunnel-setup.sh
# Setup persistent SSH tunnel for AionUI (WSL → Windows)
# 
# Usage: source this file or run ./ssh-tunnel-setup.sh

set -euo pipefail

# Configuration
WINDOWS_USER="${WINDOWS_USER:-$(whoami)}"
WINDOWS_HOST="${WINDOWS_HOST:-192.168.0.40}"
SSH_PORT="${SSH_PORT:-22}"
AIONUI_PORT="${AIONUI_PORT:-62936}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/aionui_id}"
SERVICE_NAME="aionui-ssh-tunnel"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check prerequisites
check_prerequisites() {
    local missing=()
    
    command -v ssh >/dev/null 2>&1 || missing+=("ssh")
    command -v systemctl >/dev/null 2>&1 || missing+=("systemctl")
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing prerequisites: ${missing[*]}"
        return 1
    fi
    
    info "Prerequisites OK"
    return 0
}

# Generate SSH key if it doesn't exist
generate_ssh_key() {
    if [ ! -f "${SSH_KEY}" ]; then
        info "Generating SSH key: ${SSH_KEY}"
        mkdir -p "$(dirname "${SSH_KEY}")"
        ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "aionui-tunnel@${HOSTNAME}"
    else
        info "SSH key already exists: ${SSH_KEY}"
    fi
}

# Create systemd user service
create_systemd_service() {
    local user_systemd="$HOME/.config/systemd/user"
    local service_file="${user_systemd}/${SERVICE_NAME}.service"
    
    mkdir -p "${user_systemd}"
    
    cat > "${service_file}" << EOF
[Unit]
Description=AionUI SSH Tunnel (WSL → Windows)
Documentation=https://github.com/iOfficeAI/AionUi
After=network.target
Wants=network.target

[Service]
Type=simple
Environment="WINDOWS_USER=${WINDOWS_USER}"
Environment="WINDOWS_HOST=${WINDOWS_HOST}"
Environment="SSH_PORT=${SSH_PORT}"
Environment="AIONUI_PORT=${AIONUI_PORT}"
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/ssh -i ${SSH_KEY} \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -p ${SSH_PORT} \
    -L ${AIONUI_PORT}:127.0.0.1:${AIONUI_PORT} \
    -N \
    ${WINDOWS_USER}@${WINDOWS_HOST}
Restart=always
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=default.target
EOF
    
    info "Created systemd service: ${service_file}"
}

# Enable and start the service
enable_service() {
    info "Reloading systemd daemon..."
    systemctl --user daemon-reload
    
    info "Enabling ${SERVICE_NAME}..."
    systemctl --user enable "${SERVICE_NAME}"
    
    info "Starting ${SERVICE_NAME}..."
    systemctl --user restart "${SERVICE_NAME}"
    
    sleep 2
    
    if systemctl --user is-active --quiet "${SERVICE_NAME}"; then
        info "Service is running!"
        systemctl --user status "${SERVICE_NAME}" --no-pager -l
    else
        error "Service failed to start"
        systemctl --user status "${SERVICE_NAME}" --no-pager -l
        return 1
    fi
}

# Show SSH key public part for Windows authorized_keys
show_ssh_key() {
    echo
    info "Add this public key to Windows:"
    echo "  C:\\Users\\${WINDOWS_USER}\\.ssh\\authorized_keys"
    echo
    echo "----- Begin Public Key -----"
    cat "${SSH_KEY}.pub"
    echo "----- End Public Key -----"
    echo
}

# Manual connection without systemd
start_manual() {
    info "Starting manual SSH tunnel (Ctrl+C to stop)..."
    ssh -i "${SSH_KEY}" \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -L "${AIONUI_PORT}:127.0.0.1:${AIONUI_PORT}" \
        -N \
        "${WINDOWS_USER}@${WINDOWS_HOST}"
}

# Stop the service
stop_service() {
    info "Stopping ${SERVICE_NAME}..."
    systemctl --user stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}" 2>/dev/null || true
    info "Stopped."
}

# Check status
show_status() {
    echo
    info "Service Status:"
    systemctl --user status "${SERVICE_NAME}" --no-pager -l 2>/dev/null || echo "  (not installed)"
    echo
    
    info "Port ${AIONUI_PORT} connectivity:"
    if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/${AIONUI_PORT}" 2>/dev/null; then
        echo "  ✓ Port ${AIONUI_PORT} is accessible"
    else
        echo "  ✗ Port ${AIONUI_PORT} is not accessible"
    fi
}

# Main
case "${1:-setup}" in
    setup)
        check_prerequisites
        generate_ssh_key
        create_systemd_service
        enable_service
        show_ssh_key
        show_status
        ;;
    start)
        enable_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        stop_service
        enable_service
        ;;
    manual)
        start_manual
        ;;
    status)
        show_status
        ;;
    uninstall)
        stop_service
        rm -f "$HOME/.config/systemd/user/${SERVICE_NAME}.service"
        systemctl --user daemon-reload
        info "Uninstalled"
        ;;
    *)
        echo "Usage: $0 {setup|start|stop|restart|manual|status|uninstall}"
        echo
        echo "  setup    - Full setup (default): generate key, install service, start"
        echo "  start    - Start the tunnel service"
        echo "  stop     - Stop the tunnel service"
        echo "  restart  - Restart the tunnel service"
        echo "  manual   - Start tunnel manually (foreground, Ctrl+C to stop)"
        echo "  status   - Show service and port status"
        echo "  uninstall - Remove service and clean up"
        exit 1
        ;;
esac
