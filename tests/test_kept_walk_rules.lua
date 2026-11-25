-- A route kept through a reload brings back its walks, so they are not
-- searched again. A walk the old rules found came back after their fix:
-- in development the release does not change (a walk out of a mine stayed
-- a straight line through the rock, 2026-11-25). Route.lua's
-- KEPT_WALK_RULES fingerprints the walking code and grids; this holds it
-- to them, so a change there finds kept walks afresh.
local H = require("Harness")

local function Read(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end

-- FNV-1a over the code and each grid's size, as 8 hex digits.
local function Fingerprint()
    local parts = { Read("Nav.lua"), Read("Floors.lua") }
    local p = io.popen('cd "' .. H.Path("") .. '" && ls Walk_*.lua')
    local names = {}
    for name in p:lines() do names[#names + 1] = name end
    p:close()
    table.sort(names)
    for _, name in ipairs(names) do
        local f = assert(io.open(H.Path(name), "rb"))
        parts[#parts + 1] = name .. "=" .. f:seek("end")
        f:close()
    end
    local h = 2166136261
    for _, s in ipairs(parts) do
        for i = 1, #s do h = ((h ~ s:byte(i)) * 16777619) & 0xffffffff end
    end
    return string.format("%08x", h)
end

local tests = {}

function tests.keptWalks_nameTheRulesTheyWereFoundUnder()
    local now = Fingerprint()
    local held = Read("Route.lua"):match('local KEPT_WALK_RULES = "(%x+)"')
    H.assertEq(held, now, "Nav.lua, Floors.lua or a grid changed: set KEPT_WALK_RULES in Route.lua to " .. now)
end

local pass, fail, failures = H.runSuite("KeptWalkRules", tests)
return { pass = pass, fail = fail, failures = failures }
