$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\cloud-common.ps1"

$cfg = Get-PersonalCloudConfig
$script:LastPublicUrl = '__unset__'

$PID | Set-Content -LiteralPath $cfg.PublicUrlMonitorPidFile -Encoding Ascii

function Test-CloudRunning {
  $gatewayPid = Read-PidFile -Path $cfg.GatewayPidFile
  $cloudflaredPid = Read-PidFile -Path $cfg.CloudflaredPidFile
  $fileBrowserPid = Read-PidFile -Path $cfg.FileBrowserPidFile

  return (
    (($gatewayPid -is [int]) -and (Test-ProcessAlive -ProcessId $gatewayPid)) -or
    (($cloudflaredPid -is [int]) -and (Test-ProcessAlive -ProcessId $cloudflaredPid)) -or
    (($fileBrowserPid -is [int]) -and (Test-ProcessAlive -ProcessId $fileBrowserPid))
  )
}

function Get-UploadUrl {
  param(
    [string]$PublicUrl
  )

  if ($PublicUrl) {
    return "$PublicUrl/upload-progress"
  }

  return "http://127.0.0.1:$($cfg.PublicPort)/upload-progress"
}

function Cleanup-Monitor {
  if (Test-Path -LiteralPath $cfg.PublicUrlMonitorPidFile) {
    Remove-Item -LiteralPath $cfg.PublicUrlMonitorPidFile -Force -ErrorAction SilentlyContinue
  }
}

if (-not $cfg.IsWindows) {
  try {
    while (Test-CloudRunning) {
      $publicUrl = Get-QuickTunnelUrl
      $uploadUrl = Get-UploadUrl -PublicUrl $publicUrl
      if ($publicUrl -ne $script:LastPublicUrl) {
        Write-ConnectionInfo -PublicUrl $publicUrl
        if ($publicUrl) {
          Write-Host "URL publica: $publicUrl"
          Write-Host "Upload: $uploadUrl"
        } else {
          Write-Host 'Tunnel ativo, aguardando endereco publico...'
        }
        $script:LastPublicUrl = $publicUrl
      }
      Start-Sleep -Seconds 3
    }
  } finally {
    Cleanup-Monitor
  }
  return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Nuvem Pessoal'
$form.StartPosition = 'Manual'
$form.Size = New-Object System.Drawing.Size(540, 220)
$form.MinimumSize = New-Object System.Drawing.Size(540, 220)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 241, 233)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Endereco publico da nuvem'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 16)
$form.Controls.Add($title)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Aguardando tunnel...'
$status.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)
$status.AutoSize = $true
$status.ForeColor = [System.Drawing.Color]::FromArgb(36, 89, 52)
$status.Location = New-Object System.Drawing.Point(20, 48)
$form.Controls.Add($status)

$publicLabel = New-Object System.Windows.Forms.Label
$publicLabel.Text = 'URL publica'
$publicLabel.AutoSize = $true
$publicLabel.Location = New-Object System.Drawing.Point(20, 78)
$form.Controls.Add($publicLabel)

$publicBox = New-Object System.Windows.Forms.TextBox
$publicBox.ReadOnly = $true
$publicBox.Location = New-Object System.Drawing.Point(20, 98)
$publicBox.Size = New-Object System.Drawing.Size(490, 24)
$publicBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($publicBox)

$uploadLabel = New-Object System.Windows.Forms.Label
$uploadLabel.Text = 'URL upload com progresso'
$uploadLabel.AutoSize = $true
$uploadLabel.Location = New-Object System.Drawing.Point(20, 130)
$form.Controls.Add($uploadLabel)

$uploadBox = New-Object System.Windows.Forms.TextBox
$uploadBox.ReadOnly = $true
$uploadBox.Location = New-Object System.Drawing.Point(20, 150)
$uploadBox.Size = New-Object System.Drawing.Size(490, 24)
$uploadBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($uploadBox)

$copyPublic = New-Object System.Windows.Forms.Button
$copyPublic.Text = 'Copiar publica'
$copyPublic.Size = New-Object System.Drawing.Size(108, 28)
$copyPublic.Location = New-Object System.Drawing.Point(20, 182)
$form.Controls.Add($copyPublic)

$copyUpload = New-Object System.Windows.Forms.Button
$copyUpload.Text = 'Copiar upload'
$copyUpload.Size = New-Object System.Drawing.Size(108, 28)
$copyUpload.Location = New-Object System.Drawing.Point(136, 182)
$form.Controls.Add($copyUpload)

$openUrl = New-Object System.Windows.Forms.Button
$openUrl.Text = 'Abrir'
$openUrl.Size = New-Object System.Drawing.Size(88, 28)
$openUrl.Location = New-Object System.Drawing.Point(252, 182)
$form.Controls.Add($openUrl)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Fechar'
$closeButton.Size = New-Object System.Drawing.Size(88, 28)
$closeButton.Location = New-Object System.Drawing.Point(422, 182)
$form.Controls.Add($closeButton)

function Update-Monitor {
  if (-not (Test-CloudRunning)) {
    $form.Close()
    return
  }

  $publicUrl = Get-QuickTunnelUrl
  $uploadUrl = Get-UploadUrl -PublicUrl $publicUrl

  if ($publicUrl) {
    $status.Text = 'Nuvem rodando. A janela atualiza a URL automaticamente.'
    $publicBox.Text = $publicUrl
  } else {
    $status.Text = 'Tunnel ativo, aguardando endereco publico...'
    $publicBox.Text = 'indisponivel no momento'
  }

  $uploadBox.Text = $uploadUrl
  $copyPublic.Enabled = [bool]$publicUrl
  $openUrl.Text = if ($publicUrl) { 'Abrir publica' } else { 'Abrir local' }

  if ($publicUrl -ne $script:LastPublicUrl) {
    Write-ConnectionInfo -PublicUrl $publicUrl
    $script:LastPublicUrl = $publicUrl
  }
}

$copyPublic.Add_Click({
  if ($publicBox.Text -and $publicBox.Text -ne 'indisponivel no momento') {
    [System.Windows.Forms.Clipboard]::SetText($publicBox.Text)
  }
})

$copyUpload.Add_Click({
  if ($uploadBox.Text) {
    [System.Windows.Forms.Clipboard]::SetText($uploadBox.Text)
  }
})

$openUrl.Add_Click({
  $target = if ($publicBox.Text -and $publicBox.Text -ne 'indisponivel no momento') {
    $uploadBox.Text
  } else {
    "http://127.0.0.1:$($cfg.PublicPort)/upload-progress"
  }

  Open-CloudUrl -Url $target
})

$closeButton.Add_Click({
  $form.Close()
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({
  Update-Monitor
})

$form.Add_Shown({
  $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $left = [int]($area.Right - $form.Width - 18)
  $top = [int]($area.Bottom - $form.Height - 18)
  $form.Location = New-Object System.Drawing.Point -ArgumentList @($left, $top)
  Update-Monitor
  $timer.Start()
})

$form.Add_FormClosed({
  $timer.Stop()
  Cleanup-Monitor
})

[System.Windows.Forms.Application]::Run($form)
