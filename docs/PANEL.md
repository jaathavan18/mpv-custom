# The side strip and its panels

The strip is the area on the right of the mpv window (`scripts/strip/`). It does not show anything itself: panels draw into it. The playlist panel (F6, `scripts/tabs/`) and the add-ons panel (F7, `scripts/addons/`) are the two that come with this package. Only one is shown at a time.

## What the strip does

- Pressing F6 or F7 makes the window wider by the strip's width, so the video keeps its size. Closing shrinks the window back on the same side. If there is no room on the right it grows to the left.
- F6 and F7 switch between the panels in the same space. The same key again closes it.
- **Drag the left edge of the strip** to give the video or the panel more room. The window does not change size while you drag. The strip is kept between a quarter and 60% of the window (and never narrower than the panel needs), so a small window leaves little room to move and a big window a lot. Make the window smaller and the strip follows, make it bigger again and the strip returns to the width you chose.
- The last panel and its width are remembered between runs. In full screen the strip is hidden and comes back when you leave it.

## The playlist panel

- Every tab is its own playlist and remembers which file was playing and where. Tabs are stored in your mpv config folder (`tabs-*.json`).
- A second mpv window opens with the same tabs. A tab that another window is playing is view-only there and is not resumed.
- Moving between files saves the position, so coming back to a file resumes it.

## Without Python

Widening and shrinking the window is done by a small Python helper (mpv cannot resize its own window from a script). Without Python everything still works, but the window keeps its size and the strip takes its room from the video.

## For other scripts: using the strip

A panel is a script that listens to the strip:

- show or hide yourself: `script-message-to strip strip-toggle <id>` (also `strip-open <id>`, `strip-close [id]`)
- draw, and take the mouse and keys, only while the property `user-data/strip/active` is your id
- read `user-data/strip/sizes` (`P` width, `FS` font size, `TAB_H`, `ROW_H`, `K` display scale, `FOOT` footer height, `EDGE` the grab margin on the strip's left edge)
- tell the strip how narrow you can be: `script-message-to strip strip-minwidth <id> <pixels>`

A complete minimal panel is in [`examples/hello-panel.lua`](../examples/hello-panel.lua): copy it to your `scripts` folder next to `scripts/strip/` and press F8. The strip's protocol is mine and may change between versions.
