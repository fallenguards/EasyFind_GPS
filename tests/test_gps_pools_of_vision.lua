-- Thunder Bluff's priest and mage trainers stand in the Pools of Vision,
-- a cave under the Spirit Rise. A route to EasyFind's Priest Trainer place
-- ended on the rise above (2026-11-22): the place was the middle point of
-- three trainers, a spot none stands at, so it took no trainer's height.
-- Since EasyFind 5.6.1 such a place is one trainer's own spot.
local H = require("Harness")
local Inflate = require("Inflate")

local THUNDER_BLUFF = { -1545.83, -527.08, -850.0, 516.67 }   -- its map on Kalimdor: south, east, north, west

-- A class's trainer place on Thunder Bluff's map, as world x, y.
local function Place(class)
    local f = assert(io.open(H.Path("Database/StaticLocations_Forever.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("[1456] = {", 1, true), "no Thunder Bluff places")
    local block = src:sub(s, src:find("\n    },", s, true))
    local x, y = block:match('category = "classtrainer_' .. class .. '", x = ([%d.]+), y = ([%d.]+)')
    x, y = assert(tonumber(x), class .. " trainer place"), tonumber(y)
    local r = THUNDER_BLUFF
    return r[3] - y * (r[3] - r[1]), r[4] - x * (r[4] - r[2])
end

local function Grid()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    env.IsIndoors = function() return false end
    for _, f in ipairs({ "Walk_Kalimdor.lua", "Floors_Forever.lua", "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    return ns.GPSNav, ns.GPSFloors
end

local tests = {}

function tests.aRouteToTheTrainersPlace_goesDownIntoTheCave()
    if not H.CoreAtLeast("5.6.1") then return end
    local Nav, Floors = Grid()
    for _, class in ipairs({ "priest", "mage" }) do
        local x, y = Place(class)
        local want = Floors.Want(1, x, y, true)
        H.assertTrue(want ~= nil and want.z ~= nil and want.z < 125, class .. ": the place takes a trainer's height, in the cave")
        H.assertTrue(Nav.InsideAt(1, x, y) == true, class .. ": it lies under the rise's roof")
        -- From the flight master, up top in the middle of the city.
        local pts = Nav.Path(1, -1197, 30, x, y)
        H.assertNotNil(pts, class .. ": a walk there")
    end
end

-- The same spot as the middle of the three priest trainers: no height, the
-- walk ends up top. What the place must never be again.
function tests.theMiddleOfTheTrainers_takesNoHeight()
    local _, Floors = Grid()
    H.assertNil(Floors.Want(1, -985.8, 254.0, true), "nobody stands there")
    local own = Floors.Want(1, -994.0, 249.1, true)
    H.assertTrue(own ~= nil and own.z ~= nil and own.z < 125, "a trainer's own spot is in the cave")
end

local pass, fail, failures = H.runSuite("GPS Pools of Vision", tests)
return { pass = pass, fail = fail, failures = failures }
