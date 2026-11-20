-- What a plan costs: a walk's landmark bound (a search at each end) is
-- worked out only for walks the route could take, and what walks found
-- under one drop limit is still there after a trial under another. Each
-- route ends with such trials, and a short walk in Tirisfal took 1.4 to
-- 2.4 s of planning, a re-route 4.9 s (gpsrec, 2026-11-20).
local H = require("Harness")
local Inflate = require("Inflate")

local tests = {}

-- Route.lua over a stand-in grid whose bound is the straight line; asked
-- counts the bounds worked out.
local function Engine()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
    env.CreateVector2D = vec
    env.C_Map = {
        GetMapInfo = function(m) return { name = "Map " .. tostring(m) } end,
        GetBestMapForUnit = function() return nil end,
        GetWorldPosFromMapPos = function(_, v) return 1, vec(v.x * 10000, v.y * 10000) end,
    }
    env.GetTime = function() return 0 end
    H.loadModule("Route.lua", env, ns)
    local count = { asked = 0 }
    local function Line(sx, sy, tx, ty) return math.sqrt((tx - sx) ^ 2 + (ty - sy) ^ 2) end
    ns.GPSNav = {
        Ensure = function() return true end,
        Has = function() return true end,
        CostOverTime = function() return 1 end,
        Bound = function(_, ax, ay, bx, by)
            count.asked = count.asked + 1
            return Line(ax, ay, bx, by)
        end,
        Path = function(_, sx, sy, tx, ty) return { sx, sy, tx, ty }, Line(sx, sy, tx, ty) end,
        Walk = function(_, sx, sy, tx, ty)
            local d = Line(sx, sy, tx, ty)
            return d, nil, d
        end,
    }
    return ns.GPSRoute, count
end

local function P(x, y) return { m = 1, x = x, y = y, ci = 1, wx = x * 10000, wy = y * 10000 } end

-- Forty docks across the continent, none near the walk.
local function Continent()
    local edges = {}
    for k = 1, 20 do
        edges[k] = { kind = "boat", n = "Boat " .. k, from = P(0.9, 0.04 * k), to = P(0.95, 0.04 * k), sec = 60, bidir = true }
    end
    return { speeds = { run = 7, mount = 10, fly = 20, taxi = 40 }, nodes = {}, legs = {}, edges = edges,
             abilities = {}, classic = true }
end

function tests.aShortWalk_boundsOnlyTheWalksItCouldTake()
    local Route, count = Engine()
    local steps, total = Route:Build({ name = "Spot", mapID = 1, x = 0.12, y = 0.1 },
        { data = Continent(), start = P(0.1, 0.1), faction = "Alliance", canFly = false, groundSpeed = 7,
          owns = function() return false end, cooldown = function() return 0 end })
    H.assertTrue(steps ~= nil and #steps == 1, "the walk itself")
    H.assertTrue(math.abs(total - 200 / 7) < 0.5, "200 yd on foot: " .. tostring(total))
    H.assertTrue(count.asked <= 2, "the far docks' walks are never bounded: " .. count.asked .. " asked")
end

-- Across the continent every dock on the way comes up: bounded then, and
-- the route the same as with each walk bounded at once.
function tests.aLongWalk_stillTakesTheCrossingThatSaves()
    local Route, count = Engine()
    local data = Continent()
    data.edges[21] = { kind = "portal", n = "Portal east", from = P(0.11, 0.1), to = P(0.88, 0.5), sec = 10 }
    local steps, total = Route:Build({ name = "Far", mapID = 1, x = 0.88, y = 0.52 },
        { data = data, start = P(0.1, 0.1), faction = "Alliance", canFly = false, groundSpeed = 7,
          owns = function() return false end, cooldown = function() return 0 end })
    local kinds = {}
    for i = 1, #steps do kinds[i] = steps[i].kind end
    H.assertEq(table.concat(kinds, ","), "travel,portal,travel")
    H.assertTrue(math.abs(total - (100 + 200) / 7 - 10) < 1, "100 yd, the portal, 200 yd: " .. tostring(total))
    H.assertTrue(count.asked > 0, "walks that come up are bounded")
end

-- Nav.lua on the two-tile bake of Elwynn Forest.
local GOLDSHIRE = { -9465, 64 }
local EAST = { -9300, -300 }
local function Grid()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.debugprofilestop = env.debugprofilestop or function() return 1 end
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    H.loadModule("tests/fixtures/nav_elwynn.lua", env, ns)
    H.loadModule("Nav.lua", env, ns)
    return ns.GPSNav, env
end

function tests.aTrialUnderAnotherLimit_leavesWhatWasFound()
    local Nav = Grid()
    Nav.SetDropLimit(15)
    local cost = Nav.Walk(0, GOLDSHIRE[1], GOLDSHIRE[2], EAST[1], EAST[2])
    Nav.Bound(0, GOLDSHIRE[1], GOLDSHIRE[2], EAST[1], EAST[2])
    local w = Nav._worlds[0]
    local walks, costs, reach, marks = w.walks, w.costs, w.reach, w.marks
    H.assertTrue(next(walks) ~= nil and next(costs) ~= nil and next(reach) ~= nil and next(marks) ~= nil, "the walk kept its finds")
    Nav.SetDropLimit(math.huge)
    H.assertTrue(w.walks ~= walks and next(w.walks) == nil, "the trial starts with none of them")
    H.assertTrue(next(w.costs) == nil and next(w.reach) == nil and next(w.marks) == nil, "nor costs, ends or landmarks")
    Nav.Walk(0, GOLDSHIRE[1], GOLDSHIRE[2], EAST[1], EAST[2])
    local trial = w.walks
    Nav.SetDropLimit(15)
    H.assertTrue(w.walks == walks and w.costs == costs and w.reach == reach and w.marks == marks, "back under the first limit: all found again")
    H.assertEq(Nav.Walk(0, GOLDSHIRE[1], GOLDSHIRE[2], EAST[1], EAST[2]), cost)
    Nav.SetDropLimit(math.huge)
    H.assertTrue(w.walks == trial, "and the trial's own for the next trial")
    Nav.SetDropLimit(nil)
end

-- Danger or roads changed: every walk comes out differently, shelved or not.
function tests.newDangerOrRoads_dropTheShelvedToo()
    local Nav = Grid()
    Nav.SetDropLimit(15)
    Nav.Walk(0, GOLDSHIRE[1], GOLDSHIRE[2], EAST[1], EAST[2])
    Nav.SetDropLimit(math.huge)
    local w = Nav._worlds[0]
    H.assertTrue(next(w.shelf) ~= nil, "the first limit's finds wait")
    Nav.SetDanger({ [0] = {} })
    H.assertNil(next(w.shelf), "gone with the danger changed")
    Nav.SetDropLimit(15)
    H.assertNil(next(w.walks), "nothing taken up from before")
    Nav.SetRoads(true)
    H.assertNil(next(w.shelf), "and with the roads switch")
    Nav.SetRoads(false)
    Nav.SetDanger(nil)
    Nav.SetDropLimit(nil)
end

-- Shelved costs and ends go idle like the ones in use; the landmark
-- distances outlast the continent's idle wipe.
function tests.release_shelvedFindsGoIdle_landmarksStay()
    local Nav, env = Grid()
    Nav.SetDropLimit(15)
    Nav.Walk(0, GOLDSHIRE[1], GOLDSHIRE[2], EAST[1], EAST[2])
    Nav.Bound(0, GOLDSHIRE[1], GOLDSHIRE[2], EAST[1], EAST[2])
    local w = Nav._worlds[0]
    local marks = w.marks
    Nav.SetDropLimit(math.huge)
    local shelved = w.shelf[15]
    H.assertTrue(shelved ~= nil and next(shelved[5]) ~= nil and shelved[4] > 0, "costs and ends on the shelf")
    env._clock:advance(61)
    Nav.Walk(0, EAST[1], EAST[2], EAST[1] + 60, EAST[2] + 40)
    H.assertTrue(Nav.Release(60), "the continent is in use: held")
    H.assertNil(next(shelved[5]), "the shelved costs went idle")
    H.assertNil(next(shelved[3]), "and the shelved ends")
    H.assertEq(shelved[4], 0, "their count follows")
    env._clock:advance(61)
    Nav.Release(60)
    H.assertNil(w.used, "the continent idle")
    H.assertNil(next(w.walks), "its walks gone")
    Nav.SetDropLimit(15)
    H.assertTrue(w.marks == marks and next(marks) ~= nil, "the landmark distances are still there")
    Nav.SetDropLimit(nil)
end

-- A pair's danger weight is its line's share in each quarter, worked out
-- quarter by quarter: the same as weighing the line at 20,000 points.
function tests.aLinesDangerWeight_isEachQuartersShare()
    local Nav = Grid()
    local dw = {}
    for k = 1, 16 do dw[k] = ({ 1, 1.5, 2.5, 5 })[(k * 7) % 4 + 1] end
    local function Sampled(ax, ay, bx, by)
        local sum, n = 0, 20000
        for j = 0, n - 1 do
            local f = (j + 0.5) / n
            local qx, qy = math.floor(ax + (bx - ax) * f), math.floor(ay + (by - ay) * f)
            sum = sum + dw[qx * 4 + qy + 1]
        end
        return sum / n
    end
    local lines = {
        { 0.1, 0.1, 3.9, 3.9 }, { 3.9, 0.2, 0.3, 3.7 }, { 0.5, 2.5, 3.5, 2.5 }, { 1.5, 3.9, 1.5, 0.1 },
        { 0.2, 0.3, 0.8, 0.6 }, { 2.9, 1.1, 0.4, 1.8 }, { 3.99, 3.99, 0.01, 0.02 }, { 1.2, 0.4, 1.7, 3.6 },
    }
    for _, l in ipairs(lines) do
        local got, want = Nav._lineWeight(dw, l[1], l[2], l[3], l[4]), Sampled(l[1], l[2], l[3], l[4])
        H.assertTrue(math.abs(got - want) < 0.001, table.concat(l, ", ") .. ": " .. got .. " for " .. want)
        H.assertTrue(math.abs(got - Nav._lineWeight(dw, l[3], l[4], l[1], l[2])) < 1e-9, "the same the other way round")
    end
    H.assertEq(Nav._lineWeight(dw, 2.2, 1.3, 2.8, 1.9), dw[2 * 4 + 1 + 1])
end

local pass, fail, failures = H.runSuite("GPSPlanCost", tests)
return { pass = pass, fail = fail, failures = failures }
