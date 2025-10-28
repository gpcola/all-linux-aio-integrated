param(
  [Parameter(Mandatory=$true)][string]$UsbDevice,          # e.g. \\.\PhysicalDrive2  (WIPES DRIVE)
  [string]$AioScriptPath = ".\all-linux-aio-integrated.sh",# the full AIO installer (same folder by default)
  [string]$Hostname = "arc-server"                         # autoinstall hostname
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "==> Preparing work directories..."
$Work      = Join-Path $pwd "_build_usb_offline"
$IsoDir    = Join-Path $Work "isos"
$VentoyDir = Join-Path $Work "ventoy"
New-Item -ItemType Directory -Force -Path $Work,$IsoDir,$VentoyDir | Out-Null

# ---- 1) Ventoy (Windows) ----------------------------------------------------
Write-Host "==> Downloading Ventoy (Windows release)..."
$ventoyRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/ventoy/Ventoy/releases/latest"
$ventoyZipUrl  = ($ventoyRelease.assets | Where-Object { $_.name -like "*windows.zip" } | Select-Object -First 1).browser_download_url
if (-not $ventoyZipUrl) { throw "Could not resolve Ventoy Windows zip URL." }

$VentoyZipPath = Join-Path $VentoyDir "ventoy.zip"
Invoke-WebRequest -Uri $ventoyZipUrl -OutFile $VentoyZipPath
Expand-Archive -Path $VentoyZipPath -DestinationPath $VentoyDir -Force
$VentoyExe = Get-ChildItem $VentoyDir -Recurse -Filter "Ventoy2Disk.exe" | Select-Object -First 1
if (-not $VentoyExe) { throw "Ventoy2Disk.exe not found after extraction." }

Write-Host "==> Installing Ventoy to $UsbDevice (THIS WILL WIPE THE DRIVE)..."
& "$($VentoyExe.FullName)" /I $UsbDevice | Out-Null

Start-Sleep -Seconds 2
$vols = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.FileSystemLabel -like 'Ventoy*' }
if (-not $vols) { throw "Could not find mounted Ventoy partition. Replug USB or assign a drive letter." }
$UsbDrive = ($vols | Select-Object -First 1).DriveLetter + ":"
Write-Host "==> Ventoy partition mounted as $UsbDrive"

# Create folders on USB
New-Item -ItemType Directory -Force -Path (Join-Path $UsbDrive "ISOS")                    | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $UsbDrive "ventoy")                  | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $UsbDrive "ventoy\nocloud")          | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $UsbDrive "ventoy\docs")             | Out-Null

# ---- 2) Ubuntu 24.04.3 ISO (mirror rotation) --------------------------------
$IsoCandidates = @(
  "https://hr.releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso",
  "https://nl.releases.ubuntu.com/releases/24.04.3/ubuntu-24.04.3-live-server-amd64.iso",
  "https://mirror.arizona.edu/ubuntu-releases/24.04/ubuntu-24.04.3-live-server-amd64.iso",
  "https://download.nus.edu.sg/mirror/ubuntu-releases/releases/24.04.3/ubuntu-24.04.3-live-server-amd64.iso",
  "https://mirror.cs.princeton.edu/pub/mirrors/ubuntu-releases/releases/24.04/ubuntu-24.04.3-live-server-amd64.iso"
)
$UbuntuIsoName = "ubuntu-24.04.3-live-server-amd64.iso"
$UbuntuIsoPath = Join-Path $IsoDir $UbuntuIsoName
New-Item -ItemType Directory -Force -Path $IsoDir | Out-Null

function Try-Download($url, $dst) {
  Write-Host "   -> Trying: $url"
  $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
  try {
    Invoke-WebRequest -Uri $url -OutFile $dst -Headers $headers -MaximumRedirection 10 -TimeoutSec 0 -UseBasicParsing
    if ((Get-Item $dst).Length -gt 100MB) { return $true }
  } catch { Write-Warning "IWR failed: $($_.Exception.Message)" }
  try {
    Start-BitsTransfer -Source $url -Destination $dst -Description "Ubuntu ISO" -RetryInterval 60 -RetryTimeout 86400
    if ((Get-Item $dst).Length -gt 100MB) { return $true }
  } catch { Write-Warning "BITS failed: $($_.Exception.Message)" }
  $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Path
  if ($curl) {
    & $curl -L --retry 10 --retry-all-errors --speed-time 60 --speed-limit 100000 -o $dst $url
    if ((Test-Path $dst) -and ((Get-Item $dst).Length -gt 100MB)) { return $true }
    Write-Warning "curl.exe failed or file too small."
  }
  return $false
}

if (!(Test-Path $UbuntuIsoPath) -or ((Get-Item $UbuntuIsoPath).Length -lt 100MB)) {
  Write-Host "==> Downloading Ubuntu 24.04.3 Server ISO (mirror rotation)…"
  $ok = $false
  foreach ($u in $IsoCandidates) { if (Try-Download $u $UbuntuIsoPath) { $ok = $true; break } }
  if (-not $ok) { throw "All ISO mirrors failed." }
} else {
  Write-Host "==> ISO already present: $UbuntuIsoPath (skipping download)"
}
Copy-Item $UbuntuIsoPath (Join-Path $UsbDrive "ISOS") -Force

# ---- 3) NoCloud autoinstall + firstboot (runs your AIO script) ---------------
$NoCloudUsb = Join-Path $UsbDrive "ventoy\nocloud"
Write-Host "==> Writing NoCloud files to $NoCloudUsb ..."

# meta-data
Set-Content -Path (Join-Path $NoCloudUsb "meta-data") -Value @"
instance-id: iid-ubuntu-autoinstall
local-hostname: $Hostname
"@ -Encoding ASCII

# user-data (Curtin copies and enables firstboot + your AIO script)
$userData = @"
#cloud-config
autoinstall:
  version: 1
  locale: en_GB
  keyboard: { layout: gb }
  identity:
    hostname: $Hostname
    username: gamer
    password: "\$6\$rounds=4096\$placeholder\$hash"
  ssh: { install-server: true, allow-pw: true }
  storage: { layout: { name: lvm } }
  packages: [curl, ca-certificates]
  late-commands:
    - curtin in-target --target=/target -- bash -c "cp /cdrom/nocloud/firstboot.service /etc/systemd/system/firstboot.service"
    - curtin in-target --target=/target -- bash -c "cp /cdrom/nocloud/firstboot.sh /usr/local/sbin/firstboot.sh && chmod +x /usr/local/sbin/firstboot.sh"
    - curtin in-target --target=/target -- bash -c "cp /cdrom/nocloud/all-linux-aio-integrated.sh /root/all-linux-aio-integrated.sh && chmod +x /root/all-linux-aio-integrated.sh"
    - curtin in-target --target=/target -- systemctl enable firstboot.service
"@
Set-Content -Path (Join-Path $NoCloudUsb "user-data") -Value $userData -Encoding UTF8

# firstboot: runs the big AIO script once
$firstboot = @"
#!/usr/bin/env bash
set -euo pipefail
id -u gamer >/dev/null 2>&1 || useradd -m -s /bin/bash gamer || true
echo "gamer:GameP@ss!" | chpasswd
usermod -aG sudo gamer || true
# Default GPU/display + Steam on first run; you can change later via /etc/arc-aio.conf and arc-aio-config
HEADLESS_DEFAULT_RES=1080p HEADLESS_DEFAULT_HZ=120 INSTALL_STEAM=1 /root/all-linux-aio-integrated.sh
systemctl disable firstboot.service || true
"@
Set-Content -Path (Join-Path $NoCloudUsb "firstboot.sh") -Value $firstboot -Encoding ASCII

# systemd unit
$firstbootSvc = @"
[Unit]
Description=Run ARC firstboot provisioning once
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/firstboot.sh
RemainAfterExit=no
[Install]
WantedBy=multi-user.target
"@
Set-Content -Path (Join-Path $NoCloudUsb "firstboot.service") -Value $firstbootSvc -Encoding ASCII

# ---- 4) Copy your AIO script & README to the USB -----------------------------
if (!(Test-Path $AioScriptPath)) {
  throw "AIO script not found at $AioScriptPath. Place all-linux-aio-integrated.sh next to this PS1 or pass -AioScriptPath."
}
Copy-Item $AioScriptPath (Join-Path $UsbDrive "ventoy\nocloud\all-linux-aio-integrated.sh") -Force

$Readme = @"
ARC Server USB (Ventoy + Ubuntu 24.04.3 Autoinstall)

How to use:
1) Boot the target machine from this USB.
2) In Ventoy, select the Ubuntu 24.04.3 Server ISO under /ISOS/.
3) The installer uses NoCloud from /cdrom/nocloud and completes unattended.
4) On first boot, systemd runs /usr/local/sbin/firstboot.sh, which executes:
      /root/all-linux-aio-integrated.sh
   That script installs:
     - Headless Xorg @ 1080p 120Hz (changeable)
     - Sunshine (Moonlight-ready) + Moonlight tiles
     - Steam (Game Mode auto / restore AI mode on exit)
     - GPU toggle:  arc-mode game | ai | toggle
     - Docker: Jellyfin + qBittorrent (host networking)
     - Ollama (local LLMs)
     - Web + FTP + Dynamic DNS (No-IP via ddclient) + optional TLS
     - Settings manager:
         /etc/arc-aio.conf
         arc-aio-config  (show | set | edit | menu)
         arc-aio-apply   (apply changes, restart services)

Post-install cheat sheet (SSH or local):
  sudo arc-aio-config menu
  sudo arc-aio-config set NOIP_HOST=myname.no-ip.org NOIP_USER=my@email NOIP_PASS="secret"
  sudo arc-aio-apply
  sudo nano /etc/arc-game-pause.list
  sudo arc-mode toggle

Default locations:
  Web root:        /srv/www            → http://<server-ip>/
  FTP root:        /srv/ftp            (user/pass from /etc/arc-aio.conf)
  Media root:      /srv/media
  Jellyfin config: /srv/jellyfin       (Jellyfin uses host network)
  qBittorrent:     /srv/qbittorrent    (WebUI :8080)

Security notes:
  - FTP is plain by default; enable TLS via arc-aio-config (+ certbot) if exposing to internet.
  - Firewall (ufw) is enabled and opened for SSH/HTTP/HTTPS (+FTP if enabled).
  - /etc/arc-aio.conf and /etc/ddclient.conf are root:root 0600.

Enjoy :)
"@
Set-Content -Path (Join-Path $UsbDrive "README.txt") -Value $Readme -Encoding UTF8
Copy-Item (Join-Path $UsbDrive "README.txt") (Join-Path $UsbDrive "ventoy\docs\README.txt") -Force

# ---- 5) Ventoy plugin: inject cmdline + nocloud into the ISO -----------------
Write-Host "==> Writing ventoy.json (kernel params + file injection)..."
$ventoyJson = @"
{
  "control_legacy": [ { "VTOY_DEFAULT_MENU_MODE": "0" } ],
  "control_uefi":   [ { "VTOY_DEFAULT_MENU_MODE": "0" } ],
  "injection": [
    {
      "image": "/ISOS/$UbuntuIsoName",
      "part": 1,
      "archive": [
        { "source": "/ventoy/ubuntu_kernel_params.cfg", "target": "/cmdline" },
        { "source": "/ventoy/nocloud/user-data",        "target": "/nocloud/user-data" },
        { "source": "/ventoy/nocloud/meta-data",        "target": "/nocloud/meta-data" },
        { "source": "/ventoy/nocloud/firstboot.sh",     "target": "/nocloud/firstboot.sh" },
        { "source": "/ventoy/nocloud/firstboot.service","target": "/nocloud/firstboot.service" },
        { "source": "/ventoy/nocloud/all-linux-aio-integrated.sh", "target": "/nocloud/all-linux-aio-integrated.sh" }
      ]
    }
  ]
}
"@
Set-Content -Path (Join-Path $UsbDrive "ventoy\ventoy.json") -Value $ventoyJson -Encoding UTF8
Set-Content -Path (Join-Path $UsbDrive "ventoy\ubuntu_kernel_params.cfg") -Value "autoinstall ds=nocloud;s=/cdrom/nocloud/ ---" -Encoding ASCII

# ---- 6) Summary --------------------------------------------------------------
Write-Host ""
Write-Host "===================================="
Write-Host "   OFFLINE UBUNTU USB: READY"
Write-Host "===================================="
Write-Host ("USB drive:        {0}" -f $UsbDrive)
Write-Host ("Ventoy installed: yes")
Write-Host ("Ubuntu ISO:       {0}" -f $UbuntuIsoName)
Write-Host ("NoCloud folder:   {0}" -f "$UsbDrive\ventoy\nocloud")
Write-Host ("AIO script:       {0}" -f "$UsbDrive\ventoy\nocloud\all-linux-aio-integrated.sh")
Write-Host ("README:           {0}" -f "$UsbDrive\README.txt")
Write-Host ""
Write-Host "Boot target → Ventoy menu → select the Ubuntu ISO."
Write-Host "Autoinstall will run; first boot executes the AIO script."
Write-Host "===================================="
