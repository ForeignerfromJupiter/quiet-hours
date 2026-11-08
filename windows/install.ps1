<#
  Installs the Quiet Hours screen savers from the folder this script is in.

    .\install.ps1 -Style Chorus     # just you, no admin: copies all eight to
                                    # %LOCALAPPDATA%\Programs\Quiet Hours and makes Chorus current
    .\install.ps1 -AllUsers         # admin: copies all eight to C:\Windows\System32, so every
                                    # style is listed in Screen Saver Settings
    .\install.ps1 -Uninstall        # removes both (System32 copies need admin)

  Without the script: right-click a .scr → Install. Windows then uses that file where it is,
  so move it somewhere permanent first.
#>
param(
  [string]$Style = "Hinge",
  [switch]$AllUsers,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$savers = Get-ChildItem -Path $PSScriptRoot -Filter "Quiet Hours - *.scr"
$userDir = Join-Path $env:LOCALAPPDATA "Programs\Quiet Hours"
# A 32-bit PowerShell on 64-bit Windows would be redirected to SysWOW64, which the dialog ignores.
$system = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
  Join-Path $env:WINDIR "Sysnative" } else { Join-Path $env:WINDIR "System32" }

if ($Uninstall) {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $userDir
  Get-ChildItem -Path $system -Filter "Quiet Hours - *.scr" -ErrorAction SilentlyContinue | Remove-Item -Force
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "HKCU:\Software\Quiet Hours"
  Write-Host "Removed. If a Quiet Hours saver was selected, pick another in Screen Saver Settings."
  return
}

if (-not $savers) { throw "No 'Quiet Hours - *.scr' files next to this script." }

if ($AllUsers) {
  $savers | Copy-Item -Destination $system -Force
  Write-Host "Copied $($savers.Count) savers to $system."
  Start-Process control.exe -ArgumentList "desk.cpl,,@screensaver"
  return
}

New-Item -ItemType Directory -Force -Path $userDir | Out-Null
$savers | Copy-Item -Destination $userDir -Force
$chosen = Join-Path $userDir "Quiet Hours - $Style.scr"
if (-not (Test-Path -LiteralPath $chosen)) { throw "No saver named '$Style'." }
# The same thing Explorer's right-click → Install does; it opens Screen Saver Settings.
Start-Process rundll32.exe -ArgumentList "desk.cpl,InstallScreenSaver `"$chosen`""
Write-Host "Installed to $userDir and selected $Style. Run again with another -Style to switch."
