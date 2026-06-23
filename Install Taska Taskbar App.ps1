$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$launcherScript = Join-Path $scriptRoot 'Open Taska.ps1'
$iconPath = Join-Path $scriptRoot 'assets\cfma-taska-icon.ico'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

function Get-TaskaIconLocation {
    if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
        return $iconPath
    }
    return "$env:SystemRoot\System32\imageres.dll,109"
}

function New-TaskaServerStartupShortcut {
    $startup = [Environment]::GetFolderPath('Startup')
    if ([string]::IsNullOrWhiteSpace($startup)) {
        throw 'Could not find the Windows Startup folder for this user.'
    }

    $path = Join-Path $startup 'CFMA TASKA Server.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherScript`" -ServerOnly"
    $shortcut.WorkingDirectory = $scriptRoot
    $shortcut.Description = 'Start the CFMA TASKA local server at sign-in'
    $shortcut.IconLocation = Get-TaskaIconLocation
    $shortcut.Save()

    return $path
}

if (-not (Test-Path -LiteralPath $launcherScript -PathType Leaf)) {
    throw "Could not find Open Taska.ps1 beside this installer."
}

$startupShortcut = New-TaskaServerStartupShortcut

& $launcherScript -InstallWebApp

Write-Host ''
Write-Host 'CFMA TASKA taskbar setup started.' -ForegroundColor Green
Write-Host ''
Write-Host 'In the Edge tab that opened:' -ForegroundColor Yellow
Write-Host '  1. Click the app/install icon in the address bar, or open ... > Apps > Install this site as an app.'
Write-Host '  2. Use the name CFMA TASKA.'
Write-Host '  3. When the Taska app window opens, right-click its taskbar icon and choose Pin to taskbar.'
Write-Host '  4. Unpin the old Edge-looking Taska shortcut from the taskbar.'
Write-Host ''
Write-Host 'A startup shortcut was also created so the pinned Taska app can find the local server after sign-in:' -ForegroundColor Gray
Write-Host "  $startupShortcut"
