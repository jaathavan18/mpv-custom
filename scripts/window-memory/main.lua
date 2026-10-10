-- Remembers where the mpv window was (position and size, without the playlist panel) and puts it back on the next start.
-- If the saved place is not on any screen, nothing is moved and mpv.conf's geometry stays.
local mp = require 'mp'
local utils = require 'mp.utils'
local sdir = mp.get_script_directory()
local HELPER = mp.get_opt("winmem-helper") or (sdir and utils.join_path(sdir, "winpos.py")) or "winpos.py"
local FILE = mp.command_native({"expand-path", "~~/window-memory.json"})
local TEST = mp.get_opt("winmem-file")      -- tests only: a separate state file
if TEST then FILE = TEST end

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

-- add-on switch: the add-ons panel sets user-data/addons/<name> to "on"/"off"; without the panel everything stays on
local function addon_on(name)
    local v = mp.get_property_native("user-data/addons/" .. name)
    if v then return v ~= "off" end
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if not f then return true end
    local ok, d = pcall(require("mp.utils").parse_json, f:read("*a") or ""); f:close()
    return not (ok and type(d) == "table" and d[name] == false)
end

local function run(...)
    local py = find_python()
    if not py then return nil end
    local args = {py, HELPER, ...}
    return mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = args})
end

local function restore()
    if not addon_on("window") then mp.set_property("user-data/winmem/done", "yes"); return end
    local f = io.open(FILE, "r")
    local pos = f and utils.parse_json(f:read("*a") or "")
    if f then f:close() end
    if pos and pos.l and pos.w then
        local hwnd = mp.get_property_number("window-id")
        local res = run("set", string.format("%d", hwnd), tostring(pos.l), tostring(pos.t), tostring(pos.w), tostring(pos.h))
        if not (res and res.status == 0) then mp.msg.info("saved window place not usable, keeping the default geometry") end
    end
    mp.set_property("user-data/winmem/done", "yes")
end

mp.set_property("user-data/winmem/present", "yes")   -- tells the strip to wait for the window to be placed

local tries = 0
local function start()
    tries = tries + 1
    if mp.get_property_number("window-id") then restore()
    elseif tries < 10 then mp.add_timeout(0.3, start)
    else mp.set_property("user-data/winmem/done", "yes") end
end
mp.add_timeout(0.1, start)

local extra_now = ""   -- the panel part of the window, kept up to date (properties are not reliable while shutting down)
mp.observe_property("user-data/strip/extra", "native", function(_, v) extra_now = type(v) == "string" and v or "" end)

mp.register_event("shutdown", function()
    if not addon_on("window") then return end
    local hwnd = mp.get_property_number("window-id")
    if not hwnd or mp.get_property_native("fullscreen") or mp.get_property_native("window-maximized")
       or mp.get_property_native("window-minimized") then return end
    local res = run("get", string.format("%d", hwnd))
    local l, t, w, h = ((res and res.stdout) or ""):match("(%-?%d+) (%-?%d+) (%d+) (%d+)")
    if not l then return end
    l, t, w, h = tonumber(l), tonumber(t), tonumber(w), tonumber(h)
    local side, extra = extra_now:match("^([RL])(%d+)$")
    if side then
        w = w - tonumber(extra)
        if side == "L" then l = l + tonumber(extra) end
    end
    mp.msg.info("saving window: extra=[" .. extra_now .. "] side=" .. tostring(side) .. " w=" .. w)
    local f = io.open(FILE, "w")
    if f then f:write(utils.format_json({l = l, t = t, w = w, h = h})); f:close() end
end)
