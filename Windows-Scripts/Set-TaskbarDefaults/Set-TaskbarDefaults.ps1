# To add a classic app (such as a VPN client), add a line like the Edge line below, but use DesktopApplicationLinkPath="<full path of its Start menu .lnk>" instead of DesktopApplicationID. Pins appear in the order listed.
# To add a Store app, copy an UWA line and use its AUMID (find it with Get-StartApps). Install the app before the user's first sign-in or the pin is skipped.
$ErrorActionPreference = "Stop"
$dir = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
$file = "$dir\LayoutModification.xml"
New-Item -Path $dir -ItemType Directory -Force | Out-Null
$xml = @'
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" PinGeneration="1"/>
        <taskbar:DesktopApp DesktopApplicationID="MSEdge" PinGeneration="1"/>
        <taskbar:UWA AppUserModelID="Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows" PinGeneration="1"/>
        <taskbar:UWA AppUserModelID="MSTeams_8wekyb3d8bbwe!MSTeams" PinGeneration="1"/>
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
'@
[IO.File]::WriteAllText($file, $xml, (New-Object Text.UTF8Encoding($false)))
if (Test-Path $file) { Write-Output "Layout written: $file"; exit 0 }
Write-Output "Layout file was not created."; exit 1
