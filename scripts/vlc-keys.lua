-- vlc-keys.lua: the few VLC letter-key actions that need more than one mpv command.
--   c  cycle crop ratio      l  loop: normal -> all -> repeat one      r  random (shuffle on/off)
--   s  stop; Space / the play button afterwards plays the same video again from where it stopped (like VLC)
--   i  keep the bottom bar on screen in fullscreen (press again to let it hide), like VLC
local mp = require 'mp'

local function say(text) mp.osd_message(text, 2) end

-- add-on switch: the add-ons panel sets user-data/addons/<name> to "on"/"off"; without the panel everything stays on
local function addon_on(name)
    local v = mp.get_property_native("user-data/addons/" .. name)
    if v then return v ~= "off" end
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if not f then return true end
    local ok, d = pcall(require("mp.utils").parse_json, f:read("*a") or ""); f:close()
    return not (ok and type(d) == "table" and d[name] == false)
end


-- c: crop to a ratio, centred. Order follows VLC (16:10, 16:9, 4:3, 1:1, 2.35:1, then no crop).
local ratios = {{"16:10", 16, 10}, {"16:9", 16, 9}, {"4:3", 4, 3}, {"1:1", 1, 1}, {"2.35:1", 235, 100}}
local crop_i = 0
local function source_size()
    local p = mp.get_property_native("video-dec-params") or mp.get_property_native("video-params")
    if p and p.w and p.h then return p.w, p.h end
end
mp.register_script_message("vlc-crop", function()
    local W, H = source_size()
    if not W then return end
    crop_i = crop_i + 1
    if crop_i > #ratios then
        crop_i = 0
        mp.set_property("video-crop", "")
        say("Crop: none"); return
    end
    local r = ratios[crop_i]
    local target = r[2] / r[3]
    local cw, ch = W, H
    if W / H > target then cw = math.floor(H * target + 0.5) else ch = math.floor(W / target + 0.5) end
    cw, ch = cw - cw % 2, ch - ch % 2
    mp.set_property("video-crop", string.format("%dx%d+%d+%d", cw, ch, math.floor((W - cw) / 2), math.floor((H - ch) / 2)))
    say("Crop: " .. r[1])
end)
mp.register_event("file-loaded", function() crop_i = 0 end)   -- mpv starts each file uncropped

-- l: normal -> loop all -> repeat current -> normal
mp.register_script_message("vlc-loop", function()
    local file, list = mp.get_property("loop-file", "no"), mp.get_property("loop-playlist", "no")
    if file ~= "no" then
        mp.set_property("loop-file", "no"); mp.set_property("loop-playlist", "no"); say("Loop: off")
    elseif list ~= "no" then
        mp.set_property("loop-playlist", "no"); mp.set_property("loop-file", "inf"); say("Repeat: current item")
    else
        mp.set_property("loop-playlist", "inf"); say("Loop: all")
    end
end)

-- r: shuffle on / off (off puts the playlist back in its original order)
local shuffled = false
mp.register_script_message("vlc-random", function()
    if shuffled then mp.command("playlist-unshuffle"); say("Random: off")
    else mp.command("playlist-shuffle"); say("Random: on") end
    shuffled = not shuffled
end)

-- i: show the bar and keep it there in fullscreen; press again to go back to auto-hide. Windowed it is always shown.
local pinned = false
mp.observe_property("fullscreen", "bool", function() pinned = false end)   -- leaving/entering fullscreen resets it
mp.register_script_message("vlc-bar", function()
    if not mp.get_property_native("fullscreen") then say("Bar is always shown when windowed"); return end
    pinned = not pinned
    mp.commandv("script-message", "osc-visibility", pinned and "always" or "auto", "no-osd")
    say(pinned and "Bar: kept on screen" or "Bar: auto-hide")
end)

-- s: stop, but remember what was playing. Any pause toggle (Space, the bar's play button, a media key) while stopped
-- starts that entry again at the position it was stopped at.
local stopped
mp.register_script_message("vlc-stop", function()
    if not addon_on("stoprs") then mp.commandv("stop", "keep-playlist"); return end   -- plain stop
    local path, idx = mp.get_property("path"), mp.get_property_number("playlist-pos")
    if path and idx and idx >= 0 then
        stopped = {idx = idx, pos = mp.get_property_number("time-pos"), count = mp.get_property_number("playlist-count")}
    end
    mp.commandv("stop", "keep-playlist")
end)
mp.observe_property("pause", "bool", function()
    if not addon_on("stoprs") then stopped = nil; return end
    if not stopped or not mp.get_property_native("idle-active") then return end
    local s = stopped
    stopped = nil
    if (mp.get_property_number("playlist-count") or 0) ~= s.count then return end   -- the playlist changed meanwhile
    mp.commandv("playlist-play-index", tostring(s.idx))
    mp.set_property_bool("pause", false)
    if s.pos and s.pos > 3 then
        local function seek() mp.unregister_event(seek); mp.commandv("seek", tostring(s.pos), "absolute") end
        mp.register_event("file-loaded", seek)
    end
end)
mp.register_event("start-file", function() stopped = nil end)

-- Letter keys a-z = VLC. Registered here so the add-ons panel can switch them off and on (off = mpv's own letter keys, even if input.conf has the same keys).
local LETTERS = {
    {"a", [[cycle-values video-aspect-override "16:9" "4:3" "1:1" "16:10" "2.35:1" "-2"]]},
    {"b", [[cycle audio]]},
    {"c", [[script-message vlc-crop]]},
    {"d", [[cycle deinterlace]]},
    {"e", [[frame-step]]},
    {"f", [[cycle fullscreen]]},
    {"g", [[add sub-delay -0.05]]},
    {"h", [[add sub-delay 0.05]]},
    {"i", [[script-message vlc-bar]]},
    {"j", [[add audio-delay -0.05]]},
    {"k", [[add audio-delay 0.05]]},
    {"l", [[script-message vlc-loop]]},
    {"m", [[cycle mute]]},
    {"n", [[script-message rescan-folder-next]]},
    {"o", [[cycle-values video-unscaled yes no]]},
    {"p", [[script-message rescan-folder-prev]]},
    {"q", [[ignore]]},
    {"r", [[script-message vlc-random]]},
    {"s", [[script-message vlc-stop]]},
    {"t", [[show-progress]]},
    {"u", [[ignore]]},
    {"v", [[cycle sub]]},
    {"w", [[ignore]]},
    {"x", [[ignore]]},
    {"y", [[ignore]]},
    {"z", [[cycle-values video-zoom 0 1 -2 -1]]},
}
-- mpv's own default for each of these letters (read from mpv itself); a letter mpv leaves unbound stays unbound ("ignore")
local STOCK = {
    b = "cycle deband", d = "cycle deinterlace", e = "add panscan +0.1", f = "cycle fullscreen", g = "ignore",
    i = "script-binding stats/display-stats", j = "cycle sub", l = "ab-loop", m = "cycle mute", o = "show-progress",
    p = "cycle pause", q = "quit", r = "add sub-pos -1", s = "screenshot", t = "add sub-pos +1",
    u = [[cycle-values sub-ass-override "force" "scale"]], v = "cycle sub-visibility", w = "add panscan -0.1",
    x = "add sub-delay 0.1", z = "add sub-delay -0.1",
}
local letters_on
local function set_letters(on)
    if on == letters_on then return end
    letters_on = on
    for _, e in ipairs(LETTERS) do
        local k = e[1]
        mp.remove_key_binding("vlc-letter-" .. k)
        mp.remove_key_binding("vlc-stock-" .. k)
        if on then
            mp.add_key_binding(k, "vlc-letter-" .. k, function() mp.command(e[2]) end, {repeatable = true})
        else
            -- forced, so it wins over a copy of the same keys in input.conf: off really means mpv's own keys
            local cmd = STOCK[k] or "ignore"
            mp.add_forced_key_binding(k, "vlc-stock-" .. k, function() mp.command(cmd) end, {repeatable = true})
        end
    end
end
mp.observe_property("user-data/addons/letters", "string", function() set_letters(addon_on("letters")) end)
mp.add_timeout(0.2, function() set_letters(addon_on("letters")) end)
