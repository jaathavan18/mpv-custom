-- intro-skip: skips the opening and the ending song of anime and TV episodes by itself. No chapters needed.
--  * It listens to each episode in the playlist (same folder) with ffmpeg + chromaprint, compares the episodes with each other and finds
--    the stretches that are the same in them. One in the first part of the episode is the opening, one in the last part is the ending.
--    Repeats in the middle (eyecatches, insert songs) are ignored.
--  * The times are kept in intro-skip.json (fingerprints in intro-skip-*.fp), so a folder is analysed once.
--  * When playback reaches the opening or ending it jumps to its end (a little early on purpose) and says so. What comes after the ending
--    song (a scene after the credits, a preview) still plays. Alt+I undoes the skip.
--  * A file with no match is left alone. It needs ffmpeg with chromaprint: ffmpeg.exe next to mpv.exe, on the PATH, or the path in
--    script-opts `introskip-ffmpeg=...`.
local mp = require 'mp'
local utils = require 'mp.utils'
local okbit, bitlib = pcall(require, "bit")
if not okbit then bitlib = bit32 end
local bxor, band, rshift = bitlib.bxor, bitlib.band, bitlib.rshift

local ITEM = 0.1238          -- seconds per fingerprint item (chromaprint)
local WINDOW = 2.0           -- how far past its last matching item the opening ends (measured on test episodes)
local REGION = 0.4           -- an opening lies in the first 40% of an episode, an ending in the last 40%
local MIN_S, MAX_S = 15, 150 -- an opening is between these lengths
local BRIDGE_S = 10          -- a different bit shorter than this inside the opening does not split it
local EARLY = 3.0            -- land this many seconds before the end of the opening
local S_LATE = 3.0           -- skip starts this many seconds after the opening starts to play
local ED_LATE, ED_EARLY = 3.0, 3.0   -- same for the ending: start 3 s into it, land 3 s before its end
local PEERS_MAX = 12         -- episodes compared at once
local DIST = 9               -- bits (of 32) that may differ, averaged over about a second
local MIN_FRAC = 0.6         -- share of the matched stretch that really matches

local dir = mp.command_native({"expand-path", "~~/"})
if not dir:match("[/\\]$") then dir = dir .. "/" end
local RESULTS = dir .. "intro-skip.json"

-- add-on switch: the add-ons panel sets user-data/addons/<name> to "on"/"off"; without the panel everything stays on
local function addon_on(name)
    local v = mp.get_property_native("user-data/addons/" .. name)
    if v then return v ~= "off" end
    local f = io.open(mp.command_native({"expand-path", "~~/addons-state.json"}), "r")
    if not f then return true end
    local ok, d = pcall(utils.parse_json, f:read("*a") or ""); f:close()
    return not (ok and type(d) == "table" and d[name] == false)
end
local function say(text) mp.osd_message(text, 2.5) end
local function log(...) print("[introskip] " .. string.format(...)) end

-- ---------------------------------------------------------------- files and keys
local function is_local(p) return p and not p:find("^%a[%w+.-]*://") end
local function file_key(p)
    local info = utils.file_info(p)
    if not info then return nil end
    return (p:gsub("\\", "/"):lower()) .. "|" .. tostring(info.size)
end
local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end
local function fp_path(key) return dir .. "intro-skip-" .. hash(key .. "|full") .. ".fp" end
local function exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end end

local results = {}   -- key -> {s=, e=, n=} or {none=true, n=}
local function load_results()
    local f = io.open(RESULTS, "r")
    if not f then return end
    local ok, d = pcall(utils.parse_json, f:read("*a") or ""); f:close()
    if ok and type(d) == "table" then
        for k, v in pairs(d) do if type(k) == "string" and type(v) == "table" then results[k] = v end end   -- copy: an empty parsed list is an "array"
    end
end
local function save_results()
    local f = io.open(RESULTS .. ".tmp", "w")
    if not f then return end
    f:write(utils.format_json(results)); f:close()
    os.remove(RESULTS); os.rename(RESULTS .. ".tmp", RESULTS)
end
load_results()

-- ---------------------------------------------------------------- ffmpeg
local ffmpeg   -- nil = not looked for yet, false = not found
local function find_ffmpeg(cb)
    if ffmpeg ~= nil then cb(ffmpeg); return end
    local list = {}
    local o = mp.get_opt("introskip-ffmpeg")
    if o and o ~= "" then list[#list + 1] = o end
    list[#list + 1] = mp.command_native({"expand-path", "~~exe_dir/ffmpeg.exe"})
    list[#list + 1] = "ffmpeg"
    local i = 0
    local function try()
        i = i + 1
        if i > #list then ffmpeg = false; cb(false); return end
        mp.command_native_async({name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
                                 args = {list[i], "-hide_banner", "-muxers"}}, function(ok, res)
            if ok and res and res.status == 0 and (res.stdout or ""):find("chromaprint", 1, true) then ffmpeg = list[i]; cb(ffmpeg)
            else try() end
        end)
    end
    try()
end

local function fingerprint(path, key, cb)
    local out = fp_path(key)
    if exists(out) then cb(true); return end
    mp.command_native_async({name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
        args = {ffmpeg, "-v", "error", "-y", "-i", path, "-map", "0:a:0", "-ac", "1", "-ar", "11025",
                "-f", "chromaprint", "-fp_format", "raw", out}}, function(ok, res)
        if ok and res and res.status == 0 and exists(out) then cb(true)
        else os.remove(out); cb(false) end
    end)
end

local function read_fp(key)
    local f = io.open(fp_path(key), "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    local a = {}
    for i = 1, #s - 3, 4 do
        local b1, b2, b3, b4 = s:byte(i, i + 3)
        a[#a + 1] = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end
    return a
end

-- ---------------------------------------------------------------- comparing two fingerprints
local POP = {}
for i = 0, 255 do local c, v = 0, i; while v > 0 do c = c + v % 2; v = math.floor(v / 2) end; POP[i] = c end
local function dist(a, b)
    local x = bxor(a, b)
    return POP[band(x, 255)] + POP[band(rshift(x, 8), 255)] + POP[band(rshift(x, 16), 255)] + POP[band(rshift(x, 24), 255)]
end

-- the shifts (A index = B index + d) at which the two share most 8-bit pieces: cheap candidates, checked properly afterwards
local function shifts(A, B)
    local idx = {{}, {}, {}, {}}
    for i = 1, #A do
        local v = A[i]
        for k = 0, 3 do
            local c = band(rshift(v, 8 * k), 255)
            local t = idx[k + 1][c]
            if not t then t = {}; idx[k + 1][c] = t end
            t[#t + 1] = i
        end
    end
    local votes = {}
    for j = 1, #B do
        local v = B[j]
        for k = 0, 3 do
            local lst = idx[k + 1][band(rshift(v, 8 * k), 255)]
            if lst and #lst <= 128 then
                for n = 1, #lst do local d = lst[n] - j; votes[d] = (votes[d] or 0) + 1 end
            end
        end
    end
    local all = {}
    for d, c in pairs(votes) do all[#all + 1] = {d = d, c = c} end
    table.sort(all, function(x, y) return x.c > y.c end)
    local top = {}
    for n = 1, math.min(6, #all) do top[#top + 1] = all[n].d end
    return top
end

-- the matching stretches at one shift, short different bits bridged: each is {bs, be} (items of B) with the share that truly matches
local function stretches(A, B, d)
    local jlo, jhi = math.max(1, 1 - d), math.min(#B, #A - d)
    if jhi - jlo < 20 then return {} end
    local dd = {}
    for j = jlo, jhi do dd[j] = dist(A[j + d], B[j]) end
    local good = {}
    for j = jlo, jhi do
        local s, n = 0, 0
        for q = math.max(jlo, j - 3), math.min(jhi, j + 4) do s = s + dd[q]; n = n + 1 end
        good[j] = (s / n) <= DIST
    end
    local gap = math.floor(BRIDGE_S / ITEM)
    local out, rs, last, cnt = {}, nil, nil, 0
    local SOLID = 16   -- a stretch really starts (ends) where about 2 seconds in a row match: chance matches next to it do not count
    local function solid(j)
        for q = j, j + SOLID - 1 do if not good[q] then return false end end
        return true
    end
    local function close()
        if rs then
            local a, z = rs, last
            while a <= z - SOLID + 1 and not solid(a) do a = a + 1 end
            while z >= a + SOLID - 1 and not solid(z - SOLID + 1) do z = z - 1 end
            if z - a + 1 >= SOLID and (z - a) * ITEM + WINDOW >= MIN_S then
                local n = 0
                for j = a, z do if good[j] then n = n + 1 end end
                if n / (z - a + 1) >= MIN_FRAC then out[#out + 1] = {bs = a, be = z} end
            end
        end
        rs = nil
    end
    for j = jlo, jhi do
        if good[j] then
            if not rs then rs, cnt = j, 0 end
            last = j; cnt = cnt + 1
        elseif rs and j - last > gap then close() end
    end
    close()
    return out
end

-- every stretch A and B have in common, in seconds of each: list of {a = {s, e}, b = {s, e}}
local function common(A, B)
    local found = {}
    for _, d in ipairs(shifts(A, B)) do
        for _, r in ipairs(stretches(A, B, d)) do
            local len = (r.be - r.bs) * ITEM + WINDOW
            if len >= MIN_S and len <= MAX_S then
                found[#found + 1] = {a = {(r.bs + d - 1) * ITEM, (r.be + d - 1) * ITEM + WINDOW},
                                     b = {(r.bs - 1) * ITEM, (r.be - 1) * ITEM + WINDOW}, len = len}
            end
        end
    end
    local out = {}   -- neighbouring shifts find the same stretch: keep the longest
    table.sort(found, function(x, y) return x.len > y.len end)
    for _, f in ipairs(found) do
        local dup
        for _, o in ipairs(out) do
            local lo, hi = math.max(f.a[1], o.a[1]), math.min(f.a[2], o.a[2])
            if hi - lo >= 0.6 * math.min(f.len, o.len) then dup = true; break end
        end
        if not dup then out[#out + 1] = f end
    end
    return out
end

-- one episode: the interval most of its partners agree on
local function choose(cands)
    local best, bestscore
    for _, c in ipairs(cands) do
        local score, group = 0, {}
        for _, o in ipairs(cands) do
            local lo, hi = math.max(c.s, o.s), math.min(c.e, o.e)
            local shorter = math.min(c.e - c.s, o.e - o.s)
            if hi - lo >= 0.6 * shorter then score = score + 1; group[#group + 1] = o end
        end
        if not best or score > bestscore or (score == bestscore and c.e - c.s > best.c.e - best.c.s) then best, bestscore = {c = c, group = group}, score end
    end
    if not best then return nil end
    local ss, ee = {}, {}
    for _, g in ipairs(best.group) do ss[#ss + 1] = g.s; ee[#ee + 1] = g.e end
    table.sort(ss); table.sort(ee)
    return {s = ss[math.ceil(#ss / 2)], e = ee[math.ceil(#ee / 2)]}
end

-- ---------------------------------------------------------------- analysing a folder
local busy = false
local current   -- {s=, e=} for the file that is playing
local undo_pos
local zone   -- per episode: how often the opening / ending was skipped and whether the skip is ready
local function refresh_current() end   -- defined below

local function analyse(set, done)
    local fps, pending, failed = {}, #set, {}
    local function compare_all()
        local cands, ends = {}, {}
        for i = 1, #set do cands[i] = {}; ends[i] = {} end
        local i, j = 1, 2
        local function step()
            if i >= #set then
                for n, e in ipairs(set) do
                    local op, ed = choose(cands[n]), choose(ends[n])
                    local name = e.path:match("[^/\\]*$")
                    local r = {v = 2, n = #set}
                    if op then r.s, r.e = op.s, op.e; log("%s: opening %.1f - %.1f (%d matches)", name, op.s, op.e, #cands[n]) end
                    if ed then r.es, r.ee = ed.s, ed.e; log("%s: ending %.1f - %.1f (%d matches)", name, ed.s, ed.e, #ends[n]) end
                    if not op and not ed then r.none = true; log("%s: no opening or ending found", name) end
                    results[e.key] = r
                end
                save_results(); busy = false; done()
                return
            end
            if fps[set[i].key] and fps[set[j].key] then
                local A, B = fps[set[i].key], fps[set[j].key]
                local da, db = #A * ITEM, #B * ITEM
                for _, c in ipairs(common(A, B)) do
                    local ma, mb = (c.a[1] + c.a[2]) / 2 / da, (c.b[1] + c.b[2]) / 2 / db   -- where in each episode the stretch lies
                    if ma < REGION then cands[i][#cands[i] + 1] = {s = c.a[1], e = c.a[2]}
                    elseif ma > 1 - REGION then ends[i][#ends[i] + 1] = {s = c.a[1], e = c.a[2]} end
                    if mb < REGION then cands[j][#cands[j] + 1] = {s = c.b[1], e = c.b[2]}
                    elseif mb > 1 - REGION then ends[j][#ends[j] + 1] = {s = c.b[1], e = c.b[2]} end
                end
            end
            j = j + 1
            if j > #set then i = i + 1; j = i + 1 end
            mp.add_timeout(0, step)   -- let mpv breathe between pairs
        end
        step()
    end
    local running, nextn = 0, 1
    local function pump()
        while running < 2 and nextn <= #set do
            local e = set[nextn]; nextn = nextn + 1; running = running + 1
            fingerprint(e.path, e.key, function(ok)
                running = running - 1; pending = pending - 1
                if ok then fps[e.key] = read_fp(e.key) else failed[#failed + 1] = e.path end
                if pending == 0 then compare_all() else pump() end
            end)
        end
    end
    pump()
end

-- episodes of the playing file's folder that are in the playlist (at most PEERS_MAX, nearest first)
local function folder_set()
    local path = mp.get_property("path")
    if not is_local(path) then return nil end
    local list, pos = {}, mp.get_property_number("playlist-pos") or 0
    for i, e in ipairs(mp.get_property_native("playlist") or {}) do
        if is_local(e.filename) and utils.split_path(e.filename) == utils.split_path(path) then
            local key = file_key(e.filename)
            if key then list[#list + 1] = {path = e.filename, key = key, near = (i - 1 >= pos) and (i - 1 - pos) or (pos - i + 1) * 2.5} end   -- the ones ahead count as nearer
        end
    end
    table.sort(list, function(a, b) return a.near < b.near end)
    while #list > PEERS_MAX do table.remove(list) end
    table.sort(list, function(a, b) return a.path < b.path end)
    return list
end

local warned
local function maybe_analyse()
    if not addon_on("introskip") or busy then return end
    local set = folder_set()
    if not set or #set < 2 then return end
    local missing
    for _, e in ipairs(set) do
        local r = results[e.key]
        if not (r and r.v == 2 and (r.n or 0) >= #set) then missing = true; break end
    end
    if not missing then return end   -- every episode in reach is known, and none is new
    busy = true
    find_ffmpeg(function(f)
        if not f then
            busy = false
            if not warned then warned = true; say("Auto skip intro needs ffmpeg (see the docs)") end
            log("ffmpeg with chromaprint not found")
            return
        end
        log("analysing %d episodes", #set)
        analyse(set, function() refresh_current() end)
    end)
end

-- ---------------------------------------------------------------- skipping
refresh_current = function()
    local me = mp.get_property("path") and file_key(mp.get_property("path"))
    local r = me and results[me]
    current = (r and r.v == 2 and not r.none) and {s = r.s, e = r.e, es = r.es, ee = r.ee} or nil
end

mp.register_event("start-file", function()
    undo_pos, current = nil, nil
    zone = {op = {n = 0, armed = true}, ed = {n = 0, armed = true}}
end)
local add_timer
mp.observe_property("playlist-count", "number", function()   -- episodes added while watching: scan them now, not when they start
    if add_timer then add_timer:kill() end
    add_timer = mp.add_timeout(3, function() if mp.get_property("path") then maybe_analyse() end end)
end)
mp.register_event("file-loaded", function()
    refresh_current()
    maybe_analyse()
end)

-- each song is skipped up to MAX_SKIPS times per episode (go back to before it and it skips again; the next time you can listen to it)
local MAX_SKIPS = 2
zone = {op = {n = 0, armed = true}, ed = {n = 0, armed = true}}
local function jump(pos, target, what)
    undo_pos = pos
    mp.commandv("seek", tostring(target), "absolute+exact")
    mp.osd_message("Skipped", 4)   -- same words for the opening and the ending, stays 4 seconds
    log("skipped %s %.1f -> %.1f", what, pos, target)
end
local function watch(z, pos, from, to, late, early, what)
    if not from then return end
    if pos < from + late - 0.5 then z.armed = true; return end   -- before the point where the skip starts: ready again
    if not z.armed or z.n >= MAX_SKIPS then return end
    if pos >= to - early - 1 then return end                      -- already at the end of it
    z.armed = false; z.n = z.n + 1
    jump(pos, to - early, what)
end
mp.observe_property("time-pos", "number", function(_, pos)
    if not pos or not current or not addon_on("introskip") then return end
    watch(zone.op, pos, current.s, current.e, S_LATE, EARLY, "intro")
    watch(zone.ed, pos, current.es, current.ee, ED_LATE, ED_EARLY, "ending")
end)

mp.add_key_binding("Alt+i", "intro-skip-undo", function()
    if not undo_pos then return end
    mp.commandv("seek", tostring(undo_pos), "absolute+exact")
    undo_pos = nil
    say("Skip undone")
end)

-- test hooks
mp.register_script_message("introskip-testdump", function()
    local me = file_key(mp.get_property("path") or "")
    local r = me and results[me] or {}
    print(string.format("INTRO current=%s none=%s s=%s e=%s es=%s ee=%s n=%s", tostring(current ~= nil), tostring(r.none), tostring(r.s), tostring(r.e), tostring(r.es), tostring(r.ee), tostring(r.n)))
end)
