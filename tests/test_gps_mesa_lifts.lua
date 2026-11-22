-- A mesa's lift is two cars side by side, each straight up and down
-- (Forever, 2026-11-22): the data joined one car's top to the other's
-- foot as one shaft, so a ride down Thunder Bluff's lift never counted
-- and the route asked for the lift again at its foot.
local H = require("Harness")
local Inflate = require("Inflate")

local function Source(file)
    local f = assert(io.open(H.Path(file), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

-- The world database's "Mesa Elevator" cars on Kalimdor: x, y, a spot up
-- in the town and one on the ground below.
local TB_NE, TB_SW = { -1100, -20 }, { -1240, 130 }
local CARS = {
    { -1037.3, -49.2, TB_NE, { -980, -120 } }, { -1028.0, -28.4, TB_NE, { -980, -120 } },
    { -1286.2, 189.7, TB_SW, { -1380, 260 } }, { -1308.4, 185.3, TB_SW, { -1380, 260 } },
    { -4665.4, -1827.7, { -4560, -1830 }, { -4670, -1851 } }, { -4670.8, -1849.6, { -4560, -1830 }, { -4670, -1851 } },
    { -5399.2, -2504.6, { -5440, -2440 }, { -5330, -2540 } }, { -5382.5, -2489.4, { -5440, -2440 }, { -5330, -2540 } },
}

local CLIENTS = {
    { caps = "forever", walk = "Walk_Kalimdor.lua", data = "Data_Forever.lua", lifts = 4 },
    { caps = "era", walk = "Walk_Kalimdor_Era.lua", data = "Data_Era.lua", lifts = 4 },
    { caps = "tbc", walk = "Walk_Kalimdor_TBC.lua", data = "Data_TBC.lua", lifts = 4 },
    { caps = "mists", walk = "Walk_Kalimdor_Mists.lua", data = "Data_Mists.lua", lifts = 2 },
}

local function Client(c, grid)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { [c.caps] = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    if grid then
        for _, f in ipairs({ c.walk, "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    for _, f in ipairs({ "Locales/enUS.lua", c.data }) do H.loadModule(f, env, ns) end
    return ns
end

local function MesaLifts(ns)
    local out = {}
    for _, e in ipairs(ns.GPSData.edges) do
        if e.kind == "elevator" and e.from.ci == 1 then out[#out + 1] = e end
    end
    return out
end

local function CarAt(x, y)
    for _, car in ipairs(CARS) do
        if (car[1] - x) ^ 2 + (car[2] - y) ^ 2 <= 1.5 * 1.5 then return car end
    end
end

local tests = {}

-- Each row is one car, its doors either side of it, and names the other.
function tests.eachMesaLift_isACarWithItsTwin()
    for _, c in ipairs(CLIENTS) do
        local lifts = MesaLifts(Client(c))
        H.assertEq(#lifts, c.lifts, c.data .. ": Kalimdor's lifts")
        for _, e in ipairs(lifts) do
            H.assertNotNil(e.twin, c.data .. " " .. e.n .. ": its other car")
            for _, car in ipairs({ e, e.twin or e }) do
                local mx, my = (car.from.wx + car.to.wx) / 2, (car.from.wy + car.to.wy) / 2
                H.assertNotNil(CarAt(mx, my), ("%s %s: doors either side of a car (%.1f, %.1f)"):format(c.data, e.n, mx, my))
                H.assertEq(car.from.area, e.from.area, "its top door up in the town")
                H.assertEq(car.to.area, e.to.area, "its foot door on the ground")
            end
            local a, b = e.from, e.twin and e.twin.from or e.from
            H.assertTrue((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2 > 15 * 15, e.n .. ": two cars, not one")
        end
    end
end

-- On each client's walking grid a car's top door reaches the town and
-- never the ground, its foot door the ground and never the town.
function tests.eachCarsDoors_standOnTheirOwnLevel()
    for _, c in ipairs(CLIENTS) do
        local ns = Client(c, true)
        local Nav = ns.GPSNav
        local function Reach(p, to) return (Nav.Walk(1, p.wx, p.wy, to[1], to[2], { limit = 500 })) ~= nil end
        for _, e in ipairs(MesaLifts(ns)) do
            for _, car in ipairs({ e, e.twin or e }) do
                local at = CarAt((car.from.wx + car.to.wx) / 2, (car.from.wy + car.to.wy) / 2)
                if at then
                    local label = ("%s %s (%d, %d)"):format(c.data, e.n, car.from.wx, car.from.wy)
                    H.assertTrue(Reach(car.from, at[3]), label .. ": the top door reaches the town")
                    H.assertFalse(Reach(car.from, at[4]), label .. ": the top door is not on the ground")
                    H.assertTrue(Reach(car.to, at[4]), label .. ": the foot door reaches the ground")
                    H.assertFalse(Reach(car.to, at[3]), label .. ": the foot door is not up in the town")
                end
            end
        end
    end
end

-- A function of src from its opening line to the first "end" at indent.
local function Cut(src, opening, indent)
    local s = assert(src:find(opening, 1, true), opening)
    local _, e = src:find("\n" .. (indent or "") .. "end\r?\n", s)
    return src:sub(s, e)
end

-- The ticker's own rule for a lift's step, cut from GPS.lua with what it
-- calls: true once the step counts as ridden. The level's name never
-- changes (Thunder Bluff's map reaches its lifts' feet).
local function LiftRule()
    local gps, follow = Source("GPS.lua"), Source("Follow.lua")
    local player = { ci = 1 }
    local env = setmetatable({
        GPS = {}, Follow = {},
        GetSubZoneText = function() return "" end,
        PlayerWorldPos = function() return player.ci, player.x, player.y end,
        PointWorld = function(p) return p.ci, p.wx, p.wy end,
        SpotWorld = function(p) return p.ci, p.wx, p.wy end,
    }, { __index = _G })
    env.ns = { GPS = env.GPS, GPSFollow = env.Follow }
    local sizes = assert(gps:match("\n(local LIFT_YARDS[^\n]*)")) .. "\n" .. assert(gps:match("\n(local LIFT_ABOARD[^\n]*)"))
    local rule = Cut(gps, '    if step.kind == "elevator" then\n        local level = GetSubZoneText', "    ")
    local chunk = sizes .. "\n"
        .. Cut(follow, "local function World(p)") .. Cut(follow, "local function Doors(step, x, y)")
        .. Cut(follow, "function Follow.ThroughLift(step, ci, x, y)")
        .. Cut(gps, "function GPS.LiftDoors(step, px, py)") .. Cut(gps, "local function OnLift(step)")
        .. "return OnLift, function(step, ci, px, py, sx, sy)\n" .. rule .. "    return true\nend\n"
    local OnLift, ridden = assert(load(chunk, "=lift rule", "t", env))()
    return function(step, x, y)
        player.x, player.y = x, y
        return ridden(step, 1, x, y, step.arrive.wx, step.arrive.wy) == true
    end, function(step, x, y)
        player.x, player.y = x, y
        return OnLift(step)
    end
end

-- Thunder Bluff's north-east lift down, as a route's step holds it.
local function LiftDown()
    for _, e in ipairs(MesaLifts(Client(CLIENTS[1]))) do
        if e.from.wy < 0 and e.n:find("Thunder Bluff", 1, true) then
            return { kind = "elevator", go = e.from, arrive = e.to, twin = { go = e.twin.from, arrive = e.twin.to } }
        end
    end
end

-- Each spot a second apart: the first one the step counted as ridden at.
local function Replay(spots)
    local ridden = LiftRule()
    local step = LiftDown()
    for i, p in ipairs(spots) do
        if ridden(step, p[1], p[2]) then return i end
    end
end

-- His ride (2026-11-22): on from the town, down, off the foot to where his
-- snip has him (Thunder Bluff 56.2, 25.6), 22 yd east-north-east of the car.
function tests.theCarDown_andOffAtItsFoot_isRidden()
    local at = Replay({ { -1052, -40 }, { -1046, -43 }, { -1041, -46 }, { -1037, -49 }, { -1037, -49 }, { -1037, -49 },
                        { -1037, -49 }, { -1037, -49 }, { -1034.5, -55.6 }, { -1031.8, -62.1 }, { -1028.5, -69.8 } })
    H.assertNotNil(at, "the step moves on")
    H.assertTrue(at ~= nil and at >= 9, "not before he is off its platform: " .. tostring(at))
end

-- The other car taken (the route's own was away): the same lift.
function tests.theOtherCarDown_isRiddenToo()
    local at = Replay({ { -1050, -40 }, { -1042, -33 }, { -1035, -29 }, { -1028, -28 }, { -1028, -28 }, { -1028, -28 },
                        { -1028, -28 }, { -1021, -28 }, { -1014, -28 } })
    H.assertNotNil(at, "the step moves on")
    H.assertTrue(at ~= nil and at >= 8, "not before he is off its platform: " .. tostring(at))
end

function tests.ontoACarAndBackOffUpTop_isNoRide()
    H.assertNil(Replay({ { -1052, -40 }, { -1043, -45 }, { -1037, -49 }, { -1037, -49 }, { -1043, -45 }, { -1052, -40 },
                         { -1075, -30 }, { -1100, -20 } }))
end

-- Off along the cliff, hardly past the car: ridden once well away from it.
function tests.offSideways_isRiddenOnceWellAway()
    H.assertNil(Replay({ { -1052, -40 }, { -1043, -45 }, { -1037, -49 }, { -1037, -49 }, { -1039, -55 }, { -1042, -59 } }),
        "still beside its car")
    local at = Replay({ { -1052, -40 }, { -1043, -45 }, { -1037, -49 }, { -1037, -49 }, { -1039, -55 }, { -1042, -59 },
                        { -1046, -65 } })
    H.assertEq(at, 7, "18 yd off on the foot door's side")
end

function tests.eitherCar_isItsPlatform()
    local _, onLift = LiftRule()
    local step = LiftDown()
    H.assertTrue(onLift(step, -1037, -49), "the route's car")
    H.assertTrue(onLift(step, -1028, -28), "the car beside it")
    H.assertFalse(onLift(step, -1033, -39), "between the two")
    H.assertFalse(onLift(step, -1046, -43), "the town, before its door")
end

-- A route kept through the update holds the old shaft: planned again.
function tests.aKeptRoutesOldLiftStep_isPlannedAgain()
    local gps = Source("GPS.lua")
    local ns = Client(CLIENTS[1])
    local env = setmetatable({ GPS = {}, ns = ns }, { __index = _G })
    assert(load(Cut(gps, "function GPS.LiftsChanged(route)"), "=LiftsChanged", "t", env))()
    local old = { kind = "elevator", go = { ci = 1, wx = -1041, wy = -50 }, arrive = { ci = 1, wx = -1029, wy = -30 } }
    H.assertTrue(env.GPS.LiftsChanged({ active = 1, steps = { { kind = "travel" }, old } }), "one car's top to the other's foot")
    H.assertFalse(env.GPS.LiftsChanged({ active = 3, steps = { { kind = "travel" }, old, { kind = "travel" } } }),
        "a lift behind him is no matter")
    H.assertFalse(env.GPS.LiftsChanged({ active = 1, steps = { { kind = "travel" }, LiftDown() } }), "the data's own car")
    local tick = assert(gps:find("local function Tick()", 1, true))
    H.assertTrue(gps:find("if route.replan and not GPS:IsPlanning() then", tick, true) ~= nil, "the ticker plans it again")
    H.assertTrue(gps:find("route.replan = GPS.LiftsChanged(route) or nil", 1, true) ~= nil, "asked at login")
end

-- Aboard either car while the walk to the lift is still the step: done.
function tests.theTicker_countsAWalkToTheLiftDoneAboardItsCar()
    local src = Source("GPS.lua")
    local tick = assert(src:find("local function Tick()", 1, true))
    local aboard = src:find('if not planned and lift and lift.kind == "elevator" and OnLift(lift) then', tick, true)
    local ridden = src:find("GPS.LiftRidden(route, ci, px, py)", tick, true)
    H.assertTrue(aboard ~= nil and ridden ~= nil and aboard < ridden)
end

local pass, fail, failures = H.runSuite("GPS mesa lifts", tests)
return { pass = pass, fail = fail, failures = failures }
