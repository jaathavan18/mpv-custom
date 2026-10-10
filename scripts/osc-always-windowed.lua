-- osc-always-windowed.lua
-- Keep mpv's bottom control bar (the stock OSC) on screen all the time while windowed;
-- in full screen it goes back to its normal auto-hide behaviour.
local mp = require 'mp'

-- add-on switch: the add-ons panel sets user-data/addons/<name> to "on"/"off"; without the panel everything stays on
local function addon_on(name)
    local v = mp.get_property_native("user-data/addons/" .. name)
    if v then return v ~= "off" end
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if not f then return true end
    local ok, d = pcall(require("mp.utils").parse_json, f:read("*a") or ""); f:close()
    return not (ok and type(d) == "table" and d[name] == false)
end

local function apply()
    local fs = mp.get_property_native("fullscreen")
    mp.commandv("script-message", "osc-visibility", (fs or not addon_on("bar")) and "auto" or "always", "no-osd")
end

mp.observe_property("fullscreen", "bool", apply)
-- the OSC may not be listening yet when this script loads, so say it again once things are up
mp.register_event("file-loaded", apply)
mp.add_timeout(0.5, apply)

mp.observe_property("user-data/addons/bar", "string", function() apply() end)
