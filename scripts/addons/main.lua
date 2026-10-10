-- addons: a panel (F7) that looks like the playlist panel and switches the add-ons on and off.
--  * F7 opens / closes it. It is a panel of the side strip (script strip): the strip widens the window; F6 shows the playlist in the same strip.
--  * Click a row or press Enter to switch an add-on. The choice is kept in addons-state.json and read by the add-ons themselves
--    (user-data/addons/<id> = "on" | "off"; an add-on with no panel installed is simply on).
--  * "Actions" are one-click resets of what some add-ons remember.
local mp = require 'mp'
local utils = require 'mp.utils'

local STATE = mp.command_native({"expand-path", mp.get_opt("addons-state") or "~~/addons-state.json"})

-- every add-on we know, with the script that provides it; only the ones found in the scripts folder are listed
local KNOWN = {
    {id = "tabs",     name = "Playlist panel (F6)",                     files = {"tabs"}},
    {id = "letters",  name = "VLC letter keys (a-z)",                   files = {"vlc-keys"}},
    {id = "stoprs",   name = "Stop, then Space resumes (s)",            files = {"vlc-keys"}},
    {id = "window",   name = "Window memory",                           files = {"window-memory"}},
    {id = "subtitle", name = "Subtitle track number",                   files = {"sub-track-memory"}},
    {id = "volume",   name = "Saved volume",                            files = {"save-volume"}},
    {id = "chapters", name = "Chapter keys (Shift+N / Shift+P)",        files = {"chapter-step"}},
    {id = "bar",      name = "Bottom bar always visible (windowed)",    files = {"osc-always-windowed"}},
}
local ADDONS, registered = {}, {}
local function installed(files)
    local dir = mp.command_native({"expand-path", "~~/scripts"})
    local have = {}
    for _, n in ipairs(utils.readdir(dir, "all") or {}) do have[(n:gsub("%.lua$", ""))] = true end
    for _, f in ipairs(files) do if have[f] then return true end end
end
local function detect()
    ADDONS = {}
    local seen = {}
    for _, k in ipairs(KNOWN) do
        if installed(k.files) then ADDONS[#ADDONS + 1] = k; seen[k.id] = true end
    end
    for _, k in ipairs(registered or {}) do if not seen[k.id] then ADDONS[#ADDONS + 1] = k end end
end
local ACTIONS = {
    {id = "reset-window", name = "Reset the saved window place"},
    {id = "reset-sub",    name = "Forget the subtitle track number"},
    {id = "reset-volume", name = "Forget the saved volume"},
}

-- ---------------------------------------------------------------- state
local state = {}
do
    local f = io.open(STATE, "r")
    if f then
        local d = utils.parse_json(f:read("*a") or ""); f:close()
        if type(d) == "table" then state = d end
    end
end
local function is_on(id) return state[id] ~= false end
local function publish(id) mp.set_property("user-data/addons/" .. id, is_on(id) and "on" or "off") end
local function save()
    local f = io.open(STATE, "w")
    if f then f:write(utils.format_json(state)); f:close() end
end

-- ---------------------------------------------------------------- items shown
local items = {}
local function build_items()
    detect()
    items = {}
    for _, a in ipairs(ADDONS) do items[#items + 1] = {kind = "toggle", id = a.id, name = a.name} end
    items[#items + 1] = {kind = "label", name = "Actions"}
    for _, a in ipairs(ACTIONS) do items[#items + 1] = {kind = "action", id = a.id, name = a.name} end
    for _, a in ipairs(ADDONS) do publish(a.id) end
end

local visible = false
local redraw_hook
local notice, notice_timer = nil, nil
local function tell(msg)
    notice = msg
    if notice_timer then notice_timer:kill() end
    notice_timer = mp.add_timeout(3, function() notice = nil; if visible then redraw_hook() end end)
end

local function run_action(id)
    local function rm(name) os.remove(mp.command_native({"expand-path", "~~/" .. name})) end
    if id == "reset-window" then rm("window-memory.json"); tell("Saved window place forgotten")
    elseif id == "reset-sub" then mp.commandv("script-message", "subtrack-reset"); tell("Subtitle track number forgotten")
    elseif id == "reset-volume" then rm("volume.state"); tell("Saved volume forgotten") end
end

-- ---------------------------------------------------------------- look (same constants as the playlist panel)
local C = {bg = "&H000000&", list = "&H000000&", sel = "&H2B2B2B&", txt = "&HE6E6E6&", dim = "&H9A9A9A&", yel = "&H00D4FF&"}
local function sizes()
    local s = mp.get_property_native("user-data/strip/sizes")
    if s and s.P then return s end
    local k = mp.get_property_number("display-hidpi-scale") or 1.5
    local fs = math.floor(22 * k + 0.5)
    return {P = math.floor(26 * k * 12.5), FS = fs, TAB_H = math.floor(fs * 2.3), ROW_H = math.floor(fs * 1.85), K = k, FOOT = math.floor(72.5 * k)}
end
local overlay = mp.create_osd_overlay("ass-events")
local function clean(s) return (s:gsub("[\\]", "/"):gsub("[{]", "("):gsub("[}]", ")"):gsub("[\r\n]", " ")) end
local function rect(x1, y1, x2, y2, col)
    return string.format("{\\an7\\pos(0,0)\\bord0\\shad0\\1c%s\\p1}m %d %d l %d %d l %d %d l %d %d{\\p0}", col, x1, y1, x2, y1, x2, y2, x1, y2)
end
local function text(x, y, s, col, size, right)
    return string.format("{\\an%d\\pos(%d,%d)\\fnSegoe UI\\fs%d\\bord0\\shad0\\1c%s}%s", right and 9 or 7, x, y, size, col, clean(s))
end

-- ---------------------------------------------------------------- panel state
local selected, hits, top = 1, {}, 1

local function dims() return mp.get_property_number("osd-width") or 0, mp.get_property_number("osd-height") or 0 end

local function redraw()
    if not visible or mp.get_property_native("fullscreen") then overlay:remove(); return end
    local z = sizes()
    local w, h = dims()
    if w <= z.P + 50 then overlay:remove(); return end
    local x0 = w - z.P
    local FS = z.FS
    overlay.res_x, overlay.res_y = w, h
    hits = {}
    local out = {rect(x0, 0, w, h, C.list), rect(x0, 0, w, z.TAB_H, C.bg)}
    out[#out + 1] = text(x0 + math.floor(FS * 0.9), math.floor((z.TAB_H - FS * 1.3) / 2), "Add-ons", C.txt, FS)
    out[#out + 1] = text(w - math.floor(FS * 0.9), math.floor((z.TAB_H - FS * 1.3) / 2), "F7 closes", C.dim, math.floor(FS * 0.8), true)
    local rows = math.max(1, math.floor((h - z.TAB_H - z.FOOT) / z.ROW_H))
    if selected < top then top = selected end
    if selected > top + rows - 1 then top = selected - rows + 1 end
    top = math.max(1, math.min(top, math.max(1, #items - rows + 1)))
    local ry = math.floor((z.ROW_H - FS * 1.3) / 2)
    for i = top, math.min(#items, top + rows - 1) do
        local it = items[i]
        local y1 = z.TAB_H + (i - top) * z.ROW_H
        if it.kind == "label" then
            out[#out + 1] = text(x0 + math.floor(FS * 0.9), y1 + ry + math.floor(FS * 0.1), it.name, C.dim, math.floor(FS * 0.8))
        else
            if i == selected then out[#out + 1] = rect(x0, y1, w, y1 + z.ROW_H, C.sel) end
            local maxc = math.max(6, math.floor((z.P - FS * 5.5) / (FS * 0.45)))
            local nm = #it.name > maxc and it.name:sub(1, maxc - 1) .. "…" or it.name
            out[#out + 1] = text(x0 + math.floor(FS * 0.9), y1 + ry, nm, C.txt, FS)
            if it.kind == "toggle" then
                local on = is_on(it.id)
                out[#out + 1] = text(w - math.floor(FS * 0.9), y1 + ry, on and "ON" or "OFF", on and C.yel or C.dim, FS, true)
            else
                out[#out + 1] = text(w - math.floor(FS * 0.9), y1 + ry, "Reset", C.dim, FS, true)
            end
            hits[#hits + 1] = {y1 = y1, y2 = y1 + z.ROW_H, index = i}
        end
    end
    out[#out + 1] = rect(x0, h - z.FOOT, w, h, C.bg)
    out[#out + 1] = text(x0 + math.floor(FS * 0.6), h - math.floor(z.FOOT / 2 + FS * 0.52), notice or "Click or Enter: switch on / off", notice and C.yel or C.dim, math.floor(FS * 0.8))
    overlay.data = table.concat(out, "\n")
    overlay:update()
end
redraw_hook = redraw

local last_toggle = {}
local function activate(i)
    local it = items[i]
    if not it or it.kind == "label" then return end
    selected = i
    if it.kind == "toggle" then
        local now = mp.get_time()
        if last_toggle[it.id] and now - last_toggle[it.id] < 0.25 then return end   -- a double-click must not switch twice
        last_toggle[it.id] = now
        state[it.id] = not is_on(it.id)
        if state[it.id] == true then state[it.id] = nil end
        publish(it.id); save()
    else
        run_action(it.id)
    end
    redraw()
end

local function move(d)
    local i = selected
    repeat i = i + d until i < 1 or i > #items or items[i].kind ~= "label"
    if i >= 1 and i <= #items then selected = i; redraw() end
end

-- ---------------------------------------------------------------- mouse and keys (only while the mouse is over the panel)
local fake_xy
local function mouse_xy()
    if fake_xy then return fake_xy[1], fake_xy[2] end
    local m = mp.get_property_native("mouse-pos") or {}
    return m.x or -1, m.y or -1
end
local function click()
    local x, y = mouse_xy()
    for _, r in ipairs(hits) do
        if y >= r.y1 and y < r.y2 then activate(r.index); return end
    end
end
local keys = {"addons-click", "addons-dbl", "addons-up", "addons-down", "addons-enter", "addons-wup", "addons-wdown"}
local bound = false
local function bind(on)
    if on == bound then return end
    bound = on
    if on then
        mp.add_forced_key_binding("MBTN_LEFT", "addons-click", click)
        mp.add_forced_key_binding("MBTN_LEFT_DBL", "addons-dbl", function() end)
        mp.add_forced_key_binding("UP", "addons-up", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "addons-down", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("ENTER", "addons-enter", function() activate(selected) end)
        mp.add_forced_key_binding("WHEEL_UP", "addons-wup", function() top = math.max(1, top - 1); redraw() end)
        mp.add_forced_key_binding("WHEEL_DOWN", "addons-wdown", function() top = top + 1; redraw() end)
    else
        for _, n in ipairs(keys) do mp.remove_key_binding(n) end
    end
end
mp.observe_property("mouse-pos", "native", function(_, m)
    if not visible or not m or mp.get_property_native("fullscreen") then bind(false); return end
    local z = sizes()
    local w = dims()
    bind(m.hover and m.x >= w - z.P + (z.EDGE or 12))
end)

-- ---------------------------------------------------------------- open / close (the strip does the window)
local function show_now()
    if visible then return end
    build_items()
    visible = true
    mp.add_timeout(0.3, redraw)    -- the window finishes widening first
    redraw()
end
local function hide_now() if visible then visible = false; bind(false); overlay:remove() end end
mp.add_key_binding("F7", "toggle", function() mp.commandv("script-message-to", "strip", "strip-toggle", "addons") end)
mp.observe_property("user-data/strip/active", "native", function(_, v) if v == "addons" then show_now() else hide_now() end end)
mp.observe_property("fullscreen", "bool", function() if visible then redraw() end end)
mp.observe_property("osd-dimensions", "native", function() if visible then redraw() end end)
local told_min
mp.observe_property("user-data/strip/sizes", "native", function()
    local m = math.floor(10 * sizes().FS)   -- room for a short name and ON / OFF
    if m ~= told_min then told_min = m; mp.commandv("script-message-to", "strip", "strip-minwidth", "addons", tostring(m)) end
    if visible then redraw() end
end)
-- another add-on can announce itself: script-message addons-register <id> <name>  (it then reads user-data/addons/<id>)
mp.register_script_message("addons-register", function(id, name)
    if not id or not name then return end
    for _, k in ipairs(registered) do if k.id == id then return end end
    registered[#registered + 1] = {id = id, name = name}
    build_items(); if visible then redraw() end
end)
build_items()

-- ---------------------------------------------------------------- test hooks (a headless window is never "hovered")
mp.register_script_message("addons-testclick", function(x, y) fake_xy = {tonumber(x), tonumber(y)}; click() end)
mp.register_script_message("addons-testkey", function(k)
    if k == "down" then move(1) elseif k == "up" then move(-1) elseif k == "enter" then activate(selected) end
end)
mp.register_script_message("addons-dump", function()
    local o = {}
    for _, a in ipairs(ADDONS) do o[#o + 1] = a.id .. "=" .. (is_on(a.id) and "on" or "off") end
    print("ADDONS visible=" .. tostring(visible) ..  " | " .. table.concat(o, " "))
end)
