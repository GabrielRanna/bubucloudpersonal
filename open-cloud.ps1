$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cloud-common.ps1"

$cfg = Get-PersonalCloudConfig
$publicUrl = Get-QuickTunnelUrl

if ($publicUrl) {
  Open-CloudUrl -Url "$publicUrl/upload-progress"
} else {
  Open-CloudUrl -Url "http://127.0.0.1:$($cfg.PublicPort)/upload-progress"
}
