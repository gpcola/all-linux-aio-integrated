#!/usr/bin/env bash
# =============================================================================
#  setup_all.sh
#  Master automation script for ARC-AIO Server (Ubuntu 24.04.1)
#  Author: gpcola
#  Description:
#    This script runs all setup stages sequentially:
#      00_prep.sh → 01_base_install.sh → 02_services_install.sh →
#      03_monitoring_setup.sh → 04_gpu_modes.sh → 05_optimisations.sh
#    Logs output to /var/log/1lg_install.log
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/1lg_install.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

echo "=== ARC-AIO Server Setup Start: $(date) ===" | tee -a "$LOG_FILE"

# --- Verify we're running as root ---
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo bash setup_all.sh)" | tee -a "$LOG_FILE"
  exit 1
fi

BASE_DIR="$(dirname "$(realpath "$0")")"
cd "$BASE_DIR"

# --- Ordered script list ---
scripts=(
  "00_prep.sh"
  "01_base_install.sh"
  "02_services_install.sh"
  "03_monitoring_setup.sh"
  "04_gpu_modes.sh"
  "05_optimisations.sh"
)

# --- Run each module sequentially ---
for script in "${scripts[@]}"; do
  if [[ -x "$BASE_DIR/$script" ]]; then
    echo "==> Running $script" | tee -a "$LOG_FILE"
    bash "$BASE_DIR/$script" 2>&1 | tee -a "$LOG_FILE"
    echo "==> Completed $script" | tee -a "$LOG_FILE"
  else
    echo "!! Missing or non-executable: $script" | tee -a "$LOG_FILE"
  fi
done

echo "=== ARC-AIO Server Setup Completed: $(date) ===" | tee -a "$LOG_FILE"
echo "Logs saved to $LOG_FILE"
