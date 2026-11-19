-- Distances in the unit picked in options (GPS.DistanceText): yards by
-- default, meters, bananas (7 inches) or football fields (100 yards).
local H = require("Harness")

local function Load(units)
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("-- A distance in the unit picked in options.", 1, true), "DistanceText")
    local e = assert(src:find("\nend\n", s, true), "its end")
    local GPS = {}
    local env = setmetatable({
        GPS = GPS, sformat = string.format, mfloor = math.floor,
        DB = function() return { gpsUnits = units } end,
        L = { GPS_UNIT_YD = "%d yd", GPS_UNIT_M = "%d m", GPS_UNIT_BANANA = "%d bananas",
              GPS_UNIT_FIELD = "%.1f football fields" },
    }, { __index = _G })
    assert(load(src:sub(s, e + 4), "=GPS.lua units", "t", env))()
    return GPS
end

local tests = {}

function tests.eachUnit_convertsFromYards()
    H.assertEq(Load(nil).DistanceText(119.6), "119 yd", "yards, as before")
    H.assertEq(Load("m").DistanceText(100), "91 m")
    H.assertEq(Load("banana").DistanceText(7), "36 bananas", "7 yd is 252 inches")
    H.assertEq(Load("field").DistanceText(250), "2.5 football fields")
end

function tests.theOption_isOfferedAndPlaced()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find('Choice("units", L["GPS_UNITS"]', 1, true) ~= nil, "the choice row")
    H.assertTrue(src:find('"click", "units", "textSize"', 1, true) ~= nil, "placed on the page")
    local pin = assert(io.open(H.Path("WorldPin.lua"), "rb"))
    local plate = pin:read("*a")
    pin:close()
    H.assertTrue(plate:find("GPS.DistanceText(yards)", 1, true) ~= nil, "the arrow's plate uses it")
end

local pass, fail, failures = H.runSuite("GPSUnits", tests)
return { pass = pass, fail = fail, failures = failures }
