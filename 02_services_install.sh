#!/usr/bin/env bash
# =============================================================================
# 02_services_install.sh
# Installs core services:
#   - Sunshine (game streaming)
#   - Ollama (local AI inference)
#   - Docker + NVIDIA Container Toolkit
#   - Apache + vsftpd (web + FTP)
#   - No-IP DDNS client (reads credentials from noip.conf)
# =============================================================================

set -euo pipefail
echo "==> Installing core services..."

# --- Refresh system ---
apt-get update -y && apt-get upgrade -y

# ---------------------------------------------------------------------------
# Sunshine installation
# ---------------------------------------------------------------------------
echo "==> Installing Sunshine..."
add-apt-repository -y ppa:arcticsunlight/sunshine || true
apt-get update -y
apt-get install -y sunshine

# Enable and start Sunshine
systemctl enable sunshine
systemctl start sunshine
echo "Sunshine installed and running."

# ---------------------------------------------------------------------------
# Ollama installation
# ---------------------------------------------------------------------------
echo "==> Installing Ollama..."
curl -fsSL https://ollama.com/download.sh | bash
systemctl enable ollama
systemctl start ollama
echo "Ollama service ready."

# ---------------------------------------------------------------------------
# Docker and NVIDIA Container Toolkit
# ---------------------------------------------------------------------------
echo "==> Installing Docker..."
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable
EOF

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add gp to docker group
usermod -aG docker gp

# NVIDIA Container Toolkit (Intel Arc users can skip CUDA dependency)
echo "==> Installing NVIDIA Container Toolkit (for optional GPU containers)..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -y
apt-get install -y nvidia-container-toolkit || true
systemctl restart docker || true
echo "Docker & NVIDIA toolkit setup done."

# ---------------------------------------------------------------------------
# Web and FTP servers
# ---------------------------------------------------------------------------
echo "==> Installing Apache + vsftpd..."
apt-get install -y apache2 vsftpd

# Configure vsftpd for local access
sed -i 's/^#*write_enable=.*/write_enable=YES/' /etc/vsftpd.conf
sed -i 's/^#*local_umask=.*/local_umask=022/' /etc/vsftpd.conf
systemctl enable apache2 vsftpd
systemctl restart apache2 vsftpd
echo "Web and FTP services configured."

# ---------------------------------------------------------------------------
# No-IP setup (reads from external noip.conf)
# ---------------------------------------------------------------------------
echo "==> Configuring No-IP..."
CONF_PATH="$(dirname "$0")/noip.conf"
if [[ -f "$CONF_PATH" ]]; then
  source "$CONF_PATH"
  if [[ -n "${USERNAME:-}" && -n "${PASSWORD:-}" && -n "${HOSTNAME:-}" ]]; then
    apt-get install -y noip2
    noip2 -C -u "$USERNAME" -p "$PASSWORD" -U 30 -Y -H "$HOSTNAME"
    systemctl enable noip2
    systemctl restart noip2
    echo "No-IP configured for $HOSTNAME."
  else
    echo "No-IP credentials missing; skipping setup."
  fi
else
  echo "noip.conf not found. Place it beside this script to auto-configure No-IP."
fi

# ---------------------------------------------------------------------------
# Firewall rules
# ---------------------------------------------------------------------------
echo "==> Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 8085/tcp  # metrics
ufw allow 47984:48010/udp  # Sunshine streaming range
ufw --force enable
echo "Firewall configured."

echo "Service installation complete."
