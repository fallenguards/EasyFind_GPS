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
    return ns, env
end

local CAVE = { -215, -3215 }      -- in the cave under Thorn Hill's hill (floor 74-99, hill 104-173)
local CAMP = { -100, -2950 }      -- the Razormane camp on Thorn Hill
local MINER = { -9738.1, 136.2 }  -- a Kobold Miner in Fargodeep Mine, Elwynn Forest

local HACKETT = { -850.8, 70.3 }  -- Miner Hackett, deep in Azurelode Mine (height 3; the hill over him ~50)
local ROAD = { -760, 130 }        -- the road north of the mine

local tests = {}

local MOUTH = { -848.1, 214.5 }               -- Azurelode Mine's way out
local STEP_END = { -246.6, -587.5 }           -- his route's first step out of the mine

local function Len(pts)
    local len = 0
    for i = 3, pts and #pts or 0, 2 do len = len + math.sqrt((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) end
    return len
end

-- A walk as Route hands it to the follower: its doors by yards along.
local function PathOf(pts, doors)
    local cum = { 0 }
    for v = 2, #pts / 2 do cum[v] = cum[v - 1] + Len({ pts[2 * v - 3], pts[2 * v - 2], pts[2 * v - 1], pts[2 * v] }) end
    local d
    if doors then
        d = { from = doors.from }
        for k = 1, #doors do d[k] = { at = cum[doors[k].v], x = doors[k].x, y = doors[k].y, inside = doors[k].inside } end
    end
    return { pts = pts, cum = cum, len = cum[#cum], time = cum[#cum], doors = d }
end

-- The follower in Azurelode Mine on the shipped grid. Its walks are
-- searched in the planner's slices (Plan), the player 14 yd off by then.
local function Follower(planned)
    local ns, env = Load("Walk_EasternKingdoms.lua")
    local Nav = ns.GPSNav
    local now, player = { t = 100 }, { x = 0, y = 0 }
    env.GetTime = function() return now.t end
    env.IsIndoors = function() return true end
    local route = { steps = { { kind = "travel", go = { ci = 0, wx = STEP_END[1], wy = STEP_END[2] } } }, active = 1,
                    from = planned and { ci = 0, wx = planned[1], wy = planned[2] } or nil }
    if planned then ns.GPSFloors.Indoors(0, planned[1], planned[2]) end
    local queue, drawn = {}, {}
    local function Key(sx, sy, tx, ty) return ("%.2f:%.2f>%.2f:%.2f"):format(sx, sy, tx, ty) end
    ns.GPS.CurrentRoute = function() return route end
    ns.GPS.PlayerWorldPos = function() return 0, player.x, player.y end
    ns.GPS.DrawWalk = function(_, sx, sy, tx, ty)
        queue[#queue + 1] = { sx, sy, tx, ty }
        return true
    end
    ns.GPSRoute = { WalkPath = function(_, sx, sy, tx, ty) return drawn[Key(sx, sy, tx, ty)] end }
    H.loadModule("Follow.lua", env, ns)
    local function Plan()
        local x, y = player.x, player.y
        player.x, player.y, now.t = x + 10, y + 10, now.t + 1
        for _, a in ipairs(queue) do
            local pts, _, _, _, _, doors = Nav.Path(0, a[1], a[2], a[3], a[4])
            drawn[Key(a[1], a[2], a[3], a[4])] = pts and PathOf(pts, doors) or false
        end
        queue = {}
        player.x, player.y, now.t = x, y, now.t + 1
    end
    return ns.GPSFollow, player, Plan, Nav
end

-- The nearest a walk comes to (x, y).
local function Passes(pts, x, y)
    local best = math.huge
    for i = 3, #pts, 2 do
        local ax, ay, dx, dy = pts[i - 2], pts[i - 1], pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]
        local l2 = dx * dx + dy * dy
        local t = l2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / l2)) or 0
        best = math.min(best, math.sqrt((ax + t * dx - x) ^ 2 + (ay + t * dy - y) ^ 2))
    end
    return best
end

-- Out of the mine the follower's walks are its own, from where the player
-- stands; the planner searched them once he had walked on, past the 3 yd
-- the game's indoors covers, and they ran over the hill as the crow flies
-- (Forever, 2026-11-26). His spot and the join keep their indoor floor.
function tests.azurelode_theFollowersWalkFromHere_leavesByTheMouth()
    local Follow, player, Plan = Follower(nil)
    player.x, player.y = -816.5, 105.1
    Follow.Now()
    Plan()
    local f = Follow.Now()
    H.assertTrue(f and f.path, "a walk followed")
    local miss = Passes(f.path.pts, MOUTH[1], MOUTH[2])
    H.assertTrue(miss < 12, ("out by the mouth, not over the hill: %.0f yd off it, %.0f yd"):format(miss, f.path.len))
end

-- The walk out runs over the mine once out of its mouth: in the tunnel
-- under it the player was matched to that stretch on the hill (2 yd off
-- on the map) and the line ran on from there, straight.
function tests.azurelode_inTheTunnel_theWalkOutIsFollowedThroughIt()
    local Follow, player, Plan = Follower({ -846.9, 115.0 })
    player.x, player.y = -846.9, 115.0
    Follow.Now()
    Plan()
    local f
    -- His own walk in the mine (/efd gpsahead, 18:48).
    for _, p in ipairs({ { -845.1, 124.8 }, { -827.6, 113.5 }, { -816.5, 105.1 } }) do
        player.x, player.y = p[1], p[2]
        Follow.Now()
        Plan()
        f = Follow.Now()
    end
    H.assertTrue(f and f.path and f.path.doors, "a walk followed, with its doors")
    local out
    for k = 1, #f.path.doors do
        if f.path.doors[k].inside == false then out = f.path.doors[k].at break end
    end
    H.assertTrue(out and f.along < out,
        ("in the tunnel short of the way out (%.0f yd), not on the hill past it: %.0f yd along"):format(out or -1, f.along))
end

function tests.azurelode_theWayBackOntoTheWalkOut_staysInTheTunnels()
    local Follow, player, Plan, Nav = Follower({ -846.9, 115.0 })
    player.x, player.y = -816.5, 105.1
    Follow.Now()
    Plan()
    Follow.Now()
    Plan()
    Follow.Now()
    local j = Follow._walk.join
    H.assertTrue(j and j.path, "a way back onto the walk")
    local tunnels = Nav.Path(0, j.fx, j.fy, j.tx, j.ty, { indoorsA = true, indoorsB = true })
    H.assertTrue(math.abs(j.path.len - Len(tunnels)) < 2,
        ("through the tunnels (%.0f yd), not over the hill: %.0f yd"):format(Len(tunnels), j.path.len))
end

-- A goal reached only the long way round is walked to near it; near is
-- never the hill over a mine (Forever, 2026-11-25: "Dangerous!" to Miner
-- Hackett "routing me to the spot at ground level which is wrong ... and
-- then should guide through the cave"). A near floor is on the goal's own
-- side, in or out, as the floor under an upstairs trainer still is.
-- And drawn where it was priced: the near end's floor was picked again for
-- the drawing with neither test, so a walk priced through the mine (387
-- yd) was drawn straight to the hill over it (127 yd; his own positions,
-- /efd gpsahead, 2026-11-25: the map and minimap at odds, flipping).
function tests.azurelode_aNearWalk_isDrawnInByTheMouth()
    local ns = Load("Walk_EasternKingdoms.lua")
    local Nav = ns.GPSNav
    local SPOT, FROM = { -790.0, 77.0 }, { -681.2, 132.6 }
    ns.GPSFloors.Goal(0, SPOT[1], SPOT[2])
    local cost = Nav.Walk(0, FROM[1], FROM[2], SPOT[1], SPOT[2], { near = 8 })
    local pts = Nav.Path(0, FROM[1], FROM[2], SPOT[1], SPOT[2], { near = 8 })
    local len = 0
    for i = 3, pts and #pts or 0, 2 do len = len + math.sqrt((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) end
    H.assertTrue(cost and cost > 300, "priced through the mine: " .. tostring(cost))
    H.assertTrue(len > cost * 0.8, ("drawn the way it was priced: %.0f yd drawn for %.0f priced"):format(len, cost or 0))
end

-- Out of the mine: where the game says the player is indoors, the walk
-- from where he stands sets out on the tunnel's floor, not the hill over
-- it (Forever, 2026-11-25: "guiding out of the cave isn't working", the
-- line straight through the rock).
function tests.azurelode_outOfTheMine_fromWhereThePlayerStandsIndoors()
    local ns, env = Load("Walk_EasternKingdoms.lua")
    local Nav = ns.GPSNav
    local HERE, ROAD_OUT = { -832, 118 }, { -681.2, 132.6 }
    ns.GPS.PlayerWorldPos = function() return 0, HERE[1], HERE[2] end
    local function Len()
        local pts = Nav.Path(0, HERE[1], HERE[2], ROAD_OUT[1], ROAD_OUT[2])
        local len = 0
        for i = 3, pts and #pts or 0, 2 do len = len + math.sqrt((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) end
        return len
    end
    env.IsIndoors = function() return true end
    local out = Len()
    H.assertTrue(out > 300, ("indoors: out through the tunnels, %.0f yd for 152 straight"):format(out))
end

-- A route planned from inside the mine: its first walk sets out on the
-- tunnel's floor however far the player has moved since (his run, 18:48:
-- the route's own walk from -838.7, 125.5 drawn straight, 931 yd for 927).
function tests.azurelode_aRouteFromInsideTheMine_keepsItsIndoorStart()
    local ns = Load("Walk_EasternKingdoms.lua")
    local Nav, Floors = ns.GPSNav, ns.GPSFloors
    local ROAD_OUT = { -681.2, 132.6 }
    local function Len(from)
        local pts = Nav.Path(0, from[1], from[2], ROAD_OUT[1], ROAD_OUT[2])
        local len = 0
        for i = 3, pts and #pts or 0, 2 do len = len + math.sqrt((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2) end
        return len
    end
    H.assertTrue(Len({ -812, 98 }) < 200, "unmarked, with the player gone: the hill (the cause)")
    Floors.Indoors(0, -832, 118)
    H.assertTrue(Len({ -832, 118 }) > 300, "marked indoors at the plan: out through the tunnels")
end

function tests.azurelode_aNearEnd_staysInTheMine()
    local Nav = Load("Walk_EasternKingdoms.lua").GPSNav
    local exact = Nav.Walk(0, ROAD[1], ROAD[2], HACKETT[1], HACKETT[2])
    local near = Nav.Walk(0, ROAD[1], ROAD[2], HACKETT[1], HACKETT[2], { near = 8 })
    local straight = math.sqrt((ROAD[1] - HACKETT[1]) ^ 2 + (ROAD[2] - HACKETT[2]) ^ 2)
    H.assertTrue(exact and exact > straight * 2.5, "in by the mine's mouth: " .. tostring(exact))
    H.assertTrue(near and near > exact - 20, ("near him is still in the mine, not the hilltop: %s"):format(tostring(near)))
end

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
