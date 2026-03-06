#!/bin/bash
#====================================================================
# Cloudflare Dynamic DNS Setup Script
# Automatically updates Cloudflare DNS when your public IP changes
# Usage: sudo bash setup-cloudflare-ddns.sh
#====================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Paths
CONFIG_DIR="/etc/cloudflare-ddns"
CONFIG_FILE="${CONFIG_DIR}/config"
UPDATER_SCRIPT="/usr/local/bin/cloudflare-ddns-update.sh"
LOG_FILE="/var/log/cloudflare-ddns.log"

#====================================================================
# Root check
#====================================================================
if [ "$EUID" -ne 0 ]; then
    err "Please run as root: sudo bash setup-cloudflare-ddns.sh"
fi

#====================================================================
# Step 1: Install dependencies
#====================================================================
log "Step 1: Checking dependencies..."

if ! command -v curl &>/dev/null; then
    err "curl is required but not installed. Run: apt install curl"
fi

if ! command -v jq &>/dev/null; then
    log "Installing jq..."
    apt update && apt install -y jq
fi

log "Dependencies OK (curl, jq)"

#====================================================================
# Step 2: Interactive configuration
#====================================================================
log "Step 2: Configuring Cloudflare DDNS..."

# --- API Token ---
read -p "Enter your Cloudflare API Token: " CF_API_TOKEN
if [ -z "$CF_API_TOKEN" ]; then
    err "API token is required"
fi

log "Validating API token..."
TOKEN_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

TOKEN_VALID=$(echo "$TOKEN_CHECK" | jq -r '.success')
if [ "$TOKEN_VALID" != "true" ]; then
    err "API token validation failed. Check your token and try again."
fi
log "API token is valid"

# --- Domain ---
read -p "Enter your domain (e.g., hazelorange.com) [hazelorange.com]: " CF_DOMAIN
CF_DOMAIN="${CF_DOMAIN:-hazelorange.com}"

# --- Record name ---
read -p "Enter DNS record name [${CF_DOMAIN}]: " CF_RECORD_NAME
CF_RECORD_NAME="${CF_RECORD_NAME:-$CF_DOMAIN}"

# --- Zone ID (auto-discover) ---
log "Looking up Zone ID for ${CF_DOMAIN}..."
ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CF_DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

CF_ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[0].id // empty')

if [ -n "$CF_ZONE_ID" ]; then
    log "Found Zone ID: ${CF_ZONE_ID}"
else
    warn "Could not auto-discover Zone ID"
    read -p "Enter your Cloudflare Zone ID manually: " CF_ZONE_ID
    if [ -z "$CF_ZONE_ID" ]; then
        err "Zone ID is required"
    fi
fi

# --- Record ID (auto-discover) ---
log "Looking up A record for ${CF_RECORD_NAME}..."
RECORD_RESPONSE=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${CF_RECORD_NAME}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

CF_RECORD_ID=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].id // empty')

if [ -n "$CF_RECORD_ID" ]; then
    CURRENT_DNS_IP=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].content // empty')
    log "Found existing A record: ${CF_RECORD_NAME} -> ${CURRENT_DNS_IP}"
else
    warn "No existing A record found for ${CF_RECORD_NAME}"
    read -p "Create a new A record? (y/n): " CREATE_RECORD
    if [ "$CREATE_RECORD" = "y" ]; then
        log "Getting current public IP..."
        CURRENT_IP=$(curl -s --max-time 10 "https://api.ipify.org" 2>/dev/null || \
                     curl -s --max-time 10 "https://icanhazip.com" 2>/dev/null || \
                     curl -s --max-time 10 "https://ifconfig.me/ip" 2>/dev/null)
        CURRENT_IP=$(echo "$CURRENT_IP" | tr -d '[:space:]')

        if [ -z "$CURRENT_IP" ]; then
            err "Could not determine public IP to create DNS record"
        fi

        log "Creating A record ${CF_RECORD_NAME} -> ${CURRENT_IP}..."
        CREATE_RESPONSE=$(curl -s -X POST \
            "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${CF_RECORD_NAME}\",\"content\":\"${CURRENT_IP}\",\"ttl\":1,\"proxied\":false}")

        CREATE_SUCCESS=$(echo "$CREATE_RESPONSE" | jq -r '.success')
        if [ "$CREATE_SUCCESS" = "true" ]; then
            CF_RECORD_ID=$(echo "$CREATE_RESPONSE" | jq -r '.result.id')
            log "A record created: ${CF_RECORD_ID}"
        else
            CREATE_ERRORS=$(echo "$CREATE_RESPONSE" | jq -r '.errors[]?.message // "Unknown error"')
            err "Failed to create A record: ${CREATE_ERRORS}"
        fi
    else
        err "Cannot proceed without an A record"
    fi
fi

# --- Proxied status ---
read -p "Enable Cloudflare proxy (orange cloud)? (y/n) [n]: " CF_PROXIED_INPUT
if [ "$CF_PROXIED_INPUT" = "y" ]; then
    CF_PROXIED="true"
else
    CF_PROXIED="false"
fi

# --- Confirmation ---
echo ""
log "========================================="
log "  Cloudflare DDNS Configuration"
log "========================================="
log "Domain:      $CF_DOMAIN"
log "Record:      $CF_RECORD_NAME"
log "Zone ID:     $CF_ZONE_ID"
log "Record ID:   $CF_RECORD_ID"
log "Proxied:     $CF_PROXIED"
log "Interval:    Every 5 minutes"
log "========================================="
echo ""
read -p "Proceed with setup? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
fi

#====================================================================
# Step 3: Save configuration
#====================================================================
log "Step 3: Saving configuration..."

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<CFEOF
# Cloudflare DDNS Configuration
# Generated on $(date)
CF_API_TOKEN="${CF_API_TOKEN}"
CF_ZONE_ID="${CF_ZONE_ID}"
CF_RECORD_ID="${CF_RECORD_ID}"
CF_RECORD_NAME="${CF_RECORD_NAME}"
CF_PROXIED=${CF_PROXIED}
CFEOF

chmod 600 "$CONFIG_FILE"
chown root:root "$CONFIG_FILE"
log "Config saved to ${CONFIG_FILE} (permissions: 600)"

#====================================================================
# Step 4: Create DDNS updater script
#====================================================================
log "Step 4: Creating DDNS updater script..."

cat > "$UPDATER_SCRIPT" <<'SCRIPT'
#!/bin/bash
# Cloudflare DDNS Updater
# Runs via systemd timer to keep DNS in sync with public IP

CONFIG_FILE="/etc/cloudflare-ddns/config"
LOG_FILE="/var/log/cloudflare-ddns.log"
CACHE_FILE="/var/tmp/cloudflare-ddns-ip.cache"

log_msg() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
    log_msg "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi
source "$CONFIG_FILE"

# Get current public IP (try multiple services)
get_public_ip() {
    local ip=""
    for service in "https://api.ipify.org" "https://icanhazip.com" "https://ifconfig.me/ip"; do
        ip=$(curl -s --max-time 10 "$service" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

CURRENT_IP=$(get_public_ip) || { log_msg "ERROR: Failed to determine public IP"; exit 1; }

# Check cache — skip if IP hasn't changed
if [ -f "$CACHE_FILE" ]; then
    CACHED_IP=$(cat "$CACHE_FILE")
    if [ "$CURRENT_IP" = "$CACHED_IP" ]; then
        exit 0
    fi
fi

# Fetch current DNS record from Cloudflare
DNS_RESPONSE=$(curl -s --max-time 15 -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

DNS_IP=$(echo "$DNS_RESPONSE" | jq -r '.result.content // empty')

if [ -z "$DNS_IP" ]; then
    log_msg "ERROR: Failed to get DNS record from Cloudflare"
    exit 1
fi

# Update cache and exit if IPs match
if [ "$CURRENT_IP" = "$DNS_IP" ]; then
    echo "$CURRENT_IP" > "$CACHE_FILE"
    exit 0
fi

# IPs differ — update Cloudflare
log_msg "IP changed: $DNS_IP -> $CURRENT_IP, updating DNS..."

UPDATE_RESPONSE=$(curl -s --max-time 15 -X PUT \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${CF_RECORD_NAME}\",\"content\":\"${CURRENT_IP}\",\"ttl\":1,\"proxied\":${CF_PROXIED}}")

SUCCESS=$(echo "$UPDATE_RESPONSE" | jq -r '.success')

if [ "$SUCCESS" = "true" ]; then
    log_msg "SUCCESS: DNS updated to $CURRENT_IP"
    echo "$CURRENT_IP" > "$CACHE_FILE"
else
    ERRORS=$(echo "$UPDATE_RESPONSE" | jq -r '.errors[]?.message // "Unknown error"')
    log_msg "ERROR: DNS update failed: $ERRORS"
    exit 1
fi
SCRIPT

chmod +x "$UPDATER_SCRIPT"
log "Updater script created at ${UPDATER_SCRIPT}"

#====================================================================
# Step 5: Create systemd service and timer
#====================================================================
log "Step 5: Creating systemd service and timer..."

cat > /etc/systemd/system/cloudflare-ddns.service <<'SVCEOF'
[Unit]
Description=Cloudflare Dynamic DNS Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cloudflare-ddns-update.sh
SVCEOF

cat > /etc/systemd/system/cloudflare-ddns.timer <<'SVCEOF'
[Unit]
Description=Run Cloudflare DDNS updater every 5 minutes

[Timer]
OnBootSec=30s
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
SVCEOF

systemctl daemon-reload
log "Systemd service and timer created"

#====================================================================
# Step 6: Configure log rotation
#====================================================================
log "Step 6: Configuring log rotation..."

cat > /etc/logrotate.d/cloudflare-ddns <<'LREOF'
/var/log/cloudflare-ddns.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
LREOF

log "Log rotation configured"

#====================================================================
# Step 7: Enable and start
#====================================================================
log "Step 7: Starting DDNS service..."

systemctl enable --now cloudflare-ddns.timer

# Run once immediately
log "Running initial DDNS update..."
systemctl start cloudflare-ddns.service || warn "Initial update had an issue, check logs"

sleep 2

if systemctl is-active --quiet cloudflare-ddns.timer; then
    log "DDNS timer is running!"
else
    warn "DDNS timer may not have started. Check: systemctl status cloudflare-ddns.timer"
fi

#====================================================================
# Done
#====================================================================
echo ""
echo "========================================================================="
echo -e "${GREEN} CLOUDFLARE DDNS SETUP COMPLETE!${NC}"
echo "========================================================================="
echo ""
echo "  Domain:     $CF_RECORD_NAME"
echo "  Zone ID:    $CF_ZONE_ID"
echo "  Record ID:  $CF_RECORD_ID"
echo "  Proxied:    $CF_PROXIED"
echo "  Interval:   Every 5 minutes"
echo ""
echo "  Config:     $CONFIG_FILE"
echo "  Updater:    $UPDATER_SCRIPT"
echo "  Log:        $LOG_FILE"
echo ""
echo "========================================================================="
echo ""
echo "  Useful commands:"
echo "    sudo systemctl status cloudflare-ddns.timer    # Check timer status"
echo "    sudo systemctl list-timers cloudflare-ddns*    # Next run time"
echo "    sudo systemctl start cloudflare-ddns.service   # Force update now"
echo "    sudo tail -f $LOG_FILE      # View logs"
echo "    sudo cat $CONFIG_FILE           # View config"
echo ""
echo "========================================================================="
