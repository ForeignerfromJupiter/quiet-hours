<#
  Builds the eight Windows screen savers into windows/dist/:
    "Quiet Hours - Hinge.scr" … "Quiet Hours - Module.scr", plus the font licences.

  Needs the .NET SDK (8 or later). Nothing else: the .NET Framework 4.8 reference assemblies
  come from NuGet, so this also runs on a machine without Visual Studio.

    pwsh windows/build.ps1                       # all eight, Release
    pwsh windows/build.ps1 -Styles Hinge,Chorus  # just these
#>
param(
  [string]$Configuration = "Release",
  [string[]]$Styles = @("Hinge", "Chorus", "Breath", "Lumen", "Prose", "Slice", "Poster", "Module")
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repo = Split-Path -Parent $here
$project = Join-Path $here "src/QuietHours.Windows.csproj"
$dist = Join-Path $here "dist"

dotnet restore $project
if ($LASTEXITCODE -ne 0) { throw "restore failed" }

New-Item -ItemType Directory -Force -Path $dist | Out-Null
foreach ($style in $Styles) {
  Write-Host "== $style"
  dotnet build $project -c $Configuration --no-restore "-p:QHStyle=$style"
  if ($LASTEXITCODE -ne 0) { throw "build failed: $style" }
  $exe = Join-Path $here "src/bin/$Configuration/$style/Quiet Hours - $style.exe"
  Copy-Item -LiteralPath $exe -Destination (Join-Path $dist "Quiet Hours - $style.scr") -Force
}

Copy-Item (Join-Path $repo "Resources/Fonts/OFL-*.txt") $dist -Force
Copy-Item (Join-Path $repo "LICENSE") (Join-Path $dist "LICENSE.txt") -Force
Copy-Item (Join-Path $here "install.ps1") $dist -Force
Copy-Item -LiteralPath (Join-Path $here "READ ME FIRST.txt") $dist -Force

Get-ChildItem $dist | Format-Table Name, Length
