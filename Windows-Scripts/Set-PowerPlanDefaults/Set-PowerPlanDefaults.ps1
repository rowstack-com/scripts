# Sets initial, user-changeable power settings on the active power plan. Written once, not enforced. Edit the values below.
# Minutes are whole numbers without quotes (0 = Never). Switches are $true or $false. Actions are "DoNothing", "Sleep", "Hibernate" or "Shutdown".

$DisplayTimeoutBatteryMinutes   = 15   # Turn off display after, 0-1440
$DisplayTimeoutPluggedInMinutes = 15
$SleepTimeoutBatteryMinutes     = 30   # Sleep after, 0-1440
$SleepTimeoutPluggedInMinutes   = 0

$PowerButtonActionBattery   = "Hibernate"
$PowerButtonActionPluggedIn = "Hibernate"
$SleepButtonActionBattery   = "Sleep"
$SleepButtonActionPluggedIn = "Sleep"
$LidCloseActionBattery      = "Sleep"
$LidCloseActionPluggedIn    = "DoNothing"

$EnableHibernation = $true   # Turns hibernation on, never off. Needed for the Hibernate actions and Start entry.
$DisableFastStartup = $true

$ShowHibernateInFlyout = $true   # Start > Power entries
$ShowSleepInFlyout = $true
$ShowLockInFlyout = $true

$ConfigureInactivityLock = $false   # Policy value: users cannot change it. Locks after $LockAfterMinutes (0-9999) of inactivity.
$LockAfterMinutes = 15

# --- End of configuration ---

# 32-bit PowerShell would write HKLM:\SOFTWARE values to the wrong place, so relaunch in 64-bit.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    & "$env:windir\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

# powercfg accepts a bad number silently (it stores "Never"), and a quoted "15" is not a number, so check first.
$actionCodes = @{ DoNothing = 0; Sleep = 1; Hibernate = 2; Shutdown = 3 }
$errors = @()
foreach ($n in "DisplayTimeoutBatteryMinutes", "DisplayTimeoutPluggedInMinutes", "SleepTimeoutBatteryMinutes", "SleepTimeoutPluggedInMinutes") {
    $v = Get-Variable $n -ValueOnly
    if ($v -isnot [int] -or $v -lt 0 -or $v -gt 1440) { $errors += "$n must be a whole number from 0 to 1440, without quotes." }
}
if ($LockAfterMinutes -isnot [int] -or $LockAfterMinutes -lt 0 -or $LockAfterMinutes -gt 9999) { $errors += "LockAfterMinutes must be a whole number from 0 to 9999, without quotes." }
foreach ($n in "EnableHibernation", "DisableFastStartup", "ShowHibernateInFlyout", "ShowSleepInFlyout", "ShowLockInFlyout", "ConfigureInactivityLock") {
    if ((Get-Variable $n -ValueOnly) -isnot [bool]) { $errors += "$n must be `$true or `$false, without quotes." }
}
foreach ($n in "PowerButtonActionBattery", "PowerButtonActionPluggedIn", "SleepButtonActionBattery", "SleepButtonActionPluggedIn", "LidCloseActionBattery", "LidCloseActionPluggedIn") {
    if (-not $actionCodes.ContainsKey([string](Get-Variable $n -ValueOnly))) { $errors += "$n must be DoNothing, Sleep, Hibernate or Shutdown, in quotes." }
}
if ($errors) { Write-Error ("Configuration error:`n" + ($errors -join "`n")); exit 1 }

$failed = 0

function Set-PowerValue($Mode, $Sub, $Setting, $Value, [switch]$Optional) {
    $out = & powercfg $Mode SCHEME_CURRENT $Sub $Setting $Value 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Setting could not be applied: $out"
        if (-not $Optional) { $script:failed++ }
    }
}

function Set-RegistryDword($Path, $Name, $Value) {
    try {
        if (-not (Test-Path $Path)) { New-Item $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "$Name could not be applied: $($_.Exception.Message)"
        $script:failed++
    }
}

# Hibernation first, so the Hibernate actions below have something to use.
if ($EnableHibernation) {
    powercfg /hibernate on 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "Hibernation could not be enabled."; $failed++ }
}

# All values target the active plan (SCHEME_CURRENT). The plan is never switched.
Set-PowerValue /setdcvalueindex SUB_VIDEO VIDEOIDLE ($DisplayTimeoutBatteryMinutes * 60)
Set-PowerValue /setacvalueindex SUB_VIDEO VIDEOIDLE ($DisplayTimeoutPluggedInMinutes * 60)
Set-PowerValue /setdcvalueindex SUB_SLEEP STANDBYIDLE ($SleepTimeoutBatteryMinutes * 60)
Set-PowerValue /setacvalueindex SUB_SLEEP STANDBYIDLE ($SleepTimeoutPluggedInMinutes * 60)
Set-PowerValue /setdcvalueindex SUB_BUTTONS PBUTTONACTION ($actionCodes[$PowerButtonActionBattery])
Set-PowerValue /setacvalueindex SUB_BUTTONS PBUTTONACTION ($actionCodes[$PowerButtonActionPluggedIn])
Set-PowerValue /setdcvalueindex SUB_BUTTONS SBUTTONACTION ($actionCodes[$SleepButtonActionBattery])
Set-PowerValue /setacvalueindex SUB_BUTTONS SBUTTONACTION ($actionCodes[$SleepButtonActionPluggedIn])
# A device with no lid does not expose the lid setting, so a failure here is not counted.
Set-PowerValue /setdcvalueindex SUB_BUTTONS LIDACTION ($actionCodes[$LidCloseActionBattery]) -Optional
Set-PowerValue /setacvalueindex SUB_BUTTONS LIDACTION ($actionCodes[$LidCloseActionPluggedIn]) -Optional
powercfg /setactive SCHEME_CURRENT
if ($LASTEXITCODE -ne 0) { Write-Warning "The active plan could not be re-applied."; $failed++ }

if ($DisableFastStartup) {
    Set-RegistryDword "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" HiberbootEnabled 0
}
$flyout = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
Set-RegistryDword $flyout ShowHibernateOption ([int]$ShowHibernateInFlyout)
Set-RegistryDword $flyout ShowSleepOption ([int]$ShowSleepInFlyout)
Set-RegistryDword $flyout ShowLockOption ([int]$ShowLockInFlyout)
if ($ConfigureInactivityLock) {
    Set-RegistryDword "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" InactivityTimeoutSecs ($LockAfterMinutes * 60)
}

if ($failed -gt 0) { Write-Output "Finished with $failed failure(s). See the warnings above."; exit 1 }
Write-Output "Power settings applied."
exit 0
