# Set-TaskbarDefaults

Sets the initial taskbar for new users on Windows 11. By default the script configures the following apps in order: **File Explorer, Microsoft Edge, Outlook and Microsoft Teams**. Everything else the OEM or Windows pins (Store, Copilot, Microsoft 365) is removed. Users can then pin, unpin and reorder freely, and their changes are kept.

## Prerequisites

- Windows 11 24H2 with KB5060829 (build 26100.4484) or later
- Administrator rights (SYSTEM when deployed with Intune or other MDM)
- The pinned apps installed or provisioned before the user's first sign-in. A pin for a missing app is skipped silently.

## How it works

The script writes `LayoutModification.xml` to the Default user profile (`C:\Users\Default\AppData\Local\Microsoft\Windows\Shell`). Windows copies it into each new profile and applies it at that user's first sign-in.

- Every pin has `PinGeneration="1"`, so Windows pins each app once and an app the user unpins stays unpinned.
- Each user keeps their own copy. Editing or re-running the script only affects profiles created afterwards.
- A profile created before the script ran gets the layout at its next sign-in.
- Exit code `0` means the file was written. Any failure exits `1`, which Intune reports as failed.

Tested on Windows 11 build 26300, on an activated copy of Windows (an unactivated one restricts personalization).

## Change the pins

The pins are the `<taskbar:...>` lines in the XML inside the script, shown left to right in the order listed. Delete a line to remove a pin, move lines to reorder.

Add a **classic app** (such as a VPN client) by the path of its Start menu shortcut. The shortcut only has to exist when the user signs in:

```xml
<taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\FortiClient VPN.lnk" PinGeneration="1"/>
```

Add a **Store app** by its AUMID (find it with `Get-StartApps`):

```xml
<taskbar:UWA AppUserModelID="Microsoft.WindowsCalculator_8wekyb3d8bbwe!App" PinGeneration="1"/>
```

Keep `PinGeneration="1"` on every line. The script does not validate the XML, so check it after editing.

## Recommended Deployment: Deploy for Intune Autopilot

Deploy it as a **Win32 app** that blocks the Enrollment Status Page (ESP), so the desktop waits until the layout file is in place. A platform script is not tracked by the ESP, so its timing is not guaranteed.

1. **Package.** Put the script in an empty folder and run the [Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool).
2. **Add.** **Apps** > **Windows** > **Add** > **Windows app (Win32)** > select the `.intunewin` file.
3. **Program.**

   | Setting | Value |
   |---|---|
   | Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Set-TaskbarDefaults.ps1"` |
   | Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml' -Force -ErrorAction SilentlyContinue"` |
   | Install behavior | System |
   | Device restart behavior | No specific action |

4. **Requirements.** Your device architectures, and the lowest Windows 11 version as the minimum OS.
5. **Detection.** Manually configure > **File** > path `C:\Users\Default\AppData\Local\Microsoft\Windows\Shell`, file `LayoutModification.xml`, **File or folder exists**, not associated with a 32-bit app. Once the file exists, Intune treats the app as installed and does not run it again on that device. If your device image already has a layout file there, use a detection script that checks for text unique to your layout.
6. **Dependencies (optional).** Add any app you pin as a dependency so it installs first.
7. **Assignment.** **Required**, to a **device** group.
8. **ESP.** In the Enrollment Status Page profile, set **Block device use until all apps and profiles are installed** to Yes, then under **Block device use until these required apps are installed** choose **Selected** and add this app and every app you pin.
9. **Check.** **Apps** > the app > **Device install status**. For detail, see `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs` on the device. The Win32/ESP route has not been tested on a real Autopilot device.

A platform script also works if guaranteed timing is not needed: run as SYSTEM, signature check off, assigned to a device group. If it runs late, the layout applies at the user's next sign-in.

## Test

Run the script from an elevated prompt, then sign in as a user who has never signed in (create a new local user) and check the taskbar. To view the file:

```powershell
Get-Content "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml"
```

## Undo

Delete the layout file. Users created afterwards get the default taskbar; existing pins stay until the user changes them.

```powershell
Remove-Item "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml"
```

## Keeping it working

Re-test with a new user after each Windows feature update. The supported alternative is an Intune Settings catalog "Start Layout" policy, which takes the same XML but re-applies on a schedule and can overwrite user changes. Do not run both.

## License

MIT. See [LICENSE](LICENSE).
