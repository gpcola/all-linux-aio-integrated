<#
.SYNOPSIS
  Creates a bootable Ubuntu 24.04.1 Live Server USB and copies setup scripts.

.DESCRIPTION
  - Prompts for the USB drive letter (e.g. E)
  - Confirms wipe before continuing
  - Automatically locates or downloads the Ubuntu 24.04.1 ISO
  - Formats the USB drive FAT32 (MBR)
  - Copies ISO contents and setup files from GitHub repo
  - Makes the USB bootable (Windows native)

.NOTES
  Run PowerShell as Administrator.
#>

$ErrorActionPreference = "Stop"

# --- Variables ---
$IsoName = "ubuntu-24.04.1-live-server-amd64.iso"
$IsoUrl  = "https://releases.ubuntu.com/24.04.1/$IsoName"
$WorkDir = "$PSScriptRoot\UbuntuUSB"
$RepoUrl = "https://github.com/gpcola/ARC-AIO-Server-Sunshine-Steam-Ollama-Media-No-IP-Ubuntu-24.04-.git"

# --- Prompt for drive letter ---
$UsbDrive = Read-Host "Enter the USB drive letter (for example E)"
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

# --- Locate or download Ubuntu ISO automatically ---
$IsoPath = Join-Path $WorkDir $IsoName
if (-not (Test-Path $IsoPath)) {
  Write-Host "==> Ubuntu ISO not found. Downloading..."
  Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath
} else {
  Write-Host "==> Found local ISO at $IsoPath"
}

# --- Unmount ISO if previously mounted ---
$mounts = Get-DiskImage | Where-Object { $_.ImagePath -like "*$IsoName" }
if ($mounts) { Dismount-DiskImage -ImagePath $mounts.ImagePath }

# --- Mount ISO automatically ---
Write-Host "==> Mounting ISO..."
$iso = Mount-DiskImage -ImagePath $IsoPath -PassThru
$isoDrive = ($iso | Get-Volume).DriveLetter + ":"
Write-Host "ISO mounted at $isoDrive"

# --- Format USB drive ---
Write-Host "==> Formatting USB drive..."
Format-Volume -DriveLetter $UsbDrive -FileSystem FAT32 -Force -Confirm:$false

# --- Copy ISO contents to USB ---
Write-Host "==> Copying ISO contents..."
robocopy "$isoDrive\" "$UsbDrive`:\" /E

# --- Unmount ISO ---
Dismount-DiskImage -ImagePath $IsoPath

# --- Clone GitHub repo ---
Write-Host "==> Cloning setup scripts from GitHub..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found, installing via winget..."
    winget install --id Git.Git -e
}
git clone $RepoUrl "$WorkDir\repo"
robocopy "$WorkDir\repo" "$UsbDrive`:\setup" /E

# --- Make USB bootable ---
Write-Host "==> Making USB bootable..."
bootsect /nt60 "$UsbDrive`:" /mbr
bcdboot "$UsbDrive`:\boot" /s "$UsbDrive`:"

Write-Host "`n✅ Bootable Ubuntu USB created successfully!"
Write-Host "Boot from it and run:"
Write-Host "sudo bash /cdrom/setup/setup_all.sh"
