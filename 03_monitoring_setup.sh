#!/usr/bin/env bash
# =============================================================================
# 03_monitoring_setup.sh
# Installs and configures hardware monitoring for ARC-AIO Server
# Uses lm-sensors + node_exporter + JSON proxy endpoint (:8085)
# =============================================================================

set -euo pipefail

echo "==> Setting up monitoring stack..."

# ---------------------------------------------------------------------------
# lm-sensors
# ---------------------------------------------------------------------------
echo "==> Installing lm-sensors..."
apt-get update -y
apt-get install -y lm-sensors jq

# Auto-detect sensors
yes | sensors-detect --auto
systemctl restart kmod || true

# ---------------------------------------------------------------------------
# node_exporter
# ---------------------------------------------------------------------------
echo "==> Installing Prometheus node_exporter..."
useradd --no-create-home --shell /bin/false nodeusr || true

NODE_EXPORTER_VERSION="1.8.1"
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
chown nodeusr:nodeusr /usr/local/bin/node_exporter
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

# Create systemd service
cat >/etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=nodeusr
ExecStart=/usr/local/bin/node_exporter --web.listen-address=":8085"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# ---------------------------------------------------------------------------
# JSON proxy helper
# ---------------------------------------------------------------------------
echo "==> Creating JSON proxy helper..."
mkdir -p /usr/local/bin
cat >/usr/local/bin/hwmon-to-json.sh <<'EOF'
#!/usr/bin/env bash
# Converts node_exporter /metrics to JSON-style key:value pairs
curl -s http://localhost:8085/metrics \
  | grep -E 'node_hwmon|node_cpu_temperature|node_memory|node_disk' \
  | awk -F' ' '{printf "{\"metric\":\"%s\",\"value\":%s}\n", $1, $2}' \
  | jq -s .
EOF
chmod +x /usr/local/bin/hwmon-to-json.sh

# Log location
mkdir -p /var/log/hwmon
ln -sf /usr/local/bin/hwmon-to-json.sh /usr/local/bin/update-hwmon-log
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/hwmon-to-json.sh > /var/log/hwmon/latest.json") | crontab -

echo "Monitoring stack installed. Metrics at http://<server-ip>:8085/metrics"
echo "JSON snapshot available at /var/log/hwmon/latest.json"
