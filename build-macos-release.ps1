$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$sourceDir = Join-Path $repoRoot 'macos-release'
$distRoot = Join-Path $repoRoot 'dist'
$distDir = Join-Path $distRoot 'BubuCloudPersonal-macos'

if (-not (Test-Path -LiteralPath $sourceDir)) {
  throw 'macos-release nao encontrado.'
}

if (Test-Path -LiteralPath $distDir) {
  Remove-Item -LiteralPath $distDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $distDir | Out-Null

Copy-Item -LiteralPath (Join-Path $repoRoot 'gateway.py') -Destination (Join-Path $distDir 'gateway.py')
Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination (Join-Path $distDir 'README-source.md')
Copy-Item -Path (Join-Path $sourceDir '*') -Destination $distDir -Recurse

Write-Host "Release macOS gerada em: $distDir"
Write-Host "Conteudo principal:"
Get-ChildItem -LiteralPath $distDir | Select-Object Name, Length
