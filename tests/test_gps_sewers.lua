-- Undercity's sewers on the shipped Forever grid (2026-11-17): a walk from
-- west of the city to Master Apothecary Faranell (A Recipe For Death)
-- goes in through the sewers, and the walk names that floor (Nav.Path's
-- levels, from Floors' names) so its step can say so.
local H = require("Harness")
local Inflate = require("Inflate")

local function Load()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "deDE" end
    for _, f in ipairs({ "Walk_EasternKingdoms.lua", "Floors_Forever.lua", "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    return ns
end

local WEST = { 1300, 1000 }               -- Tirisfal, west of the city
local FARANELL = { 1434.48, 404.854 }     -- in the Apothecarium (VMaNGOS spawn)

local tests = {}

function tests.aWalkIntoTheCityFromTheWest_namesTheSewers()
    local ns = Load()
    local pts, _, _, _, levels = ns.GPSNav.Path(0, WEST[1], WEST[2], FARANELL[1], FARANELL[2], { indoorsB = true })
    H.assertNotNil(pts, "a way on foot")
    local names = {}
    for _, l in ipairs(levels or {}) do names[#names + 1] = l.en end
    H.assertEq(names[1], "Sewers", "into the sewers first: " .. table.concat(names, ", "))
    H.assertEq(levels[1].name, "Die Abwasserkanäle", "and in the client's language")
    local v = levels[1].v
    H.assertTrue(v ~= nil and pts[2 * v - 1] ~= nil, "at a point of the walk, kept through its straightening")
end

-- The walk also tells where it goes in under the city's roof and comes
-- out of it (Nav.Path's doors, off the grid's indoor floors): the pipe at
-- the west wall, Undercity 15, 35, where a player stood at 14.8, 33.9
-- just out of it (2026-11-19). A roofed city's step ends there.
local PIPE = { 1650, 724 }                -- the pipe's mouth, world yards
local QUARTER = { 1616.1, 413.7 }         -- by the canals, Undercity 47.9, 40.9

function tests.theWalkOutByTheSewers_comesOutAtThePipe()
    local ns = Load()
    local pts, _, _, _, _, doors = ns.GPSNav.Path(0, QUARTER[1], QUARTER[2], WEST[1], WEST[2])
    H.assertNotNil(pts, "a way on foot")
    H.assertTrue(doors ~= nil and doors.from == true, "sets out under the city's roof")
    H.assertEq(#doors, 1, "one door: out by the pipe, and in the open from there")
    local d = doors[1]
    H.assertTrue(d.inside == false)
    H.assertTrue(math.abs(d.x - PIPE[1]) < 15 and math.abs(d.y - PIPE[2]) < 15,
        string.format("at the pipe's mouth: %.0f, %.0f", d.x, d.y))
    H.assertTrue(d.v ~= nil and pts[2 * d.v] ~= nil, "on a stretch of the walk")
end

function tests.theWalkInByTheSewers_goesInAtThePipe()
    local ns = Load()
    local _, _, _, _, _, doors = ns.GPSNav.Path(0, WEST[1], WEST[2], FARANELL[1], FARANELL[2], { indoorsB = true })
    H.assertTrue(doors ~= nil and doors.from == false, "sets out in the open")
    H.assertTrue(#doors >= 1 and doors[1].inside == true, "then in under the roof")
    H.assertTrue(math.abs(doors[1].x - PIPE[1]) < 15 and math.abs(doors[1].y - PIPE[2]) < 15,
        string.format("at the pipe's mouth: %.0f, %.0f", doors[1].x, doors[1].y))
    H.assertTrue(doors[#doors].inside == true, "and it ends under it")
end

-- The step out of the sewers keeps the tunnel for its way once the grid's
-- settings move (the parachute tip's plan, any drop): shown, it is found
-- by its ends; without that it was lost, the map drew a straight line from
-- the sewers' mouth to the pipe, and a search between those two spots set
-- out over the ground above (2026-11-19).
function tests.theStepOutOfTheSewers_keepsItsTunnelUnderOtherSettings()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    env.GetTime = function() return 0 end
    env.C_Map = { GetMapInfo = function() return { name = "" } end, GetBestMapForUnit = function() return 1458 end }
    for _, f in ipairs({ "Walk_EasternKingdoms.lua", "Floors_Forever.lua", "Floors.lua", "Nav.lua", "Route.lua" }) do
        H.loadModule(f, env, ns)
    end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    local Route, Nav = ns.GPSRoute, ns.GPSNav
    local start = { ci = 0, wx = QUARTER[1], wy = QUARTER[2] }
    local target = { ci = 0, wx = WEST[1], wy = WEST[2], m = 1420, x = 0.5, y = 0.5 }
    H.assertNotNil(Route.WalkPath(0, start.wx, start.wy, target.wx, target.wy), "the walk out")
    -- The whole walk lies in the city's box; the land past the pipe is one zone.
    local steps = Route.SplitWalks({ { kind = "travel", text = "Travel", mapID = 1420, go = target, arrive = target, sec = 100 } },
        start, {}, { zoneAt = function() return 1420, "Tirisfal Glades" end, isCity = function(m) return m == 1458 end,
                     mapPos = function() return 0.5, 0.5 end, startCity = { map = 1458, name = "Undercity", roofed = true } })
    local out
    for i = 2, #steps do
        if steps[i].door then out = i end
    end
    H.assertNotNil(out, "a step that ends at the pipe")
    local a, b = steps[out - 1].arrive, steps[out].arrive
    local straight = math.sqrt((b.wx - a.wx) ^ 2 + (b.wy - a.wy) ^ 2)
    local tunnel = Route.WalkPath(0, a.wx, a.wy, b.wx, b.wy, true)
    H.assertTrue(tunnel ~= nil and tunnel.len > straight * 1.3, "its way winds round the tunnel")
    local route = {}
    Route.ShowWalks(route, steps, start)
    Nav.SetDropLimit(math.huge)
    H.assertTrue(Route.WalkPath(0, a.wx, a.wy, b.wx, b.wy, true) == tunnel, "shown: still the tunnel, the settings moved")
    Route.ShowWalks(nil)
    H.assertNil(Route.WalkPath(0, a.wx, a.wy, b.wx, b.wy, true), "not shown: lost, and drawn straight")
    local again = Route.WalkPath(0, a.wx, a.wy, b.wx, b.wy)
    H.assertTrue(again and again.len < tunnel.len - 30, "searched again between its ends it is another way: " .. tostring(again and again.len))
end

local pass, fail, failures = H.runSuite("GPSSewers", tests)
return { pass = pass, fail = fail, failures = failures }
