-- save-volume.lua
-- Remembers the volume (and mute) when mpv closes and restores it on the next start, for every file.
-- mpv's own resume data (watch_later) keeps volume per file; mpv.conf drops it from there so this one value wins.
local mp = require 'mp'

local state_path = mp.command_native({"expand-path", "~~/volume.state"})
-- add-on switch: the add-ons panel sets user-data/addons/<name> to "on"/"off"; without the panel everything stays on
local function addon_on(name)
    local v = mp.get_property_native("user-data/addons/" .. name)
    if v then return v ~= "off" end
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if not f then return true end
    local ok, d = pcall(require("mp.utils").parse_json, f:read("*a") or ""); f:close()
    return not (ok and type(d) == "table" and d[name] == false)
end

local f = addon_on("volume") and io.open(state_path, "r")
if f then
    local vol, mute = f:read("*n"), f:read("*l")
    f:close()
    if vol and vol >= 0 and vol <= 300 then mp.set_property_number("volume", vol) end
    if mute and mute:find("yes") then mp.set_property("mute", "yes") end
end

local function save()
    if not addon_on("volume") then return end
    local vol = mp.get_property_number("volume")
    if not vol then return end
    local out = io.open(state_path, "w")
    if out then out:write(string.format("%.0f %s\n", vol, mp.get_property("mute") == "yes" and "yes" or "no")); out:close() end
end

mp.observe_property("volume", "number", function() save() end)  -- also saves on a crash or forced close
mp.observe_property("mute", "bool", function() save() end)
mp.register_event("shutdown", save)
