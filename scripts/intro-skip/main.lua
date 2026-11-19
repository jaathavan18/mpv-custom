-- intro-skip: skips the opening and the ending song of anime and TV episodes by itself. No chapters needed.
--  * It listens to each episode in the playlist (same folder) with ffmpeg + chromaprint, compares the episodes with each other and finds
--    the stretches that are the same in them. One in the first part of the episode is the opening, one in the last part is the ending.
--    Repeats in the middle (eyecatches, insert songs) are ignored.
--  * The times are kept in intro-skip.json (fingerprints in intro-skip-*.fp), so a folder is analysed once.
--  * When playback reaches the opening or ending it jumps to its end (a little early on purpose) and says so. What comes after the ending
--    song (a scene after the credits, a preview) still plays. Alt+I undoes the skip.
--  * A file with no match is left alone. It needs ffmpeg with chromaprint: ffmpeg.exe next to mpv.exe, on the PATH, or the path in
--    script-opts `introskip-ffmpeg=...`.
--  * Picture check: the sound finds where the song is; then tiny grey pictures (4 a second) of that stretch are compared with the other
--    videos that share the song. Only the seconds where the picture is the same as in the others are skipped, so a story scene or a
--    montage under the same song plays. Speech over the song also plays. Where the picture cannot decide, the F7 setting "When unsure"
--    decides. The pictures are only turned into numbers; nothing is displayed or kept except those numbers (intro-skip-*.pic).
local mp = require 'mp'
local utils = require 'mp.utils'

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
local okbit, bitlib = pcall(require, "bit")
if not okbit then bitlib = bit32 end
local bxor, band, rshift = bitlib.bxor, bitlib.band, bitlib.rshift

local ITEM = 0.1238          -- seconds per fingerprint item (chromaprint)
local WINDOW = 2.0           -- how far past its last matching item the opening ends (measured on test episodes)
-- (numbers you can change in F7: skip_start, skip_end, max_skips, min_len, max_len, region, batch, msg_time)
local BRIDGE_S = 10          -- a different bit shorter than this inside the opening does not split it
local DIST = 9               -- bits (of 32) that may differ, averaged over about a second
local MIN_FRAC = 0.6         -- share of the matched stretch that really matches
-- picture check
local PIC_W, PIC_H, RATE = 16, 9, 4   -- a picture is 16 x 9 grey values, 4 pictures a second
local PAD = 5              -- seconds read before and after a stretch
local FLAT_SD = 6          -- a picture with less spread than this (black, white, one colour) never votes
local SAME_CORR = 0.75     -- correlation from which two pictures count as the same
local JITTER = 1.0         -- a different bit this short between two same bits does not split them
local OVER_DELTA, OVER_ABS = 3, 5   -- speech on top of the song: bits above the clean copies, and at least this many bits

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
            if z - a + 1 >= SOLID and (z - a) * ITEM + WINDOW >= setting("introskip_min_len", 15) then
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
            if len >= setting("introskip_min_len", 15) and len <= setting("introskip_max_len", 300) then
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
    local ss, ee, with, offs = {}, {}, {}, {}
    for _, g in ipairs(best.group) do
        ss[#ss + 1] = g.s; ee[#ee + 1] = g.e
        if g.with and offs[g.with] == nil then offs[g.with] = g.off or 0; with[#with + 1] = g.with end
    end
    table.sort(ss); table.sort(ee)
    -- with: the videos that have this same stretch; offs[key]: this video's time = that video's time + offs[key]
    return {s = ss[math.ceil(#ss / 2)], e = ee[math.ceil(#ee / 2)], with = with, offs = offs}
end

-- ---------------------------------------------------------------- analysing a folder
local busy = false
local current   -- {s=, e=} for the file that is playing
local undo_pos
local zone   -- per episode: how often the opening / ending was skipped and whether the skip is ready
local function refresh_current() end   -- defined below

-- ---------------------------------------------------------------- pictures
-- a few jobs at once; each job is function(cb)
local function run_jobs(jobs, par, done)
    local n, running, nextj, finished = #jobs, 0, 1, 0
    if n == 0 then done(); return end
    local function pump()
        while running < par and nextj <= n do
            local job = jobs[nextj]; nextj = nextj + 1; running = running + 1
            job(function()
                running = running - 1; finished = finished + 1
                if finished == n then done() else pump() end
            end)
        end
    end
    pump()
end

local function pic_path(key, kind, t0, dur)
    return dir .. "intro-skip-" .. hash(key .. "|pic|" .. kind .. string.format("|%.1f|%.1f|%d|%d", t0, dur, RATE, PIC_W)) .. ".pic"
end

-- writes the pictures of one stretch (grey values, PIC_W x PIC_H, RATE a second) to a file; cb(file or nil)
local function picture(path, key, kind, t0, dur, cb)
    local out = pic_path(key, kind, t0, dur)
    if exists(out) then cb(out); return end
    local vf = string.format("fps=%d,crop=iw*0.9:ih*0.75:iw*0.05:ih*0.05,scale=%d:%d:flags=area,format=gray", RATE, PIC_W, PIC_H)   -- middle of the picture: no top, bottom or side bars, no lines of text
    mp.command_native_async({name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
        args = {ffmpeg, "-v", "error", "-y", "-threads", "2", "-ss", string.format("%.2f", t0), "-t", string.format("%.2f", dur),
                "-i", path, "-an", "-sn", "-dn", "-vf", vf, "-f", "rawvideo", out}}, function(ok, res)
        if ok and res and res.status == 0 and exists(out) then cb(out)
        else os.remove(out); cb(nil) end
    end)
end

-- the pictures of a file as normalised value lists (z), flat ones marked
local function pic_read(file)
    local f = io.open(file, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    local size = PIC_W * PIC_H
    local n = math.floor(#s / size)
    if n < 1 then return nil end
    local P = {n = n}
    for k = 1, n do
        local v = {s:byte((k - 1) * size + 1, k * size)}
        local sum = 0
        for i = 1, size do sum = sum + v[i] end
        local m = sum / size
        local var = 0
        for i = 1, size do local d = v[i] - m; var = var + d * d end
        local sd = math.sqrt(var / size)
        if sd < FLAT_SD then
            P[k] = {flat = true}
        else
            for i = 1, size do v[i] = (v[i] - m) / sd end
            P[k] = {z = v}
        end
    end
    return P
end

local function corr(a, b)
    local s = 0
    for i = 1, PIC_W * PIC_H do s = s + a[i] * b[i] end
    return s / (PIC_W * PIC_H)
end
local function widx(w, t) return math.floor((t - w.t0) * RATE + 0.5) + 1 end   -- sample number at a time (seconds of the file)
local function wtime(w, k) return w.t0 + (k - 1) / RATE end

-- for the samples of w inside its stretch: does a picture of the partner (time = own time - off, a shift of up to 1.5 s
-- allowed, one sample either side) look the same? m[k] = true / false; no entry = flat picture
local function match_pair(w, wp, off)
    local ks, ke = math.max(1, widx(w, w.st.s)), math.min(w.P.n, widx(w, w.st.e))
    local best, bestc = 0, -1
    for sh = -6, 6 do
        local c = 0
        for k = ks, ke, RATE do
            local a = w.P[k]
            if a and a.z then
                local b = wp.P[widx(wp, wtime(w, k) - off) + sh]
                if b and b.z and corr(a.z, b.z) >= SAME_CORR then c = c + 1 end
            end
        end
        if c > bestc or (c == bestc and math.abs(sh) < math.abs(best)) then best, bestc = sh, c end
    end
    local m = {}
    for k = ks, ke do
        local a = w.P[k]
        if a and a.z then
            local base, ok = widx(wp, wtime(w, k) - off) + best, false
            for d = -1, 1 do
                local b = wp.P[base + d]
                if b and b.z and corr(a.z, b.z) >= SAME_CORR then ok = true; break end
            end
            m[k] = ok
        end
    end
    return m
end

-- speech or effects on top of the song: where this video differs from its partners clearly more than they differ from each other
-- returns a list item -> true (needs 2 partners with fingerprints), or nil
local function overlay(n, kind, set, ops_or_eds, fps)
    local st = ops_or_eds[n]
    local A = fps[set[n].key]
    if not st or not A then return nil end
    local P = {}
    for _, key in ipairs(st.with) do
        for m, e in ipairs(set) do
            if e.key == key and fps[key] and #P < 4 then P[#P + 1] = {F = fps[key], d = math.floor(st.offs[key] / ITEM + 0.5)} end
        end
    end
    if #P < 2 then return nil end
    local a0, a1 = math.max(1, math.floor(st.s / ITEM) + 1), math.min(#A, math.floor(st.e / ITEM) + 1)
    local di, db = {}, {}
    for a = a0, a1 do
        local sum, cnt = 0, 0
        for _, p in ipairs(P) do
            local b = p.F[a - p.d]
            if b then sum = sum + dist(A[a], b); cnt = cnt + 1 end
        end
        local bs, bc = 0, 0
        for x = 1, #P do
            for y = x + 1, #P do
                local u, v = P[x].F[a - P[x].d], P[y].F[a - P[y].d]
                if u and v then bs = bs + dist(u, v); bc = bc + 1 end
            end
        end
        if cnt == #P and bc > 0 then di[a] = sum / cnt; db[a] = bs / bc end
    end
    local flag = {}
    for a = a0, a1 do
        local si, sb, c = 0, 0, 0
        for q = a - 4, a + 4 do if di[q] then si = si + di[q]; sb = sb + db[q]; c = c + 1 end end
        if c > 0 then flag[a] = (si / c >= OVER_ABS) and (si / c - sb / c >= OVER_DELTA) end
    end
    local out, a = {}, a0
    while a <= a1 do   -- only runs of at least 1.5 s count
        if flag[a] then
            local z = a
            while flag[z + 1] do z = z + 1 end
            if z - a + 1 >= 12 then for q = a, z do out[q] = true end end
            a = z + 1
        else
            a = a + 1
        end
    end
    return out
end

-- one state per sample of the stretch: S same picture, D different picture, U cannot tell (flat) -> parts to skip in seconds
local function make_parts(w, state, ks, ke, over)
    local st = {}
    for k = ks, ke do st[k] = state[k] or "U" end
    local EDGE = 2.5 * RATE   -- the stretch the sound found reaches a little past the picture: a short different bit at its very start or end is slack, not a scene
    local z = ks
    while z <= ke and st[z] == "D" do z = z + 1 end
    if z - ks <= EDGE then for q = ks, z - 1 do st[q] = "E" end end
    z = ke
    while z >= ks and st[z] == "D" do z = z - 1 end
    if ke - z <= EDGE then for q = z + 1, ke do st[q] = "E" end end
    local k = ks
    while k <= ke do   -- flat pictures follow their neighbours: next to a different picture they are different, else the sound decides (same)
        if st[k] == "U" then
            local z = k
            while z + 1 <= ke and st[z + 1] == "U" do z = z + 1 end
            local left, right = st[k - 1], st[z + 1]
            local v = (left == "D" or right == "D") and "D" or "S"
            for q = k, z do st[q] = v end
            k = z + 1
        else
            k = k + 1
        end
    end
    k = ks
    while k <= ke do   -- a different bit as short as the jitter limit, between two same bits, is the same
        if st[k] == "D" then
            local z = k
            while z + 1 <= ke and st[z + 1] == "D" do z = z + 1 end
            if z - k + 1 <= JITTER * RATE and st[k - 1] == "S" and st[z + 1] == "S" then for q = k, z do st[q] = "S" end end
            k = z + 1
        else
            k = k + 1
        end
    end
    for q = ks, ke do   -- speech on top: different, whatever the picture says
        local it = over and over[math.floor(wtime(w, q) / ITEM) + 1]
        if it then st[q] = "D" end
    end
    local parts = {}
    k = ks
    while k <= ke do
        if st[k] == "S" then
            local z = k
            while z + 1 <= ke and st[z + 1] == "S" do z = z + 1 end
            local a, b = math.max(w.st.s, wtime(w, k)), math.min(w.st.e, wtime(w, z) + 1 / RATE)
            if b - a >= 2 then parts[#parts + 1] = {a, b} end
            k = z + 1
        else
            k = k + 1
        end
    end
    return parts
end

-- the parts to skip of every video: segs[n] = {op = list, ed = list} (a missing list = no opening / ending)
local function pictures(set, ops, eds, fps, cb)
    local byKey, W, jobs = {}, {}, {}
    for n, e in ipairs(set) do
        byKey[e.key] = n
        W[n] = {}
        for _, kind in ipairs({"op", "ed"}) do
            local st = (kind == "op" and ops or eds)[n]
            if st then
                local t0 = math.max(0, st.s - PAD)
                local w = {kind = kind, st = st, t0 = t0, dur = st.e + PAD - t0, n = n}
                W[n][kind] = w
                jobs[#jobs + 1] = function(cbj) picture(e.path, e.key, kind, w.t0, w.dur, function(file) w.file = file; cbj() end) end
            end
        end
    end
    run_jobs(jobs, 2, function()
        local unsure_skip = setting("introskip_unsure", 0) >= 1
        local tasks, info = {}, {}
        for n = 1, #set do
            info[n] = {}
            for kind, w in pairs(W[n]) do
                w.P = w.file and pic_read(w.file) or nil
                tasks[#tasks + 1] = function()
                    local inf = {nS = 0, nNF = 0, state = {}, w = w}
                    info[n][kind] = inf
                    if not w.P then inf.failed = true; return end
                    local ms = {}
                    for _, key in ipairs(w.st.with) do
                        local pn = byKey[key]
                        local wp = pn and W[pn][kind]
                        if wp and wp.P and pn ~= n then ms[#ms + 1] = match_pair(w, wp, w.st.offs[key]) end
                    end
                    local needed = (#ms + 1 >= 5) and 2 or 1
                    inf.ks, inf.ke = math.max(1, widx(w, w.st.s)), math.min(w.P.n, widx(w, w.st.e))
                    inf.partners = #ms
                    for k = inf.ks, inf.ke do
                        local a = w.P[k]
                        if a and a.z then
                            inf.nNF = inf.nNF + 1
                            local c = 0
                            for _, m in ipairs(ms) do if m[k] == true then c = c + 1 end end
                            if c >= needed then inf.state[k] = "S"; inf.nS = inf.nS + 1 else inf.state[k] = "D" end
                        end
                    end
                    inf.over = overlay(n, kind, set, kind == "op" and ops or eds, fps)
                end
            end
        end
        local i = 0
        local function run()
            i = i + 1
            if i <= #tasks then tasks[i](); mp.add_timeout(0, run); return end
            local segs = {}
            for n = 1, #set do
                segs[n] = {}
                for kind, w in pairs(W[n]) do
                    local inf = info[n][kind]
                    log("picture %s %s: partners=%s same=%d notflat=%d failed=%s", set[n].path:match("[^/\\]*$"), kind, tostring(inf.partners), inf.nS, inf.nNF, tostring(inf.failed))
                    local list
                    local whole = {{w.st.s, w.st.e}}
                    if inf.failed then
                        list = unsure_skip and whole or {}
                    elseif inf.nS == 0 and inf.nNF / RATE >= 3 then
                        local others = false   -- does any partner have the real picture? then this one is a different scene
                        for _, key in ipairs(w.st.with) do
                            local pn = byKey[key]
                            local pi = pn and pn ~= n and info[pn][kind]
                            if pi and pi.nS > 0 then others = true end
                        end
                        if others or not unsure_skip then list = {}
                        else
                            local st = {}
                            for k = inf.ks, inf.ke do st[k] = "S" end
                            list = make_parts(w, st, inf.ks, inf.ke, inf.over)
                        end
                    else
                        list = make_parts(w, inf.state, inf.ks, inf.ke, inf.over)
                    end
                    segs[n][kind] = list
                end
            end
            cb(segs)
        end
        run()
    end)
end

local function finish(set, cands, ends, fps, done)
    local ops, eds = {}, {}
    for n = 1, #set do ops[n] = choose(cands[n]); eds[n] = choose(ends[n]) end
    local want = setting("introskip_pictures", 1) >= 1
    local function write(segs)
        for n, e in ipairs(set) do
            local op, ed = ops[n], eds[n]
            local name = e.path:match("[^/\\]*$")
            local old = results[e.key]
            local legacy = old and old.ow == nil and old.ew == nil   -- found before the first play was kept: it has been heard
            local r = {v = 3, n = #set, pic = want}
            if op then
                r.s, r.e, r.ow, r.ops = op.s, op.e, op.with, segs[n].op
                r.heard_op = (old and old.heard_op) or (legacy and old.s ~= nil) or nil
                log("%s: opening %.1f - %.1f (%d matches), %d part(s) to skip", name, op.s, op.e, #cands[n], #(segs[n].op or {}))
            end
            if ed then
                r.es, r.ee, r.ew, r.eds = ed.s, ed.e, ed.with, segs[n].ed
                r.heard_ed = (old and old.heard_ed) or (legacy and old.es ~= nil) or nil
                log("%s: ending %.1f - %.1f (%d matches), %d part(s) to skip", name, ed.s, ed.e, #ends[n], #(segs[n].ed or {}))
            end
            if not op and not ed then r.none = true; log("%s: no opening or ending found", name) end
            results[e.key] = r
        end
        done()
    end
    if not want then
        local segs = {}
        for n = 1, #set do
            segs[n] = {op = ops[n] and {{ops[n].s, ops[n].e}} or nil, ed = eds[n] and {{eds[n].s, eds[n].e}} or nil}
        end
        write(segs)
    else
        pictures(set, ops, eds, fps, write)
    end
end

local function analyse(set, done)
    local fps, pending, failed = {}, #set, {}
    local function compare_all()
        local cands, ends = {}, {}
        for i = 1, #set do cands[i] = {}; ends[i] = {} end
        local i, j = 1, 2
        local function step()
            if i >= #set then
                finish(set, cands, ends, fps, function() save_results(); busy = false; done() end)
                return
            end
            if fps[set[i].key] and fps[set[j].key] then
                local A, B = fps[set[i].key], fps[set[j].key]
                local da, db = #A * ITEM, #B * ITEM
                for _, c in ipairs(common(A, B)) do
                    local ma, mb = (c.a[1] + c.a[2]) / 2 / da, (c.b[1] + c.b[2]) / 2 / db   -- where in each episode the stretch lies
                    local R = setting("introskip_region", 40) / 100
                    local ki, kj = set[i].key, set[j].key
                    local oi = c.a[1] - c.b[1]
                    if ma < R then cands[i][#cands[i] + 1] = {s = c.a[1], e = c.a[2], with = kj, off = oi}
                    elseif ma > 1 - R then ends[i][#ends[i] + 1] = {s = c.a[1], e = c.a[2], with = kj, off = oi} end
                    if mb < R then cands[j][#cands[j] + 1] = {s = c.b[1], e = c.b[2], with = ki, off = -oi}
                    elseif mb > 1 - R then ends[j][#ends[j] + 1] = {s = c.b[1], e = c.b[2], with = ki, off = -oi} end
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

-- videos of the playing file's folder that are in the playlist (at most the batch size, nearest first)
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
    while #list > setting("introskip_batch", 12) do table.remove(list) end
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
        if not (r and r.v == 3 and (r.n or 0) >= #set and (r.pic == true) == (setting("introskip_pictures", 1) >= 1)) then missing = true; break end
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
    -- an old result (before the picture check) or one made with the other picture setting is not used until the folder is checked again
    local usable = r and r.v == 3 and not r.none and (r.pic == true) == (setting("introskip_pictures", 1) >= 1)
    current = usable and {op = r.ops or {}, ed = r.eds or {}, key = me} or nil
    if current then
        -- first of its kind: nobody with this same opening / ending has been heard yet, so this one plays through (decided once per play)
        for _, k in ipairs({"op", "ed"}) do
            local z = zone[k]
            if z.hold == nil then
                local partners = r[k == "op" and "ow" or "ew"]
                local held = setting("introskip_first_play", 1) >= 1 and partners ~= nil and not r["heard_" .. k]
                if held then
                    for _, p in ipairs(partners) do
                        local o = results[p]
                        if o and o["heard_" .. k] then held = false; break end
                    end
                end
                z.hold = held
            end
        end
    end
end

mp.register_event("start-file", function()
    undo_pos, current = nil, nil
    zone = {op = {}, ed = {}}
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

-- each song is skipped up to max_skips times per video (go back to before it and it skips again; the next time you can listen to it)
zone = {op = {}, ed = {}}   -- per kind: hold (first of its kind plays through) and one {n, armed} for every part to skip
local function jump(pos, target, what)
    undo_pos = pos
    mp.commandv("seek", tostring(target), "absolute+exact")
    mp.osd_message("Skipped", setting("introskip_msg_time", 4))   -- same words for the opening and the ending
    log("skipped %s %.1f -> %.1f", what, pos, target)
end
local function watch(z, pos, from, to, late, early, what)
    if pos < from + late - 0.5 then z.armed = true; return end   -- before the point where the skip starts: ready again
    if not z.armed or z.n >= setting("introskip_max_skips", 2) then return end
    if pos >= to - early - 1 then return end                      -- already at the end of it
    z.armed = false; z.n = z.n + 1
    jump(pos, to - early, what)
end
local function watch_kind(kind, what, pos, late, early)
    local list, zk = current[kind], zone[kind]
    if #list == 0 then return end
    if zk.hold then   -- the first time this opening / ending is heard: let it play and remember that it was heard
        local r = results[current.key]
        if r and pos >= list[1][1] + late and not r["heard_" .. kind] then r["heard_" .. kind] = true; save_results() end
        return
    end
    local minpart = setting("introskip_min_part", 5)
    for i, part in ipairs(list) do
        if part[2] - early - (part[1] + late) >= minpart then   -- long enough once the margins are taken off
            zk[i] = zk[i] or {n = 0, armed = true}
            watch(zk[i], pos, part[1], part[2], late, early, what)
        end
    end
end
mp.observe_property("time-pos", "number", function(_, pos)
    if not pos or not current or not addon_on("introskip") then return end
    local late, early = setting("introskip_skip_start", 3), setting("introskip_skip_end", 3)
    watch_kind("op", "intro", pos, late, early)
    watch_kind("ed", "ending", pos, late, early)
end)

mp.add_key_binding("Alt+i", "intro-skip-undo", function()
    if not undo_pos then return end
    mp.commandv("seek", tostring(undo_pos), "absolute+exact")
    undo_pos = nil
    say("Skip undone")
end)

-- test hooks
mp.register_script_message("introskip-testall", function()   -- test hook: the parts to skip of every video in the playlist
    local function parts(l)
        local o = {}
        for _, p in ipairs(l or {}) do o[#o + 1] = string.format("%.1f-%.1f", p[1], p[2]) end
        return "[" .. table.concat(o, " ") .. "]"
    end
    for _, e in ipairs(mp.get_property_native("playlist") or {}) do
        local k = file_key(e.filename)
        local r = k and results[k]
        local name = e.filename:match("[^/\\]*$")
        if r then
            print(string.format("ALL %s v=%s op stretch %s-%s parts %s | ed stretch %s-%s parts %s", name, tostring(r.v),
                r.s and string.format("%.1f", r.s) or "-", r.e and string.format("%.1f", r.e) or "-", r.s and parts(r.ops) or "none",
                r.es and string.format("%.1f", r.es) or "-", r.ee and string.format("%.1f", r.ee) or "-", r.es and parts(r.eds) or "none"))
        else print("ALL " .. name .. " no result") end
    end
end)
mp.register_script_message("introskip-testdump", function()
    local me = file_key(mp.get_property("path") or "")
    local r = me and results[me] or {}
    local function parts(l)
        local o = {}
        for _, p in ipairs(l or {}) do o[#o + 1] = string.format("%.1f-%.1f", p[1], p[2]) end
        return "[" .. table.concat(o, " ") .. "]"
    end
    print(string.format("INTRO v=%s pic=%s current=%s none=%s stretch op=%s-%s ed=%s-%s parts op=%s ed=%s hold op=%s ed=%s heard_op=%s heard_ed=%s n=%s",
        tostring(r.v), tostring(r.pic), tostring(current ~= nil), tostring(r.none), tostring(r.s and string.format("%.1f", r.s)), tostring(r.e and string.format("%.1f", r.e)),
        tostring(r.es and string.format("%.1f", r.es)), tostring(r.ee and string.format("%.1f", r.ee)), parts(r.ops), parts(r.eds),
        tostring(zone.op.hold), tostring(zone.ed.hold), tostring(r.heard_op), tostring(r.heard_ed), tostring(r.n)))
end)
