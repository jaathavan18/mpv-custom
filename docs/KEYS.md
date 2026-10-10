# Keys

## Playlist panel (`scripts/tabs`)
| Key / mouse | Action |
|---|---|
| F6 | open / close the panel (it comes back as you left it) |
| F7 | the add-ons panel in the same strip, see [ADDONS.md](ADDONS.md) |
| Drag the left edge of the strip | make the panel wider or narrower, the video takes the rest |
| Ctrl+Tab / Ctrl+Shift+Tab | next / previous tab |
| Ctrl+T | new tab |
| Ctrl+W | close tab |
| Ctrl+Shift+T | reopen the last closed tab |
| Ctrl+Shift+W | close all other tabs |
| Ctrl+V | add the paths / URLs on the clipboard to the playlist |
| Click a row | select it |
| Double-click a row | play it |
| Mouse wheel over the list | scroll |
| Double-click or right-click a tab | rename it (tabs are named after their folder until you rename them) |
| Del | remove the selected row |
| Up / Down / PgUp / PgDn / Home / End | move the selection (mouse over the panel) |
| Enter | play the selected row (mouse over the panel) |
| Drag a tab | reorder tabs |
| Middle-click a tab | close it |
| **+** / **x** on the tab strip | new tab / close tab |

## Letter keys (`scripts/vlc-keys.lua`, nothing to add to `input.conf`)
Only plain letters are changed. The add-ons panel can switch them off (then they are mpv's own keys again). Arrows, Space, numbers, F-keys, Ctrl/Shift combinations and the mouse stay mpv's own.

| Key | Action | Key | Action |
|---|---|---|---|
| a | cycle aspect ratio | n | next file in the folder |
| b | cycle audio track | o | unscaled video on / off |
| c | cycle crop | p | previous file in the folder |
| d | deinterlace: no / yes / auto | r | random on / off |
| e | next frame | s | stop (Space then plays it again from where it stopped) |
| f | fullscreen | t | show time |
| g / h | subtitle delay -0.05 / +0.05 s | v | cycle subtitle track |
| i | keep the bar on screen in fullscreen (press again for auto-hide) | z | cycle zoom |
| j / k | audio delay -0.05 / +0.05 s | l | loop: off / all / repeat one |
| m | mute | q u w x y | unused |

## Chapter keys (`scripts/chapter-step.lua` + `examples/input-chapters.conf`)
| Key | Action |
|---|---|
| Shift+N | next chapter (a second press within 0.4 s is ignored) |
| Shift+P | previous chapter |
