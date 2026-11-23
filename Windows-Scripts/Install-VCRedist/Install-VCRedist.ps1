<#
.SYNOPSIS
    Installs or updates the Microsoft Visual C++ v14 Redistributable (x64, then x86).
.NOTES
    Exit codes: 0 = success or already current, 1 = failure
    A device that already has the runtime but cannot reach the download site is left as is (exit 0, warning logged).
    Source: the aka.ms/vc14 permalinks, which always point at the latest release. Nothing here is version specific.
#>

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    & "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest very slow
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$packages = @(
    @{ Arch = 'x64'; Dll = "$env:WINDIR\System32\vcruntime140.dll" }
    @{ Arch = 'x86'; Dll = "$env:WINDIR\SysWOW64\vcruntime140.dll" }
)

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { $logDir = $env:TEMP }
Start-Transcript "$logDir\Install-VCRedist.log" -Append | Out-Null

$workDir  = Join-Path $env:TEMP "VCRedist_$([guid]::NewGuid().ToString('N'))"
$exitCode = 0

# Write-Host (not Write-Output) so log lines inside functions never leak into a function's return value.
function Write-Log($Message) { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" }

function Get-InstalledVersion($Package) {
    if (-not (Test-Path $Package.Dll)) { return }
    $versions = foreach ($root in 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node') {
        $key = Get-ItemProperty "$root\Microsoft\VisualStudio\14.0\VC\Runtimes\$($Package.Arch)" -ErrorAction SilentlyContinue
        if ($key.Installed -eq 1) { try { [version]"$($key.Major).$($key.Minor).$($key.Bld).$($key.Rbld)" } catch {} }
    }
    $versions | Sort-Object -Descending | Select-Object -First 1
}

function Get-Installer($Package) {
    $file = "$workDir\vc_redist.$($Package.Arch).exe"
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest "https://aka.ms/vc14/vc_redist.$($Package.Arch).exe" -OutFile $file -UseBasicParsing -TimeoutSec 30
            # A truncated or tampered file fails here, so no separate length check is needed.
            $sig = Get-AuthenticodeSignature $file
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw "Signature check failed ($($sig.Status))." }
            $vi = (Get-Item $file).VersionInfo
            Write-Log "$($Package.Arch): downloaded and verified, SHA256 $((Get-FileHash $file).Hash)"
            return @{ Path = $file; Version = [version]::new($vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart, $vi.FilePrivatePart) }
        }
        catch {
            Write-Log "$($Package.Arch): download attempt $i of 3 failed: $($_.Exception.Message)"
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            if ($i -lt 3) { Start-Sleep -Seconds (10 * $i) }
        }
    }
    throw 'No verified download after 3 attempts.'
}

try {
    New-Item $workDir -ItemType Directory | Out-Null

    foreach ($p in $packages) {
        try {
            $installed = Get-InstalledVersion $p
            Write-Log "$($p.Arch): installed version $(if ($installed) { $installed } else { 'none' })"

            try { $pkg = Get-Installer $p }
            catch {
                if (-not $installed) { throw }
                Write-Log "$($p.Arch): WARNING: cannot check for updates ($($_.Exception.Message)) Keeping $installed."
                continue
            }
            if ($installed -and $installed -ge $pkg.Version) { Write-Log "$($p.Arch): up to date."; continue }

            foreach ($mode in '/install', '/repair') {   # /repair fixes registry values that /install leaves untouched
                $code = (Start-Process $pkg.Path -ArgumentList "$mode /quiet /norestart /log `"$logDir\VCRedist_$($p.Arch)_$($mode.Trim('/')).log`"" -Wait -PassThru).ExitCode
                Write-Log "$($p.Arch): installer $mode exit code $code"
                if ($code -notin 0, 1638, 3010) { throw "Installer $mode failed with exit code $code." }   # 1638 = newer version present, 3010 = reboot pending
                $installed = Get-InstalledVersion $p
                if ($installed -and $installed -ge $pkg.Version) { break }
            }
            if (-not $installed -or $installed -lt $pkg.Version) { throw "Validation failed (installed: $installed, expected: $($pkg.Version))." }
            Write-Log "$($p.Arch): $installed installed and verified."
        }
        catch {
            Write-Log "$($p.Arch): ERROR: $($_.Exception.Message)"
            $exitCode = 1
        }
    }
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Exit code $exitCode"
    Stop-Transcript | Out-Null
}

exit $exitCode
