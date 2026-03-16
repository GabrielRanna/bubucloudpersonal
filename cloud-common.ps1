$script:PersonalCloud = [ordered]@{
  BaseDir                = Join-Path $env:USERPROFILE 'PersonalCloud'
  BinDir                 = Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'bin'
  ConfigDir              = Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'config'
  LogDir                 = Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'logs'
  DataRoot               = 'D:\CloudDrive'
  PythonExe              = (Get-Command python).Source
  PowerShellExe          = (Get-Command powershell).Source
  GatewayScript          = Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'gateway.py'
  GatewayLog             = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'logs') 'gateway.log'
  GatewayErrLog          = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'logs') 'gateway.stderr.log'
  GatewayPidFile         = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'config') 'gateway.pid'
  PublicUrlMonitorScript = Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'public-url-monitor.ps1'
  PublicUrlMonitorPidFile = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'config') 'public-url-monitor.pid'
  FileBrowserExe         = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'bin') 'filebrowser\filebrowser.exe'
  FileBrowserDb          = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'config') 'filebrowser.db'
  FileBrowserStdOutLog   = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'logs') 'filebrowser.stdout.log'
  FileBrowserStdErrLog   = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'logs') 'filebrowser.stderr.log'
  FileBrowserPidFile     = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'config') 'filebrowser.pid'
  CloudflaredExe         = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'bin') 'cloudflared.exe'
  CloudflaredStdOutLog   = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'logs') 'cloudflared.stdout.log'
  CloudflaredStdErrLog   = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'logs') 'cloudflared.stderr.log'
  CloudflaredPidFile     = Join-Path (Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'config') 'cloudflared.pid'
  StatusFile             = Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'connection-info.txt'
  CredentialsFile        = Join-Path (Join-Path $env:USERPROFILE 'PersonalCloud') 'credentials.txt'
  DesktopInfoFile        = Join-Path ([Environment]::GetFolderPath('Desktop')) 'MINHA-NUVEM.txt'
  DesktopOpenScript      = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ABRIR-MINHA-NUVEM.cmd'
  WelcomeFile            = Join-Path 'D:\CloudDrive' '0-COMECE-AQUI.txt'
  Username               = 'cloud'
  PublicPort             = 8394
  FileBrowserPort        = 8396
  CloudflaredMetricsPort = 8395
}

function Get-PersonalCloudConfig {
  return $script:PersonalCloud
}

function Read-PidFile {
  param(
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    return [int](Get-Content -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1)
  } catch {
    return $null
  }
}

function Test-ProcessAlive {
  param(
    [int]$ProcessId
  )

  return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Get-ProcessByCommandHint {
  param(
    [string]$ProcessName,
    [string]$CommandHint
  )

  Get-CimInstance Win32_Process -Filter "Name='$ProcessName'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*$CommandHint*" }
}

function Test-LocalCloud {
  param(
    [string]$Url
  )

  try {
    Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Get-QuickTunnelUrl {
  $cfg = Get-PersonalCloudConfig
  $pattern = 'https://[a-z0-9-]+\.trycloudflare\.com'

  foreach ($path in @($cfg.CloudflaredStdOutLog, $cfg.CloudflaredStdErrLog)) {
    if (-not (Test-Path -LiteralPath $path)) {
      continue
    }

    $content = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) {
      continue
    }
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -gt 0) {
      return $matches[$matches.Count - 1].Value
    }
  }

  return $null
}

function Get-StoredPassword {
  $cfg = Get-PersonalCloudConfig
  if (-not (Test-Path -LiteralPath $cfg.CredentialsFile)) {
    return $null
  }

  $passwordLine = Get-Content -LiteralPath $cfg.CredentialsFile -ErrorAction SilentlyContinue |
    Where-Object { $_ -like 'Senha:*' } |
    Select-Object -First 1

  if (-not $passwordLine) {
    return $null
  }

  return ($passwordLine -replace '^Senha:\s*', '').Trim()
}

function Write-ConnectionInfo {
  param(
    [string]$PublicUrl
  )

  $cfg = Get-PersonalCloudConfig
  $password = Get-StoredPassword
  $uploadUrl = if ($PublicUrl) { "$PublicUrl/upload-progress" } else { "http://127.0.0.1:$($cfg.PublicPort)/upload-progress" }
  $lines = @(
    'Nuvem Pessoal'
    "Atualizado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ''
    "Pasta da nuvem: $($cfg.DataRoot)"
    "URL local: http://127.0.0.1:$($cfg.PublicPort)"
    ("URL publica: " + ($(if ($PublicUrl) { $PublicUrl } else { 'indisponivel no momento' })))
    "URL upload com progresso: $uploadUrl"
    ''
    "Usuario: $($cfg.Username)"
    ("Senha: " + ($(if ($password) { $password } else { 'veja credentials.txt' })))
    ''
    'Observacao: a URL publica pode mudar se o processo do tunnel reiniciar.'
    'Observacao: o PC precisa ficar ligado e com a sessao do usuario ativa.'
  )

  foreach ($path in @($cfg.StatusFile, $cfg.DesktopInfoFile, $cfg.WelcomeFile)) {
    Set-Content -LiteralPath $path -Value $lines -Encoding Ascii
  }
}
