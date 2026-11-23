$dlls = @{ x64 = "$env:WINDIR\System32\vcruntime140.dll"; x86 = "$env:WINDIR\SysWOW64\vcruntime140.dll" }

foreach ($arch in 'x64', 'x86') {
    if (-not (Test-Path $dlls[$arch])) { Write-Output "$arch runtime DLL missing"; exit 1 }
    $installed = foreach ($view in 'Registry32', 'Registry64') {
        $key = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view).OpenSubKey("SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$arch")
        if ($key -and $key.GetValue('Installed') -eq 1) { $true }
    }
    if (-not $installed) { Write-Output "$arch runtime not registered"; exit 1 }
}

Write-Output 'Visual C++ v14 x64 and x86 detected'
exit 0
