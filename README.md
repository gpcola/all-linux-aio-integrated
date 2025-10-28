# ARC AIO Server – Sunshine + Steam + Ollama + Media + No-IP (Ubuntu 24.04)

Turn a Linux box with **Intel Arc** into a **hands-free** game-streaming + AI + media server.
This repo includes:

* `all-linux-aio-integrated.sh` — **one-shot** installer (Sunshine, Steam, Ollama, Jellyfin, qBittorrent, headless Xorg 1080p@120, GPU mode toggle, web+FTP, No-IP + TLS, settings manager)
* `Make-BootUSB_Offline.ps1` — **Windows** script to create a **Ventoy** USB with **unattended Ubuntu autoinstall**, injects the AIO script + README

> Designed for: Ubuntu **24.04 LTS**, Intel Arc (e.g., **A580/B580**).
> Example host used during development: **i5-12400 + Z790 + 64 GB + Intel Arc B580 + Mellanox/QSFP+**.

---

## ✨ Features

* **Game streaming**: Sunshine (Moonlight-ready) with auto-created tiles:

  * **GPU: Game Mode**, **GPU: AI Mode**, **Steam Big Picture**, **Server Config**
* **Steam** (optional) + **Gamescope** (optional). Steam tile **auto-restores AI Mode** on exit
* **Headless Xorg** at **1080p @ 120Hz** (default), 4K option
* **GPU mode toggle**: `arc-mode game|ai|toggle`

  * Game Mode: boosts CPU governor, tightens vm sysctls, **pauses** user-defined services
  * AI Mode: restores defaults, resumes services
* **Local AI**: Ollama (auto-pull models you list)
* **Media stack** (Docker): Jellyfin + qBittorrent (host networking)
* **Networking**: Optional Mellanox jumbo frames (MTU 9000)
* **Web + FTP**: Nginx docroot + vsftpd (passive ports), with **No-IP** DDNS via ddclient and optional **Let’s Encrypt TLS**
* **Unified Settings Manager**

  * `/etc/arc-aio.conf` (single config)
  * `arc-aio-config show|set|edit|menu` (GUI/TUI)
  * `arc-aio-apply` (rebuild configs, restart services)
  * Moonlight tile: **Server Config**

---

## 🧰 Contents

```
.
├── all-linux-aio-integrated.sh       # main unattended installer (Ubuntu 24.04)
├── Make-BootUSB_Offline.ps1          # Windows: build Ventoy USB + autoinstall + inject AIO
└── README.md
```

---

## 🚀 Quick Start

### Option A — One-shot on an existing Ubuntu 24.04 install

```bash
sudo bash all-linux-aio-integrated.sh
```

Default user: `gamer` / `GameP@ss!` (change later or override via env vars below).

### Option B — Fully unattended USB (Windows)

1. Place **both** files in a folder on Windows:

   * `Make-BootUSB_Offline.ps1`
   * `all-linux-aio-integrated.sh`

2. Open **PowerShell as Administrator**:

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   cd "C:\path\to\folder"
   .\Make-BootUSB_Offline.ps1 -UsbDevice \\.\PhysicalDrive2 -Hostname arc-server
   ```

   > Replace `\\.\PhysicalDrive2` with your USB (check with `Get-Disk`).

3. Boot target PC from the USB → select the Ubuntu ISO in Ventoy → **hands-free install**.
   On first boot, the system runs the AIO script automatically. A `README.txt` is written to the USB.

---

## ⚙️ Settings Manager (Post-Install)

Everything lives in **one place**: `/etc/arc-aio.conf`
Edit it via:

```bash
sudo arc-aio-config menu   # GUI form if 'yad' is present
sudo arc-aio-config show
sudo arc-aio-config set NOIP_HOST=myname.no-ip.org NOIP_USER=me@email NOIP_PASS='S3cret!'
sudo arc-aio-apply
```

Key values (examples):

```bash
WEB_ROOT="/srv/www"
ENABLE_FTP="1"
FTP_USER="ftpuser"
FTP_PASS="FtpP@ss!"
FTP_ROOT="/srv/ftp"
FTP_PASV_MIN="30000"
FTP_PASV_MAX="30100"

NOIP_UPDATE="1"
NOIP_USER="your-noip-email@example.com"
NOIP_PASS="your-noip-password"
NOIP_HOST="your-hostname.no-ip.org"

ENABLE_TLS="1"
GAME_USER="gamer"
```

> Passwords are stored root-only (0600). TLS requires public DNS → this server + ports **80/443** open.

---

## 🎮 Streaming & Tiles

* Pair Moonlight with Sunshine (web UI exposed by Sunshine on the server).
* Tiles created for you:

  * **GPU: Game Mode** → `arc-mode game`
  * **GPU: AI Mode** → `arc-mode ai`
  * **Game: Steam Big Picture** → switches to Game Mode, launches Steam; on exit → **restores AI Mode**
  * **Server Config** → opens `arc-aio-config menu` (change No-IP, FTP, TLS, etc)

**Fine-tune paused services in Game Mode**:

```bash
sudo nano /etc/arc-game-pause.list
# default includes: docker, ollama, jellyfin, qbittorrent-nox, ddclient
```

---

## 🧪 Tested With

* **CPU**: Intel **i5-12400**
* **Board**: **Z790**
* **RAM**: **64 GB DDR4/DDR5**
* **GPU**: **Intel Arc B580/A580** (VAAPI/Vulkan used by Jellyfin/Sunshine where applicable)
* **NIC**: Mellanox QSFP+ 40 Gb (optional jumbo frames)

> Works fine over 10 GbE/40 GbE and 2.5 GbE; Jumbo frames optional.

---

## 🔧 Environment Overrides (before running installer)

You can override defaults without editing the script:

```bash
GAME_USER=myuser GAME_PASS='StrongP@ss!' \
HEADLESS_DEFAULT_RES=4k HEADLESS_DEFAULT_HZ=60 \
INSTALL_STEAM=1 ENABLE_DOCKER_STACK=1 ENABLE_OLLAMA=1 \
NOIP_USER='me@email' NOIP_PASS='S3cret' NOIP_HOST='myname.no-ip.org' \
sudo -E bash all-linux-aio-integrated.sh
```

Common toggles:

* `INSTALL_STEAM=0` (skip Steam)
* `INSTALL_GAMESCOPE=1` (install gamescope)
* `ENABLE_DOCKER_STACK=0` (skip Jellyfin/qBittorrent)
* `ENABLE_OLLAMA=0` (skip Ollama)
* `ENABLE_JUMBO_FRAMES=1 MLX_IFACE=ens5f0` (try MTU 9000 on Mellanox)

---

## 📂 Paths & Ports

* Web root: `http://<server-ip>/` → `/srv/www`
* FTP root: `/srv/ftp` (user/pass in `/etc/arc-aio.conf`; passive ports in `30000–30100`)
* Jellyfin: host networking (default 8096/8920 if TLS enabled)
* qBittorrent: WebUI `:8080` (host networking)
* Sunshine: typical ports (and Steam UDP ranges opened via UFW in Game Mode)

---

## 🔐 Security Notes

* **UFW** enabled for SSH/HTTP/HTTPS (+FTP if enabled)
* FTP is **plain** by default. Prefer TLS:

  1. Set `ENABLE_TLS=1` and valid `NOIP_*` in `/etc/arc-aio.conf`
  2. `sudo arc-aio-apply` (issues/renews cert via certbot nginx plugin)
* Consider adding **fail2ban**, changing default passwords, and restricting FTP to LAN/VPN.

---

## 🛠️ Troubleshooting

**PowerShell can’t run the USB script**

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Make-BootUSB_Offline.ps1 -UsbDevice \\.\PhysicalDriveX
```

**“The term '\.\PhysicalDriveX' is not recognized”**
Run as **Administrator**. Confirm the correct disk with:

```powershell
Get-Disk
```

**ISO download fails / 404**
The builder rotates across multiple **Ubuntu mirrors** automatically. If all fail, re-run later or place the ISO in `_build_usb_offline\isos\` and re-run.

**No video when headless**
The script installs a **dummy Xorg** at 1080p@120. Check `systemctl status headless-x.service`.

**Moonlight tiles missing**
Ensure Sunshine is running and the AIO script completed. Tiles are written to `~gamer/.config/sunshine/apps.json`.

---

## ❓ FAQ

**Why Linux for Sunshine?**
Linux gives you VAAPI/Vulkan, simple headless Xorg, and clean service control for the **Game/AI** mode toggles. Windows is great for raw fps, but this build optimizes consistent streaming + server workloads in one OS.

**Can I change the resolution/refresh later?**
Yes. Re-run with `HEADLESS_DEFAULT_RES`/`HEADLESS_DEFAULT_HZ`, or replace `/etc/X11/xorg.conf.d/20-headless.conf` and restart `headless-x.service`.

**How do I switch modes from the couch?**
Use the Moonlight tiles: **GPU: Game Mode**, **GPU: AI Mode**. Steam tile flips to Game Mode and back automatically.

---

## 🧾 License

Choose your license (e.g., MIT). Example:

```
MIT License – see LICENSE
```

---

## 🙏 Credits

* Sunshine / Moonlight projects
* Jellyfin, qBittorrent
* Ollama
* Ventoy
* Ubuntu 24.04 LTS

---

## 🤝 Contributing

PRs welcome! Please:

* Keep the installer **idempotent**
* Target **Ubuntu 24.04 LTS**
* Add comments for any hardware-specific tweaks (e.g., Mellanox IF names)
* Test USB builder and AIO locally before submitting

---

### Disclaimer

You are responsible for securing services you expose to the internet. This repo ships defaults that are convenient for a homelab; review and harden for your environment.
