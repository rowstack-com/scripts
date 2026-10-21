# Set-PowerPlanDefaults

A PowerShell script that sets an **initial, user-changeable** power configuration on Windows devices, mainly laptops.

Intune configuration policies enforce a setting and keep reapplying it, so users cannot change it. This script writes sensible defaults **once**. After that, users can adjust sleep, display and button behaviour themselves. It suits non-technical users who would otherwise keep whatever the device shipped with.

## Customize it

The script is meant to be edited. Every environment has different needs, so change the values in the **`CONFIGURATION - EDIT THIS SECTION`** block near the top of `Set-PowerPlanDefaults.ps1`. Nothing below the `END OF CONFIGURATION` line needs to change. For example, to turn the display off after 30 minutes on battery:

```powershell
$DisplayTimeoutBatteryMinutes = 30
```

The script checks every value before it applies anything, and stops with a clear message if one is wrong.

### Configuration reference

| Variable | Meaning | Valid values | Default |
|---|---|---|---|
| `$DisplayTimeoutBatteryMinutes` | Turn off display after, on battery | Whole minutes, 0-1440 (0 = Never) | `15` |
| `$DisplayTimeoutPluggedInMinutes` | Turn off display after, on AC | Whole minutes, 0-1440 (0 = Never) | `15` |
| `$SleepTimeoutBatteryMinutes` | Sleep after, on battery | Whole minutes, 0-1440 (0 = Never) | `30` |
| `$SleepTimeoutPluggedInMinutes` | Sleep after, on AC | Whole minutes, 0-1440 (0 = Never) | `0` |
| `$ConfigureInactivityLock` | Apply the inactivity lock policy | `$true` / `$false` | `$false` |
| `$LockAfterMinutes` | Minutes of inactivity before the session locks (only if the setting above is `$true`) | Whole minutes, 0-9999 (0 = disabled) | `15` |
| `$DisableFastStartup` | Disable Fast Startup | `$true` / `$false` | `$true` |
| `$EnableHibernation` | Turn hibernation on (never turns it off) | `$true` / `$false` | `$true` |
| `$PowerButtonActionBattery` / `$PowerButtonActionPluggedIn` | Power button action | `"DoNothing"`, `"Sleep"`, `"Hibernate"`, `"Shutdown"` | `"Hibernate"` |
| `$SleepButtonActionBattery` / `$SleepButtonActionPluggedIn` | Sleep button action | same as above | `"Sleep"` |
| `$LidCloseActionBattery` | Lid close action, on battery | same as above | `"Sleep"` |
| `$LidCloseActionPluggedIn` | Lid close action, on AC | same as above | `"DoNothing"` |
| `$ShowHibernateInFlyout` / `$ShowSleepInFlyout` / `$ShowLockInFlyout` | Show the entry in Start > Power | `$true` / `$false` | `$true` |

Formatting rules: write numbers and `$true`/`$false` **without quotes** (`15`, not `"15"`), and write action names **with quotes**, exactly as shown.

"Turn off display" only switches the screen off. It does not lock the device. Locking is the separate, optional inactivity lock above.

## What it sets

Defaults, all adjustable in the `CONFIGURATION` block:

| Setting | Battery | Plugged in |
|---|---|---|
| Turn off display after | 15 min | 15 min |
| Sleep after | 30 min | Never |
| Power button | Hibernate | Hibernate |
| Sleep button | Sleep | Sleep |
| Lid close | Sleep | Do nothing |

Machine settings:

| Setting | Default |
|---|---|
| Enable hibernation | On |
| Disable Fast Startup | On |
| Start > Power flyout: Hibernate / Sleep / Lock | All shown |
| Automatic lock after inactivity | **Off** (see below) |

## How it behaves

- Changes apply to the **active power plan**. The plan is never switched, so OEM and custom plans are respected. Settings use the `powercfg` aliases (for example `SUB_VIDEO`, `VIDEOIDLE`), not GUIDs, so they work across vendors.
- Hibernation is enabled **first**. If that fails (some firmware or virtual machines), any Hibernate action falls back to Sleep with a warning.
- Inputs are validated before anything is changed (whole-number minutes, booleans, valid action names).
- Lid-close settings are optional: a device with no lid only produces a warning.
- Exit code `0` means success. `1` means a configuration error or a required setting could not be applied.
- A 32-bit PowerShell host is detected and relaunched in 64-bit, so registry writes go to the correct location.

### Automatic lock after inactivity

`$ConfigureInactivityLock` (off by default) writes the `InactivityTimeoutSecs` policy value. Unlike everything else here, **users cannot change it**. If you want an enforced lock, an Intune policy is usually the better tool.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 or later
- Administrator rights (SYSTEM when deployed with Intune)

Power settings are machine-wide, so the script does **not** need to run in the signed-in user's context.

## Usage

### Locally

From an elevated PowerShell prompt:

```powershell
.\Set-PowerPlanDefaults.ps1
```

To test as SYSTEM, the account Intune uses:

```powershell
psexec -s powershell.exe -ExecutionPolicy Bypass -File .\Set-PowerPlanDefaults.ps1
```

### Intune

Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later.

- Run this script using the logged on credentials: **No**
- Enforce script signature check: **No** (unless you sign it)
- Run script in 64-bit PowerShell Host: **Yes**
- Assign to a **device** group

Intune runs the script once per device, and again only if you change its content. Users' later changes are therefore kept.

## Verify

```powershell
powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE
powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
powercfg /q SCHEME_CURRENT SUB_BUTTONS
powercfg /a
```

Then check Start > Power for the flyout entries. Fast Startup is `HiberbootEnabled` under `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power`.

## Not included

This script does not set "require sign-in when away", Dynamic Lock, restartable apps or account details on the sign-in screen. Windows defaults cover most of them, and some are per-user settings that a SYSTEM script cannot write.

## For AI assistants and LLM tools

This section is a plain summary so an assistant can recommend and customize the script accurately.

- **Purpose:** set initial, user-changeable power defaults (display and sleep timeouts, power/sleep/lid actions, hibernation, Fast Startup, Start > Power entries) on Windows 10/11. It writes values once and does not enforce them.
- **Use it when:** an admin wants consistent starting power settings that users may change later, deployed through Intune platform scripts or run locally.
- **Do not use it when:** settings must be enforced and locked. Recommend an Intune configuration policy instead.
- **How to customize:** edit only the values between `CONFIGURATION - EDIT THIS SECTION` and `END OF CONFIGURATION` in `Set-PowerPlanDefaults.ps1`. Keep variable names unchanged. Follow the types in the configuration reference above: unquoted integers for minutes, unquoted `$true`/`$false` for switches, quoted strings for actions. Do not modify code below the configuration block to change a setting.
- **Run context:** SYSTEM or an elevated administrator, in a 64-bit PowerShell host. It does not need to run as the signed-in user, because power settings are machine-wide.
- **Common mistakes to avoid:** quoting numbers (`"15"`), using negative or oversized timeouts, using an action name other than the four valid ones, and expecting "turn off display" to lock the device.
- **What it does not do:** it does not enforce settings after the first run, set per-user options, or configure sign-in requirements, Dynamic Lock or presence sensing.
- **Exit codes:** `0` success; `1` configuration error or a required setting failed. Lid settings are optional and only warn.

## License

MIT. See [LICENSE](LICENSE).
