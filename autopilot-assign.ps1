# Autopilot Profile Assignment Script
# Run after autopilot-register.ps1 completes:
#   powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/kooyaniks/intune-scripts/main/autopilot-assign.ps1 | iex"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Autopilot Profile Assignment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Install Microsoft Graph module
Write-Host "[1/5] Installing Microsoft Graph module..." -ForegroundColor Yellow
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force | Out-Null
Write-Host "  Done." -ForegroundColor Green

# Step 2: Connect to Graph
Write-Host "[2/5] Connecting to Microsoft Graph..." -ForegroundColor Yellow
Write-Host "  Sign in when prompted." -ForegroundColor Cyan
Connect-MgGraph -Scopes "DeviceManagementServiceConfig.ReadWrite.All","Device.Read.All","GroupMember.ReadWrite.All","DeviceManagementManagedDevices.Read.All" -NoWelcome
Write-Host "  Connected." -ForegroundColor Green

# Step 3: Find this device in Autopilot by serial number
Write-Host "[3/5] Finding this device in Autopilot..." -ForegroundColor Yellow
$serial = (Get-WmiObject -Class Win32_BIOS).SerialNumber
Write-Host "  Device serial: $serial" -ForegroundColor Cyan

$apUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
$apDevices = Invoke-MgGraphRequest -Method GET -Uri $apUri
$apDevice = $apDevices.value | Where-Object { $_.serialNumber -eq $serial }

if (-not $apDevice) {
    Write-Host "  ERROR: Device not found in Autopilot. Run the registration script first." -ForegroundColor Red
    return
}

Write-Host "  Found: $($apDevice.serialNumber)" -ForegroundColor Green
$aadDeviceId = $apDevice.azureActiveDirectoryDeviceId
Write-Host "  Azure AD Device ID: $aadDeviceId" -ForegroundColor Cyan
$profileStatus = $apDevice.deploymentProfileAssignmentStatus
if ($profileStatus -match "assigned") {
    Write-Host "  Profile Status: Assigned" -ForegroundColor Green
} else {
    Write-Host "  Profile Status: $profileStatus (will check again after group assignment)" -ForegroundColor Yellow
}

# Step 4: Find Azure AD object and add to groups
Write-Host "[4/5] Adding device to MEM_WindowsDevices group..." -ForegroundColor Yellow

# Wait for Azure AD device to appear (may take a minute after registration)
$maxRetries = 12
$retry = 0
$aadDevice = $null

while ($retry -lt $maxRetries -and -not $aadDevice) {
    $allDevices = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/devices?`$top=999&`$select=id,displayName,deviceId"
    $aadDevice = $allDevices.value | Where-Object { $_.deviceId -eq $aadDeviceId }
    if (-not $aadDevice) {
        $retry++
        Write-Host "  Waiting for Azure AD device to appear... ($retry/$maxRetries)" -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }
}

if (-not $aadDevice) {
    Write-Host "  WARNING: Azure AD device not found yet. Groups will need to be added manually." -ForegroundColor Red
} else {
    Write-Host "  Found Azure AD device: $($aadDevice.displayName) ($($aadDevice.id))" -ForegroundColor Green
    $objectId = $aadDevice.id
    $body = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$objectId" } | ConvertTo-Json

    # MEM_WindowsDevices
    try {
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/12da6c6b-381d-4bbc-b039-473baa713141/members/`$ref" -Body $body -ContentType "application/json"
        Write-Host "  MEM_WindowsDevices: Added" -ForegroundColor Green
    } catch {
        $err = "$($_.Exception.Message) $($_.ErrorDetails.Message)"
        if ($err -match "already exist") { Write-Host "  MEM_WindowsDevices: Already a member" -ForegroundColor Green }
        else { Write-Host "  MEM_WindowsDevices: Error - $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# Step 5: Wait for Autopilot profile to be assigned
Write-Host "[5/5] Checking Autopilot profile assignment..." -ForegroundColor Yellow

# Re-check current status first
$apDevices = Invoke-MgGraphRequest -Method GET -Uri $apUri
$apDevice = $apDevices.value | Where-Object { $_.serialNumber -eq $serial }
$profileStatus = $apDevice.deploymentProfileAssignmentStatus

$maxWait = 30
$wait = 0
$assigned = $false

if ($profileStatus -match "assigned") {
    $assigned = $true
    Write-Host "  Profile status: Assigned" -ForegroundColor Green
}

if (-not $assigned) {
    # Trigger Autopilot sync to speed up profile assignment
    try {
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync"
        Write-Host "  Triggered Autopilot sync." -ForegroundColor Cyan
    } catch {
        Write-Host "  Sync already in progress." -ForegroundColor Cyan
    }

    while ($wait -lt $maxWait -and -not $assigned) {
        Start-Sleep -Seconds 30
        $apDevices = Invoke-MgGraphRequest -Method GET -Uri $apUri
        $apDevice = $apDevices.value | Where-Object { $_.serialNumber -eq $serial }
        $status = $apDevice.deploymentProfileAssignmentStatus
        $wait++

        if ($status -match "assigned") {
            $assigned = $true
            Write-Host "  Profile status: Assigned" -ForegroundColor Green
        } else {
            Write-Host "  Profile status: $status - waiting... ($wait/$maxWait)" -ForegroundColor Yellow
        }
    }

    if (-not $assigned) {
        Write-Host "  WARNING: Profile not yet assigned after 15 minutes. Check Intune portal." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Assignment complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
$confirm = Read-Host "Shutdown now? The device will start Autopilot on next power on. (Y/N)"
if ($confirm -match "^[Yy]") {
    Write-Host "  Shutting down in 5 seconds..." -ForegroundColor Yellow
    Stop-Computer -Force
} else {
    Write-Host "  Skipped. Run 'Stop-Computer -Force' when ready." -ForegroundColor Cyan
}

