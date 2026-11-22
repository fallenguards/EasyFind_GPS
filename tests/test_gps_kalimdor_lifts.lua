-- Kalimdor's lifts in each client's data: no walk climbs onto Thunder
-- Bluff's mesas or Freewind Post's, so with no flight point known the
-- route from Orgrimmar was a straight line (Forever, 2026-11-07).
local H = require("Harness")
local Inflate = require("Inflate")

local tests = {}

-- Thunder Bluff's map (1456) and Orgrimmar's (1454) on Kalimdor.
local RECTS = {
    [1456] = { -1545.83, -527.08, -850.0, 516.67 },
    [1454] = { 1338.46, -5083.21, 2273.88, -3680.6 },
}

local CLIENTS = {
    { caps = "forever", walk = "Walk_Kalimdor.lua", data = "Data_Forever.lua", lifts = 4 },
    { caps = "era", walk = "Walk_Kalimdor_Era.lua", data = "Data_Era.lua", lifts = 4 },
    { caps = "tbc", walk = "Walk_Kalimdor_TBC.lua", data = "Data_TBC.lua", lifts = 4 },
    -- Thousand Needles flooded: Thunder Bluff's two only.
    { caps = "mists", walk = "Walk_Kalimdor_Mists.lua", data = "Data_Mists.lua", lifts = 2 },
}

local function Source(file)
    local f = assert(io.open(H.Path(file), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

function tests.eachClientsData_hasKalimdorsLifts()
    for _, c in ipairs(CLIENTS) do
        local n = 0
        for line in Source(c.data):gmatch("[^\n]+") do
            if line:find('kind = "elevator"', 1, true) and line:find("ci = 1,", 1, true) then n = n + 1 end
        end
        H.assertEq(n, c.lifts, c.data .. ": Kalimdor's lifts")
    end
end

local function Route(client)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [client.caps] = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    for _, f in ipairs({ client.walk, "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    for _, f in ipairs({ "Locales/enUS.lua", client.data, "Route.lua" }) do H.loadModule(f, env, ns) end
    env.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
    env.C_Map = {
        GetWorldPosFromMapPos = function(m, v)
            local r = RECTS[m]
            if not r then return nil end
            return 1, env.CreateVector2D(r[3] - v.y * (r[3] - r[1]), r[4] - v.x * (r[4] - r[2]))
        end,
        GetMapInfo = function(m) return { name = "Map " .. m } end,
    }
    return function(dest, start)
        return ns.GPSRoute:Build(dest,
            { data = ns.GPSData, start = start or { ci = 1, wx = 1630, wy = -4420, m = 1454, x = 0.5, y = 0.5 },
              faction = "Horde", canFly = false, groundSpeed = 7, known = {},
              owns = function() return false end, cooldown = function() return 0 end })
    end
end

local function Lift(steps)
    for _, s in ipairs(steps or {}) do if s.kind == "elevator" then return s end end
end

local THUNDER_BLUFF = { name = "Thunder Bluff", mapID = 1456, x = 0.5, y = 0.5, zone = true }

-- The city is up top, though its map reaches the lifts' feet: a route
-- ended in the canyon below it (2026-11-17).
function tests.orgrimmarToThunderBluff_noFlightKnown_ridesALiftUp()
    for _, c in ipairs({ CLIENTS[1], CLIENTS[2] }) do
        local steps = Route(c)(THUNDER_BLUFF)
        H.assertTrue(steps ~= nil and #steps > 0, c.data .. ": a way there")
        H.assertNotNil(Lift(steps), c.data .. ": up a lift")
        local last = steps and steps[#steps].arrive
        H.assertTrue(last ~= nil and (last.wx + 1197) ^ 2 + (last.wy - 30) ^ 2 < 15 * 15, c.data .. ": ends up top")
    end
end

-- Standing at a lift's foot, already on the city's map: still up the lift.
function tests.atALiftsFoot_onTheCitysMap_stillRidesUp()
    for _, c in ipairs({ CLIENTS[1], CLIENTS[2] }) do
        local foot = { ci = 1, wx = -1029, wy = -30, m = 1456, x = 0.5238, y = 0.2567 }
        H.assertNotNil(Lift(Route(c)(THUNDER_BLUFF, foot)), c.data .. ": up the lift")
    end
end

-- Arrival on the city's map waits while a lift is still ahead.
function tests.zoneArrival_waitsForALiftAhead()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("A zone is reached when you are in it", 1, true))
    local block = src:sub(s, (src:find("Arrive(route)", s, true)))
    H.assertTrue(block:find('StepAhead(route, "elevator")', 1, true) ~= nil)
end

-- A spot up on the mesa: the walk rides a lift.
function tests.orgrimmarToTheMesa_noFlightKnown_ridesALift()
    for _, c in ipairs({ CLIENTS[1], CLIENTS[2] }) do
        local steps = Route(c)({ name = "Mesa", mapID = 1456, x = 0.4375, y = 0.5317 })
        H.assertNotNil(Lift(steps), c.data .. ": up a lift onto the mesa")
    end
end

-- A mesa's lift is two cars side by side: its step carries the other
-- car's doors, the way it rides.
function tests.aLiftsStep_knowsItsOtherCar()
    local lift = Lift(Route(CLIENTS[1])(THUNDER_BLUFF))
    H.assertNotNil(lift and lift.twin, "the other car")
    H.assertEq(lift.twin.go.area, lift.go.area, "boarded on the same level")
    H.assertEq(lift.twin.arrive.area, lift.arrive.area, "let off on the same level")
end

local pass, fail, failures = H.runSuite("GPS Kalimdor lifts", tests)
return { pass = pass, fail = fail, failures = failures }
