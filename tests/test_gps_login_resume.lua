-- A route resumed at login draws at once (GPS.lua's login handler): the
-- arrow's driver starts only in a refresh, and the plan after it refreshes
-- only with the planner free, which at login it may not be (Forever,
-- 2026-11-16: route saved and resumed, the arrow never built).
local H = require("Harness")

local tests = {}

function tests.aResumedRoute_refreshesItsSurfacesBeforeThePlan()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("loginFrame:SetScript(\"OnEvent\"", 1, true), "the login handler")
    local resume = assert(src:find("if not route then return end", s, true), "where it resumes a route")
    local plan = assert(src:find("AfterRoute(route.others ~= nil)", resume, true), "the plan after it")
    local body = src:sub(resume, plan)
    local ticker = assert(body:find("StartTicker()", 1, true))
    local refresh = body:find("\n    Refresh()\n", 1, true)
    H.assertTrue(refresh ~= nil and refresh > ticker, "Refresh() runs as the route resumes, before the plan")
end

local pass, fail, failures = H.runSuite("GPSLoginResume", tests)
return { pass = pass, fail = fail, failures = failures }
