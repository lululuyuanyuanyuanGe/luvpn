#!/bin/bash
#====================================================================
# Full Setup Orchestrator
# Runs Trojan-Go setup followed by Cloudflare DDNS setup
# Usage: sudo bash setup.sh
#====================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    err "Please run as root: sudo bash setup.sh"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

#====================================================================
# Step 1: Trojan-Go Setup
#====================================================================
echo ""
echo "========================================================================="
log "  Phase 1: Trojan-Go VPN Setup"
echo "========================================================================="
echo ""

bash "${SCRIPT_DIR}/setup-trojan-go.sh"

#====================================================================
# Step 2: Cloudflare DDNS Setup
#====================================================================
echo ""
echo "========================================================================="
log "  Phase 2: Cloudflare Dynamic DNS Setup"
echo "========================================================================="
echo ""

bash "${SCRIPT_DIR}/setup-cloudflare-ddns.sh"

#====================================================================
# Done
#====================================================================
echo ""
echo "========================================================================="
echo -e "${GREEN} ALL SETUP COMPLETE!${NC}"
echo "========================================================================="
echo ""
echo "  Both Trojan-Go and Cloudflare DDNS are now configured and running."
echo ""
echo "  Quick status check:"
echo "    sudo systemctl status trojan-go"
echo "    sudo systemctl status cloudflare-ddns.timer"
echo ""
echo "========================================================================="
