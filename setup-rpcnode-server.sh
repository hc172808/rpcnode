#!/usr/bin/env bash
# ============================================================
# GYDS Chain — RPC Node Setup (Ubuntu 22.04 / Debian)
# Exposes Ethereum-compatible JSON-RPC + WS behind Nginx.
# Usage: sudo GYDS_DOMAIN=rpc.yourdomain.com bash setup-rpcnode-server.sh
# Repo:  https://github.com/hc172808/rpcnode
# ============================================================
set -euo pipefail

APP_USER="gyds"
APP_DIR="/opt/gyds-rpcnode"
REPO_URL="https://github.com/hc172808/rpcnode.git"
BRANCH="main"

GYDS_DATADIR="${GYDS_DATADIR:-/var/lib/gyds-rpcnode}"
GYDS_CHAIN_ID="${GYDS_CHAIN_ID:-13370}"
GYDS_RPC_PORT="${GYDS_RPC_PORT:-8545}"
GYDS_WS_PORT="${GYDS_WS_PORT:-8546}"
GYDS_P2P_PORT="${GYDS_P2P_PORT:-30305}"
DOMAIN="${GYDS_DOMAIN:-rpc.example.com}"
SSH_PORT="22"
GO_VERSION="1.22.4"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[RPC]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && die "Run as root: sudo bash $0"
export DEBIAN_FRONTEND=noninteractive

log "Updating system..."
apt-get update -qq && apt-get upgrade -y

log "Installing base packages..."
apt-get install -y --no-install-recommends \
  curl wget git build-essential ca-certificates \
  jq ufw fail2ban nginx certbot python3-certbot-nginx \
  gnupg software-properties-common

log "Installing Go ${GO_VERSION}..."
install_go() {
  ARCH=$(dpkg --print-architecture | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -O /tmp/go.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  rm -f /tmp/go.tar.gz
  echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
}
if ! command -v go &>/dev/null; then
  install_go
else
  CURRENT="$(go version | awk '{print $3}' | tr -d 'go')"
  [[ "${CURRENT}" != "${GO_VERSION}" ]] && { warn "Upgrading Go..."; install_go; }
fi
export PATH=$PATH:/usr/local/go/bin
log "Go: $(go version)"

log "Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

id "$APP_USER" &>/dev/null || adduser --disabled-password --gecos "" "$APP_USER"
usermod -aG docker "$APP_USER"

log "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow "$GYDS_P2P_PORT"/tcp
ufw allow "$GYDS_P2P_PORT"/udp
ufw --force enable

log "Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local <<-EOF
	[DEFAULT]
	bantime = 1h
	findtime = 10m
	maxretry = 5
	[sshd]
	enabled = true
	port = $SSH_PORT
	EOF
systemctl restart fail2ban && systemctl enable fail2ban

log "Cloning repo..."
mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/.git" ]; then
  git clone "$REPO_URL" "$APP_DIR"
else
  git -C "$APP_DIR" config --global --add safe.directory "$APP_DIR"
  git -C "$APP_DIR" fetch origin
  git -C "$APP_DIR" reset --hard "origin/$BRANCH"
fi
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

log "Setting up .env..."
[ -f "$APP_DIR/.env.example" ] || die ".env.example not found in repo"
cp "$APP_DIR/.env.example" "$APP_DIR/.env"
chmod 600 "$APP_DIR/.env"
printf '\nGYDS_RPC_PORT=%s\nGYDS_P2P_PORT=%s\nGYDS_DATA_DIR=%s\n' \
  "$GYDS_RPC_PORT" "$GYDS_P2P_PORT" "$GYDS_DATADIR" >> "$APP_DIR/.env"

log "Creating data directories..."
mkdir -p "${GYDS_DATADIR}"/{chaindata,logs}
chown -R "$APP_USER:$APP_USER" "$GYDS_DATADIR"

log "Building binary..."
cd "$APP_DIR"
make build 2>/dev/null || go build -ldflags="-s -w" -o bin/gyds-rpcnode .

log "Building + starting Docker container..."
docker compose down --remove-orphans 2>/dev/null || true
docker compose build --no-cache
docker compose up -d

log "Configuring Nginx + rate limiting..."
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/gyds-rpc <<-NGINX
	limit_req_zone \$binary_remote_addr zone=rpc_limit:10m rate=60r/m;

	server {
	    listen 80;
	    server_name $DOMAIN;

	    location / {
	        limit_req zone=rpc_limit burst=20 nodelay;
	        proxy_pass http://127.0.0.1:$GYDS_RPC_PORT;
	        proxy_http_version 1.1;
	        proxy_set_header Host \$host;
	        proxy_set_header X-Real-IP \$remote_addr;
	        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	        proxy_connect_timeout 30s;
	        proxy_read_timeout 60s;
	        add_header Access-Control-Allow-Origin "*" always;
	        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
	        add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;
	        if (\$request_method = OPTIONS) { return 204; }
	    }

	    location /ws {
	        proxy_pass http://127.0.0.1:$GYDS_WS_PORT;
	        proxy_http_version 1.1;
	        proxy_set_header Upgrade \$http_upgrade;
	        proxy_set_header Connection "upgrade";
	        proxy_set_header Host \$host;
	        proxy_read_timeout 3600s;
	    }

	    location /health {
	        proxy_pass http://127.0.0.1:$GYDS_RPC_PORT/health;
	        access_log off;
	    }
	}
	NGINX
ln -sf /etc/nginx/sites-available/gyds-rpc /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx && systemctl enable nginx

log "Creating systemd service (native binary)..."
cat > /etc/systemd/system/gyds-rpcnode.service <<-SERVICE
	[Unit]
	Description=GYDS Chain RPC Node
	After=network-online.target
	Wants=network-online.target
	[Service]
	User=$APP_USER
	WorkingDirectory=$APP_DIR
	EnvironmentFile=$APP_DIR/.env
	ExecStart=$APP_DIR/bin/gyds-rpcnode start
	Restart=on-failure
	RestartSec=10s
	LimitNOFILE=65536
	StandardOutput=append:${GYDS_DATADIR}/logs/rpcnode.log
	StandardError=append:${GYDS_DATADIR}/logs/rpcnode-error.log
	[Install]
	WantedBy=multi-user.target
	SERVICE
systemctl daemon-reload

echo ""
echo "╔══════════════════════════════════════╗"
echo "║      GYDS RPC NODE DEPLOYED          ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  JSON-RPC:  http://$DOMAIN/"
echo "  WebSocket: ws://$DOMAIN/ws"
echo "  Health:    http://$DOMAIN/health"
echo ""
echo "  SSL (free): certbot --nginx -d $DOMAIN"
echo ""
echo "  Logs:   cd $APP_DIR && docker compose logs -f"
echo "  Re-run: sudo GYDS_DOMAIN=$DOMAIN ./setup-rpcnode-server.sh"
echo ""
