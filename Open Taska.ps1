param(
    [switch]$ServerOnly,
    [switch]$InstallWebApp
)

$ErrorActionPreference = 'Stop'

$port = 8080
$appUrl = "http://localhost:$port/"
$pwaInstallUrl = "http://localhost:$port/surveyors-toolbox.html?source=pwa-install"
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$serverScript = Join-Path $scriptRoot 'server.ps1'

function Test-TaskaServer {
    try {
        $response = Invoke-WebRequest -Uri $appUrl -UseBasicParsing -TimeoutSec 2
        $content = [string]$response.Content
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500 -and $content -match 'CFMA|TASKA|surveyors-toolbox')
    } catch {
        return $false
    }
}

function Start-TaskaServerHidden {
    if (-not (Test-Path -LiteralPath $serverScript -PathType Leaf)) {
        throw "Could not find server.ps1 beside this launcher."
    }

    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$serverScript`""
    )
    Start-Process -FilePath $powershell -ArgumentList $args -WorkingDirectory $scriptRoot -WindowStyle Hidden | Out-Null
}

function Get-TaskaBrowserPath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return $null
}

function Get-TaskaInstalledWebAppShortcut {
    $roots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        ([Environment]::GetFolderPath('Desktop'))
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) }

    if ($roots.Count -eq 0) { return $null }

    $shell = New-Object -ComObject WScript.Shell
    $seen = @{}

    foreach ($root in $roots) {
        foreach ($link in Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue) {
            if ($seen.ContainsKey($link.FullName)) { continue }
            $seen[$link.FullName] = $true

            try {
                $shortcut = $shell.CreateShortcut($link.FullName)
                $target = [string]$shortcut.TargetPath
                $arguments = [string]$shortcut.Arguments
                $description = [string]$shortcut.Description
            } catch {
                continue
            }

            $nameText = "$($link.BaseName) $description"
            $isTaskaShortcut = $nameText -match '(?i)\b(CFMA\s+)?TASKA\b'
            $isBrowserAppShortcut = $target -match '(?i)(msedge_proxy|chrome_proxy|msedge|chrome)\.exe$' -and
                ($arguments -match '(?i)--app-id|--app-url|localhost:8080|127\.0\.0\.1:8080|surveyors-toolbox')
            $isLauncherShortcut = $target -match '(?i)(powershell|pwsh|cmd|wscript|cscript)\.exe$'

            if ($isTaskaShortcut -and $isBrowserAppShortcut -and -not $isLauncherShortcut) {
                return $link.FullName
            }
        }
    }

    return $null
}

if (-not (Test-TaskaServer)) {
    Start-TaskaServerHidden
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-TaskaServer) {
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        throw "Taska server did not start on $appUrl. Run Start Server.bat once to see the error."
    }
}

if ($ServerOnly) {
    return
}

$browser = Get-TaskaBrowserPath

if ($InstallWebApp) {
    if ($browser) {
        Start-Process -FilePath $browser -ArgumentList @(
            '--new-window',
            $pwaInstallUrl
        ) | Out-Null
    } else {
        Start-Process $pwaInstallUrl | Out-Null
    }
    return
}

$installedAppShortcut = Get-TaskaInstalledWebAppShortcut
if ($installedAppShortcut) {
    Start-Process -FilePath $installedAppShortcut | Out-Null
} elseif ($browser) {
    Start-Process -FilePath $browser -ArgumentList @(
        '--no-first-run',
        "--app=$appUrl"
    ) | Out-Null
} else {
    Start-Process $appUrl | Out-Null
}
