-- chapter-step.lua
-- Shift+N / Shift+P: next / previous chapter, with a short cooldown so one press (or key auto-repeat)
-- cannot run through several chapters and land at the end of the video.
--  * Presses closer together than COOLDOWN seconds are ignored.
--  * A file with no chapters does nothing (mpv would otherwise treat the whole file as one chapter and jump to its end).
local mp = require 'mp'

local COOLDOWN = 0.4
local last = -math.huge

-- add-on switch: the add-ons panel sets user-data/addons/<name> to "on"/"off"; without the panel everything stays on
local function addon_on(name)
    local v = mp.get_property_native("user-data/addons/" .. name)
    if v then return v ~= "off" end
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if not f then return true end
    local ok, d = pcall(require("mp.utils").parse_json, f:read("*a") or ""); f:close()
    return not (ok and type(d) == "table" and d[name] == false)
end

mp.register_script_message("chapter-step", function(dir)
    if not addon_on("chapters") then mp.commandv("add", "chapter", tostring(tonumber(dir) or 1)); return end   -- plain mpv behaviour
    local now = mp.get_time()
    if now - last < COOLDOWN then return end
    if (mp.get_property_number("chapter-list/count") or 0) == 0 then
        mp.osd_message("No chapters in this file", 1)
        return
    end
    last = now
    mp.commandv("add", "chapter", tostring(tonumber(dir) or 1))
end)
