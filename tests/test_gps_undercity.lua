-- Undercity's GPS data on every classic client (issue #25, 2026-11-01):
-- the Ruins of Lordaeron's throne room, on the city's own map, stands for
-- the zone (its map's middle lies underground, which a walk reached
-- through the sewers), so a walk there is cut where it enters the Ruins'
-- gate; its three lifts link the Ruins' hall to the city both ways.
local H = require("Harness")

local FILES = {
    { "Data_Era.lua", "era", 1458, 1420 },
    { "Data_Forever.lua", "forever", 1458, 1420 },
    { "Data_TBC.lua", "tbc", 1458, 1420 },
    { "Data_Mists.lua", "mists", 998, 18 },
}

local function Load(file, cap)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [cap] = true }
    H.loadModule(file, env, ns)
    return assert(ns.GPSData, file .. " sets ns.GPSData")
end

local tests = {}

function tests.theRuinsThroneRoom_standsForUndercity()
    for _, f in ipairs(FILES) do
        local data = Load(f[1], f[2])
        local gate = data.gates and data.gates[f[3]]
        H.assertNotNil(gate, f[1] .. ": Undercity's gate")
        H.assertEq(gate.m, f[3], f[1] .. ": on the city's own map, so the walk ends on entering it")
        H.assertEq(gate.ci, 0)
        H.assertEq(gate.wx, 1598, "between the three lifts")
        H.assertEq(gate.wy, 243)
        H.assertTrue(gate.x > 0.65 and gate.x < 0.66 and gate.y > 0.43 and gate.y < 0.44, f[1] .. ": its place on that map")
    end
end

function tests.theThreeLifts_linkTheHallAndTheCityBothWays()
    for _, f in ipairs(FILES) do
        local data = Load(f[1], f[2])
        local n = 0
        for _, e in ipairs(data.edges) do
            if e.kind == "elevator" then
                n = n + 1
                H.assertTrue(e.bidir, f[1] .. ": ridden both ways")
                H.assertEq(e.from.m, f[3])
                H.assertEq(e.to.m, f[3])
                H.assertEq(e.from.area, 153, "the Ruins' hall names the way up")
                H.assertEq(e.to.area, 1497, "the city names the way down")
                H.assertTrue(e.sec and e.sec > 0)
            end
        end
        H.assertEq(n, 3, f[1] .. ": three lifts")
    end
end

-- The ticker rides a lift by the level's name under the player, never by
-- distance: its far door stands a few yards from its near one.
function tests.theTicker_ridesALiftByTheLevelsName()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find('if step.kind == "elevator" then', 1, true) ~= nil, "the lift's own rule")
    H.assertTrue(src:find("GetSubZoneText", 1, true) ~= nil, "by the level's name")
    H.assertTrue(src:find("step.reached, step.liftLevel = nil, nil", 1, true) ~= nil,
        "a step tracked anew forgets the level it was boarded on")
end

local pass, fail, failures = H.runSuite("GPS Undercity", tests)
return { pass = pass, fail = fail, failures = failures }
