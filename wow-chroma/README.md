# WoW Chroma Bridge

Game-reactive Razer Chroma lighting for World of Warcraft: your keyboard, mouse, mousepad, headset and
Chroma-linked lights (like Govee) react to your health, combat, death and level-ups.

Built for versions of WoW without their own Razer lighting (such as WoW Forever), and usable with any version.

> **Heads up: this project is vibe coded.** It was written largely by an AI coding assistant, with a human
> steering and testing it, and it has only been tested on the setup listed under "Known to work on".
> It's provided as-is, with no warranty. Use it at your own risk.

## How it works

WoW addons can't talk to other programs, so this comes in two parts:

1. **ChromaBridge addon** draws a tiny 128×6 pixel strip near the bottom-left corner of the game.
   Its colored squares encode your health, combat, death, mount, resting, faction and level-ups.
2. **The bridge** (`chroma-bridge.ps1`) reads that strip about 20 times a second and sends matching
   lighting to Razer's Chroma software running on your PC.

Nothing is sent back into the game. The bridge only reads pixels from your screen.

## Effects

| In game | Lights |
|---|---|
| Out of combat | Faction color, dim (blue for Alliance, red for Horde, gold if neither) |
| Mounted | Faction color, brighter |
| Resting (inn or city) | Faction color, very dim |
| In combat | Faction color, full brightness with a slow throb |
| Health under 35% | Red pulse on everything, faster as health drops |
| Dead or ghost | Dim grey |
| Level up | Gold wave rolling across the keyboard, spilling onto your other lights |
| Always (keyboard) | Number keys 1–0 show a health bar: green above 60%, yellow from 60% down, red from 30% down |

When several apply, the first match in this order wins: level up, dead, health under 35%, in combat,
resting, mounted, out of combat. For example, riding a mount in a city shows the resting color.

## Requirements

- Windows 10 or 11 (the scripts use the Windows PowerShell that comes with Windows; nothing else to install)
- **Razer Synapse 4** with the **Razer Chroma** app installed and running
- World of Warcraft in **windowed** or **windowed (fullscreen)** mode. Exclusive fullscreen may hide the strip.
- Nothing drawn over the **bottom-left corner** of the game, such as an FPS-counter overlay

## Install

1. Download the latest `WoW-Chroma-Bridge-x.y.z.zip` from the
   [Releases page](https://github.com/opnsrce/wow-forever-chroma-bridge/releases/latest) and **extract it** to a folder you'll keep, for example `Documents\WoW Chroma Bridge`.
2. Double-click **`Install.bat`**. It finds World of Warcraft and copies the addon into every
   game version you have installed (Retail, Classic, Forever, ...). If it can't find WoW, it asks you to pick the folder.
   If Windows asks for administrator permission, that's because WoW is installed in a protected folder.
   It then asks whether to **start the bridge automatically** when you sign in to Windows. Say yes unless you'd
   rather start it by hand each time.
3. Restart WoW, or type `/reload` if it's already running. At character select, open **AddOns** and
   make sure **Chroma Bridge** is enabled.
4. If **World of Warcraft** appears in the **Razer Chroma** app's list of Chroma apps, turn it off,
   so the game's own lighting doesn't compete with the bridge. (WoW Forever and Classic usually aren't listed.)

## Each time you play

**With automatic start on:** just play. The bridge runs hidden in the background, checks for WoW every
couple of seconds (using next to no CPU), and takes over the lights once you're in the world.
When you close WoW, minimize it, or cover its bottom-left corner with another window, it lets go and your normal
lighting comes back about two seconds later. (If WoW stays visible on another monitor, the lights stay in game mode.)

- To stop it until your next sign-in: double-click **`Stop Chroma Bridge.bat`**.
- To see what it's doing: open its log at `%LOCALAPPDATA%\WoWChromaBridge\bridge.log`.
- To turn automatic start on or off later: run `Install.bat` again and answer the question.

**Without automatic start:** double-click **`Start Chroma Bridge.bat`** and leave its window open while you play.
You'll see a line each time something changes, like `HP 72% | Horde | combat`. Close the window to stop.

Only one copy of the bridge runs at a time. If the background one is running, `Start Chroma Bridge.bat`
just tells you so.

## In-game commands

- `/chromabridge`: shows whether the strip is visible and its scale
- `/chromabridge hide` / `show`: turns the strip off or on (off = the bridge releases the lights).
  Hiding lasts until you type `show`, `/reload` or log in again.
- `/chromabridge levelup`: plays the level-up effect as a test

## Uninstall

Double-click **`Uninstall.bat`**. It removes the addon from every WoW version, turns off automatic start and
stops the background bridge. Then delete the folder. The bridge's log folder,
`%LOCALAPPDATA%\WoWChromaBridge`, can be deleted too.

If you move the folder, run `Install.bat` again so automatic start points at the new location.

## Troubleshooting

- **Windows says the file is blocked, or "running scripts is disabled":** use the `.bat` files rather than
  the `.ps1` files directly. `Install.bat` also clears Windows' "downloaded from the internet" mark from the package.
  If Windows SmartScreen shows a warning, choose **More info → Run anyway**.
- **The bridge keeps saying "strip not visible":**
  - Make sure you're in the world (addons don't load at the login or character screens).
  - Make sure WoW isn't in exclusive fullscreen and the addon is enabled. Type `/chromabridge` to check the strip is shown.
  - Look at the bottom-left corner of the game: you should see a tiny strip with a magenta square at its left end.
    If an overlay (an FPS counter, Discord, Razer Cortex, etc.) is drawn over it, move or turn off that overlay.
- **The lights don't change even though the bridge sees the strip:** make sure Razer Synapse and the Chroma app are
  running, and that no other app (like a game's own lighting or the Chroma Visualizer) is competing.
- **Addon says "out of date":** tick **Load out of date AddOns** at the character screen, or run `Install.bat` again
  after a WoW update so it picks up the new version number.
- **Colors look wrong with Windows HDR on:** HDR can shift the strip's colors. Try with HDR off.
- **Health bar off by a key:** expected. Each key is 10% of your health, rounded up, so 41% lights five keys.

## Advanced

Options for `chroma-bridge.ps1` (also accepted by `Start Chroma Bridge.bat`):

- `-DryRun`: print what it reads without changing any lights
- `-Fps 30`: update faster (1 to 60, default 20)
- `-ProcessName MyWow`: look for a different game executable (without `.exe`). By default it looks for
  `Wow`, `WowClassic`, `WowT`, `WowB`, `WowClassicT` and `WowClassicB`.

### Installing by hand

If you'd rather not run `Install.bat`, copy the `ChromaBridge` folder into
`World of Warcraft\<version>\Interface\AddOns\` (for example `_retail_\Interface\AddOns\ChromaBridge`),
then tick **Load out of date AddOns** at character select if WoW lists it as out of date.
You still need to run `Start Chroma Bridge.bat` while you play.

## Known to work on

- WoW Forever 1.60.1, Windows 11, Razer Synapse 4 (Chroma SDK 4.01), BlackWidow V3 Pro, Basilisk Ultimate + dock,
  Firefly V2, Govee H6063 via Chroma Connect

Other WoW versions are supported in principle but untested. Retail in particular may restrict what addons can read
in combat. Reports welcome.

## License

Copyright (c) 2026 Levi Hackwith. MIT License: provided "as is", without warranty of any kind. See [LICENSE](LICENSE).
