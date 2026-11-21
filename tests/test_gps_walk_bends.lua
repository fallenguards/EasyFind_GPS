-- Zephras Isle walks against the straight line (real grid, Forever).
local H = require("Harness")
local Inflate = require("Inflate")

local function Walk(sx, sy, dx, dy)   -- world, instance 2991
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
    ns.GPSFloors.Goal(2991, dx, dy)
    local pts = assert(ns.GPSNav.Path(2991, sx, sy, dx, dy), "a walk")
    local len = 0
    for i = 3, #pts, 2 do len = len + ((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) ^ 0.5 end
    H.assertTrue(math.abs(pts[#pts - 1] - dx) < 1 and math.abs(pts[#pts] - dy) < 1, "it ends at the goal")
    return pts, len
end

local tests = {}

-- Veena Vericloud: up the hill, not along the road to a tile's entrance.
function tests.overTheHill_notAlongTheRoadFirst()
    local pts, len = Walk(3836, 2101, 3270.1, 1743.7)
    H.assertTrue(len < 690, "669 yd straight, 701 along the road: " .. math.floor(len))
    H.assertTrue(pts[6] < 2090, "the first leg leaves the road (y 2099): y " .. math.floor(pts[6]))
end

-- Into the cave from the bump's top: down its side, not round it.
function tests.downTheBump_notRoundIt()
    local pts, len = Walk(3811, 2085, 3605.2, 1516.0)
    H.assertTrue(len < 690, "605 yd straight, 712 round the bump: " .. math.floor(len))
    H.assertTrue(pts[5] < 3760, "the first leg goes west off the bump: x " .. math.floor(pts[5]))
end

-- The Bandit Hideout: in by the cave's mouth, not round the mountain to the hill above it.
function tests.intoTheHideout_byItsMouth()
    local _, len = Walk(3610, 1716, 3687, 1412)
    H.assertTrue(len < 600, "304 yd straight, 453 by the mouth: " .. math.floor(len))
    _, len = Walk(3610, 1716, 3717, 1435)
    H.assertTrue(len < 600, "301 yd straight, 411 by the mouth, 1,290 round the mountain: " .. math.floor(len))
end

local pass, fail, failures = H.runSuite("GPSWalkBends", tests)
return { pass = pass, fail = fail, failures = failures }
