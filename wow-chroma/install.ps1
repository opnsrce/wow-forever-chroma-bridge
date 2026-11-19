<#
.SYNOPSIS
  Installs (or removes) the ChromaBridge addon in every World of Warcraft version found on this PC.

.DESCRIPTION
  Finds the WoW folder from Battle.net's records or common locations, then copies the addon
  into each game version's Interface\AddOns folder (_retail_, _classic_, _classic_era_, _forever_, ...).
  The addon's "## Interface" line is set to match each version, so WoW doesn't mark it out of date.
  Also clears Windows' "downloaded from the internet" mark from this package's files, and
  optionally sets the bridge to start automatically at Windows sign-in.

  If WoW is installed in a protected folder (such as Program Files), only the addon copy step
  is re-run with administrator rights. Everything else (the sign-in shortcut, starting the
  bridge) runs as you, so the bridge never runs as administrator.

.EXAMPLE
  .\install.ps1                         # find WoW and install
  .\install.ps1 -WowPath "D:\Games\World of Warcraft"
  .\install.ps1 -Uninstall
#>
param(
  [string]$WowPath,
  [switch]$Uninstall,
  [ValidateSet('ask', 'yes', 'no')][string]$AutoStart = 'ask',   # start the bridge in the background at Windows sign-in
  [switch]$NoPause,     # don't wait for Enter before closing
  [switch]$AddonOnly    # internal: only copy/remove addon files (used for the administrator re-run)
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonName = 'ChromaBridge'
$addonSource = Join-Path $here $addonName
$bridgeScript = Join-Path $here 'chroma-bridge.ps1'
$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'WoW Chroma Bridge.lnk'
$logFile = Join-Path $env:LOCALAPPDATA 'WoWChromaBridge\bridge.log'

# =============================================================================
# Helpers
# =============================================================================

function Done($code) {
  # The administrator re-run only pauses on failure, so its window can be read before it closes.
  $pause = if ($AddonOnly) { $code -ne 0 } else { -not $NoPause }
  if ($pause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
  exit $code
}

# A shortcut in the user's Startup folder runs the bridge hidden at every Windows sign-in.
function Set-AutoStart {
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut($startupShortcut)
  $lnk.TargetPath = $powershellExe
  $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bridgeScript`" -Background"
  $lnk.WorkingDirectory = $here
  $lnk.WindowStyle = 7   # minimized, so nothing flashes up at sign-in
  $lnk.Description = 'Runs WoW Chroma Bridge in the background'
  $lnk.Save()
}

function Start-BackgroundBridge {
  Start-Process $powershellExe -WindowStyle Hidden `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$bridgeScript`"", '-Background'
}

# Asks a running bridge to stop and waits until it has (see -Stop in chroma-bridge.ps1).
function Stop-BackgroundBridge {
  & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $bridgeScript -Stop | Out-Null
}

# A WoW install folder is recognized by the .build.info file Battle.net keeps in it.
# Plain .NET path checks: Join-Path throws for drive letters that don't exist.
function Test-WowRoot($p) {
  if (-not $p) { return $false }
  try { [IO.File]::Exists([IO.Path]::Combine($p, '.build.info')) } catch { $false }
}

function Find-WowRoot {
  $candidates = New-Object System.Collections.Generic.List[string]

  # Battle.net's install database lists where each game lives. It's a binary file, so just
  # search its text for anything that looks like a path ending in "World of Warcraft".
  $db = Join-Path $env:ProgramData 'Battle.net\Agent\product.db'
  if (Test-Path $db) {
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($db))
    foreach ($m in [regex]::Matches($text, '[A-Za-z]:[\\/][^\x00-\x1f"]{0,200}?World of Warcraft')) {
      $candidates.Add(($m.Value -replace '/', '\'))
    }
  }
  # Battle.net's default install folder, from its JSON settings file. The path may be written
  # with forward slashes or JSON-escaped backslashes ("C:\\Games"), so normalize both.
  $cfg = Join-Path $env:APPDATA 'Battle.net\Battle.net.config'
  if (Test-Path $cfg) {
    $m = Select-String -Path $cfg -Pattern '"DefaultInstallPath"\s*:\s*"([^"]+)"' | Select-Object -First 1
    if ($m) {
      $default = $m.Matches[0].Groups[1].Value -replace '\\\\', '\' -replace '/', '\'
      $candidates.Add([IO.Path]::Combine($default, 'World of Warcraft'))
    }
  }
  # Common places.
  $candidates.Add("${env:ProgramFiles(x86)}\World of Warcraft")
  $candidates.Add("$env:ProgramFiles\World of Warcraft")
  foreach ($d in (Get-PSDrive -PSProvider FileSystem).Root) {
    $candidates.Add("$d" + 'World of Warcraft'); $candidates.Add("$d" + 'Games\World of Warcraft')
  }
  $candidates | Select-Object -Unique | Where-Object { Test-WowRoot $_ } | Select-Object -First 1
}

function Select-WowRoot {
  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = 'Select your "World of Warcraft" folder (the one containing _retail_, _classic_ or _forever_)'
  if ($dlg.ShowDialog() -eq 'OK') { $dlg.SelectedPath }
}

# Reads .build.info, a pipe-separated table with one row per installed product, e.g.
#   Branch!STRING:0|...|Version!STRING:0|...|Product!STRING:0
#   us|...|11.2.5.63906|...|wow
# Returns a map of product code -> game version, such as @{ wow = '11.2.5.63906' }.
function Get-Versions($root) {
  $map = @{}
  $lines = Get-Content (Join-Path $root '.build.info')
  $header = $lines[0] -split '\|' | ForEach-Object { ($_ -split '!')[0] }   # drop the "!TYPE:n" suffixes
  $iProduct = [array]::IndexOf($header, 'Product'); $iVersion = [array]::IndexOf($header, 'Version')
  foreach ($line in $lines | Select-Object -Skip 1) {
    $cols = $line -split '\|'
    if ($iProduct -ge 0 -and $iVersion -ge 0 -and $cols.Count -gt [math]::Max($iProduct, $iVersion)) {
      $map[$cols[$iProduct]] = $cols[$iVersion]
    }
  }
  $map
}

# Converts a game version to the number WoW expects on a .toc's "## Interface" line:
# 11.2.5.12345 -> 110205 ; 1.60.1.70959 -> 16001 ; 1.15.7.x -> 11507
function Get-InterfaceNumber($version) {
  $p = $version -split '\.'
  if ($p.Count -lt 3) { return $null }
  [int]$p[0] * 10000 + [int]$p[1] * 100 + [int]$p[2]
}

# =============================================================================
# Find WoW
# =============================================================================

# Files downloaded from the internet are blocked from running until unblocked.
Get-ChildItem $here -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

if (-not (Test-WowRoot $WowPath)) {
  if ($WowPath) { Write-Host "No WoW install found at $WowPath" -ForegroundColor Yellow }
  $WowPath = Find-WowRoot
}
if (-not (Test-WowRoot $WowPath)) {
  Write-Host "Couldn't find World of Warcraft automatically. Please pick its folder."
  $WowPath = Select-WowRoot
}
if (-not (Test-WowRoot $WowPath)) { Write-Host 'No World of Warcraft folder selected. Nothing was changed.' -ForegroundColor Red; Done 1 }
$WowPath = $WowPath.TrimEnd('\')   # a trailing \ would break the quoting of the administrator re-run
Write-Host "World of Warcraft found: $WowPath"

# Each installed game version is a folder like _retail_ or _classic_era_ holding a Wow*.exe.
$versions = Get-Versions $WowPath
$flavors = Get-ChildItem $WowPath -Directory | Where-Object { $_.Name -match '^_.+_$' -and (Get-ChildItem $_.FullName -Filter 'Wow*.exe' -File -ErrorAction SilentlyContinue) }
if (-not $flavors) { Write-Host 'No installed game versions found inside that folder.' -ForegroundColor Red; Done 1 }

# =============================================================================
# Copy (or remove) the addon in each game version
# =============================================================================

$failed = $false
foreach ($f in $flavors) {
  $addons = Join-Path $f.FullName "Interface\AddOns"
  $target = Join-Path $addons $addonName
  try {
    if ($Uninstall) {
      if (Test-Path $target) { Remove-Item $target -Recurse -Force; Write-Host "  $($f.Name): removed" }
      else { Write-Host "  $($f.Name): not installed" }
      continue
    }
    # .flavor.info's last line names the product (e.g. "wow_classic_era"), which is the key
    # into the versions table from .build.info.
    $product = $null
    $flavorFile = Join-Path $f.FullName '.flavor.info'
    if (Test-Path $flavorFile) { $product = (Get-Content $flavorFile | Select-Object -Last 1).Trim() }
    $interface = if ($product -and $versions[$product]) { Get-InterfaceNumber $versions[$product] }

    New-Item -ItemType Directory -Force $target | Out-Null
    Copy-Item (Join-Path $addonSource '*') $target -Force
    if ($interface) {
      $toc = Join-Path $target "$addonName.toc"
      $lines = (Get-Content $toc) -replace '^## Interface:.*$', "## Interface: $interface"
      # Written as UTF-8 without a byte-order mark: a BOM can hide the first line from WoW.
      [IO.File]::WriteAllLines($toc, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
      Write-Host "  $($f.Name): installed (game version $($versions[$product]), interface $interface)" -ForegroundColor Green
    } else {
      Write-Host "  $($f.Name): installed, but its game version is unknown. If WoW lists the addon as out of date, tick 'Load out of date AddOns'." -ForegroundColor Yellow
    }
  } catch [System.UnauthorizedAccessException] {
    $failed = $true; Write-Host "  $($f.Name): no permission to write to $addons" -ForegroundColor Red
  } catch {
    $failed = $true; Write-Host "  $($f.Name): $($_.Exception.Message)" -ForegroundColor Red
  }
}

if ($AddonOnly) { Done $(if ($failed) { 1 } else { 0 }) }

if ($failed) {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if ($isAdmin) { Done 1 }

  # Re-run just the addon step as administrator, wait for it, then carry on here as the normal user.
  Write-Host ''
  Write-Host 'Some folders need administrator rights. Asking Windows for permission and trying again...'
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`"", '-WowPath', "`"$WowPath`"", '-AddonOnly')
  if ($Uninstall) { $argList += '-Uninstall' }
  try {
    $elevated = Start-Process $powershellExe -Verb RunAs -ArgumentList $argList -Wait -PassThru
  } catch {
    Write-Host 'Administrator permission was not given. The addon could not be fully installed or removed.' -ForegroundColor Red
    Done 1
  }
  if ($elevated.ExitCode -ne 0) {
    Write-Host 'The administrator step failed. See the messages in its window.' -ForegroundColor Red
    Done 1
  }
  Write-Host 'Administrator step finished.' -ForegroundColor Green
}

Write-Host ''
if ($Uninstall) {
  if (Test-Path $startupShortcut) { Remove-Item $startupShortcut -Force; Write-Host 'Automatic start removed.' }
  Stop-BackgroundBridge
  Write-Host 'Chroma Bridge addon removed. Restart WoW (or type /reload) to finish.'
  Done 0
}

# =============================================================================
# Automatic start
# =============================================================================

if ($AutoStart -eq 'ask') {
  Write-Host 'The bridge has to be running for the lights to react to the game.'
  Write-Host 'It can start automatically, hidden, whenever you sign in to Windows. It stays idle until WoW is running.'
  $answer = Read-Host 'Start it automatically? (Y/N)'
  $AutoStart = if ($answer -match '^\s*y') { 'yes' } else { 'no' }
}
if ($AutoStart -eq 'yes') {
  Set-AutoStart
  Stop-BackgroundBridge          # replace a copy that may be running from an older location
  Start-BackgroundBridge
  Write-Host "Automatic start is on, and the bridge is running in the background now." -ForegroundColor Green
  Write-Host "  Its log: $logFile"
} elseif (Test-Path $startupShortcut) {
  Remove-Item $startupShortcut -Force
  Write-Host 'Automatic start turned off.'
}

Write-Host ''
Write-Host 'Done. Next steps:' -ForegroundColor Green
Write-Host '  1. Restart WoW (or type /reload if it is running) and make sure "Chroma Bridge" is enabled in the AddOns list.'
Write-Host '  2. If "World of Warcraft" appears in the Razer Chroma app''s list of Chroma apps, turn it off.'
if ($AutoStart -eq 'yes') {
  Write-Host '  3. Just play. To stop the background bridge, double-click "Stop Chroma Bridge.bat".'
} else {
  Write-Host '  3. Double-click "Start Chroma Bridge.bat" whenever you play.'
}
Done 0
