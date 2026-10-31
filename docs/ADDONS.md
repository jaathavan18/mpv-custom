# The add-ons panel (F7)

A list of everything in this package with an ON / OFF switch. Click a row, or move with Up / Down and press Enter. The mouse wheel scrolls when the list is longer than the panel. F7 closes it, F6 shows the playlist instead.

| Switch | What it controls |
|---|---|
| Playlist panel | F6, the tabs and their keys |
| VLC letter keys | plain a-z. Off = mpv's own keys for those letters, even if the same keys are also in your `input.conf` |
| Stop, then Space resumes | `s` stops and Space resumes from there. Off = plain stop |
| Window memory | opens where you left it |
| Subtitle track number | one subtitle track number for every video |
| Saved volume | volume and mute restored on start |
| Chapter keys | Shift+N / Shift+P. Off = mpv's own chapter step |
| Bottom bar always visible | the bar stays on screen while windowed |
| Auto skip intro | skips the opening and ending songs of episodes (see below) |
| Remove watched videos from playlists | takes watched videos out of the playlists, never off the disk. Starts OFF (see below) |

**Actions** (one click, they reset what an add-on remembers): reset the saved window place, forget the subtitle track number, forget the saved volume.

## Auto skip intro (`scripts/intro-skip/`)

Skips the opening and the ending song of anime and TV episodes by itself, without chapters. It compares the audio of the episodes in the playlist (same folder, at most 12 nearest at a time) with ffmpeg and chromaprint and finds the stretch of 15 to 300 seconds that repeats: one in the first 40% of an episode is the opening, one in the last 40% is the ending. A scene after the credits still plays.

- **Needs `ffmpeg.exe`** with chromaprint next to `mpv.exe` (a full GPL build, for example BtbN's `ffmpeg-master-latest-win64-gpl`), on the PATH, or its path in `script-opts` as `introskip-ffmpeg=...`. It is not part of this repo.
- Needs two or more episodes of a folder in the playlist. The first scan of a folder takes a minute or two; nothing skips until it is done, so the first episode usually plays its opening. The audio of each episode is read once (`intro-skip-*.fp`) and the times are kept in `intro-skip.json`, both in the config folder.
- The skip starts 3 seconds into the song and lands 3 seconds before its end, and says "Skipped". Each song is skipped up to 2 times per episode (go back to before it and it skips again); the third time you can listen to it. Alt+I undoes a skip.
- Episodes ahead and episodes you add to the playlist are scanned in the background, so they are ready when you reach them. An episode with no match is left alone.
- The first video of each opening or ending plays it through; the videos that share it skip it. It goes by the matching audio, not by folder, so a new opening later in a series plays once too. Folders scanned before this was added skip as before. The setting "First play kept" turns it off.

## Numbers you can change

Under Settings in the panel, click a row or select it and press Enter, type a number and press Enter. A number outside the range is moved to the nearest allowed one. "Reset all settings" puts every row back. The numbers are kept in `addons-state.json`.

| Setting | Normal | Range |
|---|---|---|
| Skip starts after (s) | 3 | 0-30 |
| Lands before the end (s) | 3 | 0-30 |
| Skips per video | 2 | 1-9 |
| Shortest repeat (s) (next scan) | 15 | 5-120 |
| Longest repeat (s) (next scan) | 300 | 30-900 |
| Look in first and last (%) (next scan) | 40 | 10-50 |
| Videos scanned at once (next scan) | 12 | 2-40 |
| Message stays (s) | 4 | 1-15 |
| First play kept (1 yes, 0 no) | 1 | 0-1 |
| Watched from (%) | 90 | 50-100 |
| Chapter key pause (s) | 0.4 | 0-5 |
| Delay step g h j k (s) | 0.05 | 0.01-1 |
| New file waits (s) | 10 | 0-120 |
| Remove after (days) | 7 | 1-365 |
| Or after videos elsewhere | 10 | 1-500 |
| Held key starts repeating after (ms) | your mpv.conf | 0-3000 |
| Held key repeats per second | your mpv.conf | 1-100 |

The last two are mpv's own key repeat, so they change every key, including your `input.conf` ones.

## Remove watched videos from playlists

Takes watched videos out of the playlists (only the entry, never the file). Off until you switch it on. A video counts as watched by the playlist panel's mark (90% by default).

- A watched video leaves 7 calendar days after the day it was watched (watched at 23:59, it is a day old at midnight).
- It also leaves when its whole group is watched and 10 videos from outside the group were watched after it.
- A group is a folder with everything nested in it. Folders side by side count as one group (their parent) when every folder with videos under that parent is in the playlist.
- Videos marked watched before this was switched on count their days from the day you switch it on.
- It runs a few seconds after start, when you switch it on, and when the day changes. The playing video stays until the next run. Playlists you are not looking at are cleaned too, unless they are open in another window.
- The days and the number of videos are in the settings above. When it was watched is kept in `watched-log.json`.

## Details

- The panel looks in your `scripts` folder and lists only what is installed. Delete an add-on's script and its row disappears.
- Your choices are saved in `addons-state.json` in your mpv config folder. The keys, the panels, stop-and-resume and the bar change at once. Window memory, subtitle number and volume act when you start or quit mpv or open a file.
- Without this panel everything is simply ON.

## For other scripts: appear in the list

Send `script-message-to addons addons-register <id> <name>` from your script, then read the property `user-data/addons/<id>` (`"on"` or `"off"`; read it with `mp.get_property_native`, not as a string). Your row shows up and its switch changes the property.
