#!/bin/bash
# Setup firewall rules for LocalSend

# Check if firewalld is running
if ! systemctl is-active --quiet firewalld; then
    echo "  Starting firewalld..."
    sudo systemctl enable --now firewalld
fi

# LocalSend requires port 53317 for discovery and file transfer
if ! sudo firewall-cmd --list-ports 2>/dev/null | grep -q "53317/tcp"; then
    echo "  Opening LocalSend ports (53317/tcp, 53317/udp)..."
    sudo firewall-cmd --permanent --add-port=53317/tcp
    sudo firewall-cmd --permanent --add-port=53317/udp
    sudo firewall-cmd --reload
fi
