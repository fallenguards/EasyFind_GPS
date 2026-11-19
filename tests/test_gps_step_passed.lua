-- A walk's step is done once its spot is passed on the way to the next
-- walk's (GPS.lua GPS.StepPassed): a corner cut past the step's pin never
-- leads back to it (it did, on Forever, until 250 yd off).
local H = require("Harness")

local function Load()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function GPS.StepPassed(route, ci, px, py)", 1, true), "GPS.StepPassed not in GPS.lua")
    local _, e = src:find("\nend\r?\n", s)
    local GPS = {}
    local env = setmetatable({
        GPS = GPS,
        PointWorld = function(p) if p then return p.ci, p.wx, p.wy end end,
    }, { __index = _G })
    assert(load(src:sub(s, e), "=GPS.lua StepPassed", "t", env))()
    -- The step's spot at 0,0, the next walk's 1000 yd west.
    local route = { active = 1, steps = {
        { kind = "travel", arrive = { ci = 1, wx = 0, wy = 0 } },
        { kind = "travel", arrive = { ci = 1, wx = -1000, wy = 0 } },
    } }
    return GPS.StepPassed, route
end

local tests = {}

function tests.walkedPastThePin_nearerTheNextSpot_isDone()
    local Passed, route = Load()
    H.assertTrue(Passed(route, 1, -60, 80), "100 yd beside the pin and on past it")
    H.assertTrue(Passed(route, 1, -200, -100), "well past it, still within reach")
end

function tests.beforeThePin_orFarFromIt_isNot()
    local Passed, route = Load()
    H.assertTrue(not Passed(route, 1, 200, 0), "still coming to it")
    H.assertTrue(not Passed(route, 1, -5, 0), "abreast of it by a step: the arrival ring takes that")
    H.assertTrue(not Passed(route, 1, -400, 300), "500 yd from it: the reroute takes that")
    H.assertTrue(not Passed(route, 2, -60, 80), "on another continent")
end

function tests.onlyAWalkOnToAWalk()
    local Passed, route = Load()
    route.steps[2].kind = "taxi"
    H.assertTrue(not Passed(route, 1, -60, 80), "a flight boards at the spot")
    route.steps[2].kind = "travel"
    route.steps[1].kind = "learn"
    H.assertTrue(not Passed(route, 1, -60, 80), "a flight master to learn stays a stop")
    route.steps[1].kind = "travel"
    route.steps[1].inside = true
    H.assertTrue(not Passed(route, 1, -60, 80), "a building's hall is walked into")
    route.steps[1].inside = nil
    route.steps[2] = nil
    H.assertTrue(not Passed(route, 1, -60, 80), "the last step arrives at its spot")
end

-- Under the ground no corner is cut: Undercity's sewers wind round nearer
-- the next walk's spot than their own pipe is, and the step out of them
-- was done in the tunnel (2026-11-19). A roofed city's door, and a place
-- the game names, are gone through.
function tests.aDoorOrANamedPlace_isNeverCutPast()
    local Passed, route = Load()
    route.steps[1].door = true
    H.assertTrue(not Passed(route, 1, -60, 80), "a roofed city's door")
    route.steps[1].door = nil
    route.steps[1].enterSub = "Sewers"
    H.assertTrue(not Passed(route, 1, -60, 80), "the way into a place the game names")
end

-- GPS.ThroughDoor: the step that ends at a door is done past the door
-- along its own way's last stretch, not within reach of it on the near
-- side, where the way on lies over the tunnel.
local function LoadDoor(way)
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function GPS.ThroughDoor(route, ci, px, py)", 1, true), "GPS.ThroughDoor not in GPS.lua")
    local _, e = src:find("\nend\r?\n", s)
    local GPS = {}
    local asked = {}
    local env = setmetatable({
        GPS = GPS,
        PointWorld = function(p) if p then return p.ci, p.wx, p.wy end end,
        ns = { GPSRoute = { WalkPath = function(_, fx, fy, tx, ty, lazy)
            asked.fx, asked.fy, asked.tx, asked.ty, asked.lazy = fx, fy, tx, ty, lazy
            return way
        end } },
    }, { __index = _G })
    assert(load(src:sub(s, e), "=GPS.lua ThroughDoor", "t", env))()
    -- The tunnel from its mouth 100 yd south comes round to its door at
    -- 0,0 heading north-east; the walk on leads back south-west.
    local route = { active = 2, from = { ci = 1, wx = -300, wy = 0 }, steps = {
        { kind = "travel", arrive = { ci = 1, wx = -100, wy = 0 } },
        { kind = "travel", door = true, arrive = { ci = 1, wx = 0, wy = 0 } },
        { kind = "travel", arrive = { ci = 1, wx = -500, wy = 300 } },
    } }
    return GPS.ThroughDoor, route, asked
end

function tests.throughTheDoor_onlyPastItAlongTheWay()
    local Through, route, asked = LoadDoor({ pts = { -100, 0, -40, 30, 0, 0 } })
    H.assertTrue(not Through(route, 1, -20, 15), "25 yd short of it on the way's last stretch")
    H.assertTrue(not Through(route, 1, -30, -10), "near it round another turn of the tunnel")
    H.assertTrue(Through(route, 1, 8, -6), "10 yd out past it")
    H.assertTrue(Through(route, 1, 0, 0), "on it")
    H.assertTrue(asked.fx == -100 and asked.tx == 0 and asked.lazy == true, "the step's own way, from the step before, never searched")
end

function tests.throughTheDoor_withNoWayKnown_theRingDecides()
    local Through, route = LoadDoor(nil)
    H.assertTrue(Through(route, 1, -20, 15), "its way not drawn")
    Through, route = LoadDoor({ pts = { 0, 0, 0, 0 } })
    H.assertTrue(Through(route, 1, -20, 15), "a way with no length")
    Through, route = LoadDoor({ pts = { -100, 0, -40, 30, 0, 0 } })
    H.assertTrue(Through(route, 2, -20, 15), "on another continent")
end

function tests.theTickerAsksIt()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find("if not planned and GPS.StepPassed(route, ci, px, py) then", 1, true) ~= nil,
        "the route's tick ends a passed step")
    H.assertTrue(src:find("if step.door and not GPS.ThroughDoor(route, ci, px, py) then return end", 1, true) ~= nil,
        "and keeps a door's step until the door is gone through")
end

-- The two roofed cities by each client's map, handed to the split with
-- the city set out from and the one walked to.
function tests.theRoofedCities_reachTheSplit()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local list = assert(src:match("GPS%.ROOFED = (%b{})"), "GPS.ROOFED")
    for _, id in ipairs({ 1458, 1455, 998, 87 }) do
        H.assertTrue(list:find("[" .. id .. "] = true", 1, true) ~= nil, "map " .. id)
    end
    H.assertTrue(src:find("roofed = GPS.ROOFED[here]", 1, true) ~= nil, "the city set out from")
    H.assertTrue(src:find("roofed = GPS.ROOFED[dest.mapID]", 1, true) ~= nil, "the city walked to")
end

local pass, fail, failures = H.runSuite("GPSStepPassed", tests)
return { pass = pass, fail = fail, failures = failures }
