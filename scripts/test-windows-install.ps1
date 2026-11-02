# Verify the actual Tauri installer registered with Windows, then remove it.
# Run only on an ephemeral GitHub Windows runner after integration install.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:PAGLORA_EPHEMERAL_WINDOWS_CI -ne 'yes') {
  throw 'Refusing Windows installation/uninstallation checks outside explicitly opted-in CI.'
}
$uninstallRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
function Get-PagloraEntry {
  @(Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction SilentlyContinue | ForEach-Object {
    Get-ItemProperty -LiteralPath $_.PSPath
  } | Where-Object {
    $display = $_.PSObject.Properties['DisplayName']
    $null -ne $display -and $display.Value -eq 'Paglora'
  })
}
$entries = @(Get-PagloraEntry)
if ($entries.Count -ne 1) {
  throw "Expected exactly one current-user Paglora uninstall record; found $($entries.Count)."
}
$entry = $entries[0]
if ([string]$entry.DisplayVersion -ne $Version) {
  throw "Paglora version mismatch. Expected $Version; found $($entry.DisplayVersion)."
}
$uninstallString = [string]$entry.UninstallString
if ([string]::IsNullOrWhiteSpace($uninstallString)) { throw 'Missing NSIS uninstall command.' }
$match = [regex]::Match($uninstallString, '^"([^"]+\.exe)"|^(\S+\.exe)', 'IgnoreCase')
if (!$match.Success) { throw "Unrecognized uninstall executable: $uninstallString" }
$uninstaller = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
if (!(Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
  throw "Registered NSIS uninstaller does not exist: $uninstaller"
}
$expectedRoot = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\') + '\'
$uninstallerPath = [System.IO.Path]::GetFullPath($uninstaller)
if (!$uninstallerPath.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to execute unexpected uninstaller outside LocalAppData: $uninstaller"
}
$installedExe = Join-Path (Split-Path -Parent $uninstaller) 'paglora.exe'
if (!(Test-Path -LiteralPath $installedExe -PathType Leaf)) {
  throw "Tauri app executable missing beside NSIS uninstaller: $installedExe"
}
Write-Host "Installed Paglora $Version verified, executable: $installedExe"
Write-Host 'Invoking original Tauri NSIS uninstaller /S on isolated runner...'
$process = Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -PassThru
if ($process.ExitCode -ne 0) {
  throw "NSIS uninstaller returned code $($process.ExitCode)"
}
for ($i=0; $i -lt 30; $i++) {
  if (@(Get-PagloraEntry).Count -eq 0) {
    Write-Host 'Windows uninstall registry record removed successfully.'
    exit 0
  }
  Start-Sleep -Milliseconds 500
}
throw 'Original Tauri NSIS uninstaller did not remove its uninstall record.'
