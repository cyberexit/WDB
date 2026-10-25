# bore.ps1 - Windows 10 bore tunnel helper (force local port = remote port)
# Run: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass ; .\bore.ps1

$ErrorActionPreference = "Stop"

$BoreVersion = "v0.6.0"
$BoreZipName = "bore-$BoreVersion-x86_64-pc-windows-msvc.zip"
$BoreUrl     = "https://github.com/ekzhang/bore/releases/download/$BoreVersion/$BoreZipName"
$WorkDir     = "$env:USERPROFILE\bore_dashboard"
$BoreExe     = "$WorkDir\bore.exe"

function Write-Step { param($msg) Write-Host "`n[->] $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[X]  $msg" -ForegroundColor Red }

Write-Step "Preparing bore $BoreVersion ..."

if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

if (-not (Test-Path $BoreExe)) {
    $zipPath = Join-Path $WorkDir $BoreZipName
    if (-not (Test-Path $zipPath)) {
        Write-Host "    Downloading from GitHub ..."
        try {
            Invoke-WebRequest -Uri $BoreUrl -OutFile $zipPath -UseBasicParsing
        } catch {
            Write-Err "Download failed: $_"
            exit 1
        }
    }
    Write-Host "    Extracting ..."
    Expand-Archive -LiteralPath $zipPath -DestinationPath $WorkDir -Force
    $found = Get-ChildItem -Path $WorkDir -Filter "bore.exe" -Recurse | Select-Object -First 1
    if ($found -and $found.FullName -ne $BoreExe) {
        Copy-Item $found.FullName $BoreExe -Force
    }
    if (-not (Test-Path $BoreExe)) {
        Write-Err "bore.exe not found after extraction."
        exit 1
    }
}
Write-OK "bore.exe ready: $BoreExe"

Write-Step "Enter the port you want (used for BOTH local and remote):"
$PortInput = Read-Host "    Port"

if (-not ($PortInput -match '^\d+$')) {
    Write-Err "Port must be a number."
    exit 1
}
$Port = [int]$PortInput

Write-Step "Checking local port $Port ..."
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    Write-Warn "No service is listening on local port $Port."
    Write-Warn "Start your listener first, otherwise bore will report 'could not connect'."
    $ans = Read-Host "    Continue anyway? (y/n)"
    if ($ans -ne 'y') { exit 0 }
} else {
    $pidVal = $listener[0].OwningProcess
    $pname = (Get-Process -Id $pidVal -ErrorAction SilentlyContinue).ProcessName
    Write-OK "Local port $Port is listening (PID $pidVal, process $pname)"
}

$logFile = Join-Path $WorkDir "bore_output.log"
$errFile = Join-Path $WorkDir "bore_error.log"
Remove-Item $logFile, $errFile -ErrorAction SilentlyContinue

Write-Step "Starting bore: local $Port -> bore.pub:$Port ..."
$boreArgs = @("local", "$Port", "--to", "bore.pub", "--port", "$Port")
$boreProc = Start-Process -FilePath $BoreExe -ArgumentList $boreArgs `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError  $errFile `
    -NoNewWindow -PassThru

Start-Sleep -Seconds 4

# Check if bore exited immediately (port taken)
if ($boreProc.HasExited) {
    Write-Err "bore exited immediately. Port $Port is likely taken on bore.pub."
    if (Test-Path $errFile) {
        $err = Get-Content $errFile -Raw
        if ($err) { Write-Host "    stderr: $err" -ForegroundColor DarkGray }
    }
    if (Test-Path $logFile) {
        $log = Get-Content $logFile -Raw
        if ($log) { Write-Host "    stdout: $log" -ForegroundColor DarkGray }
    }
    Write-Host ""
    Write-Host "  Port $Port is occupied on bore.pub. Try a different port number." -ForegroundColor Yellow
    exit 1
}

# Parse public address
$publicHost = $null
$publicPort = $null

if (Test-Path $logFile) {
    $content = Get-Content $logFile -Raw
    if ($content -match 'listening at\s+(\S+):(\d+)') {
        $publicHost = $Matches[1]
        $publicPort = $Matches[2]
    }
}

if ($publicHost) {
    Write-Host ""
    Write-Host "  ==============================================" -ForegroundColor Cyan
    Write-Host "   PUBLIC ADDRESS (use this in your client)" -ForegroundColor Cyan
    Write-Host "  ==============================================" -ForegroundColor Cyan
    Write-Host "   Host : $publicHost" -ForegroundColor White
    Write-Host "   Port : $publicPort" -ForegroundColor White
    Write-Host "  ==============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Agent Builder settings:" -ForegroundColor Yellow
    Write-Host "     IP/DNS = $publicHost" -ForegroundColor Yellow
    Write-Host "     Port   = $publicPort" -ForegroundColor Yellow
} else {
    Write-Err "Could not parse public address from log."
    if (Test-Path $logFile) { Get-Content $logFile -Tail 20 }
    if (Test-Path $errFile) { Get-Content $errFile -Tail 20 }
    exit 1
}

Write-Step "Monitoring connections (Ctrl+C to stop) ..."
Write-Host "    Watching local port $Port for established connections."
Write-Host ""

$seen = @{}

while (-not $boreProc.HasExited) {
    Start-Sleep -Seconds 2

    if (Test-Path $logFile) {
        $lines = Get-Content $logFile -Tail 20 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match 'new connection' -and $line -match 'id=([a-f0-9\-]+)') {
                $connId = $Matches[1]
                if (-not $seen.ContainsKey($connId)) {
                    $seen[$connId] = $true
                    $t = Get-Date -Format "HH:mm:ss"
                    Write-Host "  [$t] NEW CONNECTION (bore proxy $connId)" -ForegroundColor Green
                }
            }
        }
    }

    $est = Get-NetTCPConnection -LocalPort $Port -State Established -ErrorAction SilentlyContinue
    if ($est) {
        foreach ($c in $est) {
            $key = "$($c.LocalAddress):$($c.LocalPort)-$($c.RemoteAddress):$($c.RemotePort)"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $t = Get-Date -Format "HH:mm:ss"
                Write-Host "  [$t] CLIENT CONNECTED  remote=$($c.RemoteAddress):$($c.RemotePort)" -ForegroundColor Green
            }
        }
    }
}

Write-Warn "bore process exited."
if (Test-Path $errFile) {
    $err = Get-Content $errFile -Raw
    if ($err) { Write-Host "    stderr: $err" -ForegroundColor DarkGray }
}