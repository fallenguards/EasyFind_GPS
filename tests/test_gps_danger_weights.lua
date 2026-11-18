-- Danger weights for a character (Route.lua DangerWeights): each danger
-- cell weighed by how far its creatures are above the character, three or
-- four levels x1.5, five to seven x2.5, eight or more x5.
local H = require("Harness")

local function Route()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    env.GetTime = function() return 0 end
    H.loadModule("Route.lua", env, ns)
    return ns.GPSRoute
end

local THREATS = { [0] = { [1] = 22, [2] = 23, [3] = 24, [4] = 25, [5] = 27, [6] = 28, [7] = 40 } }
local NPCS = { Threats = function() return THREATS end }

local tests = {}

function tests.gradedByLevelsAbove()
    local set = Route().DangerWeights(NPCS, 20, "Alliance")[0]
    H.assertNil(set[1], "two levels above: no danger")
    H.assertEq(set[2], 1.5, "three above")
    H.assertEq(set[3], 1.5, "four above")
    H.assertEq(set[4], 2.5, "five above")
    H.assertEq(set[5], 2.5, "seven above")
    H.assertEq(set[6], 5, "eight above")
    H.assertEq(set[7], 5, "twenty above")
end

-- The same table while level and map hold, so kept walks stay good.
function tests.theSameTableForTheSameLevel()
    local R = Route()
    local a = R.DangerWeights(NPCS, 20, "Alliance")
    H.assertTrue(R.DangerWeights(NPCS, 20, "Alliance") == a, "kept")
    local b = R.DangerWeights(NPCS, 21, "Alliance")
    H.assertTrue(b ~= a, "a new level, a new table")
    H.assertNil(b[0][2], "three above at 20 is two above at 21")
end

function tests.noMap_noDanger()
    local R = Route()
    H.assertNil(R.DangerWeights({}, 20, "Alliance"))
    H.assertNil(R.DangerWeights(nil, 20, "Alliance"))
    H.assertNil(R.DangerWeights(NPCS, nil, "Alliance"))
end

local pass, fail, failures = H.runSuite("GPSDangerWeights", tests)
return { pass = pass, fail = fail, failures = failures }
