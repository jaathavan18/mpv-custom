-- strip: the side strip on the right of the window, on its own. It widens the window, keeps the video out from under it, hides in
-- full screen and remembers which panel was open. It draws nothing itself: panels (playlist, add-ons, ...) draw into it.
--   A panel sends   script-message-to strip strip-toggle <id>   (also strip-open <id>, strip-close [id])
--   The strip sets  user-data/strip/active  ("" or the id of the panel to show),  user-data/strip/sizes  and  user-data/strip/extra
--   (how much of the window is strip, e.g. "R550"; window-memory uses it to save only the video part).
-- A panel draws, and takes the mouse and keys, only while user-data/strip/active is its own id.
local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local dir = mp.command_native({"expand-path", mp.get_opt("strip-dir") or "~~/"})
if not dir:match("[/\\]$") then dir = dir .. "/" end
local state_path = dir .. "strip-state.json"
local sdir = mp.get_script_directory()
local HELPER = mp.get_opt("strip-helper") or (sdir and utils.join_path(sdir, "resize.py")) or "resize.py"

-- Finds a working Python: the mpv-custom-python option if set, else python / py / python3 on the PATH, else a normal per-user install.
-- A candidate counts only if it really runs (the Microsoft Store "python" stub does not). The answer is remembered.
local python_cmd
local function find_python()
    if python_cmd ~= nil then return python_cmd or nil end
    local cands = {}
    local opt = mp.get_opt("mpv-custom-python")
    if opt then cands[#cands + 1] = opt end
    for _, n in ipairs({"python", "py", "python3"}) do cands[#cands + 1] = n end
    local base = os.getenv("LOCALAPPDATA")
    if base then
        base = base .. "\\Programs\\Python"
        local names = utils.readdir(base, "dirs") or {}
        table.sort(names, function(a, b) return a > b end)
        for _, d in ipairs(names) do cands[#cands + 1] = base .. "\\" .. d .. "\\python.exe" end
    end
    for _, c in ipairs(cands) do
        local r = mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = {c, "-c", "print(40+2)"}})
        if r and r.status == 0 and (r.stdout or ""):find("42", 1, true) then python_cmd = c; return c end
    end
    python_cmd = false
    mp.msg.warn("no working Python found: the window will not be resized or placed (set mpv-custom-python=C:\\path\\python.exe)")
end

local function read_json(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local d = utils.parse_json(f:read("*a") or ""); f:close()
    return d
end

-- Sizes follow the display scale so the text matches mpv's own on-screen controls (tuned for 150%).
local P, K, sizes_ready = 550, 1.5, false   -- P = width shown now; want_P = the width the user chose (P follows it as far as the window allows)
local want_P = 550
local saved = read_json(state_path)
local saved_width = saved and tonumber(saved.width)   -- the width the user dragged the strip to
local function publish_sizes()
    local fs = math.floor(22 * K + 0.5)
    mp.set_property_native("user-data/strip/sizes", {P = P, FS = fs, TAB_H = math.floor(fs * 2.3), ROW_H = math.floor(fs * 1.85), K = K, FOOT = math.floor(72.5 * K), EDGE = math.floor(8 * K)})
end
local function ensure_sizes()
    if sizes_ready then return end
    local k = mp.get_property_number("display-hidpi-scale")
    if not k then return end
    sizes_ready = true
    K = k
    P = math.floor(26 * k * 12.5)
    if saved_width and saved_width >= 200 and saved_width <= 4000 then P = math.floor(saved_width) end
    want_P = P
    publish_sizes()
end

local active, widened, side, added = "", false, "R", 0   -- added = how much wider the window was made (what closing takes away again)
local function fullscreen() return mp.get_property_native("fullscreen") end
local function shown() return active ~= "" and not fullscreen() end

local function resize_window(delta)
    local hwnd = mp.get_property_number("window-id")
    if not hwnd then return end
    if fullscreen() or mp.get_property_native("window-maximized") then return end
    local py = find_python()
    if not py then return end
    local res = mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true,
        args = {py, HELPER, string.format("%d", hwnd), tostring(delta), side}})
    if res and res.status == 0 then
        local s = (res.stdout or ""):match("([RL])")
        if s then side = s end
        return true
    end
    msg.warn("resize helper failed: " .. tostring(res and res.error_string) .. " " .. tostring(res and res.stderr))
end

local update_area
local function update_margin()
    local w = mp.get_property_number("osd-width") or 0
    local m = 0
    if shown() and w > P + 50 then m = math.min(0.9, P / w) end
    if mp.get_property_number("video-margin-ratio-right") ~= m then mp.set_property_number("video-margin-ratio-right", m) end
    if update_area then update_area() end
end

local function sync_window()
    if not fullscreen() then
        if active ~= "" and not widened then
            if resize_window(P) then widened = true; added = P end
        elseif active == "" and widened then
            if resize_window(-added) then widened = false; added = 0 end
        end
    end
    mp.set_property("user-data/strip/extra", widened and (side .. added) or "")
end

local function set_active(id)
    ensure_sizes()
    active = id
    sync_window()
    mp.set_property_native("user-data/strip/active", id)
    update_margin()
end

local function save()
    local f = io.open(state_path, "w")
    if f then f:write(utils.format_json({panel = active ~= "" and active or false, width = want_P})); f:close() end
end

-- a panel asks; "save" = the user's own choice (remembered for the next start)
local function toggle(id) set_active(active == id and "" or id); save() end
mp.register_script_message("strip-toggle", function(id) if id then toggle(id) end end)
mp.register_script_message("strip-open", function(id) if id and active ~= id then set_active(id); save() end end)
mp.register_script_message("strip-close", function(id)
    if active ~= "" and (not id or id == "" or id == active) then set_active(""); save() end
end)

-- ---------------------------------------------------------------- dragging the left edge: the strip grows, the video shrinks
local overlay = mp.create_osd_overlay("ass-events")
local hover, dragging, last_apply = false, false, 0
local function edge_zone() return 10 * K end   -- grab area: just left of the strip
local function draw_edge()
    local w, h = mp.get_property_number("osd-width") or 0, mp.get_property_number("osd-height") or 0
    if not (hover or dragging) or not shown() or w <= P + 50 then overlay:remove(); return end
    local x = w - P
    overlay.res_x, overlay.res_y = w, h
    overlay.data = string.format("{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H00D4FF&\\p1}m %d 0 l %d 0 l %d %d l %d %d{\\p0}", x - 4, x, x, h, x - 4, h)
    overlay:update()
end
-- Limits follow what is on show: the narrowest the open panel says it can be (strip-minwidth), the widest leaves a sliver of video
local mins = {}
mp.register_script_message("strip-minwidth", function(id, px) if id and tonumber(px) then mins[id] = tonumber(px) end end)
-- both ends scale with the window: a small window leaves little room to move the divider, a big one a lot
local MIN_SHARE, MAX_SHARE = 0.25, 0.60   -- strip width as a share of the window (the video keeps at least 40%)
local function limits(w)
    local lo = math.max(math.floor(w * MIN_SHARE), mins[active] or math.floor(260 * K))
    local hi = math.floor(w * MAX_SHARE)
    return math.min(lo, hi), hi
end
local function set_width(x)
    local w = mp.get_property_number("osd-width") or 0
    if w <= 0 then return end
    local lo, hi = limits(w)
    local new = math.floor(math.max(lo, math.min(hi, w - x)))
    if new == P then return end
    P, want_P = new, new
    local now = mp.get_time()
    if now - last_apply < 0.03 then return end   -- redrawing the panels on every mouse event is too much
    last_apply = now
    publish_sizes(); update_margin(); draw_edge()
end
local function end_drag()
    if not dragging then return end
    dragging = false
    publish_sizes(); update_margin(); draw_edge(); save()
end
local function begin_drag() if shown() then dragging = true; draw_edge() end end
local function in_zone(x)
    local w = mp.get_property_number("osd-width") or 0
    return shown() and x >= w - P - edge_zone() and x < w - P + math.floor(8 * K)
end
-- The grab area is a mouse area of its own input section (windowed mpv would otherwise move the whole window when the left button is dragged there)
local SECT = "strip-edge"
mp.add_key_binding(nil, "strip-edge", function(e)
    if e.event == "down" then begin_drag() elseif e.event == "up" then end_drag() end
end, {complex = true})
mp.commandv("define-section", SECT, "MBTN_LEFT script-binding strip/strip-edge", "force")
mp.commandv("enable-section", SECT, "allow-hide-cursor")
-- Over the panel itself the window must not be dragged either (a drag there is the panel's: reorder rows, drag tabs)
local SECT_PANEL = "strip-panel"
mp.commandv("define-section", SECT_PANEL, "", "force")
mp.commandv("enable-section", SECT_PANEL, "allow-hide-cursor")
update_area = function()
    local w, h = mp.get_property_number("osd-width") or 0, mp.get_property_number("osd-height") or 0
    if shown() and w > P + 50 then
        mp.set_mouse_area(w - P - edge_zone(), 0, w - P + math.floor(8 * K), h, SECT)
        mp.set_mouse_area(w - P + math.floor(8 * K), 0, w, h, SECT_PANEL)
    else
        mp.set_mouse_area(0, 0, 0, 0, SECT)
        mp.set_mouse_area(0, 0, 0, 0, SECT_PANEL)
    end
end
mp.observe_property("mouse-pos", "native", function(_, m)
    if dragging then
        if m and m.x then set_width(m.x) end
        return
    end
    hover = m and m.hover and in_zone(m.x) or false
    draw_edge()
end)
-- test hook: a headless window is never "hovered"
mp.register_script_message("strip-testdrag", function(what, x)
    x = tonumber(x)
    if what == "down" then hover = true; begin_drag() elseif what == "move" then set_width(x) elseif what == "up" then end_drag(); hover = false; draw_edge() end
end)

mp.observe_property("osd-dimensions", "native", function()
    local w = mp.get_property_number("osd-width") or 0
    if not dragging and shown() and w > 0 then   -- the strip follows the width the user chose, as far as this window size allows (never below a floor)
        local lo, hi = limits(w)
        local np = math.max(100, math.floor(math.max(lo, math.min(hi, want_P))))
        if np ~= P then P = np; publish_sizes() end
    end
    update_margin(); draw_edge()
end)
mp.observe_property("fullscreen", "bool", function(_, fs)
    if not fs then sync_window() end
    update_margin()
end)

-- start: bring back the panel that was open (the saved choice; the old playlist-only flag is picked up once)
local want = saved and saved.panel
if saved == nil then
    local old = read_json(dir .. "tabs-state.json")
    if old and old.panel == true then want = "tabs" end
end
mp.set_property_native("user-data/strip/active", "")
if type(want) == "string" and want ~= "" then
    local tries = 0
    local function open_saved()
        tries = tries + 1
        if active ~= "" then return end
        local restored = mp.get_property("user-data/winmem/done") or not mp.get_property("user-data/winmem/present") or tries >= 10   -- window-memory places the window first
        if restored and mp.get_property_number("window-id") and mp.get_property_number("display-hidpi-scale") then
            set_active(want)
        elseif tries < 20 then
            mp.add_timeout(0.3, open_saved)
        end
    end
    mp.add_timeout(0.5, open_saved)
end

mp.register_script_message("strip-dump", function()
    print(string.format("STRIP active=%q widened=%s side=%s P=%d margin=%s extra=%s", active, tostring(widened), side, P,
        tostring(mp.get_property_number("video-margin-ratio-right")), tostring(mp.get_property_native("user-data/strip/extra"))))
end)
