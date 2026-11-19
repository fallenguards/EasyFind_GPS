-- The advice and the other ways (GPS.lua PlanOtherWays) are worked out only
-- while one of the GPS's own views is on screen: they show nowhere else,
-- and planning them after every route held about 40% of the game's time
-- for seconds, a guide sending a route each step (2026-11-19). With none on
-- screen the route is marked, and the first view to draw its lines plans
-- them.
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

local function Load()
    local src = Source()
    local t = { route = { dest = { name = "Dangerous!" }, steps = {} }, plans = 0, views = {} }
    local GPS = { IsPlanning = function() return false end }
    function GPS:Plan() t.plans = t.plans + 1 end
    local surfaces = {}
    local env = setmetatable({
        GPS = GPS, surfaces = surfaces, Route = function() return t.route end,
        Soon = function(fn) fn() end, DB = function() return {} end,
        L = setmetatable({}, { __index = function(_, k) return k end }),
    }, { __index = _G })
    local chunk = Cut(src, "function GPS.AnySurfaceVisible()", "\nend\n")
        .. Cut(src, "local function PlanOtherWays()", "\nGPS.PlanOtherWays = PlanOtherWays\n")
        .. Cut(src, "local function AdviceLines(route)", "\n    return #out > 0 and out or nil\nend\n")
        .. "\nreturn AdviceLines"
    t.AdviceLines = assert(load(chunk, "=GPS.lua other ways", "t", env))()
    t.GPS = GPS
    function t.View(shown)
        local v = { shown = shown }
        function v:IsVisible() return self.shown end
        surfaces[#surfaces + 1] = v
        return v
    end
    return t
end

local tests = {}

function tests.noViewOnScreen_markedNotPlanned_untilOneDraws()
    local t = Load()
    local window = t.View(false)
    t.GPS.PlanOtherWays()
    H.assertEq(t.plans, 0, "nothing on screen: not planned")
    H.assertTrue(t.route.othersWanted, "marked for later")
    t.AdviceLines(t.route)
    H.assertEq(t.plans, 0, "drawn while hidden: still waits")
    window.shown = true
    t.AdviceLines(t.route)
    H.assertEq(t.plans, 1, "the window on screen draws its lines: planned")
    H.assertNil(t.route.othersWanted)
    t.AdviceLines(t.route)
    H.assertEq(t.plans, 1, "once")
end

function tests.aViewOnScreen_plansAtOnce()
    local t = Load()
    t.View(true)
    t.GPS.PlanOtherWays()
    H.assertEq(t.plans, 1)
    H.assertNil(t.route.othersWanted)
end

local pass, fail, failures = H.runSuite("GPSOtherWaysShown", tests)
return { pass = pass, fail = fail, failures = failures }
