<#
.SYNOPSIS
  Creates a bootable Ubuntu 24.04.1 Live Server USB and copies setup scripts.

.DESCRIPTION
  - Prompts for the USB drive letter (e.g. E:)
  - Confirms wipe before continuing
  - Downloads the Ubuntu 24.04.1 ISO if missing
  - Formats the USB drive FAT32 (MBR)
  - Copies ISO contents and setup files from GitHub repo
  - Makes the USB bootable

.NOTES
  Run as Administrator.
#>

$ErrorActionPreference = "Stop"

# --- Variables ---
$IsoUrl = "https://releases.ubuntu.com/24.04.1/ubuntu-24.04.1-live-server-amd64.iso"
$IsoName = "ubuntu-24.04.1-live-server-amd64.iso"
$WorkDir = "$PSScriptRoot\UbuntuUSB"
$RepoUrl = "https://github.com/gpcola/ARC-AIO-Server-Sunshine-Steam-Ollama-Media-No-IP-Ubuntu-24.04-.git"

# --- Prompt for drive letter ---
$UsbDrive = Read-Host "Enter the USB drive letter (e.g. E)"
if (-not (Test-Path "$UsbDrive`:")) {
  Write-Host "Drive $UsbDrive`: not found." -ForegroundColor Red
  exit 1
}

Write-Host "`nWARNING: This will ERASE all data on drive $UsbDrive`:" -ForegroundColor Yellow
$confirm = Read-Host "Type YES to confirm"
if ($confirm -ne "YES") {
  Write-Host "Operation cancelled."
  exit 0
}

# --- Prepare working directory ---
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Set-Location $WorkDir

# --- Download ISO if not already present ---
if (-not (Test-Path "$IsoName")) {
  Write-Host "==> Downloading Ubuntu 24.04.1 Live Server ISO..."
  Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoName
} else {
  Write-Host "==> Found existing ISO. Skipping download."
}

# --- Unmount ISO if previously mounted ---
$mounts = Get-DiskImage | Where-Object {$_.ImagePath -like "*$IsoName"}
if ($mounts) { Dismount-DiskImage -ImagePath $mounts.ImagePath }

# --- Mount ISO ---
Write-Host "==> Mounting ISO..."
$iso = Mount-DiskImage -ImagePath "$WorkDir\$IsoName" -PassThru
$isoDrive = ($iso | Get-Volume).DriveLetter + ":"
Write-Host "ISO mounted at $isoDrive"

# --- Format USB ---
Write-Host "==> Formatting USB drive..."
Get-Disk | Where-Object {$_.FriendlyName -match "$UsbDrive"} | Out-Null
Format-Volume -DriveLetter $UsbDrive -FileSystem FAT32 -Force -Confirm:$false

# --- Copy ISO contents ---
Write-Host "==> Copying ISO contents..."
robocopy "$isoDrive\" "$UsbDrive`:\" /E

# --- Unmount ISO ---
Dismount-DiskImage -ImagePath "$WorkDir\$IsoName"

# --- Clone GitHub repo ---
Write-Host "==> Cloning setup scripts..."
git clone $RepoUrl "$WorkDir\repo"
robocopy "$WorkDir\repo" "$UsbDrive`:\setup" /E

# --- Make bootable ---
Write-Host "==> Making USB bootable..."
bootsect /nt60 "$UsbDrive`:" /mbr
bcdboot "$UsbDrive`:\boot" /s "$UsbDrive`:"

Write-Host "`n✅ Bootable Ubuntu USB created successfully!"
Write-Host "Boot from it and run:"
Write-Host "sudo bash /cdrom/setup/setup_all.sh"
