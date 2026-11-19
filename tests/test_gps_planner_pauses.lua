-- Every loop a plan can spend long in gives the frame back (Nav.lua's
-- Pause, a yield once the frame's budget is spent): a tile's decode, both
-- searches' pops, and a tile's crossing pairs, thousands since a crossing
-- every 40 yards and each weighed for danger. Without the pairs' check the
-- planner held frames for 40 to 56 ms (gpsrec, 2026-11-19); offline the
-- longest went 35 to 19 ms with it.
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("Nav.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

-- The body of the local function named, up to its own end at its indent.
local function Body(src, head)
    local s = assert(src:find(head, 1, true), head)
    local indent = src:sub(1, s):match("([ ]*)$") or ""
    local e = assert(src:find("\n" .. indent .. "end\n", s, true), head .. " end")
    return src:sub(s, e)
end

local tests = {}

function tests.aTilesPairs_giveTheFrameBack()
    local body = Body(Source(), "local function TileCosts(w, key)")
    H.assertTrue(body:find("local function Pair(a, b, p, q)\n        made = made + 1\n        if made % 64 == 0 then Pause() end",
        1, true) ~= nil, "each pair counts toward the check")
    H.assertTrue(body:find("if j % 64 == 0 then Pause() end", 1, true) ~= nil, "and the drop limit's pairs")
end

function tests.theSearchesAndTheDecode_giveTheFrameBack()
    local src = Source()
    local _, pops = src:gsub("if pops %% %d+ == 0 then Pause%(%) end", "")
    H.assertTrue(pops >= 3, "the in-tile and cross-tile searches' pops: " .. pops)
    H.assertTrue(Body(src, "local function DecodeTile("):find("Pause()", 1, true) ~= nil, "a tile's decode")
end

-- A pair is weighed for danger on its first read, inside the cross-tile
-- search's pop, where a metamethod cannot yield (Lua 5.1): that search
-- checks every 8 pops, not 64.
function tests.theCrossTileSearch_checksEveryFewPops()
    local body = Body(Source(), "local function Search(w, fromA, toB, bx, by, best, limit, circle, rev)")
    H.assertTrue(body:find("if pops % 8 == 0 then Pause() end", 1, true) ~= nil)
    local costs = Body(Source(), "local function TileCosts(w, key)")
    H.assertTrue(costs:find("__index = function(t, p)", 1, true) ~= nil, "weighed on first read")
    local index = costs:match("__index = function%(t, p%)(.-)\n        end }%)")
    H.assertTrue(index ~= nil and not index:find("Pause", 1, true), "never yields inside the metamethod")
end

local pass, fail, failures = H.runSuite("GPSPlannerPauses", tests)
return { pass = pass, fail = fail, failures = failures }
