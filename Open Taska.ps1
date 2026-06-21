$ErrorActionPreference = 'Stop'

$port = 8080
$appUrl = "http://localhost:$port/"
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

$browser = Get-TaskaBrowserPath
if ($browser) {
    Start-Process -FilePath $browser -ArgumentList @(
        '--no-first-run',
        "--app=$appUrl"
    ) | Out-Null
} else {
    Start-Process $appUrl | Out-Null
}
