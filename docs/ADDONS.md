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

**Actions** (one click, they reset what an add-on remembers): reset the saved window place, forget the subtitle track number, forget the saved volume.

## Auto skip intro (`scripts/intro-skip/`)

Skips the opening and the ending song of anime and TV episodes by itself, without chapters. It compares the audio of the episodes in the playlist (same folder, at most 12 nearest at a time) with ffmpeg and chromaprint and finds the stretch of 15 to 150 seconds that repeats: one in the first 40% of an episode is the opening, one in the last 40% is the ending. A scene after the credits still plays.

- **Needs `ffmpeg.exe`** with chromaprint next to `mpv.exe` (a full GPL build, for example BtbN's `ffmpeg-master-latest-win64-gpl`), on the PATH, or its path in `script-opts` as `introskip-ffmpeg=...`. It is not part of this repo.
- Needs two or more episodes of a folder in the playlist. The first scan of a folder takes a minute or two; nothing skips until it is done, so the first episode usually plays its opening. The audio of each episode is read once (`intro-skip-*.fp`) and the times are kept in `intro-skip.json`, both in the config folder.
- The skip starts 3 seconds into the song and lands 3 seconds before its end, and says "Skipped". Each song is skipped up to 2 times per episode (go back to before it and it skips again); the third time you can listen to it. Alt+I undoes a skip.
- Episodes ahead and episodes you add to the playlist are scanned in the background, so they are ready when you reach them. An episode with no match is left alone.

## Details

- The panel looks in your `scripts` folder and lists only what is installed. Delete an add-on's script and its row disappears.
- Your choices are saved in `addons-state.json` in your mpv config folder. The keys, the panels, stop-and-resume and the bar change at once. Window memory, subtitle number and volume act when you start or quit mpv or open a file.
- Without this panel everything is simply ON.

## For other scripts: appear in the list

Send `script-message-to addons addons-register <id> <name>` from your script, then read the property `user-data/addons/<id>` (`"on"` or `"off"`; read it with `mp.get_property_native`, not as a string). Your row shows up and its switch changes the property.
