-- The shown route's ways and the grid's settings (GPS.lua). Every plan
-- leaves the walking grid under its own settings; the parachute tip,
-- planned last after each route with any drop allowed, left its own
-- behind: the route's ways, kept under the settings it was planned with,
-- were found no more (the map drew a straight line out of Undercity's
-- sewers, the arrow and the map asked for every walk again 3 s after the
-- other ways were done, 2026-11-19), and walks searched from then on took
-- any drop. The route's ways are shown apart from the kept walks
-- (Route.ShowWalks), and the grid goes back under the route's settings
-- after the trials and before any walk is searched for it.
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

local function Cut(src, from, to)
    local s = assert(src:find(from, 1, true), from)
    local _, e = src:find(to, s, true)
    assert(e, to)
    return src:sub(s, e)
end

-- a comes before b in text, both there.
local function Before(text, a, b)
    local i, j = text:find(a, 1, true), text:find(b, 1, true)
    return i ~= nil and j ~= nil and i < j
end

local tests = {}

function tests.settleGrid_putsTheRoutesSettingsBack()
    local src = Source()
    local t = { route = { wayAvoid = { hearth = true, jumps = true }, from = { ci = 1 } } }
    local GPS = { Avoids = function() return { danger = false } end }
    local env = setmetatable({
        GPS = GPS, Route = function() return t.route end,
        ns = { GPSRoute = { Settle = function(opts, ci) t.opts, t.ci, t.calls = opts, ci, (t.calls or 0) + 1 end } },
    }, { __index = _G })
    assert(load(Cut(src, "function GPS.SettleGrid()", "\nend\n"), "=GPS.lua SettleGrid", "t", env))()
    GPS.SettleGrid()
    H.assertTrue(t.opts.avoid == t.route.wayAvoid, "the ways the route itself leaves out")
    H.assertEq(t.ci, 1, "on its continent")
    t.route.wayAvoid = nil
    GPS.SettleGrid()
    H.assertEq(t.opts.avoid.danger, false, "a route with none of its own: the player's switches")
    t.route = nil
    GPS.SettleGrid()
    H.assertEq(t.calls, 2, "no route: the grid stays as it is")
end

function tests.afterTheOtherWays_theGridIsSettled()
    local body = Cut(Source(), "local function PlanOtherWays()", "\nGPS.PlanOtherWays = PlanOtherWays\n")
    H.assertTrue(Before(body, "J.ShopTip(route)", "GPS.SettleGrid()"), "after the parachute tip, the last trial")
    H.assertTrue(Before(body, "GPS.SettleGrid()", "return advice, ways, shop"), "inside the plan, before it hands back")
end

function tests.aWalkAskedFor_isSearchedUnderTheRoutesSettings()
    local src = Source()
    local draw = Cut(src, "function GPS.DrawWalk(ci, sx, sy, tx, ty, near)", "\nend\n")
    H.assertTrue(Before(draw, "GPS.SettleGrid()", "Engine.WalkPath(ci, sx, sy, tx, ty, nil, near)"), "the follower's and the map's walks")
    local after = Cut(src, "local function AfterRoute(onlyDraw)", "\nGPS.AfterRoute = AfterRoute\n")
    H.assertTrue(Before(after, "GPS.SettleGrid()", "Engine.DrawWalks(route.steps, route.from)"), "the route's walks not drawn yet")
end

function tests.theRoutesWays_areShownAtOnceAndAfterTheSplit()
    local src = Source()
    local after = Cut(src, "local function AfterRoute(onlyDraw)", "\nGPS.AfterRoute = AfterRoute\n")
    H.assertTrue(Before(after, "ShowWalks(shownRoute, shownRoute.steps, shownRoute.from)", "Soon(function()"),
        "as the route is taken up, before any job")
    H.assertTrue(Before(after, "local steps = SplitWalks(route.steps, route.dest, route.from)", "Engine.ShowWalks(route, steps, route.from)"),
        "and again once every walk is drawn and split")
    H.assertTrue(Before(after, "Engine.ShowWalks(route, steps, route.from)", "route.walks = Engine.SaveWalk and KeptWalks(steps, route.from)"),
        "before they are saved with the route")
    local replanned = Cut(src, "function GPS.Replanned(route, steps, total, advice)", "\nend\n")
    H.assertTrue(replanned:find("ShowWalks(nil)", 1, true) ~= nil, "a plan taken up by the same route: the old steps' ways go")
end

local pass, fail, failures = H.runSuite("GPSShownWays", tests)
return { pass = pass, fail = fail, failures = failures }
