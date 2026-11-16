-- Rides in the GPS searches (GPS.lua RideRows, AddRideHits): every boat,
-- zeppelin, skyship and tram leg is a place at its boarding spot, found by
-- its name, its kind or where it leaves from.
local H = require("Harness")

local AREAS = { [442] = "Auberdine", [1637] = "Orgrimmar", [215] = "Grom'gol Base Camp" }

local function Load(routes)
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function GPS.RideRows()", 1, true), "RideRows")
    local e = assert(src:find("-- Places for a typed name, for the trip editor", s, true), "after AddRideHits")
    local GPS = {}
    local env = setmetatable({
        GPS = GPS,
        ns = { GPSData = { routes = routes }, MapSearchData = { CATEGORY_ICONS = { zeppelin = 1, boat = 2 } } },
        L = { GPS_AVOID_BOAT = "Boats", GPS_AVOID_ZEPPELIN = "Zeppelins and skyships", GPS_LINE_TRAM = "Tram",
              GPS_RIDE_FROM_FMT = "from %s" },
        C_Map = { GetAreaInfo = function(a) return AREAS[a] end, GetMapInfo = function() return { name = "Map" } end },
    }, { __index = _G })
    assert(load(src:sub(s, e - 1), "=GPS.lua rides", "t", env))()
    return GPS
end

local ROUTES = {
    { kind = "zeppelin", n = "Zeppelin to Grom'gol, Stranglethorn Vale", from = { m = 85, x = 0.52, y = 0.51, area = 1637 } },
    { kind = "zeppelin", n = "Zeppelin to Orgrimmar", from = { m = 1434, x = 0.31, y = 0.29, area = 215 } },
    { kind = "boat", n = "Boat to Stormwind Harbor", from = { m = 1439, x = 0.30, y = 0.40, area = 442 } },
    { kind = "portal", n = "Portal to Orgrimmar", from = { m = 90, x = 0.1, y = 0.1 } },
    { kind = "taxi", n = "Flight to Crossroads", from = { m = 1413, x = 0.5, y = 0.3 } },
}

local function Names(GPS, q)
    local out = {}
    GPS.AddRideHits(q, out)
    local names = {}
    for i, r in ipairs(out) do names[i] = r.name end
    return table.concat(names, " | "), out
end

local tests = {}

function tests.aKindWord_listsEveryRideOfIt()
    local GPS = Load(ROUTES)
    H.assertEq(Names(GPS, "zeppelin"), "Zeppelin to Grom'gol, Stranglethorn Vale | Zeppelin to Orgrimmar")
    H.assertEq(Names(GPS, "boat"), "Boat to Stormwind Harbor", "the localized kind word too")
    H.assertEq(Names(GPS, "portal"), "", "portals and flights are not rides here")
end

function tests.everyWordMustMatch_nameOrWhereItLeaves()
    local GPS = Load(ROUTES)
    H.assertEq(Names(GPS, "zep orgrimmar"), "Zeppelin to Grom'gol, Stranglethorn Vale | Zeppelin to Orgrimmar",
        "to Orgrimmar, and from Orgrimmar")
    H.assertEq(Names(GPS, "zeppelin grom'gol"), "Zeppelin to Grom'gol, Stranglethorn Vale | Zeppelin to Orgrimmar",
        "to Grom'gol, and from Grom'gol")
    H.assertEq(Names(GPS, "boat auberdine"), "Boat to Stormwind Harbor", "leaves from Auberdine")
    H.assertEq(Names(GPS, "ze"), "", "two letters match nothing")
end

function tests.aRideRow_standsAtItsBoardingSpot()
    local GPS = Load(ROUTES)
    local _, out = Names(GPS, "boat")
    local row = out[1]
    H.assertEq(row.mapID, 1439)
    H.assertEq(row.x, 0.30)
    H.assertEq(row.category, "boat")
    H.assertEq(row.icon, 2)
    H.assertEq(row.zoneName, "from Auberdine")
end

local pass, fail, failures = H.runSuite("GPSRideSearch", tests)
return { pass = pass, fail = fail, failures = failures }
