# Changelog

## Unreleased

- Ctrl+D cycles the audio output device (auto, speakers, monitor, headset ...) and shows its name. Part of the VLC keys add-on.
- The volume bar, the seek bar and the `t` progress display now sit on the video, not across the whole window, so they no longer run under an open panel.
- Playlist panel: settings now belong to each tab. Subtitle track, audio track, volume and mute are saved per tab and never leak to another playlist; a new tab starts from your mpv.conf values and existing tabs inherit the current subtitle number and volume once. Delays, speed, zoom, pan, rotation, subtitle size and position and picture settings are not carried or saved: they go back to the player's start values at every file. The subtitle-number and saved-volume add-ons step aside while the playlist panel is on.
- Playlist panel: files you have watched are drawn dimmer. They are marked once played into the last 10% (or to the end), `w` toggles a row by hand, and the first run marks the rows before each tab's saved position. Kept in `watched.json`.
- Fixed: deleting rows above the playing file no longer scrolls the playlist to the playing file, so you can keep pressing Del down the list.
- Panels now work in full screen: the video shrinks beside the panel (the window cannot grow there) and the strip keeps the width you chose. `examples/hello-panel.lua` and `docs/PANEL.md` follow.
- Playlist panel: Del selects the next row, so pressing it again removes the next one.
- The window and panel stay open when the playlist is emptied (the playlist panel switches mpv's `force-window` on).
- The bar's empty-screen logo ("Drop files or URLs") is centred in the video area, not the whole window.
- Subtitles stay on the video and scale with the picture (`sub-use-margins=no`, `sub-scale-with-window=no`, set after each file loads). Plain subtitles no longer run under the panel.

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
