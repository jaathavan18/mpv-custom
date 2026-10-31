-- chapter-step.lua
-- Shift+N / Shift+P: next / previous chapter, with a short cooldown so one press (or key auto-repeat)
-- cannot run through several chapters and land at the end of the video.
--  * Presses closer together than the cooldown (0.4 s, changeable in F7) are ignored.
--  * A file with no chapters does nothing (mpv would otherwise treat the whole file as one chapter and jump to its end).
local mp = require 'mp'

-- numbers you can change in the add-ons panel (F7): read live, then from the saved file, then the default
local file_values = {}
do
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if f then
        local ok, d = pcall(require("mp.utils").parse_json, f:read("*a") or ""); f:close()
        if ok and type(d) == "table" and type(d.values) == "table" then
            for k, v in pairs(d.values) do if type(k) == "string" and tonumber(v) then file_values[k] = tonumber(v) end end
        end
    end
end
local function setting(key, default)
    local v = mp.get_property_native("user-data/settings/" .. key)
    if type(v) == "number" then return v end
    return file_values[key] or default
end

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
    if now - last < setting("chapters_cooldown", 0.4) then return end
    if (mp.get_property_number("chapter-list/count") or 0) == 0 then
        mp.osd_message("No chapters in this file", 1)
        return
    end
    last = now
    mp.commandv("add", "chapter", tostring(tonumber(dir) or 1))
end)
