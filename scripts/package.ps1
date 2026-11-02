# Package an existing Paglora Tauri NSIS build inside the Wails installer.
# Never use this wrapper as a substitute for Tauri release signing.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$PagloraRepository,
  [switch]$AllowUnsignedDevelopment
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo = (Resolve-Path -LiteralPath $PagloraRepository).Path
$tauri = Join-Path $repo 'apps\desktop\src-tauri\tauri.conf.json'
if (!(Test-Path -LiteralPath $tauri -PathType Leaf)) { throw "Paglora Tauri config not found: $tauri" }
$config = Get-Content -LiteralPath $tauri -Raw | ConvertFrom-Json
$version = [string]$config.version
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid Paglora version: $version" }
if (!$config.bundle.createUpdaterArtifacts -or @($config.bundle.targets) -notcontains 'nsis') {
  throw 'Paglora must retain Tauri NSIS and createUpdaterArtifacts: true'
}
if ($null -ne $config.bundle.windows -and $null -ne $config.bundle.windows.nsis -and
    $config.bundle.windows.nsis.installMode -and $config.bundle.windows.nsis.installMode -ne 'currentUser') {
  throw 'The Wails wrapper supports only Tauri currentUser NSIS installation.'
}
$filename = ('Paglora_' + $version + '_x64-setup.exe')
$nsisDir = Join-Path $repo 'apps\desktop\src-tauri\target\release\bundle\nsis'
$bundle = Join-Path $nsisDir $filename
if (!(Test-Path -LiteralPath $bundle -PathType Leaf)) {
  throw "Tauri NSIS setup was not found: $bundle. Build Paglora's NSIS bundle first."
}
$signature = Get-AuthenticodeSignature -LiteralPath $bundle
if ($signature.Status -ne 'Valid' -and !$AllowUnsignedDevelopment) {
  throw "Tauri NSIS must have valid Windows Authenticode signature. For local CI tests only use -AllowUnsignedDevelopment."
}
if (!$AllowUnsignedDevelopment) {
  $updaterSignature = "$bundle.sig"
  if (!(Test-Path -LiteralPath $updaterSignature -PathType Leaf) -or
      (Get-Item -LiteralPath $updaterSignature).Length -lt 50) {
    throw "The signed Tauri NSIS updater artifact is missing: $updaterSignature"
  }
}
if ($AllowUnsignedDevelopment) {
  Write-Warning 'DEVELOPMENT ONLY: unsigned setup. Do not distribute this package or treat it as proof that updating works.'
}
$payloadDir = Join-Path $root 'payload'
New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null
Get-ChildItem -LiteralPath $payloadDir -Filter '*.exe' -File | Remove-Item -Force
Copy-Item -LiteralPath $bundle -Destination (Join-Path $payloadDir $filename) -ErrorAction Stop
$copied = Join-Path $payloadDir $filename
$size = (Get-Item -LiteralPath $copied).Length
$hash = (Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{version=$version;fileName=$filename;sha256=$hash;size=$size} | ConvertTo-Json
# Windows PowerShell 5's UTF8 encoding writes a BOM, breaking Go json.Decoder.
[System.IO.File]::WriteAllText((Join-Path $payloadDir 'manifest.json'), $manifest,
  [System.Text.UTF8Encoding]::new($false))
Push-Location $root
try {
  Push-Location (Join-Path $root 'frontend')
  try {
    bun install
    if ($LASTEXITCODE -ne 0) { throw 'Bun install failed' }
    bun run check
    if ($LASTEXITCODE -ne 0) { throw 'Svelte typecheck failed' }
    bun run build
    if ($LASTEXITCODE -ne 0) { throw 'Svelte build failed' }
  } finally { Pop-Location }
  go test ./internal/installer/...
  if ($LASTEXITCODE -ne 0) { throw 'Go installer tests failed' }
  wails build -clean -webview2 embed
  if ($LASTEXITCODE -ne 0) { throw 'Wails build failed' }
  $result = Join-Path $root 'build\bin\Paglora-Installer.exe'
  if (!(Test-Path -LiteralPath $result -PathType Leaf)) {
    throw "Wails completed but output was not found: $result"
  }
  Write-Host "Branded Wails installer created: $result"
  Write-Host "Embedded Tauri NSIS: $filename ($size bytes, SHA-256 $hash)"
} finally { Pop-Location }
