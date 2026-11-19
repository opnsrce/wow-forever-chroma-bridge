<#
.SYNOPSIS
  Reads the Chroma Bridge addon's status strip from the WoW window and drives Razer Chroma lighting.

.DESCRIPTION
  The ChromaBridge addon draws a 128x6 pixel strip in the bottom-left corner of the game.
  This script captures those pixels about 20 times a second, decodes health, combat, death,
  mount, resting, faction and level-up, and sends matching effects to Razer's local Chroma REST API.
  Linked lights (e.g. Govee via Chroma Connect) follow through the chromalink device.

  When the strip is not visible for a couple of seconds (WoW closed, minimized, loading screen,
  covered by another window) the script releases the lights, so your normal lighting comes back.

  While WoW isn't running it only checks every couple of seconds, so it can run in the
  background all day (see -Background). Only one copy runs at a time.

  Overview of the moving parts:
    1. Find the WoW window              (Find-GameWindow)
    2. Screenshot the strip's pixels    (Read-Strip)
    3. Turn game state into colors      (Render)
    4. Send colors to Razer's software  (Open-Session, Put-Effect, Close-Session)

.PARAMETER ProcessName
  WoW process name(s) to look for, without ".exe". Defaults cover Retail, Classic, PTR and Beta clients.

.PARAMETER Fps
  How many times a second to read the strip and update the lights while playing (1-60, default 20).

.PARAMETER DryRun
  Decode and print the strip only; never touch the lights.

.PARAMETER Background
  Write to a log file instead of the console. Used by the automatic start shortcut.

.PARAMETER Stop
  Ask a running copy (for example the background one) to stop, wait for it, then exit.

.EXAMPLE
  .\chroma-bridge.ps1              # normal use, in a window
  .\chroma-bridge.ps1 -Background  # no console output, log to %LOCALAPPDATA%\WoWChromaBridge\bridge.log
  .\chroma-bridge.ps1 -Stop        # ask a running copy to stop
  .\chroma-bridge.ps1 -DryRun      # decode and print only, no lighting changes
#>
param(
  [string[]]$ProcessName = @('Wow', 'WowClassic', 'WowT', 'WowB', 'WowClassicT', 'WowClassicB'),
  [long]$WindowHandle = 0,      # testing: read this window instead of finding WoW
  [ValidateRange(1, 60)][int]$Fps = 20,
  [int]$StopAfterSeconds = 0,   # testing: exit after this many seconds (0 = run until stopped)
  [switch]$DryRun,
  [switch]$Background,
  [switch]$Stop
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# Logging, single instance, stop signal
# =============================================================================
# The background copy has no window, so other copies talk to it through two things:
#   * a named mutex: exists while a bridge is running, so a second copy can tell and exit
#   * a "stop" file: the running copy checks for it every loop and exits cleanly when it appears

$DataDir = Join-Path $env:LOCALAPPDATA 'WoWChromaBridge'
New-Item -ItemType Directory -Force $DataDir | Out-Null
$LogFile = Join-Path $DataDir 'bridge.log'
$StopFlag = Join-Path $DataDir 'stop'
$MutexName = 'Local\WoWChromaBridge'   # "Local\" = visible only within this Windows sign-in session

function Log($msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
  if ($Background) {
    # Keep the log small: once it passes 1 MB, the old one is kept as bridge.log.old.
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) { Move-Item $LogFile "$LogFile.old" -Force }
    Add-Content -Path $LogFile -Value $line
  } else {
    Write-Host ($line.Substring(11))   # console: time only, no date
  }
}

function Test-BridgeRunning {
  $existing = $null
  try {
    if ([System.Threading.Mutex]::TryOpenExisting($MutexName, [System.Security.AccessControl.MutexRights]::Synchronize, [ref]$existing)) {
      $existing.Dispose()
      return $true
    }
    return $false
  } catch {
    return $true   # access denied: it exists, but was created by an elevated (administrator) copy
  }
}

if ($Stop) {
  if (-not (Test-BridgeRunning)) {
    Write-Host 'Chroma Bridge is not running.'
    exit 0
  }
  Set-Content $StopFlag 'stop'
  Write-Host 'Asking Chroma Bridge to stop...'
  # An idle bridge checks every 2 seconds; one recovering from a lighting error may be
  # sleeping for 5, so allow a little longer than that.
  $deadline = (Get-Date).AddSeconds(10)
  while ((Test-BridgeRunning) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
  if (Test-BridgeRunning) {
    Write-Host "It hasn't stopped yet. It should within a few seconds; see its log: $LogFile"
  } else {
    Write-Host 'Chroma Bridge stopped. Your normal lighting is back.'
  }
  exit 0
}

$createdNew = $false
$Mutex = New-Object System.Threading.Mutex($true, $MutexName, [ref]$createdNew)
if (-not $createdNew) {
  $msg = "Chroma Bridge is already running (probably in the background). Its log: $LogFile"
  if ($Background) { Log $msg } else { Write-Host $msg }
  exit 0
}
Remove-Item $StopFlag -ErrorAction SilentlyContinue   # clear a stale request from an earlier -Stop
Add-Type -AssemblyName System.Drawing, System.Net.Http

# =============================================================================
# Windows API calls
# =============================================================================
# PowerShell can't call these user32.dll functions directly, so compile a tiny C# wrapper.
#   GetClientRect / ClientToScreen: where the game's drawing area (without title bar and
#     borders) is on screen.
#   IsIconic: is the window minimized?   IsWindow: does the handle still exist?
#   SetProcessDpiAwarenessContext: see below.
if (-not ('ChromaBridgeNative' -as [type])) {
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ChromaBridgeNative {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT p);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
}
'@
}
# With display scaling (e.g. 150%), Windows lies to programs that aren't "DPI aware" about window
# positions and sizes. -4 = DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: report real pixels.
[void][ChromaBridgeNative]::SetProcessDpiAwarenessContext([IntPtr](-4))

# =============================================================================
# Reading the strip (layout must match ChromaBridge.lua)
# =============================================================================
#   x   0-5   start marker, magenta     x 110-115  flags A: R combat, G dead, B mounted
#   x   8-107 health bar, 1 px per 1%   x 116-121  flags B: R faction, G level-up, B resting
#   x 122-127 end marker, cyan
$StripW = 128; $StripH = 6
$SampleY = 3       # read the middle row; edge rows can be blurred
$Margin = 8        # strip's distance from the window's bottom-left corner
$Bitmap = New-Object System.Drawing.Bitmap $StripW, $StripH   # reused every frame
$Gfx = [System.Drawing.Graphics]::FromImage($Bitmap)

# Looking up processes is the expensive part, so keep the window handle while it stays valid.
$script:GameWindow = [IntPtr]::Zero
function Find-GameWindow {
  if ($WindowHandle -ne 0) {
    $h = [IntPtr]$WindowHandle
    if ([ChromaBridgeNative]::IsWindow($h)) { return $h } else { return [IntPtr]::Zero }
  }
  if ($script:GameWindow -ne [IntPtr]::Zero -and [ChromaBridgeNative]::IsWindow($script:GameWindow)) { return $script:GameWindow }
  $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  $script:GameWindow = if ($p) { $p.MainWindowHandle } else { [IntPtr]::Zero }
  $script:GameWindow
}

# True when color $c is within $tol of (r, g, b) on every channel. The tolerance absorbs small
# shifts from color profiles, night light and similar.
function Test-Near($c, $r, $g, $b, $tol = 70) {
  [math]::Abs($c.R - $r) -le $tol -and [math]::Abs($c.G - $g) -le $tol -and [math]::Abs($c.B - $b) -le $tol
}

# Returns a state object, or $null when the strip isn't on screen.
function Read-Strip([IntPtr]$hwnd) {
  if ($hwnd -eq [IntPtr]::Zero -or [ChromaBridgeNative]::IsIconic($hwnd)) { return $null }
  $pt = New-Object ChromaBridgeNative+POINT   # client area's top-left corner, in screen coordinates
  if (-not [ChromaBridgeNative]::ClientToScreen($hwnd, [ref]$pt)) { return $null }
  $rc = New-Object ChromaBridgeNative+RECT    # client area size (Left/Top are always 0)
  if (-not [ChromaBridgeNative]::GetClientRect($hwnd, [ref]$rc) -or $rc.Bottom -lt $StripH) { return $null }

  # Copy just the strip's pixels from the screen. This captures whatever is visible there, so a
  # window or overlay covering the corner hides the strip (and the markers check below fails).
  try { $Gfx.CopyFromScreen($pt.X + $Margin, $pt.Y + $rc.Bottom - $StripH - $Margin, 0, 0, $Bitmap.Size) } catch { return $null }

  # Both end markers must be present, or this isn't the strip (yet).
  if (-not (Test-Near $Bitmap.GetPixel(3, $SampleY) 255 0 255)) { return $null }
  if (-not (Test-Near $Bitmap.GetPixel(125, $SampleY) 0 255 255)) { return $null }

  # Health: count bright pixels in the 100 px bar.
  $lit = 0
  for ($x = 8; $x -le 107; $x++) {
    $c = $Bitmap.GetPixel($x, $SampleY)
    if (($c.R + $c.G + $c.B) -gt 384) { $lit++ }
  }

  # Flags: sample the middle of each 6 px block; each channel is on (255) or off (0).
  # Faction uses three levels of red: 255 Alliance, 128 Horde, 0 neither.
  $a = $Bitmap.GetPixel(113, $SampleY)
  $b = $Bitmap.GetPixel(119, $SampleY)
  $faction = if ($b.R -gt 192) { 'Alliance' } elseif ($b.R -gt 64) { 'Horde' } else { 'None' }
  [pscustomobject]@{
    Health  = $lit            # 0-100
    Combat  = $a.R -gt 128
    Dead    = $a.G -gt 128
    Mounted = $a.B -gt 128
    Faction = $faction
    LevelUp = $b.G -gt 128
    Resting = $b.B -gt 128
  }
}

# =============================================================================
# Razer Chroma REST API
# =============================================================================
# Razer Synapse runs a small web server on this PC (http://localhost:54235). Using it:
#   1. POST /razer/chromasdk with a description of the app. The reply contains a session URI
#      such as http://localhost:XXXXX/chromasdk. While the session is open, Synapse shows our
#      colors instead of the user's normal lighting.
#   2. PUT <session>/<device> with an effect, for each device: keyboard, mouse, mousepad,
#      headset, keypad, chromalink ("chromalink" covers Chroma Connect lights such as Govee).
#   3. Send any request at least every 15 seconds, or Synapse ends the session. When nothing
#      has changed we PUT <session>/heartbeat instead.
#   4. DELETE <session> to end it and hand the lights back.
# Effects used here:
#   CHROMA_STATIC  one color for the whole device:  {"effect":"CHROMA_STATIC","param":{"color":N}}
#   CHROMA_CUSTOM  keyboard: a 6-row x 22-column grid of colors, roughly one entry per key.
#                  Row 0 is the Esc/F-key row, row 1 the number row; column 0 is the far left.
# Colors are single integers in BGR order: 0x00BBGGRR (see Bgr below).
# Reference: https://assets.razerzone.com/dev_portal/REST/html/index.html

$ChromaSdkUrl = 'http://localhost:54235/razer/chromasdk'
$Http = New-Object System.Net.Http.HttpClient
$Http.Timeout = [TimeSpan]::FromSeconds(3)
$script:SessionUri = $null
$script:LastSent = @{}    # device -> last JSON sent, so unchanged effects aren't re-sent
$script:LastHeartbeat = [DateTime]::MinValue

function Send-Json($method, $uri, $json) {
  $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod $method), $uri)
  if ($json) { $req.Content = New-Object System.Net.Http.StringContent($json, [Text.Encoding]::UTF8, 'application/json') }
  try {
    # GetAwaiter().GetResult() rather than .Result: on failure it throws the real error
    # ("connection refused", "timed out") instead of a vague "One or more errors occurred".
    $resp = $Http.SendAsync($req).GetAwaiter().GetResult()
    try { $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() } finally { $resp.Dispose() }
  } finally {
    $req.Dispose()
  }
}

function Open-Session {
  $body = @{
    title            = 'WoW Chroma Bridge'
    description      = 'Game lighting from the ChromaBridge addon'
    author           = @{ name = 'WoW Chroma Bridge'; contact = 'none' }
    device_supported = @('keyboard', 'mouse', 'headset', 'mousepad', 'keypad', 'chromalink')
    category         = 'game'
  } | ConvertTo-Json -Compress
  $r = Send-Json 'POST' $ChromaSdkUrl $body | ConvertFrom-Json
  if (-not $r.uri) { throw "Chroma SDK did not return a session: $($r | ConvertTo-Json -Compress)" }
  $script:SessionUri = $r.uri
  $script:LastSent = @{}
  Start-Sleep -Milliseconds 1500   # effects sent right after the session opens are often ignored
  Log "lighting session opened ($($r.uri))"
}

function Close-Session {
  if ($script:SessionUri) {
    try { [void](Send-Json 'DELETE' $script:SessionUri $null) } catch {}
    Log "lighting released"
    $script:SessionUri = $null
  }
}

function Put-Effect($device, $json) {
  if ($script:LastSent[$device] -eq $json) { return }
  [void](Send-Json 'PUT' "$($script:SessionUri)/$device" $json)
  $script:LastSent[$device] = $json
}

function Send-HeartbeatIfDue {
  if (((Get-Date) - $script:LastHeartbeat).TotalSeconds -ge 5) {
    [void](Send-Json 'PUT' "$($script:SessionUri)/heartbeat" $null)
    $script:LastHeartbeat = Get-Date
  }
}

# =============================================================================
# Lighting design
# =============================================================================

# Packs 0-255 red, green, blue (clamped and rounded) into Chroma's BGR integer.
function Bgr([double]$r, [double]$g, [double]$b) {
  $r = [int][math]::Max(0, [math]::Min(255, $r)); $g = [int][math]::Max(0, [math]::Min(255, $g)); $b = [int][math]::Max(0, [math]::Min(255, $b))
  ($b -shl 16) -bor ($g -shl 8) -bor $r
}
# Multiplies an @(r, g, b) color by a brightness factor $k.
# Parentheses matter: in PowerShell the comma binds tighter than *, so "a * k, b" means "a * (k, b)".
function Scale($rgb, [double]$k) { @(($rgb[0] * $k), ($rgb[1] * $k), ($rgb[2] * $k)) }

$OtherDevices = 'mouse', 'mousepad', 'headset', 'keypad', 'chromalink'
$FactionColor = @{ Alliance = @(30, 90, 255); Horde = @(230, 20, 15); None = @(255, 170, 40) }
$Gold = @(255, 140, 0)          # deep gold; lighter golds look white on keyboard LEDs
$LevelUpPassSeconds = 0.8       # time for one wave to cross the keyboard
$LevelUpWaveWidth = 2.5         # wave softness, in key columns
$script:LevelUpStart = $null
$Clock = [Diagnostics.Stopwatch]::StartNew()   # drives pulses and waves

function Render($s) {
  $t = $Clock.Elapsed.TotalSeconds
  $base = $FactionColor[$s.Faction]

  # Level-up: a gold wave rolls across the keyboard from left to right, about 3 passes
  # (the addon holds the flag for 2.5 s). The other devices are treated as sitting just past
  # the keyboard's right edge (column 23), so they glow as each wave reaches them.
  if ($s.LevelUp -and -not $s.Dead) {
    if (-not $script:LevelUpStart) { $script:LevelUpStart = $t }
    $sweep = (($t - $script:LevelUpStart) % $LevelUpPassSeconds) / $LevelUpPassSeconds   # 0..1 per pass
    # The wave's center travels from just off the left edge to just off the right edge.
    $front = -$LevelUpWaveWidth * 2 + $sweep * (22 + $LevelUpWaveWidth * 4)
    # Brightness at a column: a bell curve around the wave's center, never below 12%.
    $waveAt = { param($col) $d = $col - $front; 0.12 + 0.88 * [math]::Exp(-($d * $d) / (2 * $LevelUpWaveWidth * $LevelUpWaveWidth)) }
    $rows = for ($row = 0; $row -lt 6; $row++) {
      $cols = for ($col = 0; $col -lt 22; $col++) { $k = & $waveAt $col; Bgr ($Gold[0] * $k) ($Gold[1] * $k) ($Gold[2] * $k) }
      '[' + ($cols -join ',') + ']'
    }
    Put-Effect 'keyboard' ('{"effect":"CHROMA_CUSTOM","param":[' + ($rows -join ',') + ']}')
    $k = [math]::Max(0.3, (& $waveAt 23))
    $static = '{"effect":"CHROMA_STATIC","param":{"color":' + (Bgr ($Gold[0] * $k) ($Gold[1] * $k) ($Gold[2] * $k)) + '}}'
    foreach ($d in $OtherDevices) { Put-Effect $d $static }
    Send-HeartbeatIfDue
    return
  }
  $script:LevelUpStart = $null

  # Main color, by priority: dead > low health > combat > resting > mounted > idle.
  if ($s.Dead) {
    $main = @(35, 35, 45)
  } elseif ($s.Health -lt 35) {
    # Red pulse, from 1 Hz at 35% health up to 3 Hz at 10% and below.
    $hz = 1 + [math]::Min(2, (35 - $s.Health) / 12.5)
    $k = 0.2 + 0.8 * (0.5 + 0.5 * [math]::Sin($t * 2 * [math]::PI * $hz))
    $main = @((255 * $k), 0, 0)
  } elseif ($s.Combat) {
    $main = Scale $base (0.8 + 0.2 * (0.5 + 0.5 * [math]::Sin($t * 2 * [math]::PI * 1.5)))   # gentle 1.5 Hz throb
  } elseif ($s.Resting) {
    $main = Scale $base 0.3
  } elseif ($s.Mounted) {
    $main = Scale $base 0.7
  } else {
    $main = Scale $base 0.45
  }
  $mainColor = Bgr $main[0] $main[1] $main[2]

  # Keyboard: whole board in the main color, number keys 1-0 as a health bar.
  # In Chroma's grid the number row is row 1, and keys 1..0 are columns 2..11.
  # Each key stands for 10% health, rounded up (so 1% health still lights the "1" key).
  $keysLit = [math]::Ceiling($s.Health / 10)
  $healthColor = if ($s.Health -gt 60) { Bgr 0 255 40 } elseif ($s.Health -gt 30) { Bgr 255 200 0 } else { Bgr 255 0 0 }
  $unlit = Bgr 12 12 12
  $rows = for ($row = 0; $row -lt 6; $row++) {
    $cols = for ($col = 0; $col -lt 22; $col++) {
      if ($row -eq 1 -and $col -ge 2 -and $col -le 11 -and -not $s.Dead) {
        if (($col - 1) -le $keysLit) { $healthColor } else { $unlit }
      } else { $mainColor }
    }
    '[' + ($cols -join ',') + ']'
  }
  Put-Effect 'keyboard' ('{"effect":"CHROMA_CUSTOM","param":[' + ($rows -join ',') + ']}')

  $static = '{"effect":"CHROMA_STATIC","param":{"color":' + $mainColor + '}}'
  foreach ($d in $OtherDevices) { Put-Effect $d $static }
  Send-HeartbeatIfDue
}

# =============================================================================
# Main loop
# =============================================================================
# Each pass: find WoW, read the strip, update the lights, then sleep until the next pass.
# How long to sleep depends on what's happening, to keep CPU use near zero when not playing.
$frameMs = [int](1000 / $Fps)
$IdleMs = 2000       # WoW not running: check every 2 seconds
$WaitingMs = 250     # WoW running but strip not on screen (login screen, loading, tabbed out)
$GraceSeconds = 2    # keep the lights this long after the strip disappears (brief flickers, alt-tab)
$lastSeen = [DateTime]::MinValue
$lastSummary = ''
$script:Frames = 0; $script:BusyMs = 0   # simple performance stats, printed on exit

Log "Chroma Bridge started$(if ($DryRun) { ' (dry run, no lighting)' }). Waiting for WoW$(if (-not $Background) { '... Ctrl+C to stop' })."
try {
  $runClock = [Diagnostics.Stopwatch]::StartNew()
  $wowRunning = $null
  while ($StopAfterSeconds -le 0 -or $runClock.Elapsed.TotalSeconds -lt $StopAfterSeconds) {
    if (Test-Path $StopFlag) { Remove-Item $StopFlag -ErrorAction SilentlyContinue; Log 'stop requested'; break }
    $tick = [Diagnostics.Stopwatch]::StartNew()
    $hwnd = Find-GameWindow
    $nowRunning = $hwnd -ne [IntPtr]::Zero
    if ($nowRunning -ne $wowRunning) { Log $(if ($nowRunning) { 'WoW detected' } else { 'WoW not running, idling' }); $wowRunning = $nowRunning }
    $state = if ($nowRunning) { Read-Strip $hwnd } else { $null }
    $pace = if (-not $nowRunning) { $IdleMs } else { $WaitingMs }

    if ($state) {
      # Strip visible: update the lights at full speed.
      $pace = $frameMs
      $lastSeen = Get-Date
      $summary = "HP $($state.Health)% | $($state.Faction)" +
        $(if ($state.Combat) { ' | combat' }) + $(if ($state.Dead) { ' | dead' }) +
        $(if ($state.Mounted) { ' | mounted' }) + $(if ($state.Resting) { ' | resting' }) +
        $(if ($state.LevelUp) { ' | LEVEL UP' })
      if ($summary -ne $lastSummary) { Log $summary; $lastSummary = $summary }
      if (-not $DryRun) {
        try {
          if (-not $script:SessionUri) { Open-Session }
          Render $state
        } catch {
          # Usually Synapse isn't running or was restarted. Drop the session and try a fresh one later.
          Log "lighting error: $($_.Exception.Message) (is Razer Synapse running?) Retrying in 5s."
          Close-Session
          Start-Sleep -Seconds 5
        }
      }
    } elseif (((Get-Date) - $lastSeen).TotalSeconds -gt $GraceSeconds) {
      # Strip gone for a while: give the lights back.
      if ($lastSummary -ne 'none') { if ($nowRunning) { Log 'strip not visible' }; $lastSummary = 'none' }
      Close-Session
    } else {
      $pace = $frameMs   # brief gap: keep checking quickly before giving the lights back
    }

    $script:Frames++; $script:BusyMs += $tick.ElapsedMilliseconds
    $wait = $pace - $tick.ElapsedMilliseconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
  }
} catch {
  Log "stopped by an unexpected error: $($_.Exception.Message)"
} finally {
  # Runs on normal exit, errors and Ctrl+C: always hand the lights back and clean up.
  Close-Session
  if ($script:Frames -and -not $Background) { Write-Host ("{0} loops, average {1:N0} ms of work each" -f $script:Frames, ($script:BusyMs / $script:Frames)) }
  Log 'Chroma Bridge stopped'
  $Gfx.Dispose(); $Bitmap.Dispose(); $Http.Dispose()
  $Mutex.ReleaseMutex(); $Mutex.Dispose()
}
