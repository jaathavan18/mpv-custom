# Changelog

## 1.1.0

- Playlist panel: drag rows to reorder them. This includes folders you added and that are not opened yet, they are one row each and move like a file.
- Dragging inside a panel no longer moves the window.
- Rescan folder: a new file in a folder lands with that folder's own entries, no longer at the end after other folders.
- Known limit: the list does not scroll by itself while you drag, so on a very long playlist you can only drop onto rows you can see.

## 1.0.0

- The side strip as its own script: widens the window, keeps the video out from under the panel, resizable by dragging its left edge, remembers the open panel and its width.
- Add-ons panel (F7): ON / OFF switches for every part, one-click resets, lists only what is installed.
- Playlist panel (F6) now lives in the strip.
- VLC letter keys are built into `scripts/vlc-keys.lua` (no `input.conf` lines needed) and can be switched off. If an earlier version put them into `input.conf`, delete that block.
- Python is found automatically. The setting for an unusual location is `mpv-custom-python` (it was `tabs-python`).
- Window memory, saved volume, subtitle track number, chapter keys, the bottom bar and stop-then-resume as before.
