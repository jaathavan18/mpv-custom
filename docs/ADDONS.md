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

**Actions** (one click, they reset what an add-on remembers): reset the saved window place, forget the subtitle track number, forget the saved volume.

## Details

- The panel looks in your `scripts` folder and lists only what is installed. Delete an add-on's script and its row disappears.
- Your choices are saved in `addons-state.json` in your mpv config folder. The keys, the panels, stop-and-resume and the bar change at once. Window memory, subtitle number and volume act when you start or quit mpv or open a file.
- Without this panel everything is simply ON.

## For other scripts: appear in the list

Send `script-message-to addons addons-register <id> <name>` from your script, then read the property `user-data/addons/<id>` (`"on"` or `"off"`; read it with `mp.get_property_native`, not as a string). Your row shows up and its switch changes the property.
