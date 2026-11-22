-- Any of Undercity's lifts ridden counts (Forever, 2026-11-15): the route
-- led to the south lift, the player rode another up, and with "Go to the
-- elevator" still the step the way back down was drawn through the sewers.
-- GPS.LiftRidden cut from GPS.lua, fed a tick's spot each second.
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local LIFTS = {
    { kind = "elevator", from = { ci = 0, wx = 1553, wy = 241, area = 153 }, to = { ci = 0, wx = 1534, wy = 241, area = 1497 } },
    { kind = "elevator", from = { ci = 0, wx = 1595, wy = 198, area = 153 }, to = { ci = 0, wx = 1595, wy = 179, area = 1497 } },
    { kind = "elevator", from = { ci = 0, wx = 1596, wy = 283, area = 153 }, to = { ci = 0, wx = 1596, wy = 302, area = 1497 } },
}

local function Ridden(edges)
    local src = Source()
    local sizes = assert(src:match("\n(local LIFT_YARDS[^\n]*)"))
    local aboard = assert(src:match("\n(local LIFT_ABOARD[^\n]*)"))
    local s = assert(src:find("function GPS.LiftRidden(route, ci, px, py)", 1, true))
    local _, e = src:find("\nend\r?\n", s)
    local clock = { now = 100 }
    local env = setmetatable({
        GPS = {}, ns = { GPSData = { edges = edges or LIFTS } },
        GetTime = function() return clock.now end,
        PointWorld = function(p) return p.ci, p.wx, p.wy end,
    }, { __index = _G })
    assert(load(sizes .. "\n" .. aboard .. "\n" .. src:sub(s, e), "=GPS.lua LiftRidden", "t", env))()
    return env.GPS.LiftRidden, clock
end

-- Go to the south lift's foot, take it up, walk on.
local function UpBySouth()
    return { active = 1, steps = {
        { kind = "travel", go = { ci = 0, wx = 1534, wy = 241 } },
        { kind = "elevator", go = { ci = 0, wx = 1534, wy = 241, area = 1497 }, arrive = { ci = 0, wx = 1553, wy = 241, area = 153 } },
        { kind = "travel", go = { ci = 0, wx = 1996, wy = 54 } },
    } }
end

-- Each spot a second apart; what the last one returned, and where a ride
-- was first seen.
local function Walk(spots, route, gap)
    local ridden, clock = Ridden()
    local k, other, at
    for i, p in ipairs(spots) do
        clock.now = clock.now + (gap and gap[i] or 1)
        k, other = ridden(route, 0, p[1], p[2])
        if k and not at then at = i end
    end
    return k, other, at
end

local tests = {}

-- The north lift up as /efd gpslift logged it (2026-11-15).
local NORTH_UP = { { 1588, 309 }, { 1591, 308 }, { 1593, 307 }, { 1596, 303 }, { 1596, 296 }, { 1596, 291 },
                   { 1596, 291 }, { 1596, 291 }, { 1596, 287 }, { 1596, 284 }, { 1596, 277 } }

function tests.anotherLiftUp_startsTheRouteOverFromItsTop()
    local k, other, at = Walk(NORTH_UP, UpBySouth())
    H.assertEq(k, 2, "the route's lift step it stands for")
    H.assertTrue(other, "another lift: planned again from here")
    H.assertEq(at, #NORTH_UP, "seen once out past its top door")
end

function tests.theRoutesOwnLift_countsThoughItsWalkThereDidNot()
    local k, other = Walk({ { 1528, 241 }, { 1534, 241 }, { 1543, 241 }, { 1543, 241 }, { 1550, 241 }, { 1556, 241 } },
        UpBySouth())
    H.assertEq(k, 2)
    H.assertFalse(other, "its own lift: on to the walk after it")
end

function tests.onThePlatformAndBackOff_isNoRide()
    local route = UpBySouth()
    local ridden, clock = Ridden()
    for _, p in ipairs({ { 1593, 307 }, { 1596, 303 }, { 1596, 296 }, { 1596, 303 }, { 1596, 310 }, { 1596, 320 } }) do
        clock.now = clock.now + 1
        H.assertNil(ridden(route, 0, p[1], p[2]))
    end
end

function tests.aRideTheOtherWay_isNotTheRoutesLift()
    local down = { { 1596, 276 }, { 1596, 281 }, { 1596, 290 }, { 1596, 290 }, { 1596, 299 }, { 1596, 304 } }
    H.assertNil(Walk(down, UpBySouth()))
end

-- Its boarding side unseen (the ticker stopped a while): no ride is read.
function tests.boardedUnseen_isNoRide()
    local gap = {}
    for i = 1, #NORTH_UP do gap[i] = 1 end
    gap[5] = 30
    H.assertNil(Walk(NORTH_UP, UpBySouth(), gap))
end

function tests.noLiftAhead_nothing()
    local route = UpBySouth()
    route.active = 3
    H.assertNil(Walk(NORTH_UP, route))
end

-- Thunder Bluff's north-east lift: a car and its twin beside it, each
-- straight up and down (2026-11-22).
local MESA = { { kind = "elevator",
    from = { ci = 1, wx = -1043, wy = -45, area = 1638 }, to = { ci = 1, wx = -1032, wy = -53, area = 215 },
    twin = { from = { ci = 1, wx = -1035, wy = -28, area = 1638 }, to = { ci = 1, wx = -1021, wy = -28, area = 215 } } } }

local function DownTheMesa()
    local car = MESA[1]
    return { active = 1, steps = {
        { kind = "travel", go = car.from },
        { kind = "elevator", go = car.from, arrive = car.to, twin = { go = car.twin.from, arrive = car.twin.to } },
        { kind = "travel", go = { ci = 1, wx = -400, wy = -900 } },
    } }
end

local function MesaWalk(spots)
    local ridden, clock = Ridden(MESA)
    local route = DownTheMesa()
    local k, other
    for _, p in ipairs(spots) do
        clock.now = clock.now + 1
        k, other = ridden(route, 1, p[1], p[2])
        if k then break end
    end
    return k, other
end

function tests.aMesasOtherCar_isTheRoutesOwnLift()
    local k, other = MesaWalk({ { -1050, -28 }, { -1043, -28 }, { -1036, -28 }, { -1030, -28 }, { -1028, -28 },
                                { -1028, -28 }, { -1022, -28 }, { -1016, -28 } })
    H.assertEq(k, 2, "the walk to the lift not counted: its step all the same")
    H.assertFalse(other, "the car beside the route's: on to the walk after it")
end

function tests.aMesasCar_riddenDownAndOffAtItsFoot()
    local k, other = MesaWalk({ { -1052, -40 }, { -1046, -43 }, { -1041, -46 }, { -1037, -49 }, { -1037, -49 },
                                { -1034, -52 }, { -1030, -55 }, { -1026, -58 } })
    H.assertEq(k, 2)
    H.assertFalse(other)
end

-- The ticker reads it before a walk's own checks.
function tests.theTicker_asksIt()
    local src = Source()
    local tick = assert(src:find("local function Tick()", 1, true))
    local ask = src:find("GPS.LiftRidden(route, ci, px, py)", tick, true)
    local passed = src:find("GPS.StepPassed(route, ci, px, py)", tick, true)
    H.assertTrue(ask ~= nil and passed ~= nil and ask < passed)
end

local pass, fail, failures = H.runSuite("GPSLiftRidden", tests)
return { pass = pass, fail = fail, failures = failures }
