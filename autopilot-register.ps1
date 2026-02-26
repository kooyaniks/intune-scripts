# Autopilot Device Registration Script
# Run during OOBE after Shift+F10:
#   powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/kooyaniks/intune-scripts/main/autopilot-register.ps1 | iex"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Autopilot Device Registration" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Install NuGet provider
Write-Host "[1/4] Installing NuGet provider..." -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Write-Host "  Done." -ForegroundColor Green

# Step 2: Install Autopilot script
Write-Host "[2/4] Installing Get-WindowsAutopilotInfo..." -ForegroundColor Yellow
Install-Script -Name Get-WindowsAutopilotInfo -Force
Write-Host "  Done." -ForegroundColor Green

# Step 3: Set execution policy
Write-Host "[3/4] Setting execution policy..." -ForegroundColor Yellow
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
Write-Host "  Done." -ForegroundColor Green

# Step 4: Register device
Write-Host "[4/4] Registering device in Autopilot..." -ForegroundColor Yellow
Write-Host "  You will be prompted to sign in to proceed." -ForegroundColor Cyan
Write-Host ""
Get-WindowsAutopilotInfo -Online

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Registration complete!" -ForegroundColor Green
Write-Host "  Next steps:" -ForegroundColor Green
Write-Host "  1. Wait for profile to be assigned" -ForegroundColor White
Write-Host "  2. Power off the device" -ForegroundColor White
Write-Host "  3. Power on and let Autopilot build" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
