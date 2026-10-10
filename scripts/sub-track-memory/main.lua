-- Keeps your subtitle track number for every video until you change it (pick 2 once -> 2 on all next videos).
-- If a video has no such track it uses mpv's default for that video and the stored number is kept.
-- Stored in sub-track.json. Changes in the first second after a file loads are mpv's automatic choice and are ignored.
local mp = require 'mp'
local utils = require 'mp.utils'
local FILE = mp.get_opt("subtrack-file") or mp.command_native({"expand-path", "~~/sub-track.json"})

-- add-on switch: the add-ons panel sets user-data/addons/<name> to "on"/"off"; without the panel everything stays on
local function addon_on(name)
    local v = mp.get_property_native("user-data/addons/" .. name)
    if v then return v ~= "off" end
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if not f then return true end
    local ok, d = pcall(require("mp.utils").parse_json, f:read("*a") or ""); f:close()
    return not (ok and type(d) == "table" and d[name] == false)
end

local want
do
    local f = io.open(FILE, "r")
    local d = f and utils.parse_json(f:read("*a") or "")
    if f then f:close() end
    want = d and d.sid
end
local function save()
    local f = io.open(FILE, "w")
    if f then f:write(utils.format_json({sid = want})); f:close() end
end

local ready = false
mp.register_event("end-file", function() ready = false end)
mp.register_event("file-loaded", function()
    ready = false
    if want ~= nil and addon_on("subtitle") then
        local exists = (want == "no")
        for _, t in ipairs(mp.get_property_native("track-list") or {}) do
            if t.type == "sub" and t.id == want then exists = true end
        end
        if exists then mp.set_property("sid", tostring(want)) end
    end
    mp.add_timeout(1, function() ready = true end)
end)

mp.observe_property("sid", "native", function(_, v)
    if not ready or not addon_on("subtitle") then return end
    local val = (v == false or v == nil) and "no" or v
    if want ~= val then want = val; save() end
end)

mp.register_script_message("subtrack-reset", function() want = nil; os.remove(FILE) end)
