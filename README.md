<h1 align="center">mpv-custom</h1>

<p align="center">Custom add-ons for <a href="https://mpv.io">mpv</a>, for convenience.</p>

<p align="center">Version 1.0.0 · <a href="CHANGELOG.md">what changed</a></p>

<p align="center">
  <a href="https://github.com/jaathavan18/mpv-custom/releases/latest"><strong>Download »</strong></a> ·
  <a href="#install">Install</a><br>
  <a href="docs/KEYS.md">Keys</a> ·
  <a href="docs/PANEL.md">The side strip</a> ·
  <a href="docs/ADDONS.md">Add-ons panel</a> ·
  <a href="#limits">Limits</a>
</p>

## Features

- **A side strip you can resize.** Panels open on the right, the window gets wider and the video keeps its size. Drag the strip's left edge to give the video or the panel more room. [[how it works](docs/PANEL.md)]
- **Add-ons panel (F7).** Every part of this package with an ON / OFF switch, plus one-click resets. Only what is installed is listed. [[add-ons](docs/ADDONS.md)]
- **Tabbed playlist panel (F6)**, like PotPlayer's playlist, in that strip. Browser-style tabs, each tab its own playlist that remembers where it was. Drag to reorder, reopen closed tabs, add files or URLs by dropping them or pasting. [[keys](docs/KEYS.md)]
- **VLC's letter keys.** Plain letters a-z behave like VLC (aspect, crop, audio and subtitle delay, loop, random, stop and more). Everything else stays mpv's. Switch them off and the letters are mpv's own again. [[keys](docs/KEYS.md)]
- **Stop and resume like VLC.** `s` stops, Space plays the same video again from where it stopped.
- **Window memory.** Opens where and how big you left it. The playlist panel is not counted, and a spot that is no longer on a screen is ignored.
- **One subtitle track number.** Pick track 2 once and every next video opens on track 2 until you change it.
- **A bottom bar that stays.** mpv's own bar, always visible when windowed and laid out over the video side only (not under the panel).
- **Chapter keys.** Shift+N / Shift+P, with a short cooldown so one press cannot skip through several chapters.
- **Saved volume.** The volume and mute you left are restored on the next start, for every video.
- **Resume that saves only the position.** Nothing else leaks from one video to the next.

## Requirements

- **Windows.** Widening the window and window memory use Windows calls.
- **Python 3** for exactly those two things. It is found automatically (`python`, `py`, `python3`, the per-user install). If yours is somewhere else, see Configuration. Without Python the panels, the divider, the add-ons panel and every other part still work; the window just keeps its size and the strip takes its room from the video.
- Tested with the mpv build `x86_64-v3-20261008`. Nothing else was tried.

## Tested on

Everything was built and tried on one computer: Windows 11 Home (build 26200), the portable mpv build `x86_64-v3-20261008-git-36bf3d5290`, Python 3.13, display scale 150%, one monitor.

**Not tested**, so it may behave differently there: Windows 10, other display scales (the panel sizes follow the scale but were only seen at 150%), several monitors or monitors with different scales, other mpv builds (the bottom bar script is a copy of that build's own bar), other Python versions, and mpv installed in `%APPDATA%\mpv` instead of the portable folder. Linux and macOS are not supported: widening the window and window memory are Windows only, and the rest was never tried there.

If you try one of these, a note in an issue saying it works (or what broke) is welcome.

## Install

**Back up your mpv config folder first** (copy it somewhere). These files are provided as is, without any warranty (see [LICENSE](LICENSE)); you use them at your own risk.

1. Download `mpv-custom-1.0.0.zip` from the [Releases page](https://github.com/jaathavan18/mpv-custom/releases/latest) (the right-hand side of the repo page has a "Releases" box too). Smaller zips for single parts are listed there as well. Extract it into your mpv config folder: the `portable_config` folder next to `mpv.exe` (create it if it is not there), or `%APPDATA%\mpv` if you installed mpv normally. Extract so that the zip's `scripts` folder lands in the config folder's `scripts` folder and its files merge with what is there; do not put the files in a new sub-folder.
2. Copy the lines from `examples/mpv.conf` into your `mpv.conf`.
3. The letter keys need nothing more. For the chapter keys add `examples/input-chapters.conf` to your `input.conf`.

Resume-where-you-left-off comes from the `watch-later-options=start` line in step 2, not from the scripts.
4. Start mpv. Press **F6** for the playlist, **F7** for the add-ons panel, drag the strip's left edge to resize it. All keys: [docs/KEYS.md](docs/KEYS.md).

## Upgrading

Close mpv, back up the config folder, extract the new zip over the old files and replace them. Your own data (tabs, window place, switches, volume) is not in the zip and stays. Read the matching entry in [CHANGELOG.md](CHANGELOG.md) for anything to change by hand.

## Do and don't

- **Do** back up your config folder before installing or updating, and extract the new zip over the old files when upgrading.
- **Do** keep `scripts/strip/` if you use the playlist panel or the add-ons panel: they need it.
- **Do** use zips from the same release together.
- **Don't** edit the `tabs-*.json`, `strip-state.json` or other data files while mpv is running; mpv would overwrite your edit.
- **Don't** run the stock bar and ours together: keep `osc=no` in `mpv.conf` when you use the bottom bar.
- **Don't** expect the switches in the add-ons panel to unload a script. They change what it does; to remove a script, delete it.

## If something does not work

| Problem | Likely cause |
|---|---|
| F6 or F7 does nothing | `scripts/strip/` is missing, or the matching script (`scripts/tabs/` or `scripts/addons/`) is not in your config folder's `scripts` folder; or the playlist panel is switched off in the add-ons panel |
| The panel opens but the window does not get wider | no working Python found. Install Python 3, or set `mpv-custom-python` (see Configuration). Everything else still works |
| Two bars on screen, or the bar looks unchanged | `osc=no` is missing from `mpv.conf` |
| Letter keys do the wrong thing | the add-ons panel switch is off; or another script or your `input.conf` binds the same letter |
| Videos start from the beginning | the `watch-later-options=start` line (and mpv's resume) is missing from `mpv.conf` |
| Nothing at all | start mpv from a terminal (`mpv.com`) and read the lines about the add-ons; they say what failed |

## Use only some parts

Each part works on its own (each one was tested alone on a bare mpv). On the release page every part also has its own small zip (`mpv-custom-playlist-panel-1.0.0.zip`, `mpv-custom-window-memory-1.0.0.zip` and so on); the playlist and add-ons zips include the side strip they need. Use zips from the same release together. Or copy only what you want from the full zip:

| Part | Copy | Also needs |
|---|---|---|
| Side strip alone, to build your own panel | `scripts/strip/`, see `examples/hello-panel.lua` and [docs/PANEL.md](docs/PANEL.md) | Python for widening |
| Tabbed playlist panel | `scripts/tabs/` | the strip |
| Add-ons panel | `scripts/addons/` | the strip |
| Window memory | `scripts/window-memory/` | Python |
| Subtitle track number | `scripts/sub-track-memory/` | nothing |
| Bottom bar on the video side | `scripts/osc.lua`, `scripts/osc-always-windowed.lua`, `script-opts/osc.conf` | `osc=no` in `mpv.conf` |
| VLC letter keys, stop and resume | `scripts/vlc-keys.lua`, `scripts/rescan-folder.lua` | nothing |
| Chapter keys (Shift+N / Shift+P) | `scripts/chapter-step.lua` | the lines of `examples/input-chapters.conf` in `input.conf` |
| Saved volume | `scripts/save-volume.lua` | nothing |
| Position-only resume | nothing to copy | the line `watch-later-options=start` in `mpv.conf` |

## Configuration

- If Python is not found, add `script-opts-append=mpv-custom-python=C:\Path\To\python.exe` to `mpv.conf`.
- Bar size: `script-opts/osc.conf`.
- Do not want the letter keys? Switch them off in the add-ons panel (F7). Your own lines in `input.conf` for those letters are overridden while it is off.
- Coming from an earlier version that put the letter keys into `input.conf`? Delete that block, otherwise it keeps overriding the panel's switch.

## Files the add-ons write

All inside your mpv config folder. Delete them to reset that part.

| File | Written by | Holds |
|---|---|---|
| `tabs-state.json`, `tabs-<id>.json`, `tabs-live-<pid>.json`, `tabs-<id>.json.closed` | playlist panel | tab order and playlists, which tab is active, which window has a tab open, closed tabs that can be reopened |
| `strip-state.json` | side strip | which panel was open and its width |
| `addons-state.json` | add-ons panel | the switches you turned off |
| `window-memory.json` | window memory | window position and size (video part) |
| `sub-track.json` | subtitle number | the one subtitle track number |
| `volume.state` | saved volume | volume and mute |
| `watch_later/` | mpv | playback position only, because of `watch-later-options=start` |

## Reporting a problem

Found something that breaks? Open an issue on the project's GitHub page and include:

- the mpv build (the top line when you start `mpv.com` in a terminal) and your Windows version
- the version of the zip you installed (the `VERSION` file) and which parts
- what you did, what you expected and what happened
- your display scale (Windows Settings > Display) and how many monitors, if the window or the strip is involved
- the lines about the add-ons from starting mpv in a terminal (`mpv.com`); they say what failed
- a screenshot (or a short screen recording) when it is about how something looks or moves; the whole mpv window is best. Blur or crop anything private such as file names

Things that were only tried on one setup, so reports are especially useful: other display scales than 150%, several monitors, other mpv builds, Python installed in an unusual place. This is a hobby project provided as is; there is no promise of a fix or of a time frame.

## Uninstall

Delete the script folders and files you copied from `scripts/` and `script-opts/`, remove the lines you added to `mpv.conf` and `input.conf`, and delete the files listed above if you want them gone. Nothing else is changed on your system.

## Limits

- Widening the window and window memory are Windows only and need Python 3. Without them the window does not change size and window memory does nothing.
- The ON / OFF switches change what the scripts do; they cannot unload a script. A script you do not want, you delete.
- `scripts/osc.lua` is a copy of the bar from mpv `x86_64-v3-20261008`. After an mpv update the copy stays the old version until it is made again.
- The letter keys are VLC's, not mpv's defaults: while they are on, the default `q`, `w`, `x`, `y` and `u` bindings are switched off.

## Credits

`scripts/osc.lua` is based on the on-screen controller that comes with [mpv](https://mpv.io). See [THIRD-PARTY.md](THIRD-PARTY.md). Everything here is under the LGPL 2.1 or later, see [LICENSE](LICENSE) and [NOTICE](NOTICE).
