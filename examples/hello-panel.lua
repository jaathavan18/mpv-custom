-- hello-panel: the smallest panel for the side strip (scripts/strip). Copy this file to your scripts folder.
-- F8 shows / hides it; the strip widens the window, hides it in full screen, and lets you drag its edge.
-- A panel draws only while user-data/strip/active is its own id, and asks the strip to open or close it.
local mp = require 'mp'
local ID = "hello"
local overlay = mp.create_osd_overlay("ass-events")
local told = false

local function redraw()
    local z = mp.get_property_native("user-data/strip/sizes")
    local w, h = mp.get_property_number("osd-width") or 0, mp.get_property_number("osd-height") or 0
    if not z then return end
    if not told then   -- say how narrow this panel may be (the strip is loaded once it publishes sizes)
        told = true
        mp.commandv("script-message-to", "strip", "strip-minwidth", ID, tostring(z.FS * 10))
    end
    if mp.get_property_native("user-data/strip/active") ~= ID or mp.get_property_native("fullscreen") or w <= z.P + 50 then
        overlay:remove(); return
    end
    local x0 = w - z.P
    overlay.res_x, overlay.res_y = w, h
    overlay.data = string.format(
        "{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H000000&\\p1}m %d 0 l %d 0 l %d %d l %d %d{\\p0}\n" ..
        "{\\an7\\pos(%d,%d)\\fnSegoe UI\\fs%d\\bord0\\shad0\\1c&HE6E6E6&}Hello from my own panel",
        x0, w, w, h, x0, h, x0 + z.FS, z.FS, z.FS)
    overlay:update()
end

mp.add_key_binding("F8", "toggle", function() mp.commandv("script-message-to", "strip", "strip-toggle", ID) end)
for _, p in ipairs({"user-data/strip/active", "user-data/strip/sizes", "osd-dimensions", "fullscreen"}) do
    mp.observe_property(p, "native", redraw)
end
