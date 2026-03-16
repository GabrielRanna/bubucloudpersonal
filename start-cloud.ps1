$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cloud-common.ps1"

$cfg = Get-PersonalCloudConfig
$localUrl = "http://127.0.0.1:$($cfg.PublicPort)"
$internalFileBrowserUrl = "http://127.0.0.1:$($cfg.FileBrowserPort)"

New-Item -ItemType Directory -Force -Path $cfg.BaseDir, $cfg.ConfigDir, $cfg.LogDir, $cfg.DataRoot | Out-Null

$fileBrowserPid = Read-PidFile -Path $cfg.FileBrowserPidFile
if (-not $fileBrowserPid -or -not (Test-ProcessAlive -ProcessId $fileBrowserPid)) {
  foreach ($proc in (Get-ProcessByCommandHint -ProcessName 'filebrowser.exe' -CommandHint $cfg.FileBrowserDb)) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
  }

  $fileBrowserProc = Start-Process -FilePath $cfg.FileBrowserExe `
    -ArgumentList @('-d', $cfg.FileBrowserDb, '-a', '127.0.0.1', '-p', "$($cfg.FileBrowserPort)") `
    -WorkingDirectory (Split-Path -Path $cfg.FileBrowserExe -Parent) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $cfg.FileBrowserStdOutLog `
    -RedirectStandardError $cfg.FileBrowserStdErrLog `
    -PassThru
  $fileBrowserProc.Id | Set-Content -LiteralPath $cfg.FileBrowserPidFile -Encoding Ascii
}

for ($i = 0; $i -lt 30; $i++) {
  if (Test-LocalCloud -Url $internalFileBrowserUrl) {
    break
  }
  Start-Sleep -Seconds 1
}

if (-not (Test-LocalCloud -Url $internalFileBrowserUrl)) {
  throw 'File Browser interno nao iniciou corretamente.'
}

$gatewayPid = Read-PidFile -Path $cfg.GatewayPidFile
if (-not $gatewayPid -or -not (Test-ProcessAlive -ProcessId $gatewayPid)) {
  foreach ($proc in (Get-ProcessByCommandHint -ProcessName 'python.exe' -CommandHint $cfg.GatewayScript)) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
  }

  foreach ($path in @($cfg.GatewayLog, $cfg.GatewayErrLog)) {
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
  }

  $gatewayProc = Start-Process -FilePath $cfg.PythonExe `
    -ArgumentList @($cfg.GatewayScript) `
    -WorkingDirectory $cfg.BaseDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput $cfg.GatewayLog `
    -RedirectStandardError $cfg.GatewayErrLog `
    -PassThru
  $gatewayProc.Id | Set-Content -LiteralPath $cfg.GatewayPidFile -Encoding Ascii
}

for ($i = 0; $i -lt 30; $i++) {
  if (Test-LocalCloud -Url $localUrl) {
    break
  }
  Start-Sleep -Seconds 1
}

if (-not (Test-LocalCloud -Url $localUrl)) {
  throw 'Gateway nao iniciou corretamente.'
}

$cloudflaredPid = Read-PidFile -Path $cfg.CloudflaredPidFile
if (-not $cloudflaredPid -or -not (Test-ProcessAlive -ProcessId $cloudflaredPid)) {
  $existingTunnel = Get-ProcessByCommandHint -ProcessName 'cloudflared.exe' -CommandHint "http://127.0.0.1:$($cfg.PublicPort)"
  if ($existingTunnel) {
    foreach ($proc in $existingTunnel) {
      Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }

  foreach ($path in @($cfg.CloudflaredStdOutLog, $cfg.CloudflaredStdErrLog, $cfg.CloudflaredPidFile)) {
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
  }

  $cloudflaredProc = Start-Process -FilePath $cfg.CloudflaredExe `
    -ArgumentList @(
      'tunnel'
      '--url'
      $localUrl
      '--no-autoupdate'
      '--metrics'
      "127.0.0.1:$($cfg.CloudflaredMetricsPort)"
      '--loglevel'
      'info'
    ) `
    -WorkingDirectory (Split-Path -Path $cfg.CloudflaredExe -Parent) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $cfg.CloudflaredStdOutLog `
    -RedirectStandardError $cfg.CloudflaredStdErrLog `
    -PassThru
  $cloudflaredProc.Id | Set-Content -LiteralPath $cfg.CloudflaredPidFile -Encoding Ascii
}

$publicUrl = $null
for ($i = 0; $i -lt 45; $i++) {
  $publicUrl = Get-QuickTunnelUrl
  if ($publicUrl) {
    break
  }
  Start-Sleep -Seconds 2
}

Write-ConnectionInfo -PublicUrl $publicUrl

$monitorPid = Read-PidFile -Path $cfg.PublicUrlMonitorPidFile
if (-not $monitorPid -or -not (Test-ProcessAlive -ProcessId $monitorPid)) {
  foreach ($proc in (Get-ProcessByCommandHint -ProcessName 'powershell.exe' -CommandHint $cfg.PublicUrlMonitorScript)) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
  }

  $monitorProc = Start-Process -FilePath $cfg.PowerShellExe `
    -ArgumentList @('-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-File', $cfg.PublicUrlMonitorScript) `
    -WorkingDirectory $cfg.BaseDir `
    -WindowStyle Hidden `
    -PassThru
  $monitorProc.Id | Set-Content -LiteralPath $cfg.PublicUrlMonitorPidFile -Encoding Ascii
}

Write-Host "Local URL: $localUrl"
if ($publicUrl) {
  Write-Host "Public URL: $publicUrl"
  Write-Host "Upload URL: $publicUrl/upload-progress"
} else {
  Write-Host 'Public URL: indisponivel no momento'
}
