$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$serverScript = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot 'server.ps1'))
$escapedServerScript = [regex]::Escape($serverScript)

$matches = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
    Where-Object {
        $_.CommandLine -and
        ($_.CommandLine -match $escapedServerScript -or ($_.CommandLine -match 'server\.ps1' -and $_.CommandLine -match [regex]::Escape($scriptRoot)))
    }

if (-not $matches) {
    Write-Host 'No CFMA TASKA server process was found.' -ForegroundColor Yellow
    return
}

foreach ($proc in $matches) {
    Stop-Process -Id $proc.ProcessId -Force
    Write-Host "Stopped CFMA TASKA server process $($proc.ProcessId)." -ForegroundColor Green
}
