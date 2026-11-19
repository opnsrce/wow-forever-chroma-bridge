# WoW Chroma Bridge

Game-reactive Razer Chroma lighting for World of Warcraft. Your keyboard, mouse, mousepad, headset and
Chroma-linked lights (like Govee) react to your health, combat, death and level-ups.

It was built for versions of WoW that have no Razer lighting of their own (such as WoW Forever), and works
with any version in principle.

> [!WARNING]
> **This project is vibe coded.** It was written largely by an AI coding assistant (Claude), with a human
> steering, testing and reviewing. It has only been tested on one setup (see "Known to work on" in the
> [user guide](wow-chroma/README.md)). Read the code before you trust it, and expect rough edges.
> It's provided as-is, with no warranty of any kind. See [LICENSE](LICENSE).

## Install

You don't need to build anything or know how to code. You'll need Windows 10 or 11, **Razer Synapse 4** with the
**Razer Chroma** app, and WoW running in windowed or windowed (fullscreen) mode.

1. **Download** the latest release: go to the
   [Releases page](https://github.com/opnsrce/wow-forever-chroma-bridge/releases/latest) and click
   **`WoW-Chroma-Bridge-x.y.z.zip`** under *Assets*. (Not "Source code": that's for developers.)
2. **Extract** the zip to a folder you'll keep, for example `Documents\WoW Chroma Bridge`.
   Right-click the zip, choose **Extract All...**, and pick that folder.
3. **Double-click `Install.bat`** in the extracted folder. It finds World of Warcraft, installs the addon into
   every game version you have, and asks whether to start the bridge automatically when you sign in to Windows.
   Answer **Y** unless you'd rather start it by hand each time.
   If Windows SmartScreen warns you, click **More info**, then **Run anyway**.
4. **Restart WoW** (or type `/reload`), and make sure **Chroma Bridge** is ticked in the AddOns list at
   character select.
5. **Play.** Your lights follow your health, combat and level-ups.

To uninstall, double-click `Uninstall.bat`, then delete the folder. Settings, troubleshooting and everything
else are in the [user guide](wow-chroma/README.md), which also comes inside the zip.

## How it works

WoW addons run in a sandbox: they can't open files, network connections or other programs. So there's
no direct way for an addon to tell Razer's software what's happening in the game. This project works
around that in two parts:

```
 World of Warcraft                       Windows                          Razer Synapse
┌────────────────────┐   screen pixels  ┌──────────────────────┐   HTTP   ┌──────────────────┐
│ ChromaBridge addon │ ───────────────► │  chroma-bridge.ps1   │ ───────► │ Chroma REST API  │ ──► lights
│ draws a 128×6 strip│  (screenshot of  │ decodes the strip,   │ localhost│ localhost:54235  │
│ in the bottom-left │   just the strip)│ picks colors         │          │                  │
└────────────────────┘                  └──────────────────────┘          └──────────────────┘
```

1. **The addon** ([`ChromaBridge.lua`](wow-chroma/ChromaBridge/ChromaBridge.lua)) draws a tiny strip of
   colored blocks near the bottom-left corner of the game. The blocks encode health, combat, death,
   mount, resting, faction and level-up. It scales itself so the strip is always exactly 128×6 physical
   pixels, whatever the resolution or UI scale.
2. **The bridge** ([`chroma-bridge.ps1`](wow-chroma/chroma-bridge.ps1)) finds the WoW window, copies those
   pixels from the screen about 20 times a second, decodes them, and sends lighting effects to the
   [Razer Chroma SDK REST API](https://assets.razerzone.com/dev_portal/REST/html/index.html) that
   Razer Synapse runs on the local machine.

Nothing is sent into the game and nothing automates gameplay. The addon only draws, and the bridge only
reads pixels.

### The strip format

The strip's layout is the contract between the two halves. It's documented at the top of
`ChromaBridge.lua` and decoded in `Read-Strip` in `chroma-bridge.ps1`. Change both together.

| x (px)  | Meaning                                                                     |
|---------|-----------------------------------------------------------------------------|
| 0–5     | Start marker, magenta                                                       |
| 8–107   | Health bar: white pixels on black, one pixel per 1% health                  |
| 110–115 | Flags A: red = in combat, green = dead/ghost, blue = mounted                |
| 116–121 | Flags B: red = faction (255 Alliance, 128 Horde, 0 neither), green = level-up, blue = resting |
| 122–127 | End marker, cyan                                                            |

## Repository layout

| Path | What it is |
|---|---|
| `wow-chroma/ChromaBridge/` | The WoW addon (`.toc` metadata plus one Lua file) |
| `wow-chroma/chroma-bridge.ps1` | The bridge: screen reader, decoder and Chroma REST client |
| `wow-chroma/install.ps1` | Finds WoW, installs or removes the addon in every game version, sets up automatic start |
| `wow-chroma/*.bat` | Double-click wrappers so users don't have to deal with PowerShell's execution policy |
| `wow-chroma/README.md` | End-user guide, shipped in the zip |
| `CHANGELOG.md` | What changed in each release, also shipped in the zip |
| `.github/workflows/release.yml` | Builds the zip and publishes a GitHub release when a `v*` tag is pushed |
| `build.ps1` / `build.sh` | Packages `wow-chroma/` and `LICENSE` into `dist/WoW-Chroma-Bridge-<version>.zip` (Windows / macOS or Linux) |

## Development

You need Windows, World of Warcraft, and Razer Synapse with the Chroma app. The scripts target the
Windows PowerShell 5.1 that comes with Windows and need no other dependencies.

- **Try changes to the addon:** copy `wow-chroma/ChromaBridge` into your game's `Interface\AddOns` folder
  (or run `Install.bat`), then `/reload` in game after each edit. `/chromabridge` prints the strip's state.
  `/chromabridge levelup` triggers the level-up effect without having to level up.
- **Try changes to the bridge:** run it in a console:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\wow-chroma\chroma-bridge.ps1 -DryRun
  ```
  `-DryRun` prints the decoded state without touching the lights. `-StopAfterSeconds N` exits on its own,
  and `-WindowHandle <hwnd>` reads a specific window instead of searching for WoW. Stop any background copy
  first (`Stop Chroma Bridge.bat`). Only one copy runs at a time.
- **Build a release zip:** bump `## Version` in `ChromaBridge.toc`, then run `.\build.ps1` on Windows or
  `./build.sh` on macOS or Linux (it needs only `zip` and `perl`, both built into macOS). Attach
  `dist/WoW-Chroma-Bridge-<version>.zip` to a GitHub release. Building doesn't need Windows, but testing does.

### Versioning

The project follows [Semantic Versioning](https://semver.org): versions look like `MAJOR.MINOR.PATCH`.

**Where the version lives:** the `## Version:` line in
[`ChromaBridge.toc`](wow-chroma/ChromaBridge/ChromaBridge.toc). That's this project's equivalent of
`"version"` in a `package.json`. It's the only place the version is written down: WoW shows it in the AddOns
list, and both build scripts read it to name the zip. Don't confuse it with `## Interface:`, which is
the *game* build the addon targets and has nothing to do with this project's version.

**What each part means here.** Semver is about what users and other code rely on. For this project that's
the strip format (the contract between the addon and the bridge), the bridge's command-line options, the
installer's behavior and the requirements (Windows, Synapse, WoW versions).

| Bump | When | Examples |
|---|---|---|
| **MAJOR** (1.0.0 → 2.0.0) | Something people rely on changes incompatibly | Strip layout changes so an old addon no longer works with a new bridge; an option is removed or renamed; support for a WoW version or Synapse release is dropped |
| **MINOR** (1.0.0 → 1.1.0) | New features, nothing breaks | A new lighting effect; a new strip flag the old bridge can safely ignore; a new bridge option |
| **PATCH** (1.0.0 → 1.0.1) | Fixes only | Installer finds WoW in more places; a color or timing bug is fixed; docs corrections |

While the version starts with `0.` (as now), the project is still settling and any release may break things.
Release `1.0.0` once it's been tested on more WoW versions and the strip format feels stable.

### Releasing

Releases are published automatically by [`.github/workflows/release.yml`](.github/workflows/release.yml)
when you push a version tag. It builds the zip, uses that version's CHANGELOG section as the release notes
(with download instructions added on top), and attaches the zip to a new GitHub release.

1. Move the items under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) into a new `## x.y.z - YYYY-MM-DD` section.
2. Set `## Version:` in `ChromaBridge.toc` to the same version.
3. Build locally with `./build.sh` (macOS/Linux) or `.\build.ps1` (Windows), and test the zip on Windows.
4. Commit and push, then tag and push the tag:
   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```
5. Watch the **Actions** tab. When the workflow finishes, the release is on the Releases page.

The workflow stops with an error if the tag doesn't match the `.toc` version or CHANGELOG.md has no section
for it, so a mismatched release can't go out by accident.

Line endings are pinned in `.gitattributes`: `.bat` and `.ps1` files are checked out with CRLF, `.sh` with LF.

## Contributing

Issues and pull requests are welcome, especially reports from WoW versions other than WoW Forever (Retail,
Classic, Classic Era) and from other Razer devices. Please include the bridge's output (or its log at
`%LOCALAPPDATA%\WoWChromaBridge\bridge.log`), your WoW version, and your Windows display settings
(resolution, scaling, HDR).

## License

Copyright (c) 2026 Levi Hackwith. Released under the [MIT License](LICENSE).

The software is provided **"as is", without warranty of any kind**, express or implied. In no event are the
authors liable for any claim, damages or other liability arising from its use. See [LICENSE](LICENSE) for the full text.

World of Warcraft is a trademark of Blizzard Entertainment, Inc. Razer, Chroma and Synapse are trademarks of
Razer Inc. This project is not affiliated with or endorsed by either company.
