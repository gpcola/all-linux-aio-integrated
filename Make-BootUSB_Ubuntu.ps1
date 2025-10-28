<#
.SYNOPSIS
  Creates a bootable Ubuntu 24.04.1 Live Server USB and copies setup scripts.

.DESCRIPTION
  - Prompts for the USB drive letter (e.g. E)
  - Confirms wipe before continuing
  - Automatically locates or downloads the Ubuntu 24.04.1 ISO
  - Verifies SHA-256 integrity
  - Formats the USB drive FAT32 (MBR)
  - Copies ISO contents and setup files from GitHub repo
  - Relies on the ISO’s own GRUB bootloader (no bootsect/bcdboot)

.NOTES
  Run PowerShell as Administrator.
#>

$ErrorActionPreference = "Stop"

# --- Variables ---
$IsoName = "ubuntu-24.04.1-live-server-amd64.iso"
$IsoUrl  = "https://releases.ubuntu.com/24.04.1/$IsoName"
$WorkDir = "$PSScriptRoot\UbuntuUSB"
$RepoUrl = "https://github.com/gpcola/ARC-AIO-Server-Sunshine-Steam-Ollama-Media-No-IP-Ubuntu-24.04-.git"
$ExpectedSHA256 = "e4a0f4fcb5c2c90ce5a4f88f1c13c29615a37b25d5e7b1f7ef47243f1e8c6b91"

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

# --- Verify ISO integrity ---
Write-Host "==> Verifying ISO integrity..."
$FileHash = (Get-FileHash $IsoPath -Algorithm SHA256).Hash.ToLower()
if ($FileHash -ne $ExpectedSHA256) {
  Write-Host "ISO checksum mismatch. Re-downloading..." -ForegroundColor Yellow
  Remove-Item $IsoPath -Force
  Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath
  $FileHash = (Get-FileHash $IsoPath -Algorithm SHA256).Hash.ToLower()
  if ($FileHash -ne $ExpectedSHA256) {
    Write-Host "ERROR: ISO still invalid after re-download." -ForegroundColor Red
    exit 1
  }
}
Write-Host "ISO verified successfully."

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

# --- Finalize ---
Write-Host "==> USB copy complete. Ubuntu ISO already includes bootloader (no bootsect needed)."
Write-Host "`n✅ Bootable Ubuntu USB created successfully!"
Write-Host "Boot from it and run:"
Write-Host "sudo bash /cdrom/setup/setup_all.sh"
