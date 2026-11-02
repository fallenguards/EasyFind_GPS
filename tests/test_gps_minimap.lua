-- Tests for Minimap.lua: the route on the minimap, cut at the rim
-- and around the player's arrow, the part already walked faded, turning
-- with a turning minimap, and nothing drawn again while standing still.
local H = require("Harness")

local PASSED, BLUE, RED = { 0.7, 0.7, 0.7 }, { 0, 0, 1 }, { 1, 0, 0 }

-- Preview.Trace as shipped, onto the stubbed preview.
local function LoadTrace(env, ns)
    local f = assert(io.open(H.Path("Preview.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function Preview.Trace", 1, true), "Trace not in Preview.lua")
    local _, e = src:find("\nend\r?\n", s)
    local chunk = "local Preview, ns = ...\n" .. src:sub(s, e)
    assert(load(chunk, "=Preview.lua Trace", "t", env))(ns.GPSPreview, ns)
end

-- A walk planned 100 yd south of the player to 300 yd north of them, the
-- player on it; a minimap 100 px wide showing 100 yd each way. deadly:
-- the yards along the walk over ground deadly to the player. west: the
-- player that far west of the walk instead; sealed: no way on foot but
-- the planned walk itself.
local function fresh(deadly, west, sealed, zoom, waypoints, settings)
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    env.EasyFind.db = env.EasyFind.db or {}
    for k, v in pairs(settings or {}) do env.EasyFind.db[k] = v end
    local now = { t = 100 }
    env.GetTime = function() return now.t end
    local state = { rotate = false, facing = 0 }
    env.Minimap = H.newFrame()
    env.C_Minimap = { GetViewRadius = function() return 100 end }
    -- zoom: a classic client, no view radius call, at this zoom level.
    if zoom then
        env.C_Minimap = nil
        env.Minimap.GetZoom = function() return zoom.level end
        env.IsIndoors = function() return zoom.indoors end
        -- inside, outside: the two zoom cvars; mode: the set the minimap is
        -- on, which a SetZoom writes to.
        if zoom.outside then
            env.GetCVar = function(name) return name == "minimapZoom" and zoom.outside or zoom.inside end
            zoom.sets = 0
            env.Minimap.SetZoom = function(_, level)
                zoom.sets, zoom.level = zoom.sets + 1, level
                zoom[zoom.mode == "inside" and "inside" or "outside"] = level
            end
        end
    end
    env.GetCVarBool = function() return state.rotate end
    env.GetPlayerFacing = function() return state.facing end
    -- World x north, y west; the map's up is north and its left west.
    env.C_Map = { GetBestMapForUnit = function() return 7 end }
    -- waypoints: a client with user waypoints (retail), whose blip marks the spot.
    if waypoints then env.C_Map.SetUserWaypoint = function() end end
    local route = { steps = { { kind = "travel", go = { ci = 1, wx = 300, wy = 0 } } }, active = 1,
                    from = { ci = 1, wx = -100, wy = 0 } }
    ns.GPS = {
        CurrentRoute = function() return route end,
        PlayerWorldPos = function() return 1, 0, west or 0 end,
    }
    ns.GPSRoute = {
        WorldPos = function(_, mx, my) return 1, (0.5 - my) * 1000, (0.5 - mx) * 1000 end,
        WalkPath = function(_, sx, sy, tx, ty)
            if sealed and not (sx == -100 and sy == 0) then return false end
            local len = math.sqrt((tx - sx) ^ 2 + (ty - sy) ^ 2)
            return { pts = { sx, sy, tx, ty }, cum = { 0, len }, len = len }
        end,
    }
    local drawn = { calls = 0 }
    local lines = {
        Begin = function() drawn.pieces = {} end,
        Line = function(_, src, m, _, _, color)
            drawn.calls = drawn.calls + 1
            local pts = {}
            for i = 1, m do pts[i] = src[i] end
            drawn.pieces[#drawn.pieces + 1] = { pts = pts, color = color }
        end,
        Finish = function() end,
        Hide = function() drawn.pieces = {} end,
    }
    ns.GPSPreview = {
        NewLines = function() return lines end,
        Span = function() return 10 end,
        PASSED_COLOR = PASSED, PASSED_ALPHA = 0.5, LineColor = function() return BLUE end,
        DANGER_COLOR = RED,
    }
    env.UnitLevel = function() return 15 end
    env.UnitFactionGroup = function() return "Alliance" end
    ns.GPSNpcs = { DeadlyAlong = function() return deadly end }
    LoadTrace(env, ns)
    H.loadModule("Follow.lua", env, ns)
    H.loadModule("Minimap.lua", env, ns)
    ns.GPSMinimap:Refresh()
    ns.GPSMinimap._ns = ns   -- the test's hand on the player's spot
    return drawn, state, now, ns.GPSMinimap
end

local function near(a, b) return math.abs(a - b) < 1e-6 end

-- Half the minimap is 50 px; the line 7 px wide stops 4.5 px inside it.
local RIM = 50 - 3.5 - 1

local tests = {}

function tests.walkedPartFadedAndTheWayAheadInBlue()
    local drawn = fresh()
    H.assertEq(#drawn.pieces, 2)
    local behind, ahead = drawn.pieces[1], drawn.pieces[2]
    H.assertTrue(behind.color == PASSED, "the part behind is faded")
    H.assertTrue(ahead.color == BLUE, "the way ahead in blue")
    -- South of the player is down the minimap, north up.
    local b, a = behind.pts, ahead.pts
    H.assertTrue(near(b[1], 0) and near(b[2], -RIM), "from the rim: " .. b[1] .. "," .. b[2])
    H.assertTrue(near(b[#b - 1], 0) and near(b[#b], -7), "to the player's arrow, short of it")
    H.assertTrue(near(a[1], 0) and near(a[2], 7), "on past the arrow")
    H.assertTrue(near(a[#a - 1], 0) and near(a[#a], RIM), "up to the rim")
end

-- Era, TBC and Mists have no view radius call, and their minimap showed
-- no line at all (2026-10-27): the reach by zoom level stands in.
function tests.noViewRadiusCall_theZoomLevelSaysTheReach()
    local drawn = fresh(nil, nil, nil, { level = 4, indoors = false })
    H.assertEq(#drawn.pieces, 2, "drawn at all")
    H.assertTrue(near(drawn.pieces[1].pts[2], -RIM), "zoom 4 outdoors, 100 yd: the walk behind reaches the rim")
    drawn = fresh(nil, nil, nil, { level = 0, indoors = false })
    local b = drawn.pieces[1].pts
    H.assertTrue(math.abs(b[2] + 100 * 50 / 233.33) < 0.1, "zoom 0, 233 yd: 100 yd behind is 21 px down: " .. b[2])
    drawn = fresh(nil, nil, nil, { level = 5, indoors = true })
    H.assertTrue(near(drawn.pieces[1].pts[2], -RIM), "indoors at zoom 5, 25 yd: the rim")
end

-- Ironforge's minimap is on its inside set while IsIndoors says outdoors
-- (2026-10-30, the walk drawn through the lava): the set is the zoom
-- cvar the minimap's zoom matches, not IsIndoors.
function tests.theMinimapsOwnSet_notIsIndoors()
    local drawn = fresh(nil, nil, nil, { level = 2, indoors = false, inside = 2, outside = 0 })
    H.assertTrue(near(drawn.pieces[1].pts[2], -RIM), "zoom 2 on the inside set, 90 yd: 100 yd behind reaches the rim")
    drawn = fresh(nil, nil, nil, { level = 2, indoors = true, inside = 0, outside = 2 })
    local b = drawn.pieces[1].pts
    H.assertTrue(math.abs(b[2] + 100 * 50 / 166.67) < 0.1, "zoom 2 on the outside set, 167 yd, whatever IsIndoors says: " .. b[2])
end

-- The two cvars alike say nothing: a zoom step lands in the set the
-- minimap is on, and is put back at once.
function tests.zoomSetsAlike_aZoomStepTellsThemApart()
    local zoom = { level = 2, indoors = false, inside = 2, outside = 2, mode = "inside" }
    local drawn = fresh(nil, nil, nil, zoom)
    H.assertTrue(near(drawn.pieces[1].pts[2], -RIM), "the step landed in the inside cvar: the inside set")
    H.assertEq(zoom.level, 2, "the zoom put back")
    H.assertEq(zoom.sets, 2, "one step and its return")
    zoom = { level = 0, indoors = false, inside = 0, outside = 0, mode = "outside" }
    drawn = fresh(nil, nil, nil, zoom)
    local b = drawn.pieces[1].pts
    H.assertTrue(math.abs(b[2] + 100 * 50 / 233.33) < 0.1, "the step landed in the outside cvar: 233 yd: " .. b[2])
    H.assertEq(zoom.level, 0, "zoom 0 stepped up and put back")
end

-- Out of the door the client flips the set and says so: the next drawing reads it again.
function tests.theSetChanged_readAgainAtTheNextDrawing()
    local zoom = { level = 2, indoors = false, inside = 2, outside = 0 }
    local drawn, _, now, Mini = fresh(nil, nil, nil, zoom)
    H.assertTrue(near(drawn.pieces[1].pts[2], -RIM), "inside first")
    zoom.inside, zoom.outside = 0, 2
    Mini._driver:GetScript("OnEvent")(Mini._driver, "MINIMAP_UPDATE_ZOOM")
    now.t = now.t + 1
    Mini._driver:GetScript("OnUpdate")(Mini._driver, 1)
    local b = drawn.pieces[1].pts
    H.assertTrue(math.abs(b[2] + 100 * 50 / 166.67) < 0.1, "the outside set after the event: " .. b[2])
end

-- Era and TBC set no user waypoint, so the game shows no blip at the
-- step's spot on the minimap (2026-10-28): our disc stands there, within
-- the rim, in the step's color; retail keeps the game's own.
function tests.noUserWaypoints_theStepsSpotWearsADisc()
    local _, state, now, Mini = fresh(nil, nil, nil, { level = 1, indoors = false })   -- 200 yd: the spot at 75 px is past the rim
    local mark = Mini._mark
    H.assertTrue(mark ~= nil, "the disc is made where the client sets no waypoint")
    H.assertFalse(mark:IsShown(), "300 yd north on a 200 yd minimap: past the rim, hidden")
    local placed
    mark.SetPoint = function(_, p, _, _, x, y) placed = { x = x, y = y } end
    local color
    mark.disc.SetVertexColor = function(_, r, g, b) color = { r, g, b } end
    state.rotate = false
    now.t = now.t + 1
    -- The player 240 yd along: the spot 60 yd ahead, 15 px up the minimap.
    local ns = Mini._ns
    ns.GPS.PlayerWorldPos = function() return 1, 240, 0 end
    Mini._Draw()
    H.assertTrue(mark:IsShown(), "within the rim: shown")
    H.assertTrue(near(placed.x, 0) and near(placed.y, 15), "15 px up: " .. tostring(placed and placed.y))
    H.assertTrue(color[1] == BLUE[1] and color[3] == BLUE[3], "in the walk's color")
    ns.GPS.PlayerWorldPos = function() return 1, 298, 0 end
    Mini._Draw()
    H.assertFalse(mark:IsShown(), "under the player's arrow: hidden")
end

function tests.withUserWaypoints_theGamesBlipIsEnough()
    local _, _, _, Mini = fresh(nil, nil, nil, nil, true)
    H.assertNil(Mini._mark, "no disc of ours beside the game's")
end

-- Deadly ground from 20 to 60 yd ahead of the player: red there, the way
-- on either side blue.
function tests.deadlyGroundAheadIsRed()
    local drawn = fresh({ n = 2, 120, 160 })
    local colors = {}
    for i = 1, #drawn.pieces do colors[i] = drawn.pieces[i].color end
    H.assertEq(#drawn.pieces, 4)
    H.assertTrue(colors[1] == PASSED and colors[2] == BLUE and colors[3] == RED and colors[4] == BLUE)
    local red = drawn.pieces[3].pts
    H.assertTrue(near(red[2], 10) and near(red[#red], 30), "from 20 to 60 yd: " .. red[2] .. "," .. red[#red])
end

function tests.deadlyGroundAlreadyWalkedIsNotRed()
    local drawn = fresh({ n = 2, 20, 60 })
    H.assertEq(#drawn.pieces, 2)
    H.assertTrue(drawn.pieces[1].color == PASSED and drawn.pieces[2].color == BLUE)
end

-- The GPS settings' Red on dangerous stretches switch, off: the same
-- deadly ground ahead draws in the way's own color.
function tests.redTurnedOff_deadlyGroundAheadKeepsItsColor()
    local drawn = fresh({ n = 2, 120, 160 }, nil, nil, nil, nil, { gpsDangerRed = false })
    for i = 1, #drawn.pieces do
        H.assertTrue(drawn.pieces[i].color ~= RED, "piece " .. i .. " is red")
    end
end

function tests.aTurningMinimapTurnsTheLine()
    local drawn, state, now, Mini = fresh()
    -- Facing west: west is up, so north lies to the right.
    state.rotate, state.facing = true, math.pi / 2
    now.t = now.t + 1
    Mini._Draw()
    local a = drawn.pieces[2].pts
    H.assertTrue(near(a[1], 7) and near(a[2], 0), "on to the right: " .. a[1] .. "," .. a[2])
    H.assertTrue(near(a[#a - 1], RIM) and near(a[#a], 0))
end

-- 60 yd west of the walk with no way back on foot (a room the grid has no
-- door to, 2026-10-26): straight east onto it, in the step's color, from
-- the edge of the player's arrow.
function tests.offTheWalkWithNoWayBackDrawsTheStraightWayBack()
    local drawn = fresh(nil, 60, true)
    local back = drawn.pieces[1]
    H.assertTrue(back ~= nil and back.color == BLUE, "the way back in the step's color")
    local p = back.pts
    H.assertTrue(near(p[1], 7) and near(p[2], 0), "from the arrow's edge: " .. p[1] .. "," .. p[2])
    H.assertTrue(near(p[#p - 1], 30) and near(p[#p], 0), "to the walk 60 yd east: " .. p[#p - 1] .. "," .. p[#p])
end

function tests.onTheWalkNoWayBackIsDrawn()
    local drawn = fresh(nil, 10, true)
    H.assertTrue(drawn.pieces[1].color == PASSED, "within 20 yd the walk itself leads")
end

-- 30 yd west of the walk with a way back drawn: the walk behind stays
-- faded up to abreast of the player (15 px to the right), then across to
-- the player; the way back and the walk's rest ahead in the step's color.
function tests.offTheWalkOnAWayBackTheWalkBehindStaysFaded()
    local drawn = fresh(nil, 30)
    local behind, ahead = drawn.pieces[1], drawn.pieces[2]
    H.assertTrue(behind ~= nil and behind.color == PASSED, "the walk behind faded")
    local b = behind.pts
    H.assertTrue(near(b[1], 15) and b[2] < -RIM + 5, "up from the rim, 15 px right of the player: " .. b[1] .. "," .. b[2])
    local abreast
    for i = 1, #b - 1, 2 do
        if near(b[i], 15) and near(b[i + 1], 0) then abreast = true end
    end
    H.assertTrue(abreast, "through the point abreast of the player")
    H.assertTrue(near(b[#b - 1], 7) and near(b[#b], 0), "across to the player's arrow: " .. b[#b - 1] .. "," .. b[#b])
    H.assertTrue(ahead ~= nil and ahead.color == BLUE, "the way back ahead in the step's color")
    H.assertTrue(ahead.pts[1] > 0 and ahead.pts[2] > 0, "from the player toward the walk ahead")
end

function tests.standingStillDrawsNothingAgain()
    local drawn, _, now, Mini = fresh()
    local calls = drawn.calls
    now.t = now.t + 1
    Mini._Draw()
    H.assertEq(drawn.calls, calls, "the same spot, the same drawing")
end

-- A flying leg has no way on the ground: it is drawn from where the player
-- is, the part behind faded, never from where the leg began (a flight
-- across Eversong kept the line at the take-off spot however far the
-- player flew).
function tests.aFlyingLeg_isDrawnFromThePlayer()
    local drawn, _, now, Mini = fresh(nil, 50)
    Mini._ns.GPS.CurrentRoute().steps[1].fly = true
    -- Moved since the last draw: nothing is drawn again while standing still.
    Mini._ns.GPS.PlayerWorldPos = function() return 1, 10, 50 end
    now.t = now.t + 1
    Mini._Draw()
    local ahead, behind
    for _, p in ipairs(drawn.pieces) do
        if p.color == BLUE then ahead = p elseif p.color == PASSED then behind = p end
    end
    -- Lines keep clear of the player's arrow: a start at the player sits
    -- just outside that hole, not 50 px south where the leg began.
    local function atPlayer(x, y) return x * x + y * y < 10 * 10 end
    H.assertTrue(ahead ~= nil, "the leg ahead is drawn")
    H.assertTrue(atPlayer(ahead.pts[1], ahead.pts[2]),
        "it starts at the player: " .. tostring(ahead.pts[1]) .. "," .. tostring(ahead.pts[2]))
    local dump = {}
    for _, p in ipairs(drawn.pieces) do
        dump[#dump + 1] = (p.color == BLUE and "blue" or p.color == PASSED and "passed" or "other") .. "[" .. table.concat(p.pts, ",") .. "]"
    end
    H.assertTrue(behind ~= nil, "the part behind is drawn faded; drawn: " .. table.concat(dump, " "))
    H.assertTrue(atPlayer(behind.pts[#behind.pts - 1], behind.pts[#behind.pts]), "and ends at the player")
    H.assertFalse(atPlayer(behind.pts[1], behind.pts[2]), "from where the leg began")
end

local pass, fail, failures = H.runSuite("GPSMinimap", tests)
return { pass = pass, fail = fail, failures = failures }
