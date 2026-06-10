#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  GYDS Chain — RPC Node  /  Firewall + fail2ban hardening
#
#  Run standalone after initial setup, or call from
#  setup-rpcnode-server.sh (it does this automatically).
#
#  Usage:
#    sudo bash setup-firewall.sh [options]
#
#  Options:
#    --ssh-port PORT    SSH port (default: 22)
#    --rpc-port PORT    RPC HTTP port (default: 8545)
#    --ws-port  PORT    WebSocket port (default: 8546)
#    --p2p-port PORT    P2P port (default: 30303)
#    --status           Show current ban list and rules, then exit
#    --unban IP         Remove an IP from all bans, then exit
# ══════════════════════════════════════════════════════════════
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
RPC_PORT="${RPC_PORT:-8545}"
WS_PORT="${WS_PORT:-8546}"
P2P_PORT="${P2P_PORT:-30303}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Argument parsing ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --rpc-port) RPC_PORT="$2"; shift 2 ;;
    --ws-port)  WS_PORT="$2";  shift 2 ;;
    --p2p-port) P2P_PORT="$2"; shift 2 ;;
    --status)
      echo "=== UFW Status ===" && ufw status numbered
      echo "" && echo "=== fail2ban Banned IPs ===" && fail2ban-client status 2>/dev/null || echo "fail2ban not running"
      for j in gyds-rpc-flood gyds-rpc-badrpc gyds-scan gyds-ws-flood sshd recidive; do
        echo "--- $j ---" && fail2ban-client status "$j" 2>/dev/null | grep "Banned IP" || true
      done
      exit 0 ;;
    --unban)
      IP="$2"; shift 2
      for j in gyds-rpc-flood gyds-rpc-badrpc gyds-scan gyds-ws-flood sshd recidive; do
        fail2ban-client set "$j" unbanip "$IP" 2>/dev/null && echo "Unbanned $IP from $j" || true
      done
      ufw delete deny from "$IP" 2>/dev/null || true
      echo "Done unbanning $IP"
      exit 0 ;;
    *) shift ;;
  esac
done

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] WARNING: $*" >&2; }

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash $0"; exit 1; }

# ── 1. UFW — comprehensive firewall rules ────────────────────
log "Applying UFW firewall rules..."

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

# Allow SSH — with rate limiting (prevents brute force at kernel level)
ufw limit   "${SSH_PORT}"/tcp   comment "SSH (rate-limited)"

# GYDS node ports
ufw allow   80/tcp               comment "HTTP (Nginx)"
ufw allow   443/tcp              comment "HTTPS (Nginx + TLS)"
ufw allow   "${RPC_PORT}"/tcp    comment "GYDS RPC"
ufw allow   "${WS_PORT}"/tcp     comment "GYDS WebSocket"
ufw allow   "${P2P_PORT}"/tcp    comment "GYDS P2P"
ufw allow   "${P2P_PORT}"/udp    comment "GYDS P2P UDP"

# WireGuard VPN (allow inbound handshakes from server)
ufw allow   51820/udp            comment "WireGuard VPN"

# Block common attack ports proactively
ufw deny    23/tcp               comment "Telnet"
ufw deny    2375/tcp             comment "Docker daemon (unencrypted)"
ufw deny    2376/tcp             comment "Docker TLS"
ufw deny    3306/tcp             comment "MySQL"
ufw deny    5432/tcp             comment "PostgreSQL"
ufw deny    6379/tcp             comment "Redis"
ufw deny    27017/tcp            comment "MongoDB"

# Enable UFW logging for fail2ban to parse
ufw logging on

ufw --force enable
log "UFW enabled. Status:"
ufw status verbose

# ── 2. Sysctl — network stack hardening ─────────────────────
log "Applying sysctl network hardening..."

cat > /etc/sysctl.d/99-gyds-hardening.conf <<SYSCTL
# ── GYDS Chain network hardening ──────────────────────────

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# IP spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP redirect rejection
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Ignore ICMP ping broadcast (smurf protection)
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Source routing protection
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Connection tracking
net.netfilter.nf_conntrack_max = 524288
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Log martian packets (suspicious source addresses)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
SYSCTL

sysctl -p /etc/sysctl.d/99-gyds-hardening.conf
log "Sysctl hardening applied."

# ── 3. fail2ban — install + configure ───────────────────────
log "Configuring fail2ban..."

if ! command -v fail2ban-server &>/dev/null; then
  log "Installing fail2ban..."
  if command -v apt-get &>/dev/null; then
    apt-get install -y fail2ban
  elif command -v dnf &>/dev/null; then
    dnf install -y fail2ban
  elif command -v yum &>/dev/null; then
    yum install -y fail2ban
  else
    warn "Could not install fail2ban — install manually then re-run."
    exit 1
  fi
fi

# Deploy jail.local
cp "${SCRIPT_DIR}/fail2ban/jail.local" /etc/fail2ban/jail.local
log "Deployed /etc/fail2ban/jail.local"

# Deploy custom filters
mkdir -p /etc/fail2ban/filter.d
for f in "${SCRIPT_DIR}/fail2ban/filter.d/"*.conf; do
  cp "$f" /etc/fail2ban/filter.d/
  log "Deployed filter: $(basename "$f")"
done

# Ensure fail2ban uses the right action for UFW
if ! grep -q "\[Definition\]" /etc/fail2ban/action.d/ufw.conf 2>/dev/null; then
  cat > /etc/fail2ban/action.d/ufw.conf <<'UFW_ACTION'
[Definition]
actionstart =
actionstop  =
actioncheck =
actionban   = ufw insert 1 deny from <ip> to any
actionunban = ufw delete deny from <ip> to any
UFW_ACTION
  log "Created UFW action for fail2ban."
fi

systemctl enable fail2ban
systemctl restart fail2ban
sleep 2
log "fail2ban status:"
fail2ban-client status

# ── 4. Nginx — tighten rate limiting ────────────────────────
NGINX_CONF="/etc/nginx/sites-available/gyds-rpcnode"
if [ -f "$NGINX_CONF" ]; then
  log "Tightening Nginx rate limiting..."
  # Add connection limit zone if not already present
  NGINX_MAIN="/etc/nginx/nginx.conf"
  if ! grep -q "gyds_rpc_conn" "$NGINX_MAIN"; then
    sed -i '/http {/a\    # GYDS rate limit zones\n    limit_req_zone $binary_remote_addr zone=gyds_rpc:20m rate=30r/s;\n    limit_conn_zone $binary_remote_addr zone=gyds_conn:20m;' "$NGINX_MAIN"
    log "Added rate limit zones to nginx.conf"
  fi
  nginx -t && systemctl reload nginx
fi

# ── 5. Summary ───────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║       GYDS RPC Node — Firewall Hardened              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  UFW rules      : $(ufw status | grep -c "ALLOW\|DENY") rules active"
echo "  Sysctl         : /etc/sysctl.d/99-gyds-hardening.conf"
echo "  fail2ban jails :"
fail2ban-client status 2>/dev/null | grep "Jail list" || true
echo ""
echo "  Useful commands:"
echo "    sudo bash setup-firewall.sh --status         # show bans"
echo "    sudo bash setup-firewall.sh --unban 1.2.3.4  # unban IP"
echo "    sudo fail2ban-client status gyds-rpc-flood   # jail details"
echo "    sudo ufw status numbered                     # firewall rules"
echo "    sudo journalctl -u fail2ban -f               # live ban log"
echo ""
