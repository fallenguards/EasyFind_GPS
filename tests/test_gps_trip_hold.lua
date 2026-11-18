-- A trip's stop that holds (a guide's) is never moved past on reaching it
-- (GPS.lua GPS.MoveOn): on Forever the GPS walked on to RestedXP's next
-- stop, down a ledge and round the temple, while the guide still said use
-- Skysight where the player stood (2026-11-18).
local H = require("Harness")

local function Load()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function GPS.MoveOn(route, target)", 1, true), "GPS.MoveOn not in GPS.lua")
    local _, e = src:find("\nend\r?\n", s)
    local GPS, did = {}, {}
    local env = setmetatable({
        GPS = GPS,
        TrackStep = function(i) did[#did + 1] = i end,
        Arrive = function() did[#did + 1] = "arrive" end,
    }, { __index = _G })
    assert(load(src:sub(s, e), "=GPS.lua MoveOn", "t", env))()
    return GPS.MoveOn, did
end

local function Trip(hold)
    local a, b, c = { name = "Skysight", hold = hold }, { name = "Brutes", hold = hold }, { name = "Grind", hold = hold }
    return { active = 1, steps = {
        { kind = "travel", tripStop = a },
        { kind = "travel" },
        { kind = "travel", tripStop = b },
        { kind = "travel", tripStop = c },
    } }
end

local tests = {}

function tests.aStopThatHolds_isNotMovedPast()
    local MoveOn, did = Load()
    local route = Trip(true)
    MoveOn(route, 2)
    H.assertEq(#did, 0, "reached the guide's stop: the route stays on it")
    MoveOn(route, 4)
    H.assertEq(#did, 0, "nor jumped past it to a later step reached")
    route.active = 2
    MoveOn(route, 4)
    H.assertEq(did[1], 3, "a step after it stops at the next stop that holds")
end

function tests.theLastStop_arrivesAsEver()
    local MoveOn, did = Load()
    local route = Trip(true)
    route.active = 4
    MoveOn(route, "arrive")
    H.assertEq(did[1], "arrive")
end

function tests.stopsThatDoNotHold_moveOnAsBefore()
    local MoveOn, did = Load()
    local route = Trip(nil)
    MoveOn(route, 2)
    H.assertEq(did[1], 2)
    MoveOn(route, "arrive")
    H.assertEq(did[2], "arrive")
end

function tests.everyMoveOnOfTheTick_goesThroughIt()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("local function Tick()", 1, true))
    local e = assert(src:find("local function StartTicker()", s, true))
    local body = src:sub(s, e)
    H.assertTrue(body:find("TrackStep(", 1, true) == nil, "no step taken past the gate")
    H.assertTrue(select(2, body:gsub("GPS.MoveOn%(route", "")) >= 6, "each move on asks it")
end

local pass, fail, failures = H.runSuite("GPSTripHold", tests)
return { pass = pass, fail = fail, failures = failures }
