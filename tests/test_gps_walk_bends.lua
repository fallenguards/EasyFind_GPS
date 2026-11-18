-- A walk's bend at a tile's edge moves to the point near it that shortens
-- the walk most (Nav.lua Path): on Zephras Isle the walk to Veena Vericloud
-- ran 105 yd along a road to the tile's entrance, then turned, where the
-- player walked straight up the hill (Forever, 2026-11-18). Real grid.
local H = require("Harness")
local Inflate = require("Inflate")

local START, VEENA = { 3836, 2101 }, { 3270.1, 1743.7 }   -- world, instance 2991

local function Walk()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    for _, f in ipairs({ "Walk_ZephrasIsle.lua", "Floors_Forever.lua", "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    ns.GPSFloors.Goal(2991, VEENA[1], VEENA[2])
    return ns.GPSNav.Path(2991, START[1], START[2], VEENA[1], VEENA[2])
end

local tests = {}

function tests.overTheHill_notAlongTheRoadFirst()
    local pts = assert(Walk(), "a walk")
    local len = 0
    for i = 3, #pts, 2 do len = len + ((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) ^ 0.5 end
    H.assertTrue(len < 690, "the walk shortened at its bend (701 yd before): " .. math.floor(len))
    -- Its first leg leaves the road's line (world y 2099) toward the hill.
    H.assertTrue(pts[6] < 2090, "the first leg climbs the hill, not down the road: y " .. math.floor(pts[6]))
    H.assertTrue(math.abs(pts[#pts - 1] - VEENA[1]) < 1 and math.abs(pts[#pts] - VEENA[2]) < 1, "it ends at Veena")
end

local pass, fail, failures = H.runSuite("GPSWalkBends", tests)
return { pass = pass, fail = fail, failures = failures }
