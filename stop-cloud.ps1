$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cloud-common.ps1"

$cfg = Get-PersonalCloudConfig

$targets = @(
  @{
    PidFile = $cfg.PublicUrlMonitorPidFile
    Name = $cfg.PowerShellProcessName
    Hint = $cfg.PublicUrlMonitorScript
  }
  @{
    PidFile = $cfg.CloudflaredPidFile
    Name = $cfg.CloudflaredProcessName
    Hint = "http://127.0.0.1:$($cfg.PublicPort)"
  }
  @{
    PidFile = $cfg.GatewayPidFile
    Name = $cfg.PythonProcessName
    Hint = $cfg.GatewayScript
  }
  @{
    PidFile = $cfg.FileBrowserPidFile
    Name = $cfg.FileBrowserProcessName
    Hint = $cfg.FileBrowserDb
  }
)

foreach ($target in $targets) {
  $storedPid = Read-PidFile -Path $target.PidFile
  if ($storedPid -and (Test-ProcessAlive -ProcessId $storedPid)) {
    Stop-Process -Id $storedPid -Force -ErrorAction SilentlyContinue
  }

  foreach ($proc in (Get-ProcessByCommandHint -ProcessName $target.Name -CommandHint $target.Hint)) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
  }

  if (Test-Path -LiteralPath $target.PidFile) {
    Remove-Item -LiteralPath $target.PidFile -Force -ErrorAction SilentlyContinue
  }
}

Write-ConnectionInfo -PublicUrl $null
Write-Host 'Nuvem pessoal parada.'
