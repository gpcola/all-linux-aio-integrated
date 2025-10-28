#!/usr/bin/env bash
# =============================================================================
# 05_optimisations.sh
# System tuning for ARC-AIO Server:
#   - CPU performance governor
#   - I/O scheduler tweaks
#   - Network sysctl for low latency
# =============================================================================

set -euo pipefail
echo "==> Applying system optimisations..."

# ---------------------------------------------------------------------------
# CPU governor
# ---------------------------------------------------------------------------
echo "==> Setting CPU governor to 'performance'..."
apt-get install -y cpufrequtils

cat >/etc/default/cpufrequtils <<EOF
GOVERNOR="performance"
EOF

systemctl disable ondemand || true
systemctl stop ondemand || true
systemctl enable cpufrequtils
systemctl restart cpufrequtils

# ---------------------------------------------------------------------------
# I/O scheduler
# ---------------------------------------------------------------------------
echo "==> Optimising I/O scheduler..."
for disk in /sys/block/*/queue/scheduler; do
  echo mq-deadline >"$disk" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# Network performance
# ---------------------------------------------------------------------------
echo "==> Applying network sysctl tweaks..."
cat >/etc/sysctl.d/99-performance-tuning.conf <<'EOF'
# Network throughput and latency optimisation
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.ip_local_port_range=1024 65535
net.core.netdev_max_backlog=32768
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF

sysctl --system

# ---------------------------------------------------------------------------
# Misc performance options
# ---------------------------------------------------------------------------
echo "==> Disabling unnecessary services for headless operation..."
systemctl disable snapd.service snapd.socket || true
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true

echo "Optimisations applied successfully."
