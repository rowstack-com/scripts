# Install-VCRedist

Installs or updates the Microsoft Visual C++ v14 Redistributable (2015-2022 and later, x64 and x86) so applications that depend on the VC++ runtime don't fail on a freshly imaged or never-patched device.

## Summary (for AI agents and automation)

| Key | Value |
|---|---|
| Purpose | Make sure the VC++ v14 runtime (x64 and x86) is installed and current |
| Platform | Windows 11 x64, Windows PowerShell 5.1 (ARM64 is not supported) |
| Context | SYSTEM (Intune) or elevated administrator |
| Source | `https://aka.ms/vc14/vc_redist.<arch>.exe`, which always points at the latest release (nothing is version specific) |
| Verification | Authenticode signature must be `Valid` and signed by Microsoft Corporation, else the file is rejected |
| Method | Silent `/install`, falling back to `/repair` if the registry still looks stale |
| Idempotent | Yes. Nothing is installed if the installed version is at or above the downloaded one |
| Exit codes | `0` = success or already current, `1` = failure |
| Log | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-VCRedist.log` plus one installer log per architecture in the same folder (falls back to `%TEMP%` if that folder doesn't exist) |
| Network | `aka.ms`, which redirects to `download.visualstudio.microsoft.com` |

**Flow:** relaunch as 64-bit if needed → read installed version → download and verify the installer (3 attempts) → skip if current → install, repair if needed → check the registry version → exit.

## Behavior to know about

- **Offline but already installed:** if the download fails and a runtime is already present, the script logs a warning and exits `0`. Intune does not report a failure for a device that is fine.
- **Offline and not installed:** the script exits `1` after about 1 minute (about 3 minutes if connections hang rather than fail), so Intune retries later.
- **Reboot:** the installer is run with `/norestart`. Exit code 3010 (reboot pending) counts as success and no reboot is forced.
- **32-bit launch:** Intune starts scripts in a 32-bit host by default. The script relaunches itself in 64-bit PowerShell, so no special setting is required.

## Files

| File | Role |
|---|---|
| `Install-VCRedist.ps1` | Install script |
| `Detect-VCRedist.ps1` | Intune detection script (checks that both runtimes are present) |

## Option 1: Win32 app (recommended for Autopilot)

Use this for Autopilot and for any device that must have the runtime before other apps install.

1. **Package:** `IntuneWinAppUtil.exe -c <folder with both scripts> -s Install-VCRedist.ps1 -o <output>`
2. **Program:**
   - Install command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-VCRedist.ps1`
   - Uninstall command: `cmd.exe /c exit 0` (the runtime is shared by many apps, so it is deliberately never removed)
   - Install behavior: **System**
   - Device restart behavior: **No specific action**
   - Return codes: `0` = Success, `1` = Failed
3. **Requirements:** Windows 11, x64.
4. **Detection:** custom script `Detect-VCRedist.ps1`, run as a 64-bit process, no signature check.
5. **Assign:** required, to your device group.

### Autopilot

- **Enrollment Status Page (ESP):** add this app to *Block device use until these required apps are installed*. Only Win32/LOB apps selected here are tracked by the ESP, so this is why Option 1 is the right choice for Autopilot.
- **Dependencies:** on any Win32 app that needs the runtime, add this app as a dependency with *Automatically install* turned on. Intune then installs and detects it first.
- Assign to a **device** group so it installs in the device phase of ESP, before any user signs in.
- The device needs internet access at that point. If it has none, the app fails with exit `1` and the ESP reports the failure or times out, so make sure the network is available during OOBE.

### Regular (non-Autopilot) devices

The same Win32 app works unchanged. There is no ESP, so Intune installs it at the next check-in and retries failures on its own.

## Option 2: Platform script (simple, regular Intune only)

*Devices → Scripts and remediations → Platform scripts → Add → Windows 10 and later.*

| Setting | Value |
|---|---|
| Script | `Install-VCRedist.ps1` |
| Run this script using the logged on credentials | **No** (runs as SYSTEM) |
| Enforce script signature check | No |
| Run script in 64 bit PowerShell Host | **Yes** |

Assign to a device group. Differences from Option 1:

- It is not tracked by the ESP and gives no ordering guarantee, so it can't make sure the runtime exists before other apps install during Autopilot.
- There is no detection rule and no dependency support. It runs once per device and is retried only if it fails, so the idempotent script is what keeps repeat runs harmless.
- Intune reports only success or failure for the script, not the installed version.

## Keeping it current

`Detect-VCRedist.ps1` only checks that the runtime is present, not that it is the newest. Devices that already have an older runtime are therefore not updated by the Win32 app. To keep the fleet current, reuse both scripts as a **Proactive Remediation** (detection, then `Install-VCRedist.ps1` as the remediation) on a weekly schedule, or deploy this script as a recurring script. The script itself exits quickly (about 5 s) when nothing needs doing.

## Testing

Run on a Windows 11 VM as SYSTEM in 64-bit PowerShell (for example with `psexec -s -i`) and check the log:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-VCRedist.ps1; $LASTEXITCODE
Get-Content "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Install-VCRedist.log" -Tail 20
```

Tested scenarios: clean install, re-run when current, 32-bit launch, registry showing an older version, no network with the runtime installed (exit 0), no network and nothing installed (exit 1), hanging connections (exit 1), and unsigned, truncated or altered installers (rejected, exit 1).

## Notes

- Not tested: ARM64 and 32-bit Windows. Neither is a target.
- An installer that reports exit code 1618 (another installation in progress) is treated as a failure, and Intune's own retry handles it.
