package rpc

import (
	"bufio"
	"fmt"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

// handleMetrics serves a Prometheus-compatible /metrics endpoint.
// No external Prometheus library required — text exposition format is plain text.
func (s *Server) handleMetrics(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")

	stats := s.chain.Stats()

	chainID := uint64(0)
	if v, ok := stats["chainId"]; ok {
		switch x := v.(type) {
		case uint64:
			chainID = x
		case int:
			chainID = uint64(x)
		case int64:
			chainID = uint64(x)
		case float64:
			chainID = uint64(x)
		}
	}

	blockHeight := s.chain.Height()
	rpcReqs     := atomic.LoadInt64(&s.reqTotal)
	wsConns     := atomic.LoadInt64(&s.wsActive)
	pendingCnt  := int64(0)
	s.pendingTxMu.RLock()
	pendingCnt = int64(len(s.pendingTx))
	s.pendingTxMu.RUnlock()
	uptimeSec := time.Since(s.startTime).Seconds()

	// ── block / chain ────────────────────────────────────────────
	fmt.Fprintf(w, "# HELP gyds_block_height Current chain height (latest block number)\n")
	fmt.Fprintf(w, "# TYPE gyds_block_height gauge\n")
	fmt.Fprintf(w, "gyds_block_height %d\n\n", blockHeight)

	fmt.Fprintf(w, "# HELP gyds_chain_id Chain ID of this GYDS node\n")
	fmt.Fprintf(w, "# TYPE gyds_chain_id gauge\n")
	fmt.Fprintf(w, "gyds_chain_id %d\n\n", chainID)

	// ── RPC ──────────────────────────────────────────────────────
	fmt.Fprintf(w, "# HELP gyds_rpc_requests_total Total JSON-RPC requests handled since startup\n")
	fmt.Fprintf(w, "# TYPE gyds_rpc_requests_total counter\n")
	fmt.Fprintf(w, "gyds_rpc_requests_total %d\n\n", rpcReqs)

	// ── WebSocket ─────────────────────────────────────────────────
	fmt.Fprintf(w, "# HELP gyds_ws_connections_active Current active WebSocket subscriptions\n")
	fmt.Fprintf(w, "# TYPE gyds_ws_connections_active gauge\n")
	fmt.Fprintf(w, "gyds_ws_connections_active %d\n\n", wsConns)

	// ── mempool ───────────────────────────────────────────────────
	fmt.Fprintf(w, "# HELP gyds_pending_transactions Transactions currently in the pending pool\n")
	fmt.Fprintf(w, "# TYPE gyds_pending_transactions gauge\n")
	fmt.Fprintf(w, "gyds_pending_transactions %d\n\n", pendingCnt)

	// ── process ───────────────────────────────────────────────────
	fmt.Fprintf(w, "# HELP gyds_process_uptime_seconds Seconds since the RPC node started\n")
	fmt.Fprintf(w, "# TYPE gyds_process_uptime_seconds counter\n")
	fmt.Fprintf(w, "gyds_process_uptime_seconds %.3f\n\n", uptimeSec)

	// ── node info label ───────────────────────────────────────────
	fmt.Fprintf(w, "# HELP gyds_node_info Static node metadata\n")
	fmt.Fprintf(w, "# TYPE gyds_node_info gauge\n")
	fmt.Fprintf(w, "gyds_node_info{mode=\"rpc\",chain_id=\"%d\",symbol=\"GYDS\"} 1\n\n", chainID)

	// ── fail2ban banned IP counts (optional — needs fail2ban-client) ──
	if banned, err := fail2banBannedCount(); err == nil {
		fmt.Fprintf(w, "# HELP gyds_fail2ban_banned_ips_total Total currently banned IPs across all jails\n")
		fmt.Fprintf(w, "# TYPE gyds_fail2ban_banned_ips_total gauge\n")
		for jail, count := range banned {
			fmt.Fprintf(w, "gyds_fail2ban_banned_ips_total{jail=%q} %d\n", jail, count)
		}
		fmt.Fprintln(w)
	}
}

// fail2banBannedCount reads banned IP counts from fail2ban-client (non-blocking, best-effort).
func fail2banBannedCount() (map[string]int, error) {
	out, err := exec.Command("fail2ban-client", "status").Output()
	if err != nil {
		return nil, err
	}

	// Parse "Jail list: gyds-rpc-flood, sshd, ..."
	jails := []string{}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.Contains(line, "Jail list:") {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) == 2 {
				for _, j := range strings.Split(parts[1], ",") {
					j = strings.TrimSpace(j)
					if j != "" {
						jails = append(jails, j)
					}
				}
			}
		}
	}

	result := make(map[string]int, len(jails))
	for _, jail := range jails {
		jout, err := exec.Command("fail2ban-client", "status", jail).Output()
		if err != nil {
			result[jail] = 0
			continue
		}
		scanner := bufio.NewScanner(strings.NewReader(string(jout)))
		for scanner.Scan() {
			line := scanner.Text()
			if strings.Contains(line, "Currently banned:") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					n, err := strconv.Atoi(strings.TrimSpace(parts[1]))
					if err == nil {
						result[jail] = n
					}
				}
			}
		}
	}
	return result, nil
}
