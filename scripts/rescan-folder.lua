-- rescan-folder.lua
-- Every time a file starts playing (open, n, p, >, <, end of file), look at its folder again and add
-- video files that appeared since the last look to the playlist, sorted into place.
--  * The first look at a folder only records what is there (mpv's own autocreate-playlist already added it).
--    Exception: after a saved session was restored, files newer than that session are added (they arrived while mpv was closed).
--  * Later looks add only files that are new, so items you removed or never added are not forced back in.
--  * Files younger than MIN_AGE seconds are skipped (they may still be copying) and picked up on a later look.
--  * ".partial." files (unfinished conversions) are ignored.
local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local EXT = {mkv = true, mp4 = true, m4v = true, avi = true, mov = true, webm = true, ts = true,
             m2ts = true, wmv = true, flv = true, mpg = true, mpeg = true}
local MIN_AGE = 10
local seen = {} -- normalised directory -> set of normalised file paths already considered
local since = nil -- set by remember-session.lua after a restore: time the restored session was last saved

local function is_remote(p) return p:match("^%a[%w+.-]*://") ~= nil end

local function absolute(p)
    if is_remote(p) or p:match("^%a:[/\\]") or p:match("^[/\\]") then return p end
    return utils.join_path(mp.get_property("working-directory") or "", p)
end

local function norm(p) return (p:gsub("\\", "/"):lower()) end

-- natural sort key: digit runs are zero-padded so ep2 < ep10
local function key(s)
    return (s:lower():gsub("%d+", function(d) return ("0"):rep(math.max(0, 12 - #d)) .. d end))
end

local function rescan()
    local path = mp.get_property("path")
    if not path or is_remote(path) then return end
    local dir = utils.split_path(absolute(path))
    local entries = utils.readdir(dir, "files")
    if not entries then return end

    local ndir = norm(dir)
    local first = seen[ndir] == nil
    local set = seen[ndir] or {}
    seen[ndir] = set

    local inlist = {}
    for _, e in ipairs(mp.get_property_native("playlist") or {}) do inlist[norm(absolute(e.filename))] = true end

    local fresh = {}
    for _, name in ipairs(entries) do
        local ext = name:match("%.([^.]+)$")
        if ext and EXT[ext:lower()] and not name:lower():find(".partial.", 1, true) then
            local full = utils.join_path(dir, name)
            local n = norm(full)
            local is_new_since_session = false
            if first and not inlist[n] and since then
                local info = utils.file_info(full)
                is_new_since_session = info ~= nil and info.mtime > since
            end
            if (first and not is_new_since_session) or inlist[n] then
                set[n] = true
            elseif not set[n] then
                local info = utils.file_info(full)
                if info and os.time() - info.mtime >= MIN_AGE then
                    fresh[#fresh + 1] = {name = name, full = full}
                    set[n] = true
                end
            end
        end
    end

    table.sort(fresh, function(a, b) return key(a.name) < key(b.name) end)
    for _, f in ipairs(fresh) do
        local pl = mp.get_property_native("playlist") or {}
        local at, k = #pl, key(f.name)
        for i, e in ipairs(pl) do
            local d, base = utils.split_path(absolute(e.filename))
            if norm(d) == ndir and key(base) > k then at = i - 1; break end
        end
        mp.commandv("loadfile", f.full, "insert-at", tostring(at))
        msg.info("rescan: added " .. f.name)
    end
end

mp.register_event("file-loaded", rescan)

-- n / p / > / < in input.conf call these so the folder is looked at BEFORE moving. Without this,
-- pressing n on the last item (or p on the first) does nothing and never triggers a rescan.
mp.register_script_message("rescan-folder-next", function() rescan(); mp.commandv("playlist-next") end)
mp.register_script_message("rescan-folder-prev", function() rescan(); mp.commandv("playlist-prev") end)

mp.register_script_message("rescan-since", function(t) since = tonumber(t) end)
