<#
  Installs the Quiet Hours screen savers from the folder this script is in.

    .\install.ps1 -Style Chorus     # just you, no admin: copies all eight to
                                    # %LOCALAPPDATA%\Programs\Quiet Hours and makes Chorus current
    .\install.ps1 -AllUsers         # admin: copies all eight to C:\Windows\System32, so every
                                    # style is listed in Screen Saver Settings
    .\install.ps1 -Uninstall        # removes the files, settings, logs and cache
                                    # (System32 copies need an admin PowerShell)

  If Windows refuses to run scripts:  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Style Hinge

  Without the script: right-click a .scr → Install. Windows then uses that file where it is,
  so move it somewhere permanent first.
#>
param(
  [ValidateSet("Hinge", "Chorus", "Breath", "Lumen", "Prose", "Slice", "Poster", "Module")]
  [string]$Style = "Hinge",
  [switch]$AllUsers,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$savers = Get-ChildItem -Path $PSScriptRoot -Filter "Quiet Hours - *.scr"
$userDir = Join-Path $env:LOCALAPPDATA "Programs\Quiet Hours"
$dataDir = Join-Path $env:LOCALAPPDATA "Quiet Hours"
# A 32-bit PowerShell on 64-bit Windows would be redirected to SysWOW64, which the dialog ignores.
$system = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
  Join-Path $env:WINDIR "Sysnative" } else { Join-Path $env:WINDIR "System32" }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Uninstall) {
  # Stop any running saver first, so its files aren't locked.
  Get-Process | Where-Object { $_.Path -like "*\Quiet Hours - *.scr" } | Stop-Process -Force -ErrorAction SilentlyContinue

  # If a Quiet Hours saver is the current one, switch the screen saver to (None).
  $desktop = "HKCU:\Control Panel\Desktop"
  $current = (Get-ItemProperty -Path $desktop -Name "SCRNSAVE.EXE" -ErrorAction SilentlyContinue)."SCRNSAVE.EXE"
  if ($current -like "*Quiet Hours*") { Remove-ItemProperty -Path $desktop -Name "SCRNSAVE.EXE" }

  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $userDir, $dataDir, "HKCU:\Software\Quiet Hours"

  $systemCopies = @(Get-ChildItem -Path $system -Filter "Quiet Hours - *.scr" -ErrorAction SilentlyContinue)
  if ($systemCopies.Count -gt 0) {
    if ($isAdmin) { $systemCopies | Remove-Item -Force }
    else { Write-Warning "$($systemCopies.Count) savers in $system need an admin PowerShell to remove: run again as administrator." }
  }
  Write-Host "Quiet Hours removed."
  return
}

if (-not $savers) { throw "No 'Quiet Hours - *.scr' files next to this script." }

if ($AllUsers) {
  if (-not $isAdmin) { throw "-AllUsers copies into $system and needs an admin PowerShell (right-click PowerShell → Run as administrator)." }
  $savers | Copy-Item -Destination $system -Force
  Write-Host "Copied $($savers.Count) savers to $system. Pick one in Screen Saver Settings."
  Start-Process control.exe -ArgumentList "desk.cpl,,@screensaver"
  return
}

New-Item -ItemType Directory -Force -Path $userDir | Out-Null
$savers | Copy-Item -Destination $userDir -Force
# Files downloaded from the internet carry a "blocked" mark; the copies don't need it.
Get-ChildItem -Path $userDir -Filter "*.scr" | Unblock-File
$chosen = Join-Path $userDir "Quiet Hours - $Style.scr"
if (-not (Test-Path -LiteralPath $chosen)) { throw "No saver named '$Style' next to this script." }
# The same thing Explorer's right-click → Install does; it opens Screen Saver Settings.
Start-Process rundll32.exe -ArgumentList "desk.cpl,InstallScreenSaver `"$chosen`""
Write-Host "Installed to $userDir and selected $Style. Run again with another -Style to switch."
