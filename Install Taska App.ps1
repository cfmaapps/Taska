$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$launcherScript = Join-Path $scriptRoot 'Open Taska.ps1'
$iconPath = Join-Path $scriptRoot 'assets\cfma-taska-icon.ico'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

function Get-TaskaBrowserPath {
    $roots = @(
        ${env:ProgramFiles(x86)},
        $env:ProgramFiles,
        $env:LOCALAPPDATA
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $relativePaths = @(
        'Microsoft\Edge\Application\msedge.exe',
        'Google\Chrome\Application\chrome.exe'
    )

    foreach ($root in $roots) {
        foreach ($relative in $relativePaths) {
            $candidate = Join-Path $root $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return $null
}

function New-TaskaShortcut {
    param([string]$Path)

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherScript`""
    $shortcut.WorkingDirectory = $scriptRoot
    $shortcut.Description = 'Open CFMA TASKA'

    if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
        $shortcut.IconLocation = $iconPath
    } else {
        $browser = Get-TaskaBrowserPath
        if ($browser) {
            $shortcut.IconLocation = $browser
        } else {
            $shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
        }
    }

    $shortcut.Save()
}

if (-not (Test-Path -LiteralPath $launcherScript -PathType Leaf)) {
    throw "Could not find Open Taska.ps1 beside this installer."
}

$desktop = [Environment]::GetFolderPath('Desktop')
$programs = [Environment]::GetFolderPath('Programs')
$desktopShortcut = Join-Path $desktop 'CFMA TASKA.lnk'
$startShortcut = Join-Path $programs 'CFMA TASKA.lnk'

New-TaskaShortcut -Path $desktopShortcut
New-TaskaShortcut -Path $startShortcut

Write-Host ''
Write-Host 'CFMA TASKA shortcuts created:' -ForegroundColor Green
Write-Host "  Desktop:    $desktopShortcut"
Write-Host "  Start Menu: $startShortcut"
Write-Host ''
Write-Host 'To pin it: open Start, search CFMA TASKA, right-click it, then choose Pin to taskbar.' -ForegroundColor Yellow
Write-Host 'The shortcut starts the local server hidden and opens Taska as an app window.' -ForegroundColor Gray
