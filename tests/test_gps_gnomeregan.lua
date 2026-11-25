-- Outer Gnomeregan, under Dun Morogh and reached only by its lift
-- (Forever, 2026-11-25: "inside of gnomer area but outside the actual
-- dungeon itself is not pathing correctly. it's doing as the crow
-- flies"). The grid's build kept only ground joined to the main ground or
-- holding a known place, so the whole area was dropped and every walk
-- there failed into a straight line. A lift now joins its doors' areas.
local H = require("Harness")
local Inflate = require("Inflate")

-- Spots from the world databases (x, y; their height in the name).
local SPROK = { -5100.6, 750.3 }       -- 261, deep in the outer area
local NAMDO = { -4923.5, 725.5 }       -- 253, at its far end
local PORTAL = { -5161.3, 939.6 }      -- 258, the instance's door
local SURFACE = { -5336.7, 562.8 }     -- 396, Onin MacHammar, out on the snow

-- Era and TBC join with their grids rebuilt the same way.
local CLIENTS = {
    { caps = "forever", walk = "Walk_EasternKingdoms.lua", floors = "Floors_Forever.lua", data = "Data_Forever.lua" },
}

local function Client(c)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [c.caps] = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    for _, f in ipairs({ c.walk, c.floors, "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    for _, f in ipairs({ "Locales/enUS.lua", c.data }) do H.loadModule(f, env, ns) end
    return ns
end

local function Lift(ns)
    local found
    for _, e in ipairs(ns.GPSData.edges) do
        if e.kind == "elevator" and e.n == "Gnomeregan elevator" then
            assert(not found, "one Gnomeregan lift")
            found = e
        end
    end
    return found
end

local tests = {}

-- A spot below is a journey's end there (the cave's floor, not the snow
-- far above it); a door's own floor is the grid's pick at it.
function tests.theLift_joinsTheSnowToTheOuterArea()
    for _, c in ipairs(CLIENTS) do
        local ns = Client(c)
        local Nav, Floors = ns.GPSNav, ns.GPSFloors
        local lift = Lift(ns)
        H.assertNotNil(lift, c.data .. ": the lift")
        for _, p in ipairs({ SPROK, NAMDO, PORTAL }) do Floors.Goal(0, p[1], p[2]) end
        local function Reach(from, to) return (Nav.Walk(0, from.wx or from[1], from.wy or from[2], to[1], to[2], { limit = 900 })) ~= nil end
        H.assertTrue(Reach(lift.from, SURFACE), c.walk .. ": the top door reaches the snow")
        H.assertFalse(Reach(lift.from, SPROK), c.walk .. ": the top door is not down in the outer area")
        H.assertTrue(Reach(lift.to, SPROK), c.walk .. ": the bottom door reaches the outer area")
        H.assertTrue(Reach(lift.to, PORTAL), c.walk .. ": and the instance's door")
        H.assertFalse(Reach(lift.to, SURFACE), c.walk .. ": the bottom door is not up on the snow")
        H.assertTrue(Reach(NAMDO, PORTAL), c.walk .. ": a walk across the outer area, not a straight line")
    end
end

local pass, fail, failures = H.runSuite("GPSGnomeregan", tests)
return { pass = pass, fail = fail, failures = failures }
