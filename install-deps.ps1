[CmdletBinding()]
param(
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cloud-common.ps1"

$cfg = Get-PersonalCloudConfig

function Get-FileBrowserAssetName {
  switch ($cfg.Platform) {
    'windows' { return 'windows-amd64-filebrowser.zip' }
    'macos' {
      if ($cfg.Arch -eq 'arm64') {
        return 'darwin-arm64-filebrowser.tar.gz'
      }
      return 'darwin-amd64-filebrowser.tar.gz'
    }
    default {
      throw "Plataforma nao suportada para download automatico do File Browser: $($cfg.Platform)"
    }
  }
}

function Get-CloudflaredAssetName {
  switch ($cfg.Platform) {
    'windows' { return 'cloudflared-windows-amd64.exe' }
    'macos' {
      if ($cfg.Arch -eq 'arm64') {
        return 'cloudflared-darwin-arm64.tgz'
      }
      return 'cloudflared-darwin-amd64.tgz'
    }
    default {
      throw "Plataforma nao suportada para download automatico do cloudflared: $($cfg.Platform)"
    }
  }
}

function Remove-PathIfExists {
  param(
    [string]$Path
  )

  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Download-File {
  param(
    [string]$Url,
    [string]$Destination
  )

  Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Install-FileBrowser {
  if (-not $Force -and (Test-Path -LiteralPath $cfg.FileBrowserExe)) {
    Write-Host "File Browser ja esta presente em $($cfg.FileBrowserExe)"
    Ensure-ExecutableBit -Path $cfg.FileBrowserExe
    return
  }

  $asset = Get-FileBrowserAssetName
  $url = "https://github.com/filebrowser/filebrowser/releases/latest/download/$asset"
  $archivePath = Join-Path $cfg.BinDir $asset
  $targetDir = Join-Path $cfg.BinDir 'filebrowser'
  $extractDir = Join-Path $cfg.BinDir 'filebrowser-extract'

  Remove-PathIfExists -Path $archivePath
  Remove-PathIfExists -Path $extractDir
  Remove-PathIfExists -Path $targetDir

  Write-Host "Baixando File Browser: $asset"
  Download-File -Url $url -Destination $archivePath

  if ($cfg.IsWindows) {
    Expand-Archive -LiteralPath $archivePath -DestinationPath $targetDir -Force
  } else {
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    & tar -xzf $archivePath -C $extractDir
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Move-Item -LiteralPath (Join-Path $extractDir 'filebrowser') -Destination (Join-Path $targetDir 'filebrowser') -Force
  }

  Ensure-ExecutableBit -Path $cfg.FileBrowserExe
  Remove-PathIfExists -Path $archivePath
  Remove-PathIfExists -Path $extractDir
}

function Install-Cloudflared {
  if (-not $Force -and (Test-Path -LiteralPath $cfg.CloudflaredExe)) {
    Write-Host "cloudflared ja esta presente em $($cfg.CloudflaredExe)"
    Ensure-ExecutableBit -Path $cfg.CloudflaredExe
    return
  }

  $asset = Get-CloudflaredAssetName
  $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/$asset"
  $archivePath = Join-Path $cfg.BinDir $asset
  $extractDir = Join-Path $cfg.BinDir 'cloudflared-extract'

  Remove-PathIfExists -Path $archivePath
  Remove-PathIfExists -Path $extractDir
  Remove-PathIfExists -Path $cfg.CloudflaredExe

  Write-Host "Baixando cloudflared: $asset"
  Download-File -Url $url -Destination $archivePath

  if ($cfg.IsWindows) {
    Move-Item -LiteralPath $archivePath -Destination $cfg.CloudflaredExe -Force
  } else {
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    & tar -xzf $archivePath -C $extractDir
    Move-Item -LiteralPath (Join-Path $extractDir 'cloudflared') -Destination $cfg.CloudflaredExe -Force
    Remove-PathIfExists -Path $archivePath
    Remove-PathIfExists -Path $extractDir
  }

  Ensure-ExecutableBit -Path $cfg.CloudflaredExe
}

New-Item -ItemType Directory -Force -Path $cfg.BaseDir, $cfg.BinDir, $cfg.ConfigDir, $cfg.LogDir | Out-Null

Install-FileBrowser
Install-Cloudflared

Write-Host "Dependencias prontas para $($cfg.Platform) ($($cfg.Arch))."
Write-Host "File Browser: $($cfg.FileBrowserExe)"
Write-Host "cloudflared: $($cfg.CloudflaredExe)"
