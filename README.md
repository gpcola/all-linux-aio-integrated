
# ARC-AIO Server — Sunshine · Steam · Ollama · Media · No-IP (Ubuntu 24.04.1)



A complete automation stack for building an Intel Arc-powered home server:

- Game streaming via **Sunshine + Steam**

- Local AI models via **Ollama**

- Web + FTP access via **Apache + vsftpd**

- Dynamic DNS via **No-IP**

- Hardware monitoring via **lm-sensors + node_exporter**

- GPU mode toggling (AI/Game)

- Docker + NVIDIA Container Toolkit pre-installed

- Optimized for low-latency performance



---



## 📦 Directory Layout

\\\

setup/

├── setup_all.sh

├── 00_prep.sh

├─── 01_base_install.sh

├─── 02_services_install.sh

├─── 03_monitoring_setup.sh

├─── 04_gpu_modes.sh

├── 05_optimisations.sh

├─── configure_media_drive.sh

├── noip.conf (optional, contains credentials)

└── README_1LG.md

\\\



---



## 🧰 Installation Steps



1. **Prepare Ventoy USB**

   - Flash Ventoy to your drive.

   - Download \ubuntu-24.04.1-live-server-amd64.iso\

     from [releases.ubuntu.com/24.04.1](https://releases.ubuntu.com/24.04.1)

   - Copy the ISO and \setup/\ folder to the root of the USB.



2. **Boot and Run**

   - Boot your target machine from the USB.

   - Choose the ISO in Ventoy’s menu.

   - When in the live shell, run:

     \\\ash

     sudo bash /cdrom/setup/setup_all.sh

     \\\



3. **Logs**

   - Logs are saved to \/var/log/1lg_install.log\



4. **Primary User**

   - Default user: \gp\

   - Root SSH login: **disabled**

   - Use \sudo\ for administration.



---



## 🌍 No-IP DDNS Configuration



The installer looks for a file named **\
oip.conf\** in the same folder as your setup scripts.  

Example:



\\\ash

USERNAME="your_noip_email_or_username"

PASSWORD="your_noip_password"

HOSTNAME="your_hostname.ddns.net"

\\\



The script reads these values and runs:

\\\ash

sudo noip2 -C -u "" -p "" -U 30 -Y -H ""

\\\



To change them later:

\\\ash

sudo nano /etc/noip2.conf

sudo systemctl restart noip2

\\\



⚠️ **Security Tip:** Keep \
oip.conf\ private and never commit it to public repositories.



---



## 🎮 GPU Mode Toggle



Switch between workloads easily:



\\\ash

sudo /usr/local/bin/04_gpu_modes.sh ai

sudo /usr/local/bin/04_gpu_modes.sh game

sudo /usr/local/bin/04_gpu_modes.sh status

\\\



- **AI Mode:** starts Ollama, pauses Sunshine & Steam  

- **Game Mode:** pauses AI tasks, starts Sunshine & Steam  

- Auto-restores AI mode after Steam closes.



---



## 📊 Monitoring and Dashboard



- Metrics served on **\http://<server-ip>:8085/metrics\**

- JSON snapshot at \/var/log/hwmon/latest.json\

- Helper command:

  \\\ash

  sudo hwmon-to-json.sh

  \\\



---



## 🧩 Post-Install: Media Drive Setup



After installation, run:

\\\ash

sudo bash /setup/configure_media_drive.sh

\\\



This script:

- Detects your large HDD  

- Formats it (optional, confirmed interactively)  

- Mounts it at \/mnt/storage\  

- Creates \/mnt/storage/llms\ for Ollama models  

- Updates \/etc/fstab\ automatically



---



## ⚙️ System Optimizations

Applied automatically:

- CPU governor → \performance\

- I/O scheduler → \mq-deadline\

- TCP congestion control → \br\

- Disabled hibernation and snapd for lean operation.



---



## 🧠 Default Ports

| Service | Port | Notes |

|----------|------|-------|

| SSH | 22 | \gp\ user only |

| HTTP | 80 | Apache |

| HTTPS | 443 | Apache SSL |

| FTP | 21 | vsftpd |

| Sunshine Stream | 47984–48010/udp | |

| Node Exporter | 8085 | Metrics + JSON Proxy |



---



## 🔒 Firewall (UFW)

Enabled with rules for all required services.  

You can check with:

\\\ash

sudo ufw status

\\\



---



## 📚 Logs and Maintenance

- Setup log: \/var/log/1lg_install.log\

- GPU mode log: \/var/log/gpu_mode.log\

- Hardware metrics: \/var/log/hwmon/latest.json\



To update services:

\\\ash

sudo apt update && sudo apt upgrade -y

\\\



---



**Made for Ubuntu 24.04.1 — Intel Arc + Z790 + 64GB RAM**

