<#
.SYNOPSIS
  Creates a bootable Ubuntu 24.04.1 Live Server USB and copies setup scripts.

.DESCRIPTION
  - Prompts for USB drive letter (e.g. E)
  - Confirms before wiping
  - Automatically downloads and verifies ISO (with retries)
  - Formats USB as FAT32
  - Copies ISO contents + setup scripts from GitHub
  - Relies on Ubuntu’s built-in GRUB bootloader

.NOTES
  Run PowerShell as Administrator.
#>

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Variables ---
$IsoName = "ubuntu-24.04.1-live-server-amd64.iso"
$IsoUrl  = "https://releases.ubuntu.com/24.04.1/$IsoName"
$WorkDir = "$PWD\UbuntuUSB"
$RepoUrl = "https://github.com/gpcola/ARC-AIO-Server-Sunshine-Steam-Ollama-Media-No-IP-Ubuntu-24.04-.git"
$ExpectedSHA256 = "E240E4B801F7BB68C20D1356B60968AD0C33A41D00D828E74CEB3364A0317BE9"

# --- Prompt for USB drive ---
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

# --- Prepare work directory ---
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Set-Location $WorkDir

# --- Locate or download ISO automatically ---
$IsoPath = Join-Path $WorkDir $IsoName
if (-not (Test-Path $IsoPath)) {
  Write-Host "==> Ubuntu ISO not found. Downloading via BITS..."
  for ($i=1; $i -le 3; $i++) {
    try {
      Start-BitsTransfer -Source $IsoUrl -Destination $IsoPath -DisplayName "Ubuntu ISO Download"
      break
    } catch {
      Write-Host "Download attempt $i failed, retrying in 15s..."
      Start-Sleep 15
      if ($i -eq 3) {
        Write-Host "Download failed after 3 attempts. Please download manually." -ForegroundColor Red
        exit 1
      }
    }
  }
} else {
  Write-Host "==> Found local ISO at $IsoPath"
}

# --- Verify ISO integrity ---
Write-Host "==> Verifying ISO integrity..."
$FileHash = (Get-FileHash $IsoPath -Algorithm SHA256).Hash.ToLower()
if ($FileHash -ne $ExpectedSHA256) {
  Write-Host "ISO checksum mismatch. Re-downloading..." -ForegroundColor Yellow
  Remove-Item $IsoPath -Force
  Start-BitsTransfer -Source $IsoUrl -Destination $IsoPath -DisplayName "Ubuntu ISO Re-Download"
  $FileHash = (Get-FileHash $IsoPath -Algorithm SHA256).Hash.ToLower()
  if ($FileHash -ne $ExpectedSHA256) {
    Write-Host "ERROR: ISO still invalid after re-download." -ForegroundColor Red
    exit 1
  }
}
Write-Host "ISO verified successfully."

# --- Unmount ISO if previously mounted ---
try {
    $mounts = Get-CimInstance -ClassName Win32_DiskDrive |
        Where-Object { $_.Model -like "*CD-ROM*" -and $_.DeviceID -like "*CDROM*" }
} catch { $mounts = @() }

if ($mounts) {
    Write-Host "==> Dismounting any previously mounted ISOs..."
    Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
}
if ($mounts) { Dismount-DiskImage -ImagePath $mounts.ImagePath }

# --- Mount ISO automatically ---
Write-Host "==> Mounting ISO..."
$iso = Mount-DiskImage -ImagePath $IsoPath -PassThru
$isoDrive = ($iso | Get-Volume).DriveLetter + ":"
Write-Host "ISO mounted at $isoDrive"

# --- Format USB ---
Write-Host "==> Formatting USB drive..."
Format-Volume -DriveLetter $UsbDrive -FileSystem exFAT -Force -Confirm:$false

# --- Copy ISO contents ---
Write-Host "==> Copying ISO contents..."
robocopy "$isoDrive\" "$UsbDrive`:\" /E

# --- Unmount ISO ---
Dismount-DiskImage -ImagePath $IsoPath

# --- Clone GitHub repo ---
Write-Host "==> Cloning setup scripts from GitHub..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host "Git not found. Installing via winget..."
  winget install --id Git.Git -e
}
git clone $RepoUrl "$WorkDir\repo"
robocopy "$WorkDir\repo" "$UsbDrive`:\setup" /E

# --- Finalize ---
Write-Host "==> USB copy complete. Ubuntu ISO already includes bootloader (no bootsect needed)."
Write-Host "`n✅ Bootable Ubuntu USB created successfully!"
Write-Host "Boot from it and run:"
Write-Host "sudo bash /cdrom/setup/setup_all.sh"
