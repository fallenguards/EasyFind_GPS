-- Route planning > Avoid (GPS.lua GPS.Avoids, GPS.AvoidKinds, GPS.AvoidRow):
-- the hearthstone has a switch of its own, the teleports another, shown
-- only to a character that has one. Until 1.7.0 one switch held both
-- ("Hearthstone and teleports"): a save from then has both off.
local H = require("Harness")

local function Slice(src, from, to)
    local s = assert(src:find(from, 1, true), from)
    local e = assert(src:find(to, s, true), to)
    return src:sub(s, e - 1)
end

local function Load(db, hasTeleports)
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local GPS, rerouted = {}, 0
    local L = setmetatable({}, { __index = function(_, k) return k end })
    local env = setmetatable({
        GPS = GPS, L = L, DB = function() return db end,
        ns = { GPSRoute = { HasTeleports = function() return hasTeleports end } },
        Route = function() return { arrived = false } end,
    }, { __index = _G })
    -- Planned again at once, whatever the planner is at (test_gps_avoid_replan.lua).
    GPS.PlanAgain = function() rerouted = rerouted + 1 end
    local chunk = Slice(src, "function GPS.Avoids()", "\n-- This character's slot")
        .. Slice(src, "function GPS.AvoidKinds()", "\n-- The menu row hiding the steps already done")
    assert(load(chunk, "=GPS.lua Avoid", "t", env))()
    return GPS, function() return rerouted end
end

local function Has(list, kind)
    for i = 1, #list do if list[i] == kind then return true end end
    return false
end

local tests = {}

function tests.theHearthstoneHasItsOwnSwitch()
    local db = {}
    local GPS, rerouted = Load(db, true)
    local hearth, teleports = GPS.AvoidRow("hearth"), GPS.AvoidRow("teleports")
    H.assertEq(hearth.label, "GPS_AVOID_HEARTH")
    H.assertEq(teleports.label, "GPS_AVOID_TELEPORTS")
    hearth.set(true)
    H.assertTrue(hearth.get(), "the hearthstone, off")
    H.assertFalse(teleports.get(), "the teleports, untouched")
    H.assertEq(rerouted(), 1, "the route in progress is planned again")
    hearth.set(false)
    teleports.set(true)
    H.assertFalse(hearth.get())
    H.assertTrue(teleports.get())
end

function tests.aSaveFromTheOneSwitch_hasBothOff()
    local db = { gpsAvoid = { teleport = true, boat = true } }
    local GPS = Load(db, true)
    H.assertTrue(GPS.AvoidRow("hearth").get())
    H.assertTrue(GPS.AvoidRow("teleports").get())
    H.assertNil(db.gpsAvoid.teleport, "the old switch is gone from the save")
    H.assertTrue(db.gpsAvoid.boat, "the rest stays")
    -- Turned on again, the hearthstone stays on: nothing carries over twice.
    GPS.AvoidRow("hearth").set(false)
    H.assertFalse(GPS.AvoidRow("hearth").get())
    H.assertTrue(GPS.AvoidRow("teleports").get())
end

function tests.noSave_avoidsNothing()
    local GPS = Load({}, true)
    H.assertNil(GPS.Avoids())
    H.assertFalse(GPS.AvoidRow("hearth").get())
end

-- Dangerous areas are avoided until turned off: only the off is saved.
function tests.dangerousAreas_onUntilTurnedOff()
    local db = {}
    local danger = Load(db, true).AvoidRow("danger")
    H.assertTrue(danger.get(), "on with nothing saved")
    danger.set(false)
    H.assertFalse(danger.get())
    H.assertEq(db.gpsAvoid.danger, false, "the off is saved")
    danger.set(true)
    H.assertTrue(danger.get())
    H.assertNil(db.gpsAvoid.danger, "on again: nothing saved")
    H.assertTrue(Load({ gpsAvoid = { danger = true } }, true).AvoidRow("danger").get(), "a save from before: on")
end

function tests.theTeleportsSwitch_isForACharacterWithOne()
    local with = Load({}, true).AvoidKinds()
    H.assertTrue(Has(with, "hearth") and Has(with, "teleports"))
    H.assertFalse(Has(with, "teleport"), "the one switch is gone")
    local without = Load({}, false).AvoidKinds()
    H.assertTrue(Has(without, "hearth"), "everyone has a hearthstone")
    H.assertFalse(Has(without, "teleports"))
end

-- Every switch has its text in every language.
function tests.bothSwitchesAreNamedInEveryLanguage()
    for _, locale in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local f = assert(io.open(H.Path("Locales/" .. locale .. ".lua"), "rb"))
        local text = f:read("*a")
        f:close()
        H.assertTrue(text:find('L["GPS_AVOID_HEARTH"]', 1, true) ~= nil, locale .. " names the hearthstone")
        H.assertTrue(text:find('L["GPS_AVOID_TELEPORTS"]', 1, true) ~= nil, locale .. " names the teleports")
        H.assertTrue(text:find('L["GPS_AVOID_TELEPORT"]', 1, true) == nil, locale .. " still has the one switch's text")
    end
end

local pass, fail, failures = H.runSuite("GPSAvoidSwitches", tests)
return { pass = pass, fail = fail, failures = failures }
