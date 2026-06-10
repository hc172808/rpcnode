#!/usr/bin/env bash
# ============================================================
# GYDS Chain — RPC Node Setup
# Supports: Ubuntu 20.04/22.04/24.04, Debian 11/12,
#           CentOS/RHEL/Rocky/AlmaLinux 8/9, Fedora 38+
#
# Usage: sudo bash setup-rpcnode-server.sh [OPTIONS]
#
# Options:
#   --datadir  DIR     Chain data directory (default: /var/lib/gyds-rpcnode)
#   --rpc-port PORT    JSON-RPC HTTP port (default: 8545)
#   --ws-port  PORT    WebSocket port (default: 8546)
#   --p2p-port PORT    P2P port (default: 30303)
#   --ssh-port PORT    SSH port for firewall (default: 22)
#   --domain   DOMAIN  Domain name for TLS via Certbot (optional)
#   --bootstrap-nodes  Comma-separated peer list
#   --log-level LEVEL  trace|debug|info|warn|error (default: info)
#   --no-docker        Run as native systemd service
#   --update           Update existing installation
#   --uninstall        Remove node (preserves chain data)
#   --help             Show this help and exit
# ============================================================
set -euo pipefail

APP_NAME="gyds-rpcnode"
APP_USER="gyds"
APP_DIR="/opt/gyds-rpcnode"
REPO_URL="https://github.com/hc172808/rpcnode.git"
BRANCH="main"
GO_VERSION="1.22.4"

GYDS_DATADIR="${GYDS_DATADIR:-/var/lib/gyds-rpcnode}"
GYDS_CHAIN_ID="${GYDS_CHAIN_ID:-13370}"
GYDS_RPC_PORT="${GYDS_RPC_PORT:-8545}"
GYDS_WS_PORT="${GYDS_WS_PORT:-8546}"
GYDS_P2P_PORT="${GYDS_P2P_PORT:-30303}"
SSH_PORT="22"
DOMAIN=""
LOG_LEVEL="info"
BOOTSTRAP_NODES=""
USE_DOCKER=true
IS_UPDATE=false
UNINSTALL=false

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[RPC]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

show_help() {
  cat <<EOF

GYDS Chain — RPC Node Setup
=============================

Usage: sudo bash setup-rpcnode-server.sh [OPTIONS]

OPTIONS
  --rpc-port  PORT   JSON-RPC HTTP port         (default: 8545)
  --ws-port   PORT   WebSocket port             (default: 8546)
  --p2p-port  PORT   P2P networking port        (default: 30303)
  --ssh-port  PORT   SSH port for firewall      (default: 22)
  --datadir   DIR    Chain data directory       (default: /var/lib/gyds-rpcnode)
  --domain    FQDN   Domain for auto-TLS (Certbot — DNS must point here first)
  --log-level LEVEL  trace|debug|info|warn|error (default: info)
  --bootstrap-nodes  Comma-separated peer list  e.g. tcp://1.2.3.4:30303
  --no-docker        Run as native systemd service
  --update           Update existing installation
  --uninstall        Remove node (preserves chain data)
  --help             Show this help and exit

PORT REFERENCE
  8545  TCP   JSON-RPC HTTP — MetaMask, Trust Wallet, dApps connect here
  8546  TCP   WebSocket — real-time eth_subscribe notifications
  30303 TCP+UDP P2P — peer discovery and block sync

EXAMPLES
  Fresh install (public RPC, default ports):
    sudo bash setup-rpcnode-server.sh

  With TLS (required for Trust Wallet over internet):
    sudo bash setup-rpcnode-server.sh --domain rpc.yourdomain.com

  With bootstrap peers:
    sudo bash setup-rpcnode-server.sh \\
      --bootstrap-nodes tcp://BOOST_IP:30306

  Update existing install:
    sudo bash ${APP_DIR}/setup-rpcnode-server.sh --update

  Remove:
    sudo bash ${APP_DIR}/setup-rpcnode-server.sh --uninstall

METAMASK / TRUST WALLET CONFIG
  Network Name : GYDS Chain
  Chain ID     : 13370
  RPC URL      : http://YOUR_IP:8545  (or https:// if --domain is set)
  WebSocket    : ws://YOUR_IP:8546    (or wss:// if --domain is set)
  Symbol       : GYDS
  Decimals     : 18

EOF
}

[[ $EUID -ne 0 ]] && die "Run as root: sudo bash $0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --datadir)         GYDS_DATADIR="$2";     shift 2 ;;
    --rpc-port)        GYDS_RPC_PORT="$2";    shift 2 ;;
    --ws-port)         GYDS_WS_PORT="$2";     shift 2 ;;
    --p2p-port)        GYDS_P2P_PORT="$2";    shift 2 ;;
    --ssh-port)        SSH_PORT="$2";         shift 2 ;;
    --domain)          DOMAIN="$2";           shift 2 ;;
    --bootstrap-nodes) BOOTSTRAP_NODES="$2";  shift 2 ;;
    --log-level)       LOG_LEVEL="$2";        shift 2 ;;
    --no-docker)       USE_DOCKER=false;      shift   ;;
    --update)          IS_UPDATE=true;        shift   ;;
    --uninstall)       UNINSTALL=true;        shift   ;;
    --help|-h)         show_help; exit 0      ;;
    *) die "Unknown flag: $1" ;;
  esac
done

if $UNINSTALL; then
  log "Uninstalling GYDS rpcnode..."
  systemctl stop  gyds-rpcnode 2>/dev/null || true
  systemctl disable gyds-rpcnode 2>/dev/null || true
  rm -f /etc/systemd/system/gyds-rpcnode.service
  systemctl daemon-reload 2>/dev/null || true
  [[ -f "$APP_DIR/docker-compose.yml" ]] && \
    docker compose -f "$APP_DIR/docker-compose.yml" down --remove-orphans 2>/dev/null || true
  rm -rf "$APP_DIR"
  rm -f /etc/nginx/sites-enabled/gyds-rpcnode /etc/nginx/sites-available/gyds-rpcnode
  nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  log "Uninstall complete. Chain data at ${GYDS_DATADIR} was preserved."
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  curl wget git build-essential ca-certificates gnupg lsb-release \
  nginx ufw fail2ban jq logrotate \
  $([ -n "$DOMAIN" ] && echo "certbot python3-certbot-nginx" || true)

if ! command -v docker &>/dev/null && $USE_DOCKER; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
fi

if ! id "$APP_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER" \
    || adduser --system --no-create-home "$APP_USER"
fi
$USE_DOCKER && command -v docker &>/dev/null && usermod -aG docker "$APP_USER" || true

log "Configuring firewall + fail2ban..."
SSH_PORT="$SSH_PORT" \
RPC_PORT="$GYDS_RPC_PORT" \
WS_PORT="$GYDS_WS_PORT" \
P2P_PORT="$GYDS_P2P_PORT" \
  bash "${APP_DIR}/setup-firewall.sh"
log "Firewall + fail2ban configured."

mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/.git" ]; then
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR" || \
    { warn "Could not clone repo — place files in $APP_DIR manually"; }
else
  git -C "$APP_DIR" fetch origin
  git -C "$APP_DIR" reset --hard "origin/$BRANCH"
fi
chown -R "${APP_USER}:${APP_USER}" "$APP_DIR"

ENV_FILE="${APP_DIR}/.env"
if [[ ! -f "$ENV_FILE" ]] || $IS_UPDATE; then
  cat > "$ENV_FILE" <<ENV
GYDS_CHAIN_ID=${GYDS_CHAIN_ID}
GYDS_NODE_MODE=rpc
GYDS_RPC_PORT=${GYDS_RPC_PORT}
GYDS_RPC_HOST=0.0.0.0
GYDS_WS_PORT=${GYDS_WS_PORT}
GYDS_P2P_PORT=${GYDS_P2P_PORT}
GYDS_DATA_DIR=/app/data
GYDS_LOG_LEVEL=${LOG_LEVEL}
GYDS_CORS_ORIGINS=*
$([ -n "$BOOTSTRAP_NODES" ] && echo "GYDS_BOOTSTRAP_NODES=${BOOTSTRAP_NODES}")
ENV
  chmod 600 "$ENV_FILE"
  chown "${APP_USER}:${APP_USER}" "$ENV_FILE"
fi

mkdir -p "${GYDS_DATADIR}/logs"
chown -R "${APP_USER}:${APP_USER}" "$GYDS_DATADIR"

log "Setting up Nginx reverse proxy..."
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/gyds-rpcnode <<NGINX
limit_req_zone  \$binary_remote_addr zone=rpc_limit:10m rate=30r/s;
limit_conn_zone \$binary_remote_addr zone=ws_conn:10m;

server {
    listen 80;
    server_name ${DOMAIN:-_};

    proxy_http_version 1.1;
    proxy_read_timeout  300s;
    proxy_send_timeout  300s;
    proxy_connect_timeout 10s;
    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    location / {
        limit_req zone=rpc_limit burst=60 nodelay;
        proxy_pass http://127.0.0.1:${GYDS_RPC_PORT};
        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /api/ws {
        limit_conn ws_conn 10;
        proxy_pass         http://127.0.0.1:${GYDS_RPC_PORT};
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_read_timeout 3600s;
    }

    location /health {
        proxy_pass http://127.0.0.1:${GYDS_RPC_PORT}/health;
        access_log off;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/gyds-rpcnode /etc/nginx/sites-enabled/gyds-rpcnode
nginx -t
systemctl enable nginx
systemctl restart nginx
log "Nginx configured with rate limiting (30 req/s RPC, 10 WS connections/IP)."

if [[ -n "$DOMAIN" ]]; then
  certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN"
  (crontab -l 2>/dev/null | grep -v certbot; \
   echo "0 3 * * * certbot renew --quiet --nginx") | crontab -
  log "SSL certificate issued for ${DOMAIN}."
fi

if $USE_DOCKER; then
  cd "$APP_DIR"
  docker compose down --remove-orphans 2>/dev/null || true
  docker compose build --no-cache
  docker compose up -d
else
  export PATH="${PATH}:/usr/local/go/bin"
  if ! command -v go &>/dev/null; then
    ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz
  fi
  cd "$APP_DIR" && go build -o bin/gyds-rpcnode .
  cat > /etc/systemd/system/gyds-rpcnode.service <<SVC
[Unit]
Description=GYDS RPC Node
After=network-online.target
Wants=network-online.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${APP_DIR}/bin/gyds-rpcnode start
Restart=always
RestartSec=5s
LimitNOFILE=65536
StandardOutput=append:${GYDS_DATADIR}/logs/rpc.log
StandardError=append:${GYDS_DATADIR}/logs/rpc-error.log

[Install]
WantedBy=multi-user.target
SVC
  systemctl daemon-reload
  systemctl enable --now gyds-rpcnode
fi

cat > /usr/local/bin/gyds-rpcnode-health <<HEALTH
#!/usr/bin/env bash
NOW="\$(date '+%Y-%m-%dT%H:%M:%S')"
RESP=\$(curl -sf --max-time 5 -X POST "http://localhost:${GYDS_RPC_PORT}" \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null || true)
if [[ -n "\$RESP" ]]; then
  echo "\$NOW [OK]   RPC up | \$RESP"
else
  echo "\$NOW [WARN] RPC not responding — restarting..."
  cd ${APP_DIR} && docker compose restart 2>/dev/null || systemctl restart gyds-rpcnode 2>/dev/null || true
fi
HEALTH
chmod +x /usr/local/bin/gyds-rpcnode-health
(crontab -l 2>/dev/null | grep -v gyds-rpcnode-health; \
 echo "*/5 * * * * /usr/local/bin/gyds-rpcnode-health >> ${GYDS_DATADIR}/logs/health.log 2>&1") | crontab -

sleep 5
SERVER_IP=$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}' || echo "YOUR_SERVER_IP")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              GYDS RPC NODE DEPLOYED                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
if [[ -n "$DOMAIN" ]]; then
echo "  JSON-RPC  : https://${DOMAIN}"
echo "  WebSocket : wss://${DOMAIN}/api/ws"
echo "  JSON-RPC (direct) : http://${SERVER_IP}:${GYDS_RPC_PORT}"
else
echo "  JSON-RPC  : http://${SERVER_IP}:${GYDS_RPC_PORT}"
echo "  WebSocket : ws://${SERVER_IP}:${GYDS_WS_PORT}"
echo "  Via Nginx : http://${SERVER_IP} (port 80)"
fi
echo "  P2P       : tcp://${SERVER_IP}:${GYDS_P2P_PORT}"
echo ""
echo "  ── MetaMask / Trust Wallet ──────────────────────────────"
echo "  Network Name : GYDS Chain"
echo "  Chain ID     : ${GYDS_CHAIN_ID}"
if [[ -n "$DOMAIN" ]]; then
echo "  RPC URL      : https://${DOMAIN}"
else
echo "  RPC URL      : http://${SERVER_IP}:${GYDS_RPC_PORT}"
fi
echo "  Symbol       : GYDS  |  Decimals: 18"
echo ""
if $USE_DOCKER; then
echo "  ── Management ───────────────────────────────────────────"
echo "  Logs   : cd ${APP_DIR} && docker compose logs -f"
echo "  Status : docker compose ps"
echo "  Restart: docker compose restart"
else
echo "  ── Management ───────────────────────────────────────────"
echo "  Logs   : journalctl -u gyds-rpcnode -f"
echo "  Status : systemctl status gyds-rpcnode"
echo "  Restart: systemctl restart gyds-rpcnode"
fi
echo ""
echo "  Health : gyds-rpcnode-health"
echo "  Update : sudo bash ${APP_DIR}/setup-rpcnode-server.sh --update"
echo ""
echo "  ── Quick RPC test ───────────────────────────────────────"
echo "  curl -X POST http://${SERVER_IP}:${GYDS_RPC_PORT} \\"
echo '    -H "Content-Type: application/json" \'
echo '    --data '"'"'{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'"'"
echo "  Expected: 0x343a"
echo ""
