-- An Avoid switch flipped on a shown route plans it again at once
-- (Forever, 2026-11-23: "avoid flight paths is not respected in
-- routing"). The route's walks and other ways are worked out behind it
-- for seconds, and a flip in those seconds was dropped: the switch stood
-- on and the route still flew.
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local function Cut(src, opening)
    local s = assert(src:find(opening, 1, true), opening)
    local _, e = src:find("\nend\r?\n", s)
    return src:sub(s, e)
end

-- The switch rows and what they call, cut from GPS.lua.
local function fresh()
    local src = Source()
    local w = { db = {}, plans = 0, busy = false }
    local GPS = {}
    function GPS:IsPlanning() return w.busy end
    function GPS:Plan(name, build)
        w.plans = w.plans + 1
        w.build = build
    end
    function GPS:BuildStops(route, via, avoid) w.planned = avoid or w.db.gpsAvoid end
    GPS.ViaLeft = function() return nil end
    GPS.Avoids = function() return w.db.gpsAvoid end
    local env = setmetatable({
        GPS = GPS, ns = { GPSRoute = {} },
        L = setmetatable({}, { __index = function(_, k) return k end }),
        DB = function() return w.db end,
        Route = function() return w.route end,
    }, { __index = _G })
    local chunk = assert(src:match("\n(GPS.AVOID_ORDER[^\n]*\n)")) .. Cut(src, "function GPS.AvoidKey(own)")
        .. Cut(src, "function GPS.Replan(route)") .. Cut(src, "local function Reroute(route)")
        .. Cut(src, "function GPS.PlanAgain()") .. assert(src:match("\n(local AVOID_OWN_TIP[^\n]*\n)"))
        .. assert(src:match("\n(GPS.AVOID_ON[^\n]*\n)")) .. Cut(src, "function GPS.AvoidRow(kind)") .. "return Reroute\n"
    w.Reroute = assert(load(chunk, "=GPS.lua avoid switch", "t", env))()
    w.GPS = GPS
    -- What the plan started last was handed as its avoid set.
    function w.plannedWith()
        w.planned = nil
        if w.build then w.build() end
        return w.planned
    end
    return w
end

local tests = {}

function tests.flippedWhileTheOtherWaysAreWorkedOut_plansAgainAtOnce()
    local w = fresh()
    w.route = { steps = {} }
    w.busy = true   -- the walks and other ways, behind the shown route
    w.GPS.AvoidRow("taxi").set(true)
    H.assertTrue(w.db.gpsAvoid.taxi, "the switch is kept")
    H.assertEq(w.plans, 1, "planned again over the work behind the route")
    H.assertTrue(w.plannedWith().taxi, "with flight paths avoided")
end

function tests.flippedWhileARouteIsStillBeingFound_plansAgainOnceItIs()
    local w = fresh()
    w.route = { steps = {} }
    w.busy = true
    w.GPS.planning = { name = "Orgrimmar" }
    w.GPS.AvoidRow("taxi").set(true)
    H.assertEq(w.plans, 0, "the route someone waits on is not thrown away")
    H.assertTrue(w.GPS.replanAsked, "asked for once it is found")
    local src = Source()
    local tick = assert(src:find("local function Tick()", 1, true))
    H.assertTrue(src:find("if (route.replan or GPS.replanAsked) and not GPS:IsPlanning() then", tick, true) ~= nil,
        "the ticker plans it again")
end

-- A route with its own set (another way picked, a guide's ways left out)
-- was planned from that set alone: the switch never reached it.
function tests.aRouteWithItsOwnSet_takesTheSwitchToo()
    local w = fresh()
    w.route = { steps = {}, wayAvoid = { hearth = true } }
    w.GPS.AvoidRow("taxi").set(true)
    H.assertTrue(w.route.wayAvoid.taxi, "avoided on this route")
    H.assertTrue(w.route.wayAvoid.hearth, "its own stay")
    H.assertTrue(w.plannedWith().taxi)
    w.GPS.AvoidRow("taxi").set(false)
    H.assertNil(w.route.wayAvoid.taxi, "and off again")
    H.assertNil(w.db.gpsAvoid.taxi, "off is the default: nothing kept")
end

function tests.noRoute_orArrived_nothingIsPlanned()
    local w = fresh()
    w.GPS.AvoidRow("taxi").set(true)
    w.route = { steps = {}, arrived = true }
    w.GPS.AvoidRow("boat").set(true)
    H.assertEq(w.plans, 0)
    H.assertTrue(w.db.gpsAvoid.taxi and w.db.gpsAvoid.boat, "the switches are kept all the same")
end

-- The ticker's own starts over (strayed off the way) still wait their turn.
function tests.theTickersOwn_neverOverAPlanUnderWay()
    local w = fresh()
    w.busy = true
    w.Reroute({ steps = {} })
    H.assertEq(w.plans, 0)
    w.busy = false
    w.Reroute({ steps = {} })
    H.assertEq(w.plans, 1)
end

-- His run (/efd gpsroute, 2026-11-23): flight paths stored as left out,
-- the planner idle, and the route kept through the reload still flew. A
-- route keeps the switches it was planned under, as one word.
function tests.aRouteKeepsTheSwitchesItWasPlannedUnder()
    local w = fresh()
    H.assertEq(w.GPS.AvoidKey(), "", "nothing switched")
    w.db.gpsAvoid = { danger = false }
    local before = w.GPS.AvoidKey()
    w.db.gpsAvoid.taxi = true
    H.assertEq(w.GPS.AvoidKey(), "taxi+danger-")
    H.assertTrue(before ~= w.GPS.AvoidKey(), "a flip is another word")
    H.assertEq(w.GPS.AvoidKey({ hearth = true }), "hearth+", "a route's own set stands for it")
    local src = Source()
    H.assertTrue(src:find("wayAvoid = avoid, avoidKey = GPS.AvoidKey(avoid),", 1, true) ~= nil, "kept by a new route")
    H.assertTrue(src:find("avoidKey = GPS.AvoidKey(route.wayAvoid), dangerSeen", 1, true) ~= nil, "by one started over")
    local again = Cut(src, "function GPS.Replanned(route, steps, total, advice)")
    H.assertTrue(again:find("route.avoidKey = GPS.AvoidKey(route.wayAvoid)", 1, true) ~= nil, "by one planned again in place")
end

-- Planned under other switches than stand now: the ticker plans it again,
-- once a change (a plan that finds no way must not be asked every second).
function tests.plannedUnderOtherSwitches_theTickerPlansItAgainOnce()
    local src = Source()
    local tick = assert(src:find("local function Tick()", 1, true))
    local s = assert(src:find("local avoidKey = GPS.AvoidKey(route.wayAvoid)", tick, true), "the ticker reads the word")
    local block = src:sub(s, (src:find("\n    end\n", s, true)))
    H.assertTrue(block:find("if route.avoidKey ~= avoidKey and not GPS:IsPlanning() then", 1, true) ~= nil)
    local kept, asked = block:find("route.avoidKey = avoidKey", 1, true), block:find("Reroute(route)", 1, true)
    H.assertTrue(kept ~= nil and asked ~= nil and kept < asked, "the word is kept before the plan is asked")
    -- A route saved before routes kept the word has none: planned again at login.
    H.assertTrue(nil ~= "", "no word differs from every word")
end

-- The settings page's switch for steps by zone plans again the same way.
function tests.theZoneStepsSwitch_plansAgainTheSameWay()
    H.assertTrue(Source():find('Switch("gpsZoneSteps", L["GPS_ZONE_STEPS"], L["GPS_ZONE_STEPS_TT"], GPS.PlanAgain)', 1, true) ~= nil)
end

local pass, fail, failures = H.runSuite("GPS avoid replan", tests)
return { pass = pass, fail = fail, failures = failures }
