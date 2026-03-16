$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cloud-common.ps1"

$cfg = Get-PersonalCloudConfig
$localUrl = "http://127.0.0.1:$($cfg.PublicPort)"
$internalUrl = "http://127.0.0.1:$($cfg.FileBrowserPort)"
$publicUrl = Get-QuickTunnelUrl
$monitorPid = Read-PidFile -Path $cfg.PublicUrlMonitorPidFile
$gatewayPid = Read-PidFile -Path $cfg.GatewayPidFile
$fileBrowserPid = Read-PidFile -Path $cfg.FileBrowserPidFile
$cloudflaredPid = Read-PidFile -Path $cfg.CloudflaredPidFile

Write-ConnectionInfo -PublicUrl $publicUrl

[pscustomobject]@{
  GatewayOnline     = Test-LocalCloud -Url $localUrl
  FileBrowserOnline = Test-LocalCloud -Url $internalUrl
  MonitorPid        = $monitorPid
  GatewayPid        = $gatewayPid
  FileBrowserPid    = $fileBrowserPid
  CloudflaredPid    = $cloudflaredPid
  LocalUrl          = $localUrl
  PublicUrl         = $(if ($publicUrl) { $publicUrl } else { 'indisponivel' })
  UploadUrl         = $(if ($publicUrl) { "$publicUrl/upload-progress" } else { "$localUrl/upload-progress" })
  DataRoot          = $cfg.DataRoot
  InfoFile          = $cfg.DesktopInfoFile
} | Format-List
