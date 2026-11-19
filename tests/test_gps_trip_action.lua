-- The navigateTrip action (GPS.lua NavigateTrip): several places in order,
-- planned as the trip editor plans one, for an extension following a guide;
-- and dest.quietArrival, an arrival with no sound.
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

local function Slice(src, a)
    local s = assert(src:find(a, 1, true), a)
    local _, e = assert(src:find("\nend\n", s, true))
    return src:sub(s, e)
end

local function Load()
    local src = Source()
    local GPS, seen = {}, { opened = 0, sounds = 0 }
    function GPS.LeadsTo(data) return data end
    function GPS:CanNavigate(data) return data.mapID ~= nil end
    function GPS:Open() seen.opened = seen.opened + 1 end
    function GPS:ShowWindow() seen.window = true end
    function GPS:Plan(_, build, done) done(build()) end
    function GPS.Navigated(dest, _, _, _, stops, avoid) seen.dest, seen.stops, seen.kept = dest, stops, avoid end
    function GPS.Avoids() return seen.settings end
    function GPS:BuildRoute(_, _, avoid) seen.planned = avoid return {}, 1 end
    local env = setmetatable({
        GPS = GPS, INSTANCE_CATEGORIES = {}, EntranceOf = function() return nil end,
        DB = function() return {} end,
        ns = { GPSTrip = { Build = function(stops, _, avoid) seen.built, seen.planned = stops, avoid return {}, 1 end } },
        EasyFind = { API = { Fire = function() end }, db = {} },
        StopTicker = function() end, LiftPin = function() end, Refresh = function() end, Route = function() end,
        Utils = { SafeAfter = function() end }, ARRIVED_LINGER = 1, time = os.time,
        PlaySound = function() seen.sounds = seen.sounds + 1 end, SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 1 },
    }, { __index = _G })
    local code = Slice(src, "local function Destination(data)") .. Slice(src, "local function Arrive(route)")
        .. Slice(src, "function GPS.CallerAvoid(opts)") .. Slice(src, "function GPS:NavigateTo(data, opts)")
        .. Slice(src, "function GPS:NavigateTrip(list, opts)") .. "\nreturn Arrive"
    local Arrive = assert(load(code, "=GPS.lua trip", "t", env))()
    return GPS, seen, Arrive
end

local tests = {}

function tests.aTrip_isPlannedThroughItsPlacesInOrder_toTheLast()
    local GPS, seen = Load()
    local ok = GPS:NavigateTrip({
        { name = "Farmer Furlbrow", npcName = "Farmer Furlbrow", mapID = 1436, x = 0.6, y = 0.19, quietArrival = true },
        { name = "Nowhere" },
        { name = "Gryan Stoutmantle", mapID = 1436, x = 0.56, y = 0.47 },
    }, { quiet = true })
    H.assertTrue(ok)
    H.assertEq(#seen.built, 2, "a place it cannot reach is left out")
    H.assertEq(seen.built[1].npc, "Farmer Furlbrow", "the first stop's NPC for the Target button")
    H.assertTrue(seen.built[1].quietArrival)
    H.assertEq(seen.dest, seen.built[2], "the route's end is the last stop")
    H.assertEq(seen.stops, seen.built, "its stops kept for the trip editor")
    H.assertEq(seen.opened, 0, "quiet: the window is not opened")
end

-- A guide leaves the Hearthstone to its own steps (2026-11-19: a guide's
-- "Travel back to Brill" hearthed): opts.avoid joins the player's own
-- ways left out, for the plan and kept on the route for its replans.
function tests.aCallersAvoid_joinsThePlayersOwn_andStaysWithTheRoute()
    local GPS, seen = Load()
    seen.settings = { taxi = true, danger = false }
    local trip = { { name = "Apothecary Johaan", mapID = 1420, x = 0.6, y = 0.52 },
                   { name = "Executor Zygand", mapID = 1420, x = 0.61, y = 0.52 } }
    GPS:NavigateTrip(trip, { quiet = true, avoid = { hearth = true } })
    H.assertTrue(seen.planned.hearth, "the hearth left out")
    H.assertTrue(seen.planned.taxi, "the player's own still left out")
    H.assertEq(seen.planned.danger, false, "and the player's own switches as set")
    H.assertEq(seen.kept, seen.planned, "kept on the route")
    H.assertNil(seen.settings.hearth, "the player's settings untouched")
    GPS:NavigateTo(trip[1], { quiet = true, avoid = { hearth = true } })
    H.assertTrue(seen.planned.hearth and seen.planned.taxi, "one place the same")
    H.assertEq(seen.kept, seen.planned)
    GPS:NavigateTrip(trip, { quiet = true })
    H.assertNil(seen.planned, "none given: the player's own, as before")
    H.assertNil(seen.kept)
end

function tests.nothingReachable_noTrip()
    local GPS = Load()
    H.assertFalse(GPS:NavigateTrip({ { name = "Nowhere" } }))
    H.assertFalse(GPS:NavigateTrip(nil))
end

function tests.aQuietArrival_playsNoSound()
    local _, seen, Arrive = Load()
    Arrive({ dest = { name = "Farmer Furlbrow", quietArrival = true } })
    H.assertEq(seen.sounds, 0)
    Arrive({ dest = { name = "Booty Bay" } })
    H.assertEq(seen.sounds, 1, "any other arrival still sounds")
end

local pass, fail, failures = H.runSuite("GPSTripAction", tests)
return { pass = pass, fail = fail, failures = failures }
