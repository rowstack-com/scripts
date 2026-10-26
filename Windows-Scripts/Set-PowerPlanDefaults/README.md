# Set-PowerPlanDefaults

Sets initial, user-changeable power settings on Windows 10 and 11 for laptop or desktop systems. The values are written once and not enforced, so users can change sleep, display and button behavior afterwards. This is the difference from an Intune configuration policy, which keeps reapplying and locks the setting.

## Prerequisites

- Windows 10 or 11
- Administrator rights (SYSTEM when deployed with Intune or other MDM)

## How it works

The script applies the values to the **active power plan** with `powercfg`. It never switches plans, so OEM and custom plans are respected. It also sets a few machine settings: hibernation, Fast Startup, the Start > Power entries and an optional inactivity lock.

- Values are checked before anything is changed. `powercfg` silently turns a negative or oversized number into "Never", so a bad value stops the script with exit code `1` and nothing is applied.
- Lid close is optional. A device with no lid, such as a desktop, does not expose it, and that is not counted as a failure.
- Exit code `0` means everything applied. Any other failure exits `1`, which Intune reports as failed.
- A 32-bit PowerShell host is relaunched in 64-bit so registry writes reach the correct keys.

## Configuration

Edit the values at the top of `Set-PowerPlanDefaults.ps1`. Write minutes and `$true`/`$false` **without quotes**, and action names **with quotes**.

| Variable | Meaning | Valid values | Default |
|---|---|---|---|
| `$DisplayTimeoutBatteryMinutes` / `$DisplayTimeoutPluggedInMinutes` | Turn off display after | Minutes, 0-1440 (0 = Never) | `15` / `15` |
| `$SleepTimeoutBatteryMinutes` / `$SleepTimeoutPluggedInMinutes` | Sleep after | Minutes, 0-1440 (0 = Never) | `30` / `0` |
| `$PowerButtonActionBattery` / `$PowerButtonActionPluggedIn` | Power button action | `"DoNothing"`, `"Sleep"`, `"Hibernate"`, `"Shutdown"` | `"Hibernate"` |
| `$SleepButtonActionBattery` / `$SleepButtonActionPluggedIn` | Sleep button action | same | `"Sleep"` |
| `$LidCloseActionBattery` / `$LidCloseActionPluggedIn` | Lid close action | same | `"Sleep"` / `"DoNothing"` |
| `$EnableHibernation` | Turn hibernation on (never off). Needed for Hibernate actions and the Start entry | `$true` / `$false` | `$true` |
| `$DisableFastStartup` | Disable Fast Startup | `$true` / `$false` | `$true` |
| `$ShowHibernateInFlyout` / `$ShowSleepInFlyout` / `$ShowLockInFlyout` | Show the entry in Start > Power | `$true` / `$false` | `$true` |
| `$ConfigureInactivityLock` | Apply the inactivity lock policy. Users **cannot** change it | `$true` / `$false` | `$false` |
| `$LockAfterMinutes` | Minutes of inactivity before the session locks. Used only if the setting above is `$true` | Minutes, 0-9999 (0 = disabled) | `15` |

"Turn off display" only switches the screen off. It does not lock the device.

## Deploy with Intune

Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later. Set **Run this script using the logged on credentials** to No, **Enforce script signature check** to No, **Run script in 64-bit PowerShell host** to Yes, and assign it to a **device** group. Intune runs it once per device, and again only if you change the script, so users' later changes are kept.

To test as SYSTEM: `psexec -s powershell.exe -ExecutionPolicy Bypass -File .\Set-PowerPlanDefaults.ps1`

## Verify

```powershell
powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE
powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
powercfg /qh SCHEME_CURRENT SUB_BUTTONS
powercfg /a
```

Then check Start > Power for the entries.

## Not included

"Require sign-in when away", Dynamic Lock, restartable apps and sign-in screen account details. Windows defaults cover most of them, and some are per-user settings a SYSTEM script cannot write.

## License

MIT. See [LICENSE](LICENSE).
