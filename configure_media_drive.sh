#!/usr/bin/env bash
# =============================================================================
# configure_media_drive.sh
# Post-install helper for ARC-AIO Server
# Detects large drive, formats and mounts to /mnt/storage and /mnt/storage/llms
# =============================================================================

set -euo pipefail

echo "==> Configuring media drive..."

read -rp "List available disks? [Y/n]: " ans
[[ "${ans,,}" != "n" ]] && lsblk -o NAME,SIZE,MODEL,MOUNTPOINT

read -rp "Enter device name for the 10TB drive (e.g. sdb): " DEV
DEV_PATH="/dev/${DEV}"

if ! [ -b "$DEV_PATH" ]; then
  echo "Device $DEV_PATH not found. Aborting."
  exit 1
fi

read -rp "Format drive $DEV_PATH as ext4? [y/N]: " format
if [[ "${format,,}" == "y" ]]; then
  echo "Creating ext4 filesystem..."
  mkfs.ext4 -F "$DEV_PATH"
fi

# Create mount point
mkdir -p /mnt/storage/llms
mount "$DEV_PATH" /mnt/storage

# Add to fstab for persistence
UUID=$(blkid -s UUID -o value "$DEV_PATH")
echo "UUID=$UUID /mnt/storage ext4 defaults,noatime 0 2" >>/etc/fstab

# Ensure permissions
chown -R gp:gp /mnt/storage
chmod -R 755 /mnt/storage

# Optional Ollama model path reconfiguration
if systemctl is-active --quiet ollama; then
  echo "Moving Ollama model storage to /mnt/storage/llms..."
  systemctl stop ollama
  mkdir -p /mnt/storage/llms
  chown gp:gp /mnt/storage/llms
  ln -sf /mnt/storage/llms /usr/share/ollama/models
  systemctl start ollama
fi

echo "Drive configured and mounted at /mnt/storage"
df -h | grep /mnt/storage
