#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  GYDS Chain — Uptime Kuma automated monitor setup
#
#  Adds all GYDS node monitors to Uptime Kuma via its REST API.
#  Run AFTER Uptime Kuma is started and you have created an
#  admin account through the web UI (http://YOUR_SERVER:3001).
#
#  Usage:
#    bash setup-uptime.sh [options]
#
#  Options:
#    --url    URL     Uptime Kuma URL (default: http://localhost:3001)
#    --user   USER    Admin username
#    --pass   PASS    Admin password
#    --rpc    HOST    RPC node hostname/IP     (e.g. 1.2.3.4 or rpc.gydschain.io)
#    --val    HOST    Validator node hostname/IP
#    --full   HOST    Full node hostname/IP
#    --lite   HOST    Lite node hostname/IP
#    --vpn    HOST    WireGuard server hostname/IP
#    --dry-run        Print monitors that would be created, no actual API calls
# ══════════════════════════════════════════════════════════════
set -euo pipefail

KUMA_URL="${KUMA_URL:-http://localhost:3001}"
KUMA_USER="${KUMA_USER:-}"
KUMA_PASS="${KUMA_PASS:-}"
RPC_HOST="${RPC_HOST:-}"
VAL_HOST="${VAL_HOST:-}"
FULL_HOST="${FULL_HOST:-}"
LITE_HOST="${LITE_HOST:-}"
VPN_HOST="${VPN_HOST:-}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --url)     KUMA_URL="$2";   shift 2 ;;
    --user)    KUMA_USER="$2";  shift 2 ;;
    --pass)    KUMA_PASS="$2";  shift 2 ;;
    --rpc)     RPC_HOST="$2";   shift 2 ;;
    --val)     VAL_HOST="$2";   shift 2 ;;
    --full)    FULL_HOST="$2";  shift 2 ;;
    --lite)    LITE_HOST="$2";  shift 2 ;;
    --vpn)     VPN_HOST="$2";   shift 2 ;;
    --dry-run) DRY_RUN=true;    shift ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC}  $*"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; }

# ── Interactive prompts ───────────────────────────────────────
[[ -z "$KUMA_USER" ]] && read -rp "  Uptime Kuma username: " KUMA_USER
[[ -z "$KUMA_PASS" ]] && read -rsp "  Uptime Kuma password: " KUMA_PASS && echo
[[ -z "$RPC_HOST"  ]] && read -rp  "  RPC node IP/hostname: " RPC_HOST
[[ -z "$VAL_HOST"  ]] && read -rp  "  Validator node IP/hostname (Enter to skip): " VAL_HOST || true
[[ -z "$FULL_HOST" ]] && read -rp  "  Full node IP/hostname (Enter to skip): " FULL_HOST || true
[[ -z "$LITE_HOST" ]] && read -rp  "  Lite node IP/hostname (Enter to skip): " LITE_HOST || true
[[ -z "$VPN_HOST"  ]] && read -rp  "  WireGuard server IP/hostname (Enter to skip): " VPN_HOST || true

[[ -z "$KUMA_USER" || -z "$KUMA_PASS" ]] && { err "Username and password required."; exit 1; }
[[ -z "$RPC_HOST"  ]] && { err "RPC host required."; exit 1; }

# ── Login → get token ─────────────────────────────────────────
log "Logging in to Uptime Kuma at ${KUMA_URL}..."
TOKEN=$(curl -sf -X POST "${KUMA_URL}/api/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${KUMA_USER}\",\"password\":\"${KUMA_PASS}\"}" \
  | grep -o '"token":"[^"]*"' | cut -d'"' -f4) || {
  err "Login failed. Is Uptime Kuma running and the credentials correct?"
  exit 1
}
log "Login successful."

AUTH="-H \"Authorization: Bearer ${TOKEN}\""

# ── Monitor creation helper ───────────────────────────────────
CREATED=0
SKIPPED=0

add_http_monitor() {
  local NAME="$1" URL="$2" KEYWORD="${3:-}" METHOD="${4:-GET}"
  local BODY="{\"name\":\"${NAME}\",\"type\":\"http\",\"url\":\"${URL}\",\"method\":\"${METHOD}\",\"interval\":60,\"retryInterval\":60,\"maxretries\":3,\"upsideDown\":false"
  [[ -n "$KEYWORD" ]] && BODY="${BODY},\"keyword\":\"${KEYWORD}\",\"type\":\"keyword\""
  BODY="${BODY}}"
  if $DRY_RUN; then
    echo "  DRY RUN — would create HTTP monitor: ${NAME} → ${URL}"
    return
  fi
  RESULT=$(curl -sf -X POST "${KUMA_URL}/api/monitors" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d "$BODY" 2>/dev/null) && {
    log "  ✓ Created: ${NAME}"
    ((CREATED++)) || true
  } || {
    warn "  Could not create: ${NAME} (may already exist)"
    ((SKIPPED++)) || true
  }
}

add_port_monitor() {
  local NAME="$1" HOST="$2" PORT="$3"
  local BODY="{\"name\":\"${NAME}\",\"type\":\"port\",\"hostname\":\"${HOST}\",\"port\":${PORT},\"interval\":60,\"retryInterval\":60,\"maxretries\":3}"
  if $DRY_RUN; then
    echo "  DRY RUN — would create port monitor: ${NAME} → ${HOST}:${PORT}"
    return
  fi
  RESULT=$(curl -sf -X POST "${KUMA_URL}/api/monitors" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d "$BODY" 2>/dev/null) && {
    log "  ✓ Created: ${NAME}"
    ((CREATED++)) || true
  } || {
    warn "  Could not create: ${NAME} (may already exist)"
    ((SKIPPED++)) || true
  }
}

# ── RPC Node monitors (always created) ───────────────────────
echo ""
log "Adding RPC Node monitors (${RPC_HOST})..."
add_http_monitor "GYDS RPC — Health"        "http://${RPC_HOST}/health"  "ok"
add_http_monitor "GYDS RPC — JSON-RPC"      "http://${RPC_HOST}"         "result"  "POST"
add_http_monitor "GYDS RPC — Prometheus"    "http://${RPC_HOST}/metrics" "gyds_block_height"
add_port_monitor "GYDS RPC — WebSocket"     "${RPC_HOST}"  8546
add_port_monitor "GYDS RPC — P2P TCP"       "${RPC_HOST}"  30303

# ── Validator monitors (optional) ─────────────────────────────
if [[ -n "$VAL_HOST" ]]; then
  echo ""
  log "Adding Validator Node monitors (${VAL_HOST})..."
  add_port_monitor "GYDS Validator — P2P"   "${VAL_HOST}" 30303
  add_port_monitor "GYDS Validator — VPN"   "${VAL_HOST}" 51820
  # NOTE: validator 8545 is intentionally NOT monitored from outside
fi

# ── Full Node monitors (optional) ─────────────────────────────
if [[ -n "$FULL_HOST" ]]; then
  echo ""
  log "Adding Full Node monitors (${FULL_HOST})..."
  add_port_monitor "GYDS Full Node — P2P"   "${FULL_HOST}" 30303
  add_port_monitor "GYDS Full Node — VPN"   "${FULL_HOST}" 51820
fi

# ── Lite Node monitors (optional) ─────────────────────────────
if [[ -n "$LITE_HOST" ]]; then
  echo ""
  log "Adding Lite Node monitors (${LITE_HOST})..."
  add_port_monitor "GYDS Lite Node — P2P"   "${LITE_HOST}" 30303
  add_port_monitor "GYDS Lite Node — VPN"   "${LITE_HOST}" 51820
fi

# ── VPN server monitor (optional) ─────────────────────────────
if [[ -n "$VPN_HOST" ]]; then
  echo ""
  log "Adding WireGuard VPN server monitor (${VPN_HOST})..."
  add_port_monitor "WireGuard VPN Server"   "${VPN_HOST}" 51820
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║      GYDS Uptime Kuma — Monitor Setup Complete       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "  Created : ${CREATED}"
echo "  Skipped : ${SKIPPED} (already existed)"
echo ""
echo "  Open your status page: ${KUMA_URL}"
echo ""
echo "  To set up alerts (Discord / Telegram / Email):"
echo "    → Uptime Kuma UI → Settings → Notifications → Add"
echo "    → Then attach notifications to each monitor"
