# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The "Versioning" section of the project's README on
GitHub explains what counts as a breaking change here.

## Unreleased

## 0.1.0 - 2026-11-18

First public release.

### Added

- **ChromaBridge addon**: draws a 128×6 pixel status strip in the bottom-left corner of the game window.
  The strip encodes health, combat, dead/ghost, mounted, resting, faction and level-up. It's always exactly
  128×6 physical pixels, whatever the resolution or UI scale, and stays visible when the UI is hidden with Alt+Z.
- `/chromabridge` slash command, with `show`, `hide` and `levelup` (test the level-up effect).
- **Bridge** (`chroma-bridge.ps1`): reads the strip about 20 times a second and drives Razer Chroma lighting
  through the Chroma SDK REST API on the keyboard, mouse, mousepad, headset, keypad and Chroma Connect
  lights (`chromalink`). It:
  - shows your faction color (Alliance blue, Horde red, gold for neither), dimmer when resting and brighter
    when mounted, with a slow throb in combat
  - pulses red when health drops under 35%, faster as health falls
  - turns dim grey while you're dead or a ghost
  - rolls a gold wave across the keyboard when you level up
  - turns the number keys 1–0 into a health bar
  - hands the lights back about 2 seconds after the strip disappears (WoW closed, minimized, covered or
    on a loading screen)
  - idles at near-zero CPU while WoW isn't running, and only one copy can run at a time
  - takes `-DryRun`, `-Fps`, `-ProcessName`, `-Background` and `-Stop` options
- **Installer** (`Install.bat` / `install.ps1`):
  - finds World of Warcraft through Battle.net's records or common folders, or lets you pick the folder
  - installs the addon into every installed game version, setting each `.toc` to match that version
  - asks for administrator rights only for the addon copy, and only when WoW is in a protected folder
  - can start the bridge hidden at every Windows sign-in
- `Uninstall.bat`, `Start Chroma Bridge.bat` and `Stop Chroma Bridge.bat` helpers.

### Known limitations

- Tested only on WoW Forever 1.60.1, Windows 11 and Razer Synapse 4. Retail and Classic should work but are
  untested, and Retail may restrict what addons can read in combat.
- Needs windowed or windowed (fullscreen) mode, and nothing covering the bottom-left corner of the game.
- Windows HDR can shift the strip's colors enough to confuse the bridge.
