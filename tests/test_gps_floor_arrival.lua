-- Forever, 2026-11-15: on the ground floor under Brill's warlock trainer
-- (the inn's upper floor) the route said arrived. A room's floors share
-- the game's place name, so nothing tells them apart there: a route whose
-- end is upstairs or below stays until ended, unless the option says to
-- end it anyway (GPS.lua's tick, before Arrive).
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local tests = {}

function tests.anEndUpstairsOrBelow_holdsArrivalUnlessSet()
    local src = Source()
    local same = assert(src:find("ns.GPSFloors.SameLevel(ci, sx, sy)", 1, true), "the floor check")
    local hold = assert(src:find('(step.floor == "upper" or step.floor == "lower")', same, true), "the hold after it")
    local arrive = assert(src:find("Arrive(route)", hold, true), "before the arrival")
    local body = src:sub(hold, arrive)
    H.assertTrue(src:sub(hold - 12, hold):find("if spot and", 1, true) ~= nil, "on the journey's end only (spot)")
    H.assertTrue(body:find("gpsArriveAnyFloor", 1, true) ~= nil, "the option ends it anyway")
end

function tests.theOption_isOfferedAndPlaced()
    local src = Source()
    H.assertTrue(src:find('Check("arriveAnyFloor", L["GPS_ARRIVE_ANY_FLOOR"]', 1, true) ~= nil, "the row")
    H.assertTrue(src:find('"autoClose", "arriveAnyFloor"', 1, true) ~= nil, "placed on the page")
end

local pass, fail, failures = H.runSuite("GPSFloorArrival", tests)
return { pass = pass, fail = fail, failures = failures }
