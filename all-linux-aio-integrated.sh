#!/usr/bin/env bash
# all-linux-aio-integrated.sh
# AIO setup for an Intel Arc B580 Ubuntu 24.04 server:
# - Sunshine + Moonlight tiles
# - Steam (Gamescope optional) with auto-restore to AI mode on exit
# - Headless Xorg @ 1080p 120Hz
# - GPU mode toggle (Game <-> AI) with pause lists
# - Docker: Jellyfin + qBittorrent
# - Ollama (local LLMs)
# - Optional Mellanox jumbo frames
# - Web stack: Nginx + vsftpd + ddclient (No-IP) + Let's Encrypt
# - Unified settings manager: /etc/arc-aio.conf, arc-aio-config, arc-aio-apply
# Idempotent and safe to re-run.

set -euo pipefail

############################################
# Defaults (override via env before running)
############################################
: "${GAME_USER:=gamer}"
: "${GAME_PASS:=GameP@ss!}"

# Display & Steam
: "${HEADLESS_DEFAULT_RES:=1080p}"        # 1080p | 4k
: "${HEADLESS_DEFAULT_HZ:=120}"           # 120 | 60
: "${INSTALL_STEAM:=1}"
: "${INSTALL_GAMESCOPE:=0}"

# Docker media
: "${ENABLE_DOCKER_STACK:=1}"
: "${DOCKER_ROOT:=/opt/arc/docker}"
: "${JELLYFIN_DATA:=/srv/jellyfin}"
: "${QBITTORRENT_DATA:=/srv/qbittorrent}"
: "${MEDIA_ROOT:=/srv/media}"

# Ollama
: "${ENABLE_OLLAMA:=1}"
: "${OLLAMA_MODELS:=phi3:medium}"

# Mellanox
: "${ENABLE_JUMBO_FRAMES:=0}"             # 1 to enable MTU 9000
: "${MLX_IFACE:=}"                        # e.g. ens5f0

# Web / FTP / No-IP (these are reified into /etc/arc-aio.conf by settings manager)
: "${WEB_ROOT:=/srv/www}"
: "${ENABLE_FTP:=1}"
: "${FTP_USER:=ftpuser}"
: "${FTP_PASS:=FtpP@ss!}"
: "${FTP_ROOT:=/srv/ftp}"
: "${FTP_PASV_MIN:=30000}"
: "${FTP_PASV_MAX:=30100}"
: "${NOIP_UPDATE:=1}"
: "${NOIP_USER:=your-noip-email@example.com}"
: "${NOIP_PASS:=your-noip-password}"
: "${NOIP_HOST:=your-hostname.no-ip.org}"
: "${ENABLE_TLS:=1}"

# Services to pause while gaming (you can tweak later in /etc/arc-game-pause.list)
DEFAULT_PAUSE_LIST=("docker" "ollama" "jellyfin" "qbittorrent-nox" "ddclient")

############################################
# Helpers
############################################
log(){ echo -e "\033[1;34m==>\033[0m $*"; }
warn(){ echo -e "\033[1;33m!!\033[0m $*"; }
die(){ echo -e "\033[1;31mXX\033[0m $*" >&2; exit 1; }
need_root(){ [[ $EUID -eq 0 ]] || die "Run as root (sudo)."; }

############################################
# User & base
############################################
setup_user() {
  need_root
  if ! id -u "$GAME_USER" >/dev/null 2>&1; then
    log "Creating user $GAME_USER"
    useradd -m -s /bin/bash "$GAME_USER"
    echo "${GAME_USER}:${GAME_PASS}" | chpasswd
    usermod -aG sudo "$GAME_USER"
  fi
}

install_base() {
  log "Updating and installing base packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y jq curl wget ca-certificates git unzip tar \
    build-essential pkg-config python3-pip htop net-tools ufw \
    xserver-xorg-video-dummy xserver-xorg-core xinit \
    mesa-va-drivers intel-media-va-driver-non-free vainfo \
    libva2 libva-drm2 libva-x11-2 libvulkan1 vulkan-tools \
    x11-xserver-utils systemd-timesyncd
  systemctl enable --now systemd-timesyncd
}

############################################
# Headless Xorg 1080p@120 (or 4K@60) 
############################################
setup_headless_xorg() {
  local w=1920 h=1080 rate="$HEADLESS_DEFAULT_HZ"
  if [[ "$HEADLESS_DEFAULT_RES" == "4k" ]]; then w=3840; h=2160; rate=60; fi
  log "Setting up headless Xorg at ${w}x${h}@${rate}"
  mkdir -p /etc/X11/xorg.conf.d
  cat >/etc/X11/xorg.conf.d/20-headless.conf <<EOF
Section "Monitor"
  Identifier "Monitor0"
  HorizSync 28.0-80.0
  VertRefresh 48.0-75.0
  Modeline "custom" $(gtf $w $h $rate | awk '/Modeline/{$1="";print}')
  Option "PreferredMode" "custom"
EndSection
Section "Device"
  Identifier "Device0"
  Driver "dummy"
  VideoRam 256000
EndSection
Section "Screen"
  Identifier "Screen0"
  Device "Device0"
  Monitor "Monitor0"
  DefaultDepth 24
  SubSection "Display"
    Depth 24
    Modes "custom"
  EndSubSection
EndSection
EOF

  # systemd unit to ensure Xvfb replacement: use Xorg vt7
  cat >/etc/systemd/system/headless-x.service <<'EOF'
[Unit]
Description=Headless Xorg
After=multi-user.target

[Service]
User=root
Environment=DISPLAY=:0
ExecStart=/usr/lib/xorg/Xorg :0 -noreset -nolisten tcp vt7
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now headless-x.service
}

############################################
# Sunshine + Moonlight tiles
############################################
install_sunshine() {
  log "Installing Sunshine"
  # Official repo for Ubuntu 24.04 (Jammy/Noble builds compatible)
  apt-get install -y software-properties-common
  add-apt-repository -y ppa:linuxgndu/sunshine
  apt-get update
  apt-get install -y sunshine

  # Enable + first-run
  systemctl enable --now sunshine

  # Ensure config dir
  su - "$GAME_USER" -c 'mkdir -p ~/.config/sunshine; [[ -f ~/.config/sunshine/apps.json ]] || echo "[]" > ~/.config/sunshine/apps.json'
}

############################################
# Gamescope + Steam (optional)
############################################
install_steam() {
  [[ "$INSTALL_STEAM" -eq 1 ]] || return 0
  log "Installing Steam"
  dpkg --add-architecture i386
  apt-get update
  apt-get install -y steam steam-devices
  if [[ "$INSTALL_GAMESCOPE" -eq 1 ]]; then
    apt-get install -y gamescope
  fi

  # Wrapper that sets Game Mode, runs Steam Big Picture, then restores AI Mode
  cat >/usr/local/bin/steam-bp-wrap <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
arc-mode game
# trap restoration even on ctrl+c
finish(){ arc-mode ai; }
trap finish EXIT
if command -v gamescope >/dev/null 2>&1; then
  gamescope -f -- steam -tenfoot
else
  steam -tenfoot
fi
EOF
  chmod +x /usr/local/bin/steam-bp-wrap
}

############################################
# GPU mode toggle + pause lists
############################################
install_arc_mode() {
  log "Installing arc-mode (GPU toggle Game/AI) and pause lists"
  # Default pause list
  if [[ ! -f /etc/arc-game-pause.list ]]; then
    printf "%s\n" "${DEFAULT_PAUSE_LIST[@]}" > /etc/arc-game-pause.list
  fi

  # The mode switcher
  cat >/usr/local/bin/arc-mode <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-}"
[[ -n "$MODE" ]] || { echo "Usage: arc-mode [game|ai|toggle]"; exit 1; }
log(){ echo -e "\033[1;34m==>\033[0m $*"; }
pause_list="/etc/arc-game-pause.list"

game_on(){
  log "Setting CPU governor to performance"
  for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance | sudo tee "$c" >/dev/null || true; done
  log "Increasing VM responsiveness"
  sysctl -w vm.swappiness=10 vm.dirty_ratio=10 vm.dirty_background_ratio=5 >/dev/null || true
  log "Pausing services"
  [[ -f "$pause_list" ]] && while read -r svc; do systemctl stop "$svc" 2>/dev/null || true; done < "$pause_list"
  log "Uncapping Steam ports in firewall"
  ufw allow 27031:27036/udp >/dev/null 2>&1 || true
  ufw allow 47984:48010/udp >/dev/null 2>&1 || true
  log "Game Mode ready"
}

ai_on(){
  log "Restoring CPU governor to schedutil"
  for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo schedutil | sudo tee "$c" >/dev/null || true; done
  log "Restoring sysctl defaults"
  sysctl -w vm.swappiness=60 vm.dirty_ratio=20 vm.dirty_background_ratio=10 >/dev/null || true
  log "Resuming services"
  [[ -f "$pause_list" ]] && while read -r svc; do systemctl start "$svc" 2>/dev/null || true; done < "$pause_list"
  log "AI Mode ready"
}

case "$MODE" in
  game) game_on ;;
  ai)   ai_on ;;
  toggle)
    # naive detection: if docker & ollama are active, assume AI; else assume Game
    if systemctl is-active --quiet docker || systemctl is-active --quiet ollama; then
      game_on
    else
      ai_on
    fi
    ;;
  *) echo "Usage: arc-mode [game|ai|toggle]"; exit 1 ;;
esac
EOF
  chmod +x /usr/local/bin/arc-mode
}

############################################
# Docker stack: Jellyfin + qBittorrent
############################################
install_docker_stack() {
  [[ "$ENABLE_DOCKER_STACK" -eq 1 ]] || return 0
  log "Installing Docker and media stack"
  apt-get install -y apt-transport-https gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  usermod -aG docker "$GAME_USER" || true
  mkdir -p "$DOCKER_ROOT" "$JELLYFIN_DATA" "$QBITTORRENT_DATA" "$MEDIA_ROOT"

  # docker compose file
  cat >"${DOCKER_ROOT}/compose.yml" <<EOF
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    network_mode: host
    volumes:
      - ${JELLYFIN_DATA}:/config
      - ${MEDIA_ROOT}:/media
    devices:
      - /dev/dri:/dev/dri
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: host
    environment:
      - PUID=1000
      - PGID=1000
      - WEBUI_PORT=8080
    volumes:
      - ${QBITTORRENT_DATA}:/config
      - ${MEDIA_ROOT}:/downloads
    restart: unless-stopped
EOF

  # systemd unit to manage the stack
  cat >/etc/systemd/system/arc-docker.service <<EOF
[Unit]
Description=ARC Docker media stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker compose -f ${DOCKER_ROOT}/compose.yml up -d
ExecStop=/usr/bin/docker compose -f ${DOCKER_ROOT}/compose.yml down

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now arc-docker.service
}

############################################
# Ollama
############################################
install_ollama() {
  [[ "$ENABLE_OLLAMA" -eq 1 ]] || return 0
  log "Installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
  systemctl enable --now ollama
  if [[ -n "$OLLAMA_MODELS" ]]; then
    for m in $OLLAMA_MODELS; do
      ollama pull "$m" || true
    done
  fi
}

############################################
# Mellanox Jumbo Frames (optional)
############################################
setup_mlx_jumbo() {
  [[ "$ENABLE_JUMBO_FRAMES" -eq 1 && -n "$MLX_IFACE" ]] || return 0
  log "Enabling MTU 9000 on ${MLX_IFACE}"
  nmcli connection show || apt-get install -y network-manager
  nmcli connection modify "Wired connection 1" 2>/dev/null || true
  ip link set "$MLX_IFACE" mtu 9000 || warn "Failed to set MTU on $MLX_IFACE"
  cat >/etc/systemd/system/mtu-${MLX_IFACE}.service <<EOF
[Unit]
Description=Set MTU 9000 on ${MLX_IFACE}
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/sbin/ip link set ${MLX_IFACE} mtu 9000
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now mtu-${MLX_IFACE}.service
}

############################################
# Settings Manager: /etc/arc-aio.conf + CLI
############################################
install_settings_manager() {
  local CONF="/etc/arc-aio.conf"
  local UMASK_OLD
  UMASK_OLD=$(umask); umask 077

  # Create config if missing (seed from current env)
  if [[ ! -f "$CONF" ]]; then
    cat >"$CONF" <<EOF
# ===== ARC AIO GLOBAL CONFIG =====
# Web / FTP
WEB_ROOT="${WEB_ROOT}"
ENABLE_FTP="${ENABLE_FTP}"
FTP_USER="${FTP_USER}"
FTP_PASS="${FTP_PASS}"
FTP_ROOT="${FTP_ROOT}"
FTP_PASV_MIN="${FTP_PASV_MIN}"
FTP_PASV_MAX="${FTP_PASV_MAX}"

# Dynamic DNS (No-IP via ddclient)
NOIP_UPDATE="${NOIP_UPDATE}"
NOIP_USER="${NOIP_USER}"
NOIP_PASS="${NOIP_PASS}"
NOIP_HOST="${NOIP_HOST}"

# TLS via Let's Encrypt (requires NOIP_HOST -> this server)
ENABLE_TLS="${ENABLE_TLS}"

# System user that owns web files
GAME_USER="${GAME_USER}"
EOF
  fi
  chown root:root "$CONF"; chmod 600 "$CONF"; umask "$UMASK_OLD"

  # arc-aio-apply
  cat >/usr/local/bin/arc-aio-apply <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
CONF="/etc/arc-aio.conf"
[[ -f "$CONF" ]] || { echo "Missing $CONF"; exit 1; }
# shellcheck disable=SC1090
source "$CONF"
log(){ echo -e "\033[1;34m==>\033[0m $*"; }
warn(){ echo -e "\033[1;33m!!\033[0m $*"; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y nginx vsftpd ddclient ufw >/dev/null 2>&1 || true
command -v certbot >/dev/null 2>&1 || apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1 || true

# NGINX
mkdir -p "$WEB_ROOT"
chown -R "${GAME_USER:-gamer}:${GAME_USER:-gamer}" "$WEB_ROOT"
NGINX_CONF="/etc/nginx/sites-available/arc-server.conf"
cat > "$NGINX_CONF" <<NGX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root ${WEB_ROOT};
    index index.html index.htm;
    location / { try_files \$uri \$uri/ =404; }
}
NGX
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/arc-server.conf
rm -f /etc/nginx/sites-enabled/default || true
nginx -t && systemctl enable --now nginx && systemctl reload nginx || warn "nginx reload failed"

# VSFTPD
if [[ "${ENABLE_FTP}" == "1" ]]; then
  id -u "${FTP_USER}" >/dev/null 2>&1 || useradd -m -d "${FTP_ROOT}" -s /usr/sbin/nologin "${FTP_USER}"
  [[ -n "${FTP_PASS}" ]] && echo "${FTP_USER}:${FTP_PASS}" | chpasswd
  mkdir -p "${FTP_ROOT}/upload"; chown -R "${FTP_USER}:${FTP_USER}" "${FTP_ROOT}"; chmod 750 "${FTP_ROOT}"
  cat > /etc/vsftpd.conf <<VFTPD
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=${FTP_PASV_MIN}
pasv_max_port=${FTP_PASV_MAX}
pasv_address=0.0.0.0
pasv_addr_resolve=NO
secure_chroot_dir=/var/run/vsftpd/empty
ssl_enable=NO
VFTPD
  systemctl enable --now vsftpd
else
  systemctl disable --now vsftpd 2>/dev/null || true
fi

# UFW
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 80/tcp  >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true
if [[ "${ENABLE_FTP}" == "1" ]]; then
  ufw allow 21/tcp >/dev/null 2>&1 || true
  ufw allow ${FTP_PASV_MIN}:${FTP_PASV_MAX}/tcp >/dev/null 2>&1 || true
else
  ufw delete allow 21/tcp >/dev/null 2>&1 || true
  ufw delete allow ${FTP_PASV_MIN}:${FTP_PASV_MAX}/tcp >/dev/null 2>&1 || true
fi
ufw --force enable >/dev/null 2>&1 || true

# ddclient (No-IP)
if [[ "${NOIP_UPDATE}" == "1" ]]; then
  cat > /etc/ddclient.conf <<DDC
daemon=60
protocol=noip
use=web, web=checkip.dyndns.com
server=dynupdate.no-ip.com
login=${NOIP_USER}
password='${NOIP_PASS}'
${NOIP_HOST}
DDC
  chmod 600 /etc/ddclient.conf; chown root:root /etc/ddclient.conf
  systemctl enable --now ddclient || warn "ddclient enable failed"
  ddclient -force >/dev/null 2>&1 || true
else
  systemctl disable --now ddclient 2>/dev/null || true
fi

# TLS
if [[ "${ENABLE_TLS}" == "1" && "${NOIP_UPDATE}" == "1" && "${NOIP_HOST}" != "your-hostname.no-ip.org" ]]; then
  certbot --nginx -n --agree-tos --email "${NOIP_USER}" -d "${NOIP_HOST}" || warn "certbot failed (check DNS/ports)"
  systemctl reload nginx || true
fi

echo -e "\n==== APPLY COMPLETE ===="
echo "WEB_ROOT=${WEB_ROOT}"
echo "FTP=${ENABLE_FTP} (${FTP_USER})  Passive ${FTP_PASV_MIN}-${FTP_PASV_MAX}"
echo "No-IP=${NOIP_UPDATE} (${NOIP_HOST})"
echo "TLS=${ENABLE_TLS}"
EOS
  chmod +x /usr/local/bin/arc-aio-apply

  # arc-aio-config
  cat >/usr/local/bin/arc-aio-config <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
CONF="/etc/arc-aio.conf"
[[ -f "$CONF" ]] || { echo "Missing $CONF"; exit 1; }

usage(){ cat <<USG
Usage:
  arc-aio-config show
  arc-aio-config edit
  arc-aio-config set KEY=VALUE [KEY=VALUE ...]
  arc-aio-config menu
After changing settings, run:
  sudo arc-aio-apply
USG
}

case "${1:-}" in
  show) sed 's/^NOIP_PASS=.*/NOIP_PASS=******/' "$CONF" ;;
  edit) ${EDITOR:-nano} "$CONF" ;;
  set)
    shift; [[ $# -gt 0 ]] || { echo "No KEY=VALUE pairs."; exit 1; }
    for kv in "$@"; do
      key="${kv%%=*}"; val="${kv#*=}"
      [[ "$key" =~ ^[A-Za-z0-9_]+$ ]] || { echo "Invalid key: $key"; exit 1; }
      if grep -q "^${key}=" "$CONF"; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$CONF"
      else
        echo "${key}=\"${val}\"" >> "$CONF"
      fi
    done
    chmod 600 "$CONF"; echo "Updated. Run: sudo arc-aio-apply"
    ;;
  menu)
    if command -v yad >/dev/null 2>&1; then
      # shellcheck disable=SC1090
      source "$CONF"
      resp="$(yad --title="ARC Server Settings" --form --separator='|' \
        --field="WEB_ROOT":DIR "${WEB_ROOT}" \
        --field="ENABLE_FTP (0/1)":NUM "${ENABLE_FTP}" \
        --field="FTP_USER" "${FTP_USER}" \
        --field="FTP_PASS":H "${FTP_PASS}" \
        --field="FTP_ROOT":DIR "${FTP_ROOT}" \
        --field="FTP_PASV_MIN":NUM "${FTP_PASV_MIN}" \
        --field="FTP_PASV_MAX":NUM "${FTP_PASV_MAX}" \
        --field="NOIP_UPDATE (0/1)":NUM "${NOIP_UPDATE}" \
        --field="NOIP_USER" "${NOIP_USER}" \
        --field="NOIP_PASS":H "${NOIP_PASS}" \
        --field="NOIP_HOST" "${NOIP_HOST}" \
        --field="ENABLE_TLS (0/1)":NUM "${ENABLE_TLS}" \
        --button="Apply:0" --button="Cancel:1")" || exit 1
      IFS='|' read -r WEB_ROOT ENABLE_FTP FTP_USER FTP_PASS FTP_ROOT FTP_PASV_MIN FTP_PASV_MAX NOIP_UPDATE NOIP_USER NOIP_PASS NOIP_HOST ENABLE_TLS <<<"$resp"
      sed -i "s|^WEB_ROOT=.*|WEB_ROOT=\"${WEB_ROOT}\"|" "$CONF"
      sed -i "s|^ENABLE_FTP=.*|ENABLE_FTP=\"${ENABLE_FTP}\"|" "$CONF"
      sed -i "s|^FTP_USER=.*|FTP_USER=\"${FTP_USER}\"|" "$CONF"
      sed -i "s|^FTP_PASS=.*|FTP_PASS=\"${FTP_PASS}\"|" "$CONF"
      sed -i "s|^FTP_ROOT=.*|FTP_ROOT=\"${FTP_ROOT}\"|" "$CONF"
      sed -i "s|^FTP_PASV_MIN=.*|FTP_PASV_MIN=\"${FTP_PASV_MIN}\"|" "$CONF"
      sed -i "s|^FTP_PASV_MAX=.*|FTP_PASV_MAX=\"${FTP_PASV_MAX}\"|" "$CONF"
      sed -i "s|^NOIP_UPDATE=.*|NOIP_UPDATE=\"${NOIP_UPDATE}\"|" "$CONF"
      sed -i "s|^NOIP_USER=.*|NOIP_USER=\"${NOIP_USER}\"|" "$CONF"
      sed -i "s|^NOIP_PASS=.*|NOIP_PASS=\"${NOIP_PASS}\"|" "$CONF"
      sed -i "s|^NOIP_HOST=.*|NOIP_HOST=\"${NOIP_HOST}\"|" "$CONF"
      sed -i "s|^ENABLE_TLS=.*|ENABLE_TLS=\"${ENABLE_TLS}\"|" "$CONF"
      chmod 600 "$CONF"
      yad --info --text="Saved. Now applying…"
      exec sudo arc-aio-apply
    else
      echo "No 'yad' found. Use: arc-aio-config edit   or   arc-aio-config set KEY=VALUE ..."
    fi
    ;;
  *) usage; exit 1 ;;
esac
EOS
  chmod +x /usr/local/bin/arc-aio-config

  # Create web and ftp roots + sample index
  mkdir -p "$WEB_ROOT" "$FTP_ROOT"
  chown -R "$GAME_USER:$GAME_USER" "$WEB_ROOT"
  [[ -f "$WEB_ROOT/index.html" ]] || cat >"$WEB_ROOT/index.html" <<'EOF'
<html><head><title>ARC Server</title></head>
<body><h1>ARC Server</h1><p>Welcome — web server is running.</p></body></html>
EOF
  chown "$GAME_USER:$GAME_USER" "$WEB_ROOT/index.html"
}

############################################
# Moonlight tiles (Sunshine apps.json)
############################################
add_moonlight_tiles() {
  local apps="/home/${GAME_USER}/.config/sunshine/apps.json"
  [[ -f "$apps" ]] || return 0

  # Merge tiles using jq
  local tmp; tmp=$(mktemp)
  jq '
    . += [
      {"name":"GPU: Game Mode","cmd":["/usr/local/bin/arc-mode","game"],"workingdir":"/home/'"$GAME_USER"'","auto":false},
      {"name":"GPU: AI Mode","cmd":["/usr/local/bin/arc-mode","ai"],"workingdir":"/home/'"$GAME_USER"'","auto":false},
      {"name":"Game: Steam Big Picture","cmd":["/usr/local/bin/steam-bp-wrap"],"workingdir":"/home/'"$GAME_USER"'","auto":false},
      {"name":"Server Config","cmd":["/usr/local/bin/arc-aio-config","menu"],"workingdir":"/home/'"$GAME_USER"'","auto":false}
    ]
  ' "$apps" > "$tmp" && mv "$tmp" "$apps"
  chown "$GAME_USER:$GAME_USER" "$apps"
}

############################################
# Main
############################################
main() {
  need_root
  setup_user
  install_base
  setup_headless_xorg
  install_sunshine
  install_steam
  install_arc_mode
  install_docker_stack
  install_ollama
  setup_mlx_jumbo
  install_settings_manager
  # Apply initial web/ftp/no-ip config once
  arc-aio-apply || warn "Initial arc-aio-apply reported issues"

  add_moonlight_tiles

  # Summary
  echo ""
  echo "===================================="
  echo " ARC Server Installation Summary"
  echo "===================================="
  echo "User:             $GAME_USER"
  echo "Headless Display: ${HEADLESS_DEFAULT_RES}@${HEADLESS_DEFAULT_HZ}"
  echo "Sunshine:         enabled (configure via https://<server>:47990 or Moonlight pair)"
  echo "Steam:            $( [[ $INSTALL_STEAM -eq 1 ]] && echo installed || echo skipped )"
  echo "Docker stack:     $( [[ $ENABLE_DOCKER_STACK -eq 1 ]] && echo Jellyfin+qBittorrent || echo disabled )"
  echo "Ollama:           $( [[ $ENABLE_OLLAMA -eq 1 ]] && echo enabled || echo disabled )  Models: $OLLAMA_MODELS"
  echo "Mellanox MTU9000: $( [[ $ENABLE_JUMBO_FRAMES -eq 1 ]] && echo iface=$MLX_IFACE || echo disabled )"
  echo "Web:              http://<server-ip>/ (root: $WEB_ROOT)"
  echo "FTP:              $( [[ $ENABLE_FTP -eq 1 ]] && echo enabled user=$FTP_USER || echo disabled )"
  echo "No-IP (ddclient): $( [[ $NOIP_UPDATE -eq 1 ]] && echo enabled host=$NOIP_HOST || echo disabled )"
  echo "TLS (certbot):    $( [[ $ENABLE_TLS -eq 1 ]] && echo enabled || echo disabled )"
  echo ""
  echo "Moonlight Tiles:"
  echo "  - GPU: Game Mode"
  echo "  - GPU: AI Mode"
  echo "  - Game: Steam Big Picture (auto-restores AI mode on exit)"
  echo "  - Server Config (GUI settings)"
  echo ""
  echo "Post-install commands:"
  echo "  sudo arc-aio-config menu               # GUI settings editor (needs 'yad')"
  echo "  sudo arc-aio-config set NOIP_HOST=... NOIP_USER=... NOIP_PASS='...' && sudo arc-aio-apply"
  echo "  sudo nano /etc/arc-game-pause.list     # fine-tune what pauses in Game mode"
  echo "  sudo arc-mode toggle                   # quick switch"
  echo "===================================="
}

main "$@"
