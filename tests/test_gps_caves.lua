-- Caves under open ground on the shipped Forever grid (2026-11-15): the
-- walk to Chol'aruk, a Forever quest beast deep in the cave under Thorn
-- Hill, ended on the hilltop. No spawn of his is in the world databases,
-- and an end of unknown height took the outdoor floor. A journey's end now
-- takes the cave; a known spawn there has its height and says inside; the
-- arrival waits for the game's indoors.
local H = require("Harness")
local Inflate = require("Inflate")

local function Load(walk)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "enUS" end
    for _, f in ipairs({ walk, "Floors_Forever.lua", "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    return ns
end

local CAVE = { -215, -3215 }      -- in the cave under Thorn Hill's hill (floor 74-99, hill 104-173)
local CAMP = { -100, -2950 }      -- the Razormane camp on Thorn Hill
local MINER = { -9738.1, 136.2 }  -- a Kobold Miner in Fargodeep Mine, Elwynn Forest

local tests = {}

function tests.thornHill_aJourneysEndOfUnknownHeight_isTheCave()
    local ns = Load("Walk_Kalimdor.lua")
    local Nav, Floors = ns.GPSNav, ns.GPSFloors
    H.assertNil(Floors.Level(1, CAVE[1], CAVE[2]), "no spawn of his is known")
    H.assertFalse(Nav.InsideAt(1, CAVE[1], CAVE[2]), "any other spot there: the hilltop")
    local hill = Nav.Walk(1, CAMP[1], CAMP[2], CAVE[1], CAVE[2])
    Floors.Goal(1, CAVE[1], CAVE[2])
    H.assertTrue(Nav.InsideAt(1, CAVE[1], CAVE[2]), "a journey's end: the cave")
    local cave = Nav.Walk(1, CAMP[1], CAMP[2], CAVE[1], CAVE[2])
    H.assertTrue(hill and cave and cave > hill + 200, "round to the cave's mouth and in, not up the hill: "
        .. tostring(hill) .. " then " .. tostring(cave))
end

-- A continent with no floors file (Mists; Kalimdor on Era and TBC): its
-- journeys' ends still ask for the indoor floor.
function tests.noFloorsFile_aJourneysEndStillAsksIndoors()
    local ns = Load("Walk_EasternKingdoms.lua")
    local Floors = ns.GPSFloors
    H.assertNil(Floors.Want(5, 100, 200))
    Floors.Goal(5, 100, 200)
    local w = Floors.Want(5, 100, 200)
    H.assertTrue(w ~= nil and w.inside == true and w.z == nil)
    H.assertEq(Floors.Tag(5, 100, 200), "i")
    H.assertTrue(Floors.SameLevel(5, 100, 200))
end

function tests.fargodeep_aMinersKnownHeight_isInside()
    local ns = Load("Walk_EasternKingdoms.lua")
    H.assertEq(ns.GPSFloors.Level(0, MINER[1], MINER[2]), "inside")
    H.assertTrue(ns.GPSNav.InsideAt(0, MINER[1], MINER[2]), "its height picks the mine's floor")
end

-- The last step's spot in a cave (or on the hill over one) is reached only
-- with the game's indoors agreeing.
function tests.theArrival_asksTheGamesIndoors()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local same = assert(src:find("ns.GPSFloors.SameLevel(ci, sx, sy)", 1, true))
    local inside = src:find("Nav.InsideAt(ci, sx, sy)", same, true)
    H.assertTrue(inside ~= nil, "after the floor check")
    H.assertTrue(src:find("inside ~= (IsIndoors() and true or false)", inside, true) ~= nil)
end

-- A route kept through a reload marks its end again: the arrival there and
-- any walk drawn to it take the cave.
function tests.aKeptRoute_marksItsEndAgain()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local kept = assert(src:find("Engine.KeepWalk(w)", 1, true))
    H.assertTrue(src:find("Floors.Goal(p.ci, p.wx, p.wy)", kept, true) ~= nil)
end

local pass, fail, failures = H.runSuite("GPSCaves", tests)
return { pass = pass, fail = fail, failures = failures }
