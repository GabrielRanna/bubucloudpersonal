$script:PlatformInfo = $null
$script:PersonalCloud = $null

function Test-IsWindowsPlatform {
  $platformVar = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
  if ($platformVar) {
    return [bool]$platformVar.Value
  }

  return $env:OS -eq 'Windows_NT'
}

function Test-IsMacOSPlatform {
  $platformVar = Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue
  if ($platformVar) {
    return [bool]$platformVar.Value
  }

  try {
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
  } catch {
    return $false
  }
}

function Get-HomeDirectory {
  if ($HOME) {
    return $HOME
  }

  $userProfile = [Environment]::GetFolderPath('UserProfile')
  if ($userProfile) {
    return $userProfile
  }

  return [Environment]::GetFolderPath('Personal')
}

function Resolve-CommandPath {
  param(
    [string[]]$Names
  )

  foreach ($name in $Names) {
    $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
      continue
    }

    foreach ($property in @('Source', 'Path', 'Definition')) {
      if ($command.PSObject.Properties.Name -contains $property) {
        $value = $command.$property
        if ($value) {
          return $value
        }
      }
    }
  }

  return $null
}

function Get-PlatformInfo {
  if ($script:PlatformInfo) {
    return $script:PlatformInfo
  }

  $isWindows = Test-IsWindowsPlatform
  $isMacOS = Test-IsMacOSPlatform
  $platform = if ($isWindows) {
    'windows'
  } elseif ($isMacOS) {
    'macos'
  } else {
    'other'
  }

  $arch = 'amd64'
  try {
    switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()) {
      'arm64' { $arch = 'arm64' }
      'x64' { $arch = 'amd64' }
      default { $arch = 'amd64' }
    }
  } catch {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
      $arch = 'arm64'
    }
  }

  $script:PlatformInfo = [ordered]@{
    IsWindows = $isWindows
    IsMacOS   = $isMacOS
    Platform  = $platform
    Arch      = $arch
    HomeDir   = Get-HomeDirectory
  }

  return $script:PlatformInfo
}

function Get-StoredSetting {
  param(
    [string]$Path,
    [string]$Key
  )

  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $prefix = "${Key}:"
  $line = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
    Where-Object { $_ -like "$prefix*" } |
    Select-Object -First 1

  if (-not $line) {
    return $null
  }

  return ($line -replace ('^' + [regex]::Escape($prefix)), '').Trim()
}

function Get-PersistedDataRoot {
  param(
    [string]$CredentialsPath,
    [string]$DefaultValue
  )

  $stored = Get-StoredSetting -Path $CredentialsPath -Key 'Pasta da nuvem'
  if ($stored) {
    return $stored.Trim()
  }

  return $DefaultValue
}

function New-InternalPassword {
  return "Pc!$([guid]::NewGuid().ToString('N'))$([guid]::NewGuid().ToString('N').Substring(0, 8))Aa1"
}

function New-PublicPassword {
  return '1987'
}

function Get-DesktopPath {
  param(
    [hashtable]$PlatformInfo,
    [string]$BaseDir
  )

  $desktop = $null
  if ($PlatformInfo.IsWindows) {
    $desktop = [Environment]::GetFolderPath('Desktop')
  } else {
    $desktop = Join-Path $PlatformInfo.HomeDir 'Desktop'
  }

  if ($desktop -and (Test-Path -LiteralPath $desktop)) {
    return $desktop
  }

  return $BaseDir
}

function Get-PersonalCloudConfig {
  if ($script:PersonalCloud) {
    return $script:PersonalCloud
  }

  $platformInfo = Get-PlatformInfo
  $baseDir = $PSScriptRoot
  $binDir = Join-Path $baseDir 'bin'
  $configDir = Join-Path $baseDir 'config'
  $logDir = Join-Path $baseDir 'logs'
  $credentialsFile = Join-Path $baseDir 'credentials.txt'
  $desktopDir = Get-DesktopPath -PlatformInfo $platformInfo -BaseDir $baseDir

  $defaultDataRoot = if ($env:PERSONAL_CLOUD_DATA_ROOT) {
    $env:PERSONAL_CLOUD_DATA_ROOT
  } elseif ($platformInfo.IsWindows -and (Test-Path -LiteralPath 'D:\')) {
    'D:\CloudDrive'
  } else {
    Join-Path $platformInfo.HomeDir 'CloudDrive'
  }

  $dataRoot = Get-PersistedDataRoot -CredentialsPath $credentialsFile -DefaultValue $defaultDataRoot
  $pythonExe = Resolve-CommandPath -Names @('python', 'python3')
  $powerShellExe = Resolve-CommandPath -Names @('pwsh', 'powershell')

  $fileBrowserExe = if ($platformInfo.IsWindows) {
    Join-Path (Join-Path $binDir 'filebrowser') 'filebrowser.exe'
  } else {
    Join-Path (Join-Path $binDir 'filebrowser') 'filebrowser'
  }

  $cloudflaredExe = if ($platformInfo.IsWindows) {
    Join-Path $binDir 'cloudflared.exe'
  } else {
    Join-Path $binDir 'cloudflared'
  }

  $desktopOpenScript = if ($platformInfo.IsWindows) {
    Join-Path $desktopDir 'ABRIR-MINHA-NUVEM.cmd'
  } else {
    Join-Path $desktopDir 'ABRIR-MINHA-NUVEM.command'
  }

  $script:PersonalCloud = [ordered]@{
    Platform               = $platformInfo.Platform
    Arch                   = $platformInfo.Arch
    IsWindows              = $platformInfo.IsWindows
    IsMacOS                = $platformInfo.IsMacOS
    BaseDir                = $baseDir
    BinDir                 = $binDir
    ConfigDir              = $configDir
    LogDir                 = $logDir
    DataRoot               = $dataRoot
    PythonExe              = $pythonExe
    PowerShellExe          = $powerShellExe
    GatewayScript          = Join-Path $baseDir 'gateway.py'
    GatewayLog             = Join-Path $logDir 'gateway.log'
    GatewayErrLog          = Join-Path $logDir 'gateway.stderr.log'
    GatewayPidFile         = Join-Path $configDir 'gateway.pid'
    PublicUrlMonitorScript = Join-Path $baseDir 'public-url-monitor.ps1'
    PublicUrlMonitorPidFile = Join-Path $configDir 'public-url-monitor.pid'
    FileBrowserExe         = $fileBrowserExe
    FileBrowserDb          = Join-Path $configDir 'filebrowser.db'
    FileBrowserStdOutLog   = Join-Path $logDir 'filebrowser.stdout.log'
    FileBrowserStdErrLog   = Join-Path $logDir 'filebrowser.stderr.log'
    FileBrowserPidFile     = Join-Path $configDir 'filebrowser.pid'
    CloudflaredExe         = $cloudflaredExe
    CloudflaredStdOutLog   = Join-Path $logDir 'cloudflared.stdout.log'
    CloudflaredStdErrLog   = Join-Path $logDir 'cloudflared.stderr.log'
    CloudflaredPidFile     = Join-Path $configDir 'cloudflared.pid'
    StatusFile             = Join-Path $baseDir 'connection-info.txt'
    CredentialsFile        = $credentialsFile
    DesktopInfoFile        = Join-Path $desktopDir 'MINHA-NUVEM.txt'
    DesktopOpenScript      = $desktopOpenScript
    WelcomeFile            = Join-Path $dataRoot '0-COMECE-AQUI.txt'
    OpenCloudScript        = Join-Path $baseDir 'open-cloud.ps1'
    InstallDepsScript      = Join-Path $baseDir 'install-deps.ps1'
    Username               = 'cloud'
    PublicPort             = 8394
    FileBrowserPort        = 8396
    CloudflaredMetricsPort = 8395
    FileBrowserProcessName = Split-Path -Path $fileBrowserExe -Leaf
    CloudflaredProcessName = Split-Path -Path $cloudflaredExe -Leaf
    PowerShellProcessName  = if ($powerShellExe) { Split-Path -Path $powerShellExe -Leaf } else { 'powershell' }
    PythonProcessName      = if ($pythonExe) { Split-Path -Path $pythonExe -Leaf } else { 'python' }
    SupportsMonitorUi      = $platformInfo.IsWindows
  }

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

  $cfg = Get-PersonalCloudConfig
  if ($cfg.IsWindows -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    return Get-CimInstance Win32_Process -Filter "Name='$ProcessName'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -like "*$CommandHint*" }
  }

  $psBinary = if (Test-Path -LiteralPath '/bin/ps') { '/bin/ps' } else { 'ps' }
  $lines = & $psBinary -ax -o pid= -o command= 2>$null
  if (-not $lines) {
    return @()
  }

  $matches = @()
  foreach ($line in $lines) {
    $entry = [string]$line
    $match = [regex]::Match($entry, '^\s*(\d+)\s+(.*)$')
    if (-not $match.Success) {
      continue
    }

    $processId = [int]$match.Groups[1].Value
    $commandLine = $match.Groups[2].Value
    if ($commandLine -notlike "*$ProcessName*" -or $commandLine -notlike "*$CommandHint*") {
      continue
    }

    $matches += [pscustomobject]@{
      ProcessId   = $processId
      CommandLine = $commandLine
    }
  }

  return $matches
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
  $password = Get-StoredSetting -Path $cfg.CredentialsFile -Key 'Senha'
  if ($password) {
    return $password.Trim()
  }

  return $null
}

function Ensure-ExecutableBit {
  param(
    [string]$Path
  )

  $cfg = Get-PersonalCloudConfig
  if ($cfg.IsWindows -or -not (Test-Path -LiteralPath $Path)) {
    return
  }

  & chmod +x $Path 2>$null
}

function Write-DesktopOpenScript {
  $cfg = Get-PersonalCloudConfig

  if ($cfg.IsWindows) {
    $contents = @(
      '@echo off'
      "`"$($cfg.PowerShellExe)`" -NoProfile -ExecutionPolicy Bypass -File `"$($cfg.OpenCloudScript)`""
    )
  } else {
    $contents = @(
      '#!/bin/bash'
      "`"$($cfg.PowerShellExe)`" -NoProfile -File `"$($cfg.OpenCloudScript)`""
    )
  }

  Set-Content -LiteralPath $cfg.DesktopOpenScript -Value $contents -Encoding Ascii
  Ensure-ExecutableBit -Path $cfg.DesktopOpenScript
}

function Ensure-PersonalCloudCredentials {
  $cfg = Get-PersonalCloudConfig
  $publicPassword = Get-StoredSetting -Path $cfg.CredentialsFile -Key 'Senha'
  if (-not $publicPassword) {
    $publicPassword = New-PublicPassword
  }

  $internalPassword = Get-StoredSetting -Path $cfg.CredentialsFile -Key 'SenhaInternaFileBrowser'
  if (-not $internalPassword) {
    $internalPassword = New-InternalPassword
  }

  $lines = @(
    'Nuvem Pessoal'
    "Usuario: $($cfg.Username)"
    "Senha: $publicPassword"
    "SenhaInternaFileBrowser: $internalPassword"
    "Pasta da nuvem: $($cfg.DataRoot)"
    "Arquivo de status: $($cfg.DesktopInfoFile)"
  )

  Set-Content -LiteralPath $cfg.CredentialsFile -Value $lines -Encoding Ascii
}

function Ensure-PersonalCloudDependencies {
  $cfg = Get-PersonalCloudConfig
  if ((Test-Path -LiteralPath $cfg.FileBrowserExe) -and (Test-Path -LiteralPath $cfg.CloudflaredExe)) {
    Ensure-ExecutableBit -Path $cfg.FileBrowserExe
    Ensure-ExecutableBit -Path $cfg.CloudflaredExe
    return
  }

  if (-not (Test-Path -LiteralPath $cfg.InstallDepsScript)) {
    throw 'install-deps.ps1 nao encontrado para baixar as dependencias da stack.'
  }

  & $cfg.PowerShellExe -NoProfile -File $cfg.InstallDepsScript

  if (-not (Test-Path -LiteralPath $cfg.FileBrowserExe) -or -not (Test-Path -LiteralPath $cfg.CloudflaredExe)) {
    throw 'As dependencias da nuvem nao foram instaladas corretamente.'
  }

  Ensure-ExecutableBit -Path $cfg.FileBrowserExe
  Ensure-ExecutableBit -Path $cfg.CloudflaredExe
}

function Invoke-FileBrowserCli {
  param(
    [string[]]$Arguments
  )

  $cfg = Get-PersonalCloudConfig
  & $cfg.FileBrowserExe @Arguments | Out-Null
  return $LASTEXITCODE
}

function Test-FileBrowserServerRunning {
  $cfg = Get-PersonalCloudConfig
  $storedPid = Read-PidFile -Path $cfg.FileBrowserPidFile
  if ($storedPid -and (Test-ProcessAlive -ProcessId $storedPid)) {
    return $true
  }

  return (@(Get-ProcessByCommandHint -ProcessName $cfg.FileBrowserProcessName -CommandHint $cfg.FileBrowserDb)).Count -gt 0
}

function Ensure-PersonalCloudDatabase {
  $cfg = Get-PersonalCloudConfig
  $internalPassword = Get-StoredSetting -Path $cfg.CredentialsFile -Key 'SenhaInternaFileBrowser'
  if (-not $internalPassword) {
    throw 'SenhaInternaFileBrowser nao encontrada em credentials.txt.'
  }

  if (-not (Test-Path -LiteralPath $cfg.FileBrowserDb)) {
    $exitCode = Invoke-FileBrowserCli -Arguments @(
      'config', 'init',
      '-d', $cfg.FileBrowserDb,
      '-r', $cfg.DataRoot,
      '-a', '127.0.0.1',
      '-p', "$($cfg.FileBrowserPort)",
      '--branding.name', 'Bubu Drive',
      '--branding.disableExternal',
      '--locale', 'pt-br',
      '--signup'
    )
    if ($exitCode -ne 0) {
      throw 'Nao foi possivel inicializar o banco do File Browser.'
    }

    $exitCode = Invoke-FileBrowserCli -Arguments @(
      'users', 'add', $cfg.Username, $internalPassword,
      '--perm.admin',
      '--locale', 'pt-br',
      '--scope', '/',
      '-d', $cfg.FileBrowserDb
    )
    if ($exitCode -ne 0) {
      throw 'Nao foi possivel criar o usuario administrador inicial.'
    }
    return
  }

  $exitCode = Invoke-FileBrowserCli -Arguments @(
    'config', 'set',
    '-d', $cfg.FileBrowserDb,
    '-r', $cfg.DataRoot,
    '-a', '127.0.0.1',
    '-p', "$($cfg.FileBrowserPort)",
    '--branding.name', 'Bubu Drive',
    '--branding.disableExternal',
    '--locale', 'pt-br',
    '--signup'
  )
  if ($exitCode -ne 0) {
    throw 'Nao foi possivel atualizar a configuracao do File Browser.'
  }

  $exitCode = Invoke-FileBrowserCli -Arguments @(
    'users', 'update', $cfg.Username,
    '-p', $internalPassword,
    '--locale', 'pt-br',
    '--scope', '/',
    '--perm.admin',
    '-d', $cfg.FileBrowserDb
  )

  if ($exitCode -eq 0) {
    return
  }

  $exitCode = Invoke-FileBrowserCli -Arguments @(
    'users', 'add', $cfg.Username, $internalPassword,
    '--perm.admin',
    '--locale', 'pt-br',
    '--scope', '/',
    '-d', $cfg.FileBrowserDb
  )
  if ($exitCode -ne 0) {
    throw 'Nao foi possivel garantir o usuario administrador no File Browser.'
  }
}

function Ensure-PersonalCloudBootstrap {
  $cfg = Get-PersonalCloudConfig
  if (-not $cfg.PythonExe) {
    throw 'Python nao encontrado. Instale python/python3 antes de subir a nuvem.'
  }
  if (-not $cfg.PowerShellExe) {
    throw 'PowerShell nao encontrado. Instale pwsh antes de subir a nuvem.'
  }

  New-Item -ItemType Directory -Force -Path $cfg.BaseDir, $cfg.ConfigDir, $cfg.LogDir, $cfg.DataRoot | Out-Null
  Ensure-PersonalCloudCredentials
  Ensure-PersonalCloudDependencies
  if (-not (Test-FileBrowserServerRunning)) {
    Ensure-PersonalCloudDatabase
  }
  Write-DesktopOpenScript
}

function Open-CloudUrl {
  param(
    [string]$Url
  )

  $cfg = Get-PersonalCloudConfig
  if ($cfg.IsMacOS) {
    & open $Url
    return
  }

  Start-Process $Url
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
    "Plataforma: $($cfg.Platform)"
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
    $parent = Split-Path -Path $path -Parent
    if ($parent) {
      New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding Ascii
  }

  Write-DesktopOpenScript
}
