-- Undercity's sewers on the shipped Forever grid (2026-11-17): a walk from
-- west of the city to Master Apothecary Faranell (A Recipe For Death)
-- goes in through the sewers, and the walk names that floor (Nav.Path's
-- levels, from Floors' names) so its step can say so.
local H = require("Harness")
local Inflate = require("Inflate")

local function Load()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    ns.Caps = { forever = true }
    env.C_EncodingUtil = { DecodeBase64 = Inflate.DecodeBase64, DecompressString = function(s) return Inflate.Raw(s) end }
    env.GetSubZoneText = function() return "" end
    env.GetZoneText = function() return "" end
    env.GetLocale = function() return "deDE" end
    for _, f in ipairs({ "Walk_EasternKingdoms.lua", "Floors_Forever.lua", "Floors.lua", "Nav.lua" }) do H.loadModule(f, env, ns) end
    ns.GPS = { PlayerWorldPos = function() return nil end }
    return ns
end

local WEST = { 1300, 1000 }               -- Tirisfal, west of the city
local FARANELL = { 1434.48, 404.854 }     -- in the Apothecarium (VMaNGOS spawn)

local tests = {}

function tests.aWalkIntoTheCityFromTheWest_namesTheSewers()
    local ns = Load()
    local pts, _, _, _, levels = ns.GPSNav.Path(0, WEST[1], WEST[2], FARANELL[1], FARANELL[2], { indoorsB = true })
    H.assertNotNil(pts, "a way on foot")
    local names = {}
    for _, l in ipairs(levels or {}) do names[#names + 1] = l.en end
    H.assertEq(names[1], "Sewers", "into the sewers first: " .. table.concat(names, ", "))
    H.assertEq(levels[1].name, "Die Abwasserkanäle", "and in the client's language")
    local v = levels[1].v
    H.assertTrue(v ~= nil and pts[2 * v - 1] ~= nil, "at a point of the walk, kept through its straightening")
end

local pass, fail, failures = H.runSuite("GPSSewers", tests)
return { pass = pass, fail = fail, failures = failures }
