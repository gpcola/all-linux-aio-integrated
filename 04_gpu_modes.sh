#!/usr/bin/env bash
# =============================================================================
# 04_gpu_modes.sh
# GPU mode manager for ARC-AIO Server
# Toggles between:
#   - AI Mode: Ollama + background workloads
#   - Game Mode: Sunshine + Steam streaming, pauses AI tasks
# Includes Steam process trap to auto-restore AI mode
# =============================================================================

set -euo pipefail

AI_SERVICES=("ollama" "apache2" "vsftpd" "node_exporter")
GAME_SERVICES=("sunshine" "steam")

STATE_FILE="/var/tmp/gpu_mode_state"
LOG_FILE="/var/log/gpu_mode.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

pause_services() {
  for s in "$@"; do
    systemctl stop "$s" 2>/dev/null || true
    log "Paused service: $s"
  done
}

resume_services() {
  for s in "$@"; do
    systemctl start "$s" 2>/dev/null || true
    log "Resumed service: $s"
  done
}

set_ai_mode() {
  log "Switching to AI Mode..."
  resume_services "${AI_SERVICES[@]}"
  pause_services "${GAME_SERVICES[@]}"
  echo "AI" > "$STATE_FILE"
  log "AI Mode active."
}

set_game_mode() {
  log "Switching to Game Mode..."
  pause_services "${AI_SERVICES[@]}"
  resume_services "${GAME_SERVICES[@]}"
  echo "GAME" > "$STATE_FILE"

  # Launch Steam and monitor process
  if command -v steam >/dev/null; then
    log "Launching Steam Big Picture..."
    sudo -u gp steam -tenfoot &
    STEAM_PID=$!
    wait "$STEAM_PID"
    log "Steam closed. Restoring AI Mode..."
    set_ai_mode
  else
    log "Steam not found. Sunshine session only."
  fi
}

status_mode() {
  if [[ -f "$STATE_FILE" ]]; then
    MODE=$(cat "$STATE_FILE")
    echo "Current GPU Mode: $MODE"
  else
    echo "Mode not set yet."
  fi
}

case "${1:-}" in
  ai)
    set_ai_mode
    ;;
  game)
    set_game_mode
    ;;
  status)
    status_mode
    ;;
  *)
    echo "Usage: $0 {ai|game|status}"
    exit 1
    ;;
esac
