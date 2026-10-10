-- tabs: browser-style playlist tabs in a panel on the right of the mpv window (F6 shows / hides it).
--  * Each tab is its own playlist and remembers its list and the item it was on; switching tabs saves the
--    current one and loads the other (mpv's own watch-later data resumes the position inside the file).
--  * The panel is drawn by mpv inside its own window, in the side strip (script strip: it widens the window, keeps the video
--    out from under the panel and hides in full screen). F6 asks the strip to show or hide this panel.
--  * Tab files: tabs-<id>.json plus tabs-state.json (order, active tab) in the config folder.
local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- Sizes come from the strip (user-data/strip/sizes); these are only the starting values.
local P, TAB_H, ROW_H, FS, K, FOOT, EDGE = 550, 92, 77, 44, 1.5, 109, 12
local function ensure_sizes()
    local z = mp.get_property_native("user-data/strip/sizes")
    if z and z.P then P, TAB_H, ROW_H, FS, K, FOOT, EDGE = z.P, z.TAB_H, z.ROW_H, z.FS, z.K, z.FOOT, z.EDGE or 12 end
end
local function foot_h(h) return FOOT end
local function cw() return FS * 0.38 end   -- average character width
local dir = mp.command_native({"expand-path", mp.get_opt("tabs-dir") or "~~/"})
if not dir:match("[/\\]$") then dir = dir .. "/" end

-- colours (ASS wants BGR)
local C = {bg = "&H000000&", tab = "&H0D0D0D&", tabact = "&H1F1F1F&", list = "&H000000&", sel = "&H2B2B2B&",
           txt = "&HE6E6E6&", dim = "&H9A9A9A&", yel = "&H00D4FF&"}

-- ---------------------------------------------------------------- storage
local function read_json(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return utils.parse_json(s)
end

local function write_json(path, tbl)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    local data = utils.format_json(tbl)
    f:write(data); f:close()
    os.remove(path)               -- os.rename does not overwrite on Windows
    if os.rename(tmp, path) then return true end
    local g = io.open(path, "w")  -- rename lost a race with another window: write in place instead
    if not g then return false end
    g:write(data); g:close(); os.remove(tmp)
    return true
end

local function tab_path(id) return dir .. "tabs-" .. id .. ".json" end
local state_path = dir .. "tabs-state.json"

local tabs, order, active = {}, {}, nil   -- tabs[id] = {id,name,files,index,updated,autoname}
local switching = false
local function is_active() return mp.get_property_native("user-data/strip/active") == "tabs" end
-- add-on switch: the add-ons panel sets user-data/addons/<name> to "on"/"off"; without the panel everything stays on
local function addon_on(name)
    local v = mp.get_property_native("user-data/addons/" .. name)
    if v then return v ~= "off" end
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if not f then return true end
    local ok, d = pcall(utils.parse_json, f:read("*a") or ""); f:close()
    return not (ok and type(d) == "table" and d[name] == false)
end
local function gate(fn) return function(...) if addon_on("tabs") then return fn(...) end end end
local my_pid = mp.get_property_number("pid") or 0
local launch_time = os.time()
local decided = false      -- becomes true once we know whether mpv was started with files or with nothing
local readonly = {}        -- tabs that are open in another window: shown here, never written by this window

local function pid_alive(pid)
    local r = mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
                                 args = {"tasklist", "/FI", "PID eq " .. tostring(pid), "/FO", "CSV", "/NH"}})
    if not r or r.status ~= 0 then return nil end
    return (r.stdout or ""):find('","' .. tostring(pid) .. '"', 1, true) ~= nil
end
local function live_path(pid) return dir .. "tabs-live-" .. pid .. ".json" end

math.randomseed(os.time() + math.floor(mp.get_time() * 1000))
local function new_id() return string.format("%x%04x", os.time(), math.random(0, 0xffff)) end

local function read_tab(id) return read_json(tab_path(id)) or read_json(tab_path(id) .. ".tmp") end
local function tab_exists(id)
    for _, p in ipairs({tab_path(id), tab_path(id) .. ".tmp"}) do
        local f = io.open(p, "r"); if f then f:close(); return true end
    end
    return false
end
local function save_tab(t) write_json(tab_path(t.id), t) end
local closed = {}      -- tabs closed in this window (so a merge with the shared list does not bring them back)
-- Merge tabs created or closed by other windows into our list. Returns true if the list changed.
local function sync_tabs()
    local st = read_json(state_path)
    if not st or type(st.order) ~= "table" then return false end
    local changed, have = false, {}
    for _, id in ipairs(order) do have[id] = true end
    for _, id in ipairs(st.order) do
        if not have[id] and not closed[id] then
            local t = read_tab(id)
            if t and type(t.files) == "table" then tabs[id] = t; order[#order + 1] = id; changed = true end
        end
    end
    for i = #order, 1, -1 do
        local id = order[i]
        if id ~= active and not tab_exists(id) then table.remove(order, i); tabs[id] = nil; changed = true end
    end
    return changed
end
local function save_state()
    sync_tabs()
    local cur = read_json(state_path)
    -- a window with no active tab (opened idle beside another) must not erase the shared "active" tab
    write_json(state_path, {order = order, active = active or (cur and cur.active)})
end

local function load_all()
    tabs, order = {}, {}
    local st = read_json(state_path) or read_json(state_path .. ".tmp")
    if not st or type(st.order) ~= "table" then return end
    for _, id in ipairs(st.order) do
        local t = read_json(tab_path(id)) or read_json(tab_path(id) .. ".tmp")
        if t and type(t.files) == "table" then tabs[id] = t; order[#order + 1] = id end
    end
    active = tabs[st.active] and st.active or order[1]
end

-- ---------------------------------------------------------------- helpers
local function is_remote(p) return p:match("^%a[%w+.-]*://") ~= nil end
local function absolute(p)
    if is_remote(p) or p:match("^%a:[/\\]") or p:match("^[/\\]") then return p end
    return utils.join_path(mp.get_property("working-directory") or "", p)
end
local function base(p) return (p:match("([^/\\]+)$") or p) end
local function folder_name(p)
    if is_remote(p) then return "Playlist" end
    local d = (utils.split_path(p) or ""):gsub("[/\\]+$", "")
    local n = base(d)
    return n ~= "" and n or "Playlist"
end
local function clean(s) return (s:gsub("[\\]", "/"):gsub("[{]", "("):gsub("[}]", ")"):gsub("[\r\n]", " ")) end
local function trunc(s, maxc) if #s > maxc then return s:sub(1, math.max(1, maxc - 1)) .. "…" end return s end

local function snapshot(t)
    local files = {}
    for _, e in ipairs(mp.get_property_native("playlist") or {}) do files[#files + 1] = absolute(e.filename) end
    t.files = files
    t.index = (mp.get_property_number("playlist-pos") or 0) + 1
    if t.index < 1 then t.index = 1 end
    t.updated = os.time()
    if t.autoname and #files > 0 then t.name = folder_name(files[1]); t.autoname = false end
end

local redraw -- forward

local function persist_active()
    local t = tabs[active]
    if not t or switching or not decided or readonly[active] then return end
    snapshot(t); save_tab(t)
end

-- ---------------------------------------------------------------- tab operations
local function load_tab(t)
    switching = true
    local files = t.files
    if #files == 0 then
        mp.commandv("playlist-clear"); mp.commandv("stop")
    else
        local k = math.min(math.max(t.index or 1, 1), #files)
        mp.commandv("script-message-to", "rescan_folder", "rescan-since", tostring(t.updated or 0))
        mp.commandv("loadfile", files[k], "replace")
        for i = 1, k - 1 do mp.commandv("loadfile", files[i], "insert-at", tostring(i - 1)) end
        for i = k + 1, #files do mp.commandv("loadfile", files[i], "append") end
    end
    local tries = 0
    local function settle()
        tries = tries + 1
        local n = mp.get_property_number("playlist-count") or 0
        local pos = mp.get_property_number("playlist-pos") or -1
        local want = #files == 0 and 0 or math.min(math.max(t.index or 1, 1), #files) - 1
        if (n == #files and (#files == 0 or pos == want)) or tries > 40 then
            switching = false; redraw()
        else
            mp.add_timeout(0.1, settle)
        end
    end
    settle()
end

local function switch_to(id)
    if id == active or not tabs[id] then return end
    local cur = tabs[active]
    if cur and not switching and decided and not readonly[active] then
        snapshot(cur); mp.command("write-watch-later-config"); cur.live_pid = nil; save_tab(cur)
    end
    local fresh = read_tab(id)        -- another window may have changed it since we loaded
    if fresh and type(fresh.files) == "table" then tabs[id] = fresh end
    local t = tabs[id]
    readonly[id] = nil
    if t.live_pid and t.live_pid ~= my_pid and pid_alive(t.live_pid) then
        readonly[id] = true
    else
        t.live_pid = my_pid; save_tab(t)
    end
    active = id
    decided = true
    save_state()
    load_tab(t)
    redraw()
end

local function new_tab(name, files, index)
    local t = {id = new_id(), name = name or "New playlist", files = files or {}, index = index or 1,
               updated = os.time(), autoname = (name == nil)}
    tabs[t.id] = t; order[#order + 1] = t.id
    save_tab(t)
    return t
end

local function add_blank_tab()
    local t = new_tab()
    switch_to(t.id)
end

local closed_stack = {}
local function close_tab(id)
    local t = tabs[id]
    if not t then return end
    local pos
    for i, v in ipairs(order) do if v == id then pos = i end end
    if #order == 1 then            -- last tab: empty it instead of removing it
        t.files, t.index, t.name, t.autoname = {}, 1, "New playlist", true
        save_tab(t)
        if id == active then load_tab(t) end
        redraw(); return
    end
    table.remove(order, pos)
    tabs[id] = nil
    closed[id] = true
    os.rename(tab_path(id), tab_path(id) .. ".closed")      -- kept so Ctrl+Shift+T can bring it back
    closed_stack[#closed_stack + 1] = {id = id, pos = pos}
    if id == active then
        active = order[math.min(pos, #order)]
        save_state()
        load_tab(tabs[active])
    else
        save_state()
    end
    redraw()
end

local function reopen_closed()
    while #closed_stack > 0 do
        local c = table.remove(closed_stack)
        local ok = os.rename(tab_path(c.id) .. ".closed", tab_path(c.id))
        local t = ok and read_json(tab_path(c.id))
        if t and type(t.files) == "table" then
            closed[c.id] = nil
            tabs[c.id] = t
            table.insert(order, math.min(c.pos, #order + 1), c.id)
            save_state()
            switch_to(c.id)
            return
        end
    end
    mp.osd_message("No closed tab to reopen", 2)
end

local function close_others()
    local keep = active
    for i = #order, 1, -1 do
        if order[i] ~= keep then close_tab(order[i]) end
    end
end

local function step_tab(d)
    if #order < 2 then return end
    local cur = 1
    for i, id in ipairs(order) do if id == active then cur = i end end
    switch_to(order[(cur - 1 + d) % #order + 1])
end

local function rename_tab(id)
    local t = tabs[id]
    if not t then return end
    local ok, input = pcall(require, 'mp.input')
    if not ok then return end
    input.get({prompt = "Tab name:", default_text = t.name, submit = function(text)
        input.terminate()
        text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then t.name = text; t.autoname = false; save_tab(t); redraw() end
    end})
end

-- ---------------------------------------------------------------- drawing + hit areas
local scroll, selected = 0, nil
local hits = {tabs = {}, rows = {}}
local overlay = mp.create_osd_overlay("ass-events")

local function dims()
    local w = mp.get_property_number("osd-width") or 0
    local h = mp.get_property_number("osd-height") or 0
    return w, h
end

local function shown() return is_active() and not mp.get_property_native("fullscreen") end

local function rect(x1, y1, x2, y2, col)
    return string.format("{\\an7\\pos(0,0)\\bord0\\shad0\\1c%s\\p1}m %d %d l %d %d l %d %d l %d %d{\\p0}",
        col, x1, y1, x2, y1, x2, y2, x1, y2)
end
local function text(x, y, s, col, clip, size)
    return string.format("{\\an7\\pos(%d,%d)\\fnSegoe UI\\fs%d\\bord0\\shad0\\1c%s\\clip(%d,%d,%d,%d)}%s",
        x, y, size or FS, col, clip[1], clip[2], clip[3], clip[4], clip and clean(s) or s)
end

local function row_label(e)
    local n = e.title or e.filename or ""
    return (base(n):gsub("%.%w+$", ""))
end

local function layout()
    local w, h = dims()
    local x0 = w - P
    local rows = math.max(1, math.floor((h - TAB_H - foot_h(h)) / ROW_H))
    return w, h, x0, rows
end

redraw = function()
    ensure_sizes()
    if not shown() then
        overlay:remove()
        hits = {tabs = {}, rows = {}}
        return
    end
    local w, h, x0, rows = layout()
    if w <= P + 50 then overlay:remove(); return end
    overlay.res_x, overlay.res_y = w, h
    hits = {tabs = {}, rows = {}}
    local out = {rect(x0, 0, w, h, C.list), rect(x0, 0, w, TAB_H, C.bg)}

    -- tabs
    local n = #order
    local plus_w = math.floor(FS * 2.4)
    local avail = P - plus_w
    local tw = math.max(math.floor(FS * 3.6), math.min(math.floor(FS * 9), math.floor(avail / math.max(n, 1))))
    local x = x0
    for _, id in ipairs(order) do
        local t = tabs[id]
        local act = (id == active)
        local x2 = math.min(x + tw, w - plus_w)
        out[#out + 1] = rect(x, 0, x2 - 1, TAB_H, act and C.tabact or C.tab)
        if act then out[#out + 1] = rect(x, TAB_H - 3, x2 - 1, TAB_H, C.yel) end
        local maxc = math.floor((tw - FS * 2.8) / cw())
        local ty = math.floor((TAB_H - FS * 1.3) / 2)
        out[#out + 1] = text(x + math.floor(FS * 0.6), ty, trunc(t.name, maxc), act and C.txt or C.dim, {x, 0, x2 - math.floor(FS * 1.5), TAB_H})
        out[#out + 1] = text(x2 - math.floor(FS * 1.35), math.floor((TAB_H - FS * 1.9) / 2), "×", C.dim, {x2 - math.floor(FS * 1.5), 0, x2, TAB_H}, math.floor(FS * 1.45))
        hits.tabs[#hits.tabs + 1] = {x1 = x, x2 = x2, id = id, close_x1 = x2 - math.floor(FS * 1.5)}
        x = x2
    end
    out[#out + 1] = text(x + math.floor(FS * 0.55), math.floor((TAB_H - FS * 1.9) / 2), "+", C.dim, {x, 0, w, TAB_H}, math.floor(FS * 1.45))
    hits.plus = {x1 = x, x2 = w}

    -- list
    local playlist = mp.get_property_native("playlist") or {}
    local count = #playlist
    local cur = (mp.get_property_number("playlist-pos") or -1) + 1
    scroll = math.max(0, math.min(scroll, math.max(0, count - rows)))
    local maxc = math.floor((P - FS * 2.2) / cw())
    local ry = math.floor((ROW_H - FS * 1.3) / 2)
    for r = 1, rows do
        local i = scroll + r
        if i > count then break end
        local y1 = TAB_H + (r - 1) * ROW_H
        local playing, sel = (i == cur), (i == selected)
        if playing or sel then out[#out + 1] = rect(x0, y1, w, y1 + ROW_H, C.sel) end
        out[#out + 1] = text(x0 + math.floor(FS * 0.4), y1 + ry, string.format("%02d", i), playing and C.yel or C.dim, {x0, y1, x0 + math.floor(FS * 1.4), y1 + ROW_H})
        out[#out + 1] = text(x0 + math.floor(FS * 1.5), y1 + ry, trunc(row_label(playlist[i]), maxc), playing and C.yel or C.txt, {x0 + math.floor(FS * 1.4), y1, w, y1 + ROW_H})
        hits.rows[#hits.rows + 1] = {y1 = y1, y2 = y1 + ROW_H, index = i}
    end
    if count == 0 then
        out[#out + 1] = text(x0 + math.floor(FS * 0.9), TAB_H + math.floor(FS * 0.4), "Empty playlist", C.dim, {x0, TAB_H, w, TAB_H + ROW_H})
    end
    out[#out + 1] = rect(x0, h - foot_h(h), w, h, C.bg)
    out[#out + 1] = text(x0 + math.floor(FS * 0.6), h - math.floor(foot_h(h) / 2 + FS * 0.52), string.format("%d items%s", count, (active and readonly[active]) and "  -  open in another window (view only)" or ""), C.dim, {x0, h - foot_h(h), w, h}, math.floor(FS * 0.8))
    overlay.data = table.concat(out, "\n")
    overlay:update()
end

-- ---------------------------------------------------------------- open / close (the strip does the window)
local function toggle()
    if not addon_on("tabs") then return end
    mp.commandv("script-message-to", "strip", "strip-toggle", "tabs")
end

local inside = false
local fake_xy
local function mouse_xy()
    if fake_xy then return fake_xy[1], fake_xy[2] end
    local m = mp.get_property_native("mouse-pos") or {}
    return m.x or -1, m.y or -1
end

local press = nil            -- left button held on something in the panel: {x, y, tab, dragging}
local function tab_at(x, y)
    if y >= TAB_H then return nil end
    for i, t in ipairs(hits.tabs) do if x >= t.x1 and x < t.x2 then return t, i end end
end

local function click_action(x, y)
    local t = tab_at(x, y)
    if t then
        if x >= t.close_x1 then close_tab(t.id) else switch_to(t.id) end
        return
    end
    if hits.plus and x >= hits.plus.x1 and y < TAB_H then add_blank_tab(); return end
    for _, r in ipairs(hits.rows) do
        if y >= r.y1 and y < r.y2 then selected = r.index; redraw(); return end
    end
end

local function left_button(e)
    local x, y = mouse_xy()
    if e.event == "down" then
        local t = tab_at(x, y)
        press = {x = x, y = y, tab = (t and x < t.close_x1) and t.id or nil, dragging = false}
    elseif e.event == "up" then
        local pr = press
        press = nil
        if not pr then return end
        if pr.dragging then save_state() else click_action(pr.x, pr.y) end
    end
end

local function drag_to(x)
    if not press or not press.tab then return end
    if not press.dragging and math.abs(x - press.x) < 14 then return end
    press.dragging = true
    local t, to = tab_at(x, 0)
    if not t or t.id == press.tab then return end
    local from
    for i, id in ipairs(order) do if id == press.tab then from = i end end
    if not from then return end
    table.remove(order, from); table.insert(order, to, press.tab)
    redraw()
end

local function middle_click()
    local x, y = mouse_xy()
    local t = tab_at(x, y)
    if t then close_tab(t.id) end
end

-- keyboard while the mouse is over the panel
local function move_selection(d)
    local count = mp.get_property_number("playlist-count") or 0
    if count == 0 then return end
    local base_i = selected or ((mp.get_property_number("playlist-pos") or 0) + 1)
    selected = math.max(1, math.min(count, base_i + d))
    local _, _, _, rows = layout()
    if selected <= scroll then scroll = selected - 1 elseif selected > scroll + rows then scroll = selected - rows end
    redraw()
end
local function play_selected()
    if selected then mp.commandv("playlist-play-index", tostring(selected - 1)) end
end

local function dblclick()
    local x, y = mouse_xy()
    for _, r in ipairs(hits.rows) do
        if y >= r.y1 and y < r.y2 then
            mp.commandv("playlist-play-index", tostring(r.index - 1)); return
        end
    end
    for _, t in ipairs(hits.tabs) do
        if x >= t.x1 and x < t.x2 and y < TAB_H and x < t.close_x1 then rename_tab(t.id); return end
    end
end

local function rightclick()
    local x, y = mouse_xy()
    for _, t in ipairs(hits.tabs) do
        if x >= t.x1 and x < t.x2 and y < TAB_H then rename_tab(t.id); return end
    end
end

local function wheel(dir_)
    scroll = scroll + dir_ * 3
    redraw()
end

local function delete_selected()
    if selected then
        mp.commandv("playlist-remove", tostring(selected - 1))
        selected = nil
    end
end

local panel_keys = {"tabs-click", "tabs-dbl", "tabs-right", "tabs-mid", "tabs-up", "tabs-down", "tabs-del",
                    "tabs-kup", "tabs-kdown", "tabs-kpgup", "tabs-kpgdn", "tabs-khome", "tabs-kend", "tabs-kenter"}
local function bind(on)
    if on == inside then return end
    inside = on
    if on then
        mp.add_forced_key_binding("MBTN_LEFT", "tabs-click", left_button, {complex = true})
        mp.add_forced_key_binding("MBTN_LEFT_DBL", "tabs-dbl", dblclick)
        mp.add_forced_key_binding("MBTN_RIGHT", "tabs-right", rightclick)
        mp.add_forced_key_binding("MBTN_MID", "tabs-mid", middle_click)
        mp.add_forced_key_binding("WHEEL_UP", "tabs-up", function() wheel(-1) end)
        mp.add_forced_key_binding("WHEEL_DOWN", "tabs-down", function() wheel(1) end)
        mp.add_forced_key_binding("DEL", "tabs-del", delete_selected)
        mp.add_forced_key_binding("UP", "tabs-kup", function() move_selection(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "tabs-kdown", function() move_selection(1) end, {repeatable = true})
        mp.add_forced_key_binding("PGUP", "tabs-kpgup", function() move_selection(-10) end, {repeatable = true})
        mp.add_forced_key_binding("PGDWN", "tabs-kpgdn", function() move_selection(10) end, {repeatable = true})
        mp.add_forced_key_binding("HOME", "tabs-khome", function() move_selection(-100000) end)
        mp.add_forced_key_binding("END", "tabs-kend", function() move_selection(100000) end)
        mp.add_forced_key_binding("ENTER", "tabs-kenter", play_selected)
    else
        for _, n in ipairs(panel_keys) do mp.remove_key_binding(n) end
    end
end

mp.observe_property("mouse-pos", "native", function(_, m)
    if not m or not shown() then press = nil; bind(false); return end
    local w = dims()
    if press and not m.hover then press = nil end                 -- released outside the window: cancel
    bind((m.hover and m.x >= w - P + EDGE) or press ~= nil)
    if press and m.hover then drag_to(m.x) end
end)

-- ---------------------------------------------------------------- events
local save_timer
local function schedule_save()
    if save_timer then save_timer:kill() end
    save_timer = mp.add_timeout(1.0, persist_active)
end

mp.observe_property("playlist", "native", function() schedule_save(); redraw() end)
mp.observe_property("playlist-pos", "number", function()
    local pos = mp.get_property_number("playlist-pos") or 0
    local _, _, _, rows = layout()
    if pos < scroll or pos >= scroll + rows then scroll = math.max(0, pos - math.floor(rows / 2)) end
    schedule_save(); redraw()
end)
mp.observe_property("osd-dimensions", "native", function() redraw() end)
mp.observe_property("fullscreen", "bool", function() redraw() end)
mp.observe_property("user-data/strip/active", "native", function() redraw() end)
local told_min
mp.observe_property("user-data/strip/sizes", "native", function()
    ensure_sizes()
    local m = math.floor(9 * FS)   -- room for the tab row and a row number plus some name
    if m ~= told_min then told_min = m; mp.commandv("script-message-to", "strip", "strip-minwidth", "tabs", tostring(m)) end
    redraw()
end)
mp.register_event("shutdown", function()
    local t = tabs[active]
    if t and decided and not switching and not readonly[active] then snapshot(t) end
    if t and t.live_pid == my_pid then t.live_pid = nil end
    if t and not readonly[active] then save_tab(t) end
    os.remove(live_path(my_pid))
end)

-- mpv only stores a file's position when mpv quits. Store it whenever a file is left (next/previous, clicking a row,
-- switching tabs) so coming back resumes there. A finished file (or the last few seconds) is forgotten instead.
mp.add_hook("on_unload", 50, function()
    local pos, dur = mp.get_property_number("time-pos"), mp.get_property_number("duration")
    if not pos or not mp.get_property("path") then return end
    if mp.get_property_native("eof-reached") or (dur and pos > dur - 5) then
        mp.command("delete-watch-later-config")
    else
        mp.command("write-watch-later-config")
    end
end)

mp.add_key_binding("F6", "toggle", toggle)
mp.add_key_binding("Ctrl+TAB", "next-tab", gate(function() step_tab(1) end))
mp.add_key_binding("Ctrl+Shift+TAB", "prev-tab", gate(function() step_tab(-1) end))
mp.add_key_binding("Ctrl+t", "new-tab", gate(add_blank_tab))
mp.add_key_binding("Ctrl+w", "close-tab", gate(function() if active then close_tab(active) end end))
mp.add_key_binding("Ctrl+T", "reopen-tab", gate(reopen_closed))
mp.add_key_binding("Ctrl+W", "close-other-tabs", gate(close_others))
mp.add_periodic_timer(2, function() if sync_tabs() then redraw() end end)

-- ---------------------------------------------------------------- startup
-- Started with a file (double-click, drag onto exe): it gets its own new tab and nothing is resumed.
-- Started with no file: the first window resumes the last active tab; any later window shows the saved tabs
-- but plays nothing (the first window is already playing them) until a tab is clicked.
write_json(live_path(my_pid), {pid = my_pid, started = launch_time})
load_all()
if #order == 0 then
    local t = new_tab()
    active = t.id
    save_state()
end

local function is_first()
    for _, name in ipairs(utils.readdir(dir, "files") or {}) do
        local p = name:match("^tabs%-live%-(%d+)%.json$")
        if p and tonumber(p) ~= my_pid then
            local d = read_json(dir .. name)
            if d and pid_alive(d.pid) then
                if d.started < launch_time or (d.started == launch_time and d.pid < my_pid) then return false end
            else
                os.remove(dir .. name)
            end
        end
    end
    return true
end

local function decide_files()
    if decided then return end
    decided = true
    local t = tabs[active]
    if not (t and #t.files == 0 and t.autoname) then t = new_tab() end   -- reuse an empty tab
    snapshot(t)
    t.autoname = false
    t.live_pid = my_pid
    save_tab(t)
    active = t.id
    save_state()
    redraw()
end

local function decide_idle()
    mp.add_timeout(0.3, function()               -- lets windows started together see each other
        if decided or (mp.get_property_number("playlist-count") or 0) > 0 then return end
        decided = true
        if is_first() then
            local t = tabs[active]
            if t then t.live_pid = my_pid; save_tab(t); load_tab(t) end
        else
            active = nil
        end
        redraw()
    end)
end

mp.register_event("file-loaded", decide_files)
mp.observe_property("idle-active", "bool", function(_, idle)
    if idle and not decided and (mp.get_property_number("playlist-count") or 0) == 0 then decide_idle() end
end)

-- Files dropped on the window are appended to the current playlist instead of replacing it.
mp.set_property("drag-and-drop", "append")
mp.observe_property("playlist-count", "number", function(_, n)
    if not decided or switching or not n or n == 0 then return end
    if not active then
        local t = new_tab(); t.live_pid = my_pid; save_tab(t); active = t.id; save_state()
    end
    if mp.get_property_native("idle-active") then mp.commandv("playlist-play-index", "0") end
end)

-- Ctrl+V: add file paths or links from the clipboard to the playlist.
local function add_lines(clip)
    local n = 0
    for line in (clip or ""):gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub('^"(.*)"$', "%1")
        if line ~= "" and (is_remote(line) or utils.file_info(line)) then
            mp.commandv("loadfile", line, "append"); n = n + 1
        end
    end
    mp.osd_message(n > 0 and string.format("Added %d to the playlist", n) or "Clipboard has no file path or link")
    return n
end
mp.add_key_binding("Ctrl+v", "paste", gate(function() add_lines(mp.get_property("clipboard/text")) end))
mp.register_script_message("tabs-add", function(text) add_lines(text) end)

-- test / debug hooks
mp.register_script_message("tabs-new", function() add_blank_tab() end)
mp.register_script_message("tabs-switch", function(i) switch_to(order[tonumber(i)]) end)
mp.register_script_message("tabs-close", function(i) close_tab(order[tonumber(i)]) end)
mp.register_script_message("tabs-dump", function()
    local o = {}
    for i, id in ipairs(order) do
        local t = tabs[id]
        o[#o + 1] = string.format("%d:%s%s files=%d idx=%d", i, t.name, id == active and "*" or "", #t.files, t.index or 0)
    end
    print("TABS " .. table.concat(o, " | ") .. string.format(" || active=%s ro=%s decided=%s playlist=%d pos=%s", tostring(active and tabs[active] and tabs[active].name), tostring(active and readonly[active]), tostring(decided), mp.get_property_number("playlist-count") or 0, tostring(mp.get_property_number("playlist-pos"))))
end)
mp.register_script_message("tabs-toggle", toggle)
-- switched off: close the playlist if it is the panel on show
mp.observe_property("user-data/addons/tabs", "native", function()
    if not addon_on("tabs") and is_active() then mp.commandv("script-message-to", "strip", "strip-close", "tabs") end
end)

mp.register_script_message("tabs-rename", function(i, name) local t = tabs[order[tonumber(i)]]; if t then t.name = name; t.autoname = false; save_tab(t); redraw() end end)
mp.register_script_message("tabs-hits", function()
    local o = {}
    for i, t in ipairs(hits.tabs) do o[#o + 1] = string.format("%d:%d-%d:%s", i, t.x1, t.x2, tabs[t.id] and tabs[t.id].name or "?") end
    local on = {}; for _, id in ipairs(order) do on[#on+1] = tabs[id].name end; local ww, hh = layout(); print("HITS w=" .. tostring(ww) .. " shown=" .. tostring(shown()) .. " P=" .. P .. " order=" .. table.concat(on, ",") .. " " .. table.concat(o, " ") .. " TAB_H=" .. TAB_H .. " ROW_H=" .. ROW_H)
end)
mp.register_script_message("tabs-reopen", reopen_closed)
-- test hook: act as if the mouse did <what> at x,y (the headless test window is never "hovered")
mp.register_script_message("tabs-testmouse", function(what, x, y)
    fake_xy = {tonumber(x), tonumber(y)}
    if what == "down" or what == "up" then left_button({event = what})
    elseif what == "move" then drag_to(fake_xy[1])
    elseif what == "mid" then middle_click() end
end)
