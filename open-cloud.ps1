$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cloud-common.ps1"

$cfg = Get-PersonalCloudConfig
$publicUrl = Get-QuickTunnelUrl

if ($publicUrl) {
  Start-Process "$publicUrl/upload-progress"
} else {
  Start-Process "http://127.0.0.1:$($cfg.PublicPort)/upload-progress"
}
