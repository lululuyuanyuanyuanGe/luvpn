#!/bin/bash
#====================================================================
# Trojan-Go Automated Setup Script for Raspberry Pi (ARM64)
# Usage: sudo bash setup-trojan-go.sh
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

#====================================================================
# CONFIGURATION - Edit these before running
#====================================================================
DOMAIN=""
PASSWORD=""
WS_PATH="/ws-$(openssl rand -hex 4)"
TROJAN_GO_VERSION="v0.10.6"
FALLBACK_PORT=8080

#====================================================================
# Interactive prompts if not pre-configured
#====================================================================
if [ "$EUID" -ne 0 ]; then
    err "Please run as root: sudo bash setup-trojan-go.sh"
fi

if [ -z "$DOMAIN" ]; then
    read -p "Enter your domain name (e.g. example.com): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    err "Domain name is required"
fi

if [ -z "$PASSWORD" ]; then
    read -p "Enter your Trojan password (leave empty to auto-generate): " PASSWORD
fi

if [ -z "$PASSWORD" ]; then
    PASSWORD=$(openssl rand -base64 32)
    log "Generated password: $PASSWORD"
    log "SAVE THIS PASSWORD - you will need it for client setup"
fi

echo ""
log "========================================="
log "  Trojan-Go Setup Configuration"
log "========================================="
log "Domain:    $DOMAIN"
log "Password:  $PASSWORD"
log "WS Path:   $WS_PATH"
log "========================================="
echo ""
read -p "Proceed with installation? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
fi

#====================================================================
# Step 1: Install dependencies
#====================================================================
log "Step 1: Installing dependencies..."
apt update
apt install -y nginx unzip wget certbot ufw git

#====================================================================
# Step 1.5: Configure UFW firewall
#====================================================================
log "Step 1.5: Configuring UFW firewall..."

ufw allow 22/tcp comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

if ! ufw status | grep -q "Status: active"; then
    log "Enabling UFW..."
    echo "y" | ufw enable
else
    log "UFW already active, rules updated"
    ufw reload
fi

log "UFW configured - SSH (22), HTTP (80), HTTPS (443) allowed"

#====================================================================
# Step 1.6: Configure SSH idle timeout
#====================================================================
log "Step 1.6: Configuring SSH idle timeout..."

sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config

# Add the settings if they don't exist at all
grep -q '^ClientAliveInterval' /etc/ssh/sshd_config || echo 'ClientAliveInterval 300' >> /etc/ssh/sshd_config
grep -q '^ClientAliveCountMax' /etc/ssh/sshd_config || echo 'ClientAliveCountMax 3' >> /etc/ssh/sshd_config

systemctl restart sshd
log "SSH idle timeout set (disconnects after ~15 minutes of inactivity)"

#====================================================================
# Step 2: Obtain TLS certificate
#====================================================================
log "Step 2: Obtaining TLS certificate..."

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    log "Certificate already exists for $DOMAIN, skipping..."
else
    systemctl stop nginx 2>/dev/null || true

    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

    if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        err "Certificate generation failed. Make sure port 80 is open and DNS points to this server."
    fi
    log "Certificate obtained successfully"
fi

# Create renewal hooks
mkdir -p /etc/letsencrypt/renewal-hooks/pre
mkdir -p /etc/letsencrypt/renewal-hooks/post

cat > /etc/letsencrypt/renewal-hooks/pre/stop-trojan.sh <<'HOOK'
#!/bin/bash
systemctl stop trojan-go
systemctl stop nginx
HOOK

cat > /etc/letsencrypt/renewal-hooks/post/start-trojan.sh <<'HOOK'
#!/bin/bash
systemctl start nginx
systemctl start trojan-go
HOOK

chmod +x /etc/letsencrypt/renewal-hooks/pre/stop-trojan.sh
chmod +x /etc/letsencrypt/renewal-hooks/post/start-trojan.sh
log "Renewal hooks created"

#====================================================================
# Step 3: Install Trojan-Go
#====================================================================
log "Step 3: Installing Trojan-Go..."

# Stop trojan-go if running (binary can't be overwritten while in use)
systemctl stop trojan-go 2>/dev/null || true

ARCH=$(uname -m)
case $ARCH in
    aarch64) BINARY="trojan-go-linux-armv8.zip" ;;
    x86_64)  BINARY="trojan-go-linux-amd64.zip" ;;
    armv7l)  BINARY="trojan-go-linux-armv7.zip" ;;
    *)       err "Unsupported architecture: $ARCH" ;;
esac

mkdir -p /usr/local/bin /etc/trojan-go /usr/share/trojan-go /var/log/trojan-go

cd /tmp
wget -q "https://github.com/p4gefau1t/trojan-go/releases/download/${TROJAN_GO_VERSION}/${BINARY}" -O trojan-go.zip
rm -rf /tmp/trojan-go-extract
mkdir -p /tmp/trojan-go-extract
unzip -o trojan-go.zip -d /tmp/trojan-go-extract

cp /tmp/trojan-go-extract/trojan-go /usr/local/bin/trojan-go
chmod +x /usr/local/bin/trojan-go

cp /tmp/trojan-go-extract/geoip.dat /usr/share/trojan-go/ 2>/dev/null || true
cp /tmp/trojan-go-extract/geosite.dat /usr/share/trojan-go/ 2>/dev/null || true

rm -rf /tmp/trojan-go.zip /tmp/trojan-go-extract

log "Trojan-Go installed"

#====================================================================
# Step 4: Configure Trojan-Go
#====================================================================
log "Step 4: Configuring Trojan-Go..."

cat > /etc/trojan-go/config.json <<TJEOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": ${FALLBACK_PORT},
    "log_level": 1,
    "log_file": "/var/log/trojan-go/trojan-go.log",
    "password": [
        "${PASSWORD}"
    ],
    "ssl": {
        "cert": "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem",
        "key": "/etc/letsencrypt/live/${DOMAIN}/privkey.pem",
        "sni": "${DOMAIN}",
        "alpn": ["http/1.1"],
        "fallback_addr": "127.0.0.1",
        "fallback_port": ${FALLBACK_PORT}
    },
    "mux": {
        "enabled": true,
        "concurrency": 8,
        "idle_timeout": 60
    },
    "websocket": {
        "enabled": false,
        "path": "${WS_PATH}",
        "host": "${DOMAIN}"
    },
    "router": {
        "enabled": false,
        "default_policy": "proxy",
        "geoip": "/usr/share/trojan-go/geoip.dat",
        "geosite": "/usr/share/trojan-go/geosite.dat"
    }
}
TJEOF

log "Trojan-Go config created"

#====================================================================
# Step 5: Configure Nginx fallback
#====================================================================
log "Step 5: Configuring Nginx fallback page..."

cat > /etc/nginx/sites-available/trojan-disguise <<NGEOF
server {
    listen 127.0.0.1:${FALLBACK_PORT};
    server_name ${DOMAIN};
    root /var/www/trojan-disguise;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ /\\.git {
        deny all;
    }
}
NGEOF

cat > /etc/nginx/sites-available/redirect <<NGEOF
server {
    listen 80;
    server_name ${DOMAIN};
    location / {
        return 301 https://\$host\$request_uri;
    }
}
NGEOF

PORTFOLIO_REPO="https://github.com/lululuyuanyuanyuanGe/luyuan-resume-portfolio.git"
PORTFOLIO_DIR="/var/www/trojan-disguise"

if [ -d "$PORTFOLIO_DIR/.git" ]; then
    log "Portfolio repo already cloned, pulling latest..."
    git -C "$PORTFOLIO_DIR" pull || warn "Git pull failed, using existing files"
else
    rm -rf "$PORTFOLIO_DIR"
    git clone "$PORTFOLIO_REPO" "$PORTFOLIO_DIR" || err "Failed to clone portfolio repo"
fi

log "Portfolio disguise page deployed"

ln -sf /etc/nginx/sites-available/trojan-disguise /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/redirect /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t || err "Nginx config test failed"
log "Nginx configured"

#====================================================================
# Step 6: Create systemd service
#====================================================================
log "Step 6: Creating systemd service..."

cat > /etc/systemd/system/trojan-go.service <<'SVCEOF'
[Unit]
Description=Trojan-Go Proxy Server
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
log "Systemd service created"

#====================================================================
# Step 6.5: Create portfolio auto-update timer
#====================================================================
log "Step 6.5: Creating portfolio auto-update service..."

cat > /etc/systemd/system/portfolio-update.service <<'SVCEOF'
[Unit]
Description=Pull latest portfolio website from GitHub

[Service]
Type=oneshot
WorkingDirectory=/var/www/trojan-disguise
ExecStart=/usr/bin/git pull --ff-only
SVCEOF

cat > /etc/systemd/system/portfolio-update.timer <<'SVCEOF'
[Unit]
Description=Auto-update portfolio website every 10 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
SVCEOF

systemctl daemon-reload
log "Portfolio auto-update timer created (every 10 minutes)"

#====================================================================
# Step 7: Start services
#====================================================================
log "Step 7: Starting services..."

systemctl enable --now nginx
systemctl enable --now trojan-go
systemctl enable --now portfolio-update.timer

sleep 2

if systemctl is-active --quiet trojan-go; then
    log "Trojan-Go is running!"
else
    err "Trojan-Go failed to start. Check: journalctl -u trojan-go"
fi

if systemctl is-active --quiet nginx; then
    log "Nginx is running!"
else
    err "Nginx failed to start. Check: journalctl -u nginx"
fi

#====================================================================
# Done - Print client info
#====================================================================
echo ""
echo "========================================================================="
echo -e "${GREEN} SETUP COMPLETE!${NC}"
echo "========================================================================="
echo ""
echo "  Domain:     $DOMAIN"
echo "  Password:   $PASSWORD"
echo "  Port:       443"
echo "  WebSocket:  disabled (enable in /etc/trojan-go/config.json if needed)"
echo "  WS Path:    $WS_PATH (for future use)"
echo ""
echo "  v2rayN Share Link (copy and import):"
echo ""
echo "  trojan://${PASSWORD}@${DOMAIN}:443?sni=${DOMAIN}#Trojan-${DOMAIN}"
echo ""
echo "========================================================================="
echo ""
echo "  Useful commands:"
echo "    sudo systemctl status trojan-go    # Check status"
echo "    sudo systemctl restart trojan-go   # Restart"
echo "    sudo tail -f /var/log/trojan-go/trojan-go.log  # Live logs"
echo "    sudo cat /etc/trojan-go/config.json  # View config"
echo ""
echo "  Portfolio auto-update (pulls from GitHub every 10 minutes):"
echo "    sudo systemctl status portfolio-update.timer  # Check timer"
echo "    sudo systemctl start portfolio-update.service # Force update now"
echo ""
echo "  IMPORTANT: Make sure your router forwards ports 80 and 443 to this Pi"
echo "  IMPORTANT: If using Cloudflare, set SSL/TLS to 'Full' or 'Full (Strict)'"
echo "  IMPORTANT: If using Cloudflare, set DNS to 'DNS only' (grey cloud)"
echo ""
echo "========================================================================="
