#!/usr/bin/env bash
# =============================================================================
# 01_base_install.sh
# Unattended Ubuntu base setup for ARC-AIO Server
# Creates user 'gp', disables root SSH, configures SSH and locales
# =============================================================================

set -euo pipefail

echo "==> Starting base system installation..."

# --- Set timezone and locale ---
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# --- Create main user 'gp' ---
if id "gp" &>/dev/null; then
  echo "User 'gp' already exists, skipping creation."
else
  echo "Creating user 'gp'..."
  useradd -m -s /bin/bash gp
  echo "gp ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/gp
  chmod 440 /etc/sudoers.d/gp
fi

# --- Configure SSH ---
apt-get update -y
apt-get install -y openssh-server ufw

systemctl enable ssh
systemctl start ssh

# Disable root SSH login
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

# --- Basic network setup (DHCP fallback) ---
echo "==> Configuring network (DHCP fallback)..."
cat >/etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    all:
      dhcp4: true
EOF

netplan apply || true

# --- Basic packages ---
echo "==> Installing essential packages..."
apt-get install -y curl wget vim htop git unzip gnupg lsb-release ca-certificates apt-transport-https software-properties-common build-essential dkms

# --- Verify disk mounts and swap ---
echo "==> Checking for swap..."
if ! swapon --show | grep -q '^'; then
  echo "Creating 4G swapfile..."
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi

echo "Base installation complete."
