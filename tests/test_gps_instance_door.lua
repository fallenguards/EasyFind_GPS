-- A route to Wailing Caverns ended at the cave's mouth (Forever,
-- 2026-11-17): an instance's spot is its map label on the hill, and the
-- portal is down the cave. The instance tables now carry the portal (dx,
-- dy, the game's ghost point) beside the label; the route ends there, at a
-- spot's ring, or on stepping into the instance.
local H = require("Harness")
local Inflate = require("Inflate")

local BARRENS, KALIMDOR, WC = 1413, 1414, 43
local LABEL = { -838, -2037 }
local DOOR = { -751.13, -2209.24 }

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

-- Destination cut from GPS.lua, its entrance list answering as given.
local function Destination(entrance)
    local src = Source()
    local s = assert(src:find("-- Instances carry isZone in search", 1, true))
    local e = assert(src:find("-- The engine plans over", s, true))
    local env = setmetatable({
        EntranceOf = function() if entrance then return table.unpack(entrance) end end,
    }, { __index = _G })
    return assert(load(src:sub(s, e - 1) .. "\nreturn Destination", "=GPS.lua Destination", "t", env))()
end

local tests = {}

function tests.anInstanceUnderItsLabel_endsAtItsPortal()
    local D = Destination({ BARRENS, 0.4769, 0.3498, true, WC })
    local dest = D({ name = "Wailing Caverns", category = "dungeon", isDungeonEntrance = true,
                     entranceMapID = BARRENS, mapID = BARRENS, x = 0.4599, y = 0.3627 })
    H.assertEq(dest.mapID, BARRENS)
    H.assertEq(dest.x, 0.4769, "the portal, not the row's label spot")
    H.assertEq(dest.y, 0.3498)
    H.assertTrue(dest.door)
    H.assertEq(dest.instance, WC)
    H.assertNil(dest.zone)
end

function tests.theWorldsRow_onTheContinent_endsThereToo()
    local D = Destination({ BARRENS, 0.4769, 0.3498, true, WC })
    local dest = D({ name = "Wailing Caverns", category = "dungeon", isDungeonEntrance = true, isZone = true,
                     entranceMapID = KALIMDOR, zoneMapID = KALIMDOR })
    H.assertEq(dest.x, 0.4769)
    H.assertTrue(dest.door)
end

function tests.anInstanceAtItsDoor_keepsTheRowsSpot()
    local D = Destination({ BARRENS, 0.4227, 0.8987, false, 47 })
    local dest = D({ name = "Razorfen Kraul", category = "dungeon", isDungeonEntrance = true,
                     entranceMapID = BARRENS, mapID = BARRENS, x = 0.42, y = 0.89, instanceID = 47 })
    H.assertEq(dest.x, 0.42)
    H.assertNil(dest.door)
    H.assertEq(dest.instance, 47, "reached on stepping in all the same")
end

function tests.aRouteMadeAgain_keepsItsPortal()
    local dest = Destination(nil)({ name = "Wailing Caverns", category = "dungeon", mapID = BARRENS,
                                    x = 0.4769, y = 0.3498, door = true, instanceID = WC })
    H.assertTrue(dest.door)
    H.assertEq(dest.instance, WC)
    local src = Source()
    H.assertTrue(src:find("door = dest.door, instanceID = dest.instance", 1, true) ~= nil,
        "a new start plans the same end again")
end

function tests.theArrival_atThePortalsRingOrInside()
    local src = Source()
    local tick = assert(src:find("local function Tick()", 1, true))
    local inside = src:find("select(8, GetInstanceInfo()) == into", tick, true)
    local planned = src:find("local planned = route.origin and not route.joined", tick, true)
    H.assertTrue(inside ~= nil and inside < planned, "inside the instance ends it before anything else")
    H.assertTrue(src:find("and (dest.door or not INSTANCE_CATEGORIES[dest.category])", 1, true) ~= nil,
        "a portal's end is a spot: its small ring, the cave's floor")
end

-- The shipped Kalimdor grid walks down the cave to it.
function tests.theWalkGoesDownTheCave()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    for _, f in ipairs({ "Walk_Kalimdor.lua", "Floors_Forever.lua", "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    local Nav = ns.GPSNav
    ns.GPSFloors.Goal(1, DOOR[1], DOOR[2])
    local cost = Nav.Walk(1, LABEL[1], LABEL[2], DOOR[1], DOOR[2])
    local straight = math.sqrt((DOOR[1] - LABEL[1]) ^ 2 + (DOOR[2] - LABEL[2]) ^ 2)
    H.assertTrue(cost and cost > straight * 1.5, "round through the cave, not over the hill: " .. tostring(cost))
    local pts = Nav.Path(1, LABEL[1], LABEL[2], DOOR[1], DOOR[2])
    H.assertTrue(pts and math.abs(pts[#pts - 1] - DOOR[1]) < 1 and math.abs(pts[#pts] - DOOR[2]) < 1, "it ends at the portal")
end

local pass, fail, failures = H.runSuite("GPSInstanceDoor", tests)
return { pass = pass, fail = fail, failures = failures }
