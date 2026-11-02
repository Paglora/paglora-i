# Build a branded Wails installer containing an existing Tauri-generated NSIS executable.
# Tauri remains the owner of app installation, Windows registry, uninstaller
# and signed updater artifacts.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$PagloraRepository,
  [switch]$AllowUnsignedDevelopment
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo = (Resolve-Path $PagloraRepository).Path
$tauri = Join-Path $repo 'apps\desktop\src-tauri\tauri.conf.json'
if (!(Test-Path -LiteralPath $tauri)) { throw "Paglora Tauri config not found: $tauri" }
$config = Get-Content -LiteralPath $tauri -Raw | ConvertFrom-Json
$version = [string]$config.version
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid Paglora version: $version" }
if (!$config.bundle.createUpdaterArtifacts -or @($config.bundle.targets) -notcontains 'nsis') {
  throw 'Tauri must generate NSIS installers and signed updater artifacts'
}
if ($config.bundle.windows.nsis.installMode -and $config.bundle.windows.nsis.installMode -ne 'currentUser') {
  throw 'Installer prototype supports the default currentUser NSIS installation only'
}
$filename = ('Paglora_' + $version + '_x64-setup.exe')
$bundle = Join-Path $repo "apps\desktop\src-tauri\target\release\bundle\nsis\$filename"
if (!(Test-Path -LiteralPath $bundle -PathType Leaf)) {
  throw "Expected real Tauri NSIS setup file: $bundle. Build Paglora with bun tauri build first."
}
$signature = Get-AuthenticodeSignature -LiteralPath $bundle
if ($signature.Status -ne 'Valid' -and !$AllowUnsignedDevelopment) {
  throw "NSIS is not Authenticode-signed. Use -AllowUnsignedDevelopment ONLY for local test builds."
}
$payloadDir = Join-Path $root 'payload'
Get-ChildItem -LiteralPath $payloadDir -Filter '*.exe' -File | Remove-Item -Force
Copy-Item -LiteralPath $bundle -Destination (Join-Path $payloadDir $filename)
$copied = Join-Path $payloadDir $filename
$info = Get-Item -LiteralPath $copied
$hash = (Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash.ToLowerInvariant()
[ordered]@{
  version = $version
  fileName = $filename
  sha256 = $hash
  size = $info.Length
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $payloadDir 'manifest.json') -Encoding utf8
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
  wails build -clean
  if ($LASTEXITCODE -ne 0) { throw 'Wails Windows build failed' }
  Write-Host 'Created branded installer: build\bin\Paglora-Installer.exe'
  Write-Host "Embedded official Tauri NSIS: $filename"
  if ($AllowUnsignedDevelopment) {
    Write-Warning 'Development build: never distribute an unsigned test installer as stable.'
  }
} finally { Pop-Location }
