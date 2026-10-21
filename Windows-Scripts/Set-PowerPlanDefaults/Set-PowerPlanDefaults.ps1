<#
.SYNOPSIS
Sets an initial, user-changeable power configuration on Windows devices.

.DESCRIPTION
Applies a set of default power settings to the ACTIVE power plan and to a few
related machine settings. The values are written once; they are NOT enforced
afterwards, so users can change them in Settings or Control Panel. This is the
difference from an Intune configuration policy, which keeps reapplying and
locks the setting.

What it configures (all values are set in the CONFIGURATION block below):
  - Turn off the display after a set idle time, on battery and on AC.
  - Put the computer to sleep after a set idle time, on battery and on AC.
  - Power button, sleep button and lid close actions, on battery and on AC.
  - Optionally enable hibernation and disable Fast Startup.
  - Which entries appear in the Start > Power flyout (Hibernate/Sleep/Lock).
  - Optionally, an automatic lock after a period of inactivity (off by default;
    see NOTES, this one is a policy value that users cannot change).

Settings are applied to whichever power plan is active; the plan is never
switched. Hibernate actions fall back to Sleep if hibernation cannot be enabled.

.NOTES
Requirements : Windows 10/11, Windows PowerShell 5.1 or later, administrator
               rights (SYSTEM when deployed through Intune).
Context      : Power settings are machine-wide, so run as SYSTEM or an elevated
               administrator, not as the signed-in user.
Intune       : Devices > Scripts and remediations > Platform scripts. Set "Run
               this script using the logged on credentials" = No and "Run script
               in 64-bit PowerShell Host" = Yes. Assign to a device group. The
               script runs once per device and again only if its content changes.
               A 32-bit host is detected and relaunched in 64-bit automatically.
Exit codes   : 0 = success. 1 = configuration error, or a required setting could
               not be applied. Lid close settings are optional (a device with no
               lid does not expose them) and only produce a warning.
Inactivity   : $ConfigureInactivityLock writes the policy value
               InactivityTimeoutSecs. Unlike the other settings, users cannot
               change it. It is off by default.
Status       : Edit the CONFIGURATION block, then test on a non-production
               device before deploying.

.EXAMPLE
.\Set-PowerPlanDefaults.ps1
Run from an elevated 64-bit PowerShell prompt using the values in the
CONFIGURATION block.

.EXAMPLE
psexec -s powershell.exe -ExecutionPolicy Bypass -File .\Set-PowerPlanDefaults.ps1
Run as SYSTEM, the same account Intune uses, to test an Intune deployment.
#>

# ===========================================================================
# CONFIGURATION - EDIT THIS SECTION
#
# This is the only part of the script meant to be changed. Everything below the
# "END OF CONFIGURATION" line is logic and should not need editing. Change the
# values to suit your environment; the script validates them before applying
# anything and stops with a clear message if one is wrong.
#
# Rules:
#   - Timeouts are whole numbers of MINUTES, written without quotes: 15, not "15".
#   - 0 means "Never".
#   - On/off settings are $true or $false, written without quotes.
#   - Actions are one of these exact strings, in quotes:
#     "DoNothing", "Sleep", "Hibernate", "Shutdown"
#   - "Battery" means running on battery. "PluggedIn" means on AC power.
# ===========================================================================

# --- Display ---------------------------------------------------------------
# Turn off the display after this many minutes without input.
# Valid: 0-1440 (0 = Never). Default: 15 and 15.
# This only turns the screen off. It does not lock the device on its own.
$DisplayTimeoutBatteryMinutes = 15
$DisplayTimeoutPluggedInMinutes = 15

# --- Sleep -----------------------------------------------------------------
# Put the computer to sleep after this many minutes without input.
# Valid: 0-1440 (0 = Never). Default: 30 on battery, Never when plugged in.
$SleepTimeoutBatteryMinutes = 30
$SleepTimeoutPluggedInMinutes = 0

# --- Automatic lock after inactivity (OPTIONAL, off by default) ------------
# $true writes the Windows policy value "Machine inactivity limit". Unlike
# every other setting here, users CANNOT change it afterwards.
# $ConfigureInactivityLock: $true to apply it, $false to skip. Default: $false.
# $LockAfterMinutes: minutes of inactivity before the session locks.
#   Valid: 0-9999 (0 = disabled). Only used when $ConfigureInactivityLock is $true.
$ConfigureInactivityLock = $false
$LockAfterMinutes = 15

# --- Fast Startup ----------------------------------------------------------
# Fast Startup makes shutdown a partial hibernate. Disabling it forces a true
# restart-style boot. $true disables it (recommended). $false leaves it as found.
$DisableFastStartup = $true

# --- Hibernation -----------------------------------------------------------
# Hibernation must be enabled before the button and lid actions below can use it.
# $true turns the feature on. $false leaves it as found; it never turns it off.
# If it cannot be enabled, any "Hibernate" action falls back to "Sleep".
$EnableHibernation = $true

# --- Button and lid actions ------------------------------------------------
# Valid: "DoNothing", "Sleep", "Hibernate", "Shutdown".
# Defaults: power button Hibernate; sleep button Sleep; lid close Sleep on
# battery and DoNothing when plugged in.
$PowerButtonActionBattery = "Hibernate"
$PowerButtonActionPluggedIn = "Hibernate"

$SleepButtonActionBattery = "Sleep"
$SleepButtonActionPluggedIn = "Sleep"

$LidCloseActionBattery = "Sleep"
$LidCloseActionPluggedIn = "DoNothing"

# --- Start menu power flyout (Start > Power) -------------------------------
# Which entries users see. $true shows the entry, $false hides it. Default: all $true.
# NOTE: Hibernate only appears if $EnableHibernation = $true is configured.
$ShowHibernateInFlyout = $true
$ShowSleepInFlyout = $true
$ShowLockInFlyout = $true

# ===========================================================================
# END OF CONFIGURATION - do not edit below this line unless you are changing
# how the script works.
# ===========================================================================

# If launched from a 32-bit PowerShell on 64-bit Windows (Intune's default
# host), HKLM:\SOFTWARE writes are silently redirected to Wow6432Node and never
# reach the real keys. Relaunch in the native 64-bit host before doing anything.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $nativePowerShell = Join-Path $env:windir "sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if ($PSCommandPath -and (Test-Path $nativePowerShell)) {
        Write-Output "32-bit PowerShell detected on 64-bit Windows. Relaunching in 64-bit..."
        & $nativePowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
    Write-Error "Running in 32-bit PowerShell and could not relaunch in 64-bit. Registry settings would be written to the wrong location. Run in 64-bit PowerShell."
    exit 1
}

# Script requires elevation to run.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Validate the settings above before anything is applied. This matters more
# than it looks: powercfg silently ACCEPTS a negative or oversized number and
# stores it as 0xffffffff, which means "Never" - the exact opposite of a
# timeout. A quoted value like "15" is worse: PowerShell multiplies it into
# "151515..." (string repetition, not maths), powercfg rejects it, and the
# script would otherwise carry on and report success having changed nothing.
function Assert-Minutes {
    param(
        [string]$SettingName,
        $Value,
        [int]$MaxMinutes
    )

    if ($Value -isnot [int]) {
        throw "$SettingName must be a whole number of minutes, unquoted and without decimals. Found: '$Value' (type $(if ($null -eq $Value) { 'none' } else { $Value.GetType().Name }))."
    }
    if ($Value -lt 0) {
        throw "$SettingName cannot be negative. Found: $Value. Use 0 for Never."
    }
    if ($Value -gt $MaxMinutes) {
        throw "$SettingName is too large. Found: $Value. Maximum is $MaxMinutes minutes."
    }
}

function Assert-Boolean {
    param(
        [string]$SettingName,
        $Value
    )

    if ($Value -isnot [bool]) {
        throw "$SettingName must be `$true or `$false, unquoted. Found: '$Value'."
    }
}

try {
    # 1440 minutes = 24 hours, a sane ceiling for a display/sleep timeout.
    Assert-Minutes "DisplayTimeoutBatteryMinutes" $DisplayTimeoutBatteryMinutes 1440
    Assert-Minutes "DisplayTimeoutPluggedInMinutes" $DisplayTimeoutPluggedInMinutes 1440
    Assert-Minutes "SleepTimeoutBatteryMinutes" $SleepTimeoutBatteryMinutes 1440
    Assert-Minutes "SleepTimeoutPluggedInMinutes" $SleepTimeoutPluggedInMinutes 1440

    # 9999 minutes is the maximum the inactivity limit policy accepts (599940s).
    Assert-Minutes "LockAfterMinutes" $LockAfterMinutes 9999

    Assert-Boolean "ConfigureInactivityLock" $ConfigureInactivityLock
    Assert-Boolean "EnableHibernation" $EnableHibernation
    Assert-Boolean "DisableFastStartup" $DisableFastStartup
    Assert-Boolean "ShowHibernateInFlyout" $ShowHibernateInFlyout
    Assert-Boolean "ShowSleepInFlyout" $ShowSleepInFlyout
    Assert-Boolean "ShowLockInFlyout" $ShowLockInFlyout
}
catch {
    Write-Error "Configuration error: $($_.Exception.Message)"
    exit 1
}

# Convert the values above from minutes.
$DisplayTimeoutBatterySeconds = $DisplayTimeoutBatteryMinutes * 60
$DisplayTimeoutPluggedInSeconds = $DisplayTimeoutPluggedInMinutes * 60
$SleepTimeoutBatterySeconds = $SleepTimeoutBatteryMinutes * 60
$SleepTimeoutPluggedInSeconds = $SleepTimeoutPluggedInMinutes * 60
$LockAfterSeconds = $LockAfterMinutes * 60

# Convert button and lid actions to numeric.
$ButtonActionValues = @{
    "DoNothing" = 0
    "Sleep"     = 1
    "Hibernate" = 2
    "Shutdown"  = 3
}

# Translate a friendly action name into the numeric value powercfg expects.
# Stops the script on a typo rather than silently applying the wrong action.
function Get-ButtonActionValue {
    param(
        [string]$SettingName,
        [string]$ActionName
    )

    if (-not $ButtonActionValues.ContainsKey($ActionName)) {
        $valid = ($ButtonActionValues.Keys | Sort-Object) -join ", "
        throw "Invalid value '$ActionName' for $SettingName. Valid values are: $valid"
    }

    return $ButtonActionValues[$ActionName]
}

try {
    $PowerButtonActionBatteryValue = Get-ButtonActionValue "PowerButtonActionBattery" $PowerButtonActionBattery
    $PowerButtonActionPluggedInValue = Get-ButtonActionValue "PowerButtonActionPluggedIn" $PowerButtonActionPluggedIn
    $SleepButtonActionBatteryValue = Get-ButtonActionValue "SleepButtonActionBattery" $SleepButtonActionBattery
    $SleepButtonActionPluggedInValue = Get-ButtonActionValue "SleepButtonActionPluggedIn" $SleepButtonActionPluggedIn
    $LidCloseActionBatteryValue = Get-ButtonActionValue "LidCloseActionBattery" $LidCloseActionBattery
    $LidCloseActionPluggedInValue = Get-ButtonActionValue "LidCloseActionPluggedIn" $LidCloseActionPluggedIn
}
catch {
    Write-Error "Configuration error: $($_.Exception.Message)"
    exit 1
}

# Warn if hibernation is left disabled but other settings rely on it. These
# are not errors - the settings still apply, they just will not do anything
# visible until hibernation is enabled.
if (-not $EnableHibernation) {
    $dependsOnHibernate = @()

    if ($PowerButtonActionBattery -eq "Hibernate" -or $PowerButtonActionPluggedIn -eq "Hibernate") {
        $dependsOnHibernate += "power button action"
    }
    if ($SleepButtonActionBattery -eq "Hibernate" -or $SleepButtonActionPluggedIn -eq "Hibernate") {
        $dependsOnHibernate += "sleep button action"
    }
    if ($LidCloseActionBattery -eq "Hibernate" -or $LidCloseActionPluggedIn -eq "Hibernate") {
        $dependsOnHibernate += "lid close action"
    }
    if ($ShowHibernateInFlyout) {
        $dependsOnHibernate += "Start menu Hibernate entry"
    }

    if ($dependsOnHibernate.Count -gt 0) {
        Write-Warning "`$EnableHibernation is `$false, but these settings depend on hibernation: $($dependsOnHibernate -join ', '). They will have no effect unless hibernation is already enabled on this machine."
    }
}

# Run powercfg and report anything it rejects. Failures are warnings rather
# than errors while the script runs, so one unsupported setting does not
# abandon the rest of the configuration. They are counted, and the script exits
# non-zero at the end if any required setting failed (so Intune shows the
# failure and retries).
# Settings passed with -Optional are different: some hardware legitimately
# does not expose them (a device with no lid does not expose LIDACTION), so
# a failure there is a warning only and does not affect the exit code.
# Note this catches rejected calls, not nonsensical ones - powercfg returns 0
# for an out-of-range number and silently stores "Never", which is what the
# validation above exists to prevent.
$PowerCfgFailures = 0
$OptionalFailures = 0
$RegistryFailures = 0
$LastPowerCfgSucceeded = $true

function Invoke-PowerCfg {
    param(
        [string]$Description,
        [string[]]$Arguments,
        [switch]$Optional
    )

    $output = & powercfg @Arguments 2>&1
    $script:LastPowerCfgSucceeded = ($LASTEXITCODE -eq 0)
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Description could not be applied. powercfg exited $LASTEXITCODE : $(($output | Out-String).Trim())"
        if ($Optional) {
            $script:OptionalFailures++
        }
        else {
            $script:PowerCfgFailures++
        }
    }
}

# Write a DWORD registry value, creating the key if needed. A failure is
# reported and counted but does not stop the rest of the script.
# Returns $true on success, $false on failure.
function Set-RegistryDword {
    param(
        [string]$Description,
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Warning "$Description could not be applied. $($_.Exception.Message)"
        $script:RegistryFailures++
        return $false
    }
}

# If a button or lid action is set to Hibernate but hibernation could not be
# enabled, use Sleep instead so the button/lid still does something.
function Resolve-HibernateFallback {
    param(
        [string]$SettingName,
        [string]$ActionName
    )

    if ($ActionName -eq "Hibernate") {
        Write-Warning "$SettingName is set to Hibernate but hibernation is not available. Using Sleep instead."
        return "Sleep"
    }
    return $ActionName
}

Write-Output "Modifying power settings for the active power plan..."

# Hibernation is enabled FIRST so the button and lid actions below that rely
# on it are applied to a machine that can actually hibernate. If it cannot be
# enabled (some firmware and virtual machines do not support it), Hibernate
# actions fall back to Sleep.
if ($EnableHibernation) {
    Invoke-PowerCfg "Enabling hibernation" @("/hibernate", "on")
    if ($LastPowerCfgSucceeded) {
        Write-Output "  Hibernation: enabled"
    }
    else {
        $PowerButtonActionBattery = Resolve-HibernateFallback "Power button action (battery)" $PowerButtonActionBattery
        $PowerButtonActionPluggedIn = Resolve-HibernateFallback "Power button action (plugged in)" $PowerButtonActionPluggedIn
        $SleepButtonActionBattery = Resolve-HibernateFallback "Sleep button action (battery)" $SleepButtonActionBattery
        $SleepButtonActionPluggedIn = Resolve-HibernateFallback "Sleep button action (plugged in)" $SleepButtonActionPluggedIn
        $LidCloseActionBattery = Resolve-HibernateFallback "Lid close action (battery)" $LidCloseActionBattery
        $LidCloseActionPluggedIn = Resolve-HibernateFallback "Lid close action (plugged in)" $LidCloseActionPluggedIn

        $PowerButtonActionBatteryValue = $ButtonActionValues[$PowerButtonActionBattery]
        $PowerButtonActionPluggedInValue = $ButtonActionValues[$PowerButtonActionPluggedIn]
        $SleepButtonActionBatteryValue = $ButtonActionValues[$SleepButtonActionBattery]
        $SleepButtonActionPluggedInValue = $ButtonActionValues[$SleepButtonActionPluggedIn]
        $LidCloseActionBatteryValue = $ButtonActionValues[$LidCloseActionBattery]
        $LidCloseActionPluggedInValue = $ButtonActionValues[$LidCloseActionPluggedIn]
    }
}
else {
    Write-Output "  Hibernation: left unchanged"
}

# All values below target SCHEME_CURRENT: the plan that is active on the
# device. The plan is never switched, so an OEM or custom plan is respected.

# Display timeout settings
# Subgroup: Display
# Setting: Turn off display after
Invoke-PowerCfg "Display timeout (battery)" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_VIDEO", "VIDEOIDLE", $DisplayTimeoutBatterySeconds)
Invoke-PowerCfg "Display timeout (plugged in)" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_VIDEO", "VIDEOIDLE", $DisplayTimeoutPluggedInSeconds)
Write-Output "  Display off after: $DisplayTimeoutBatteryMinutes min (battery), $DisplayTimeoutPluggedInMinutes min (plugged in)"

# Sleep after settings
# Subgroup: Sleep
# Setting: Sleep after
Invoke-PowerCfg "Sleep timeout (battery)" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_SLEEP", "STANDBYIDLE", $SleepTimeoutBatterySeconds)
Invoke-PowerCfg "Sleep timeout (plugged in)" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_SLEEP", "STANDBYIDLE", $SleepTimeoutPluggedInSeconds)
Write-Output "  Sleep after: $SleepTimeoutBatteryMinutes min (battery), $SleepTimeoutPluggedInMinutes min (plugged in)  [0 = Never]"

# Power button action settings
# Subgroup: Power buttons and lid
# Setting: Power button action
Invoke-PowerCfg "Power button action (battery)" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_BUTTONS", "PBUTTONACTION", $PowerButtonActionBatteryValue)
Invoke-PowerCfg "Power button action (plugged in)" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_BUTTONS", "PBUTTONACTION", $PowerButtonActionPluggedInValue)
Write-Output "  Power button: $PowerButtonActionBattery (battery), $PowerButtonActionPluggedIn (plugged in)"

# Sleep button action settings
Invoke-PowerCfg "Sleep button action (battery)" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_BUTTONS", "SBUTTONACTION", $SleepButtonActionBatteryValue)
Invoke-PowerCfg "Sleep button action (plugged in)" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_BUTTONS", "SBUTTONACTION", $SleepButtonActionPluggedInValue)
Write-Output "  Sleep button: $SleepButtonActionBattery (battery), $SleepButtonActionPluggedIn (plugged in)"

# Lid close action settings (optional: not exposed on devices with no lid)
Invoke-PowerCfg "Lid close action (battery)" @("/setdcvalueindex", "SCHEME_CURRENT", "SUB_BUTTONS", "LIDACTION", $LidCloseActionBatteryValue) -Optional
Invoke-PowerCfg "Lid close action (plugged in)" @("/setacvalueindex", "SCHEME_CURRENT", "SUB_BUTTONS", "LIDACTION", $LidCloseActionPluggedInValue) -Optional
Write-Output "  Lid close: $LidCloseActionBattery (battery), $LidCloseActionPluggedIn (plugged in)"

# Re-apply the active scheme so the changes above take effect immediately.
# SCHEME_CURRENT means "the plan that is already active" - it does not switch plans.
Invoke-PowerCfg "Re-applying the active scheme" @("/setactive", "SCHEME_CURRENT")
Write-Output "Power plan settings modified."

# Fast Startup
if ($DisableFastStartup) {
    if (Set-RegistryDword "Fast Startup" "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0) {
        Write-Output "  Fast Startup: disabled"
    }
}
else {
    Write-Output "  Fast Startup: left unchanged"
}

# Start Menu > Power - Flyout menu options.
$flyoutPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
$flyoutOk = $true
$flyoutOk = (Set-RegistryDword "Start menu Hibernate entry" $flyoutPath "ShowHibernateOption" ([int]$ShowHibernateInFlyout)) -and $flyoutOk
$flyoutOk = (Set-RegistryDword "Start menu Sleep entry" $flyoutPath "ShowSleepOption" ([int]$ShowSleepInFlyout)) -and $flyoutOk
$flyoutOk = (Set-RegistryDword "Start menu Lock entry" $flyoutPath "ShowLockOption" ([int]$ShowLockInFlyout)) -and $flyoutOk
if ($flyoutOk) {
    Write-Output "  Start menu power flyout - Hibernate: $ShowHibernateInFlyout, Sleep: $ShowSleepInFlyout, Lock: $ShowLockInFlyout"
}

# Inactivity Lock
if ($ConfigureInactivityLock) {
    $policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

    if (Set-RegistryDword "Inactivity lock" $policyPath "InactivityTimeoutSecs" $LockAfterSeconds) {
        if ($LockAfterMinutes -gt 0) {
            Write-Output "  Lock after: $LockAfterMinutes min of inactivity"
        }
        else {
            Write-Output "  Lock after: never (automatic lock disabled)"
        }
    }
}
else {
    Write-Output "  Lock after: left unchanged"
}

if ($OptionalFailures -gt 0) {
    Write-Warning "$OptionalFailures optional setting(s) are not supported by this hardware (for example lid close on a device with no lid) and were skipped. This does not affect the result."
}

$TotalFailures = $PowerCfgFailures + $RegistryFailures
if ($TotalFailures -gt 0) {
    Write-Warning "$TotalFailures setting(s) could not be applied - see the warnings above."
    Write-Output "Finished with errors."
    exit 1
}

Write-Output "All changes complete."
exit 0
