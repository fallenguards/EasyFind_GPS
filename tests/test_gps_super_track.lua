-- One thing lit at a time (GPS.lua): a quest the player picks while the
-- route is tracked (a click on a frame in that frame) makes the route let
-- go; one with no click (a guide tracking its step's quest) is taken back;
-- tracking the route clears a quest's super-track, so the tracker never
-- lights both.
local H = require("Harness")

local POI, WORLD = {}, {}

local function Load(state)
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local s = assert(src:find("function GPS.ReleaseTracking(route)", 1, true), "GPS.ReleaseTracking")
    local e = assert(src:find("-- The toggle's faces", s, true), "the block's end")
    local onEvent
    local ST = {
        IsSuperTrackingQuest = function() return state.quest ~= 0 end,
        SetSuperTrackedQuestID = function(id) state.quest = id end,
        SetSuperTrackedUserWaypoint = function(on) state.waypoint = on end,
    }
    -- The game's pin changed at once, as with the world map closed.
    local GPS = { GamePinChange = function(_, fn) fn() end }
    function GPS.TrackGamePin(on) ST.SetSuperTrackedUserWaypoint(on) end
    local env = setmetatable({
        GPS = GPS, C_SuperTrack = ST, ns = {},
        Route = function() return state.route end,
        RouteTracked = function() return state.route ~= nil and not state.route.untracked end,
        Refresh = function() state.refreshed = (state.refreshed or 0) + 1 end,
        TrackStep = function()
            state.retaken = (state.retaken or 0) + 1
            state.quest = 0
            ST.SetSuperTrackedUserWaypoint(true)
        end,
        GetTime = function() return state.now or 0 end,
        GetMouseFoci = function() return { state.over } end,
        WorldFrame = WORLD,
        Utils = {
            SafeAfter = function(_, fn) fn() end,
            RegisterEventIfValid = function(f, event) f:RegisterEvent(event) return true end,
        },
        CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function(_, _, fn) onEvent = fn end }
        end,
    }, { __index = _G })
    assert(load(src:sub(s, e - 1), "=GPS.lua tracking", "t", env))()
    return GPS, function(event) onEvent(nil, event or "SUPER_TRACKING_CHANGED") end
end

local tests = {}

function tests.aQuestPickedByAClick_makesTheRouteLetGo()
    local state = { route = {}, quest = 0, waypoint = true, now = 10, over = POI }
    local _, fire = Load(state)
    fire("GLOBAL_MOUSE_UP")
    state.quest = 1234   -- the player clicked a quest's POI
    fire()
    H.assertTrue(state.route.untracked, "the route lets go")
    H.assertFalse(state.waypoint, "the game's waypoint no longer super-tracked")
    H.assertEq(state.refreshed, 1, "drawn again")
end

-- A guide tracks its step's quest as the step comes up (2026-11-19: the
-- arrow went on reaching Brill, A New Plague's turn-in step tracked, and
-- nothing brought it back): no click, so the route takes the track back.
function tests.aQuestTrackedWithNoClick_isTakenBackByTheRoute()
    local state = { route = {}, quest = 0, waypoint = true, now = 10, over = POI }
    local _, fire = Load(state)
    fire("GLOBAL_MOUSE_UP")
    state.now = 12
    state.quest = 369
    fire()
    H.assertNil(state.route.untracked, "the route keeps leading")
    H.assertEq(state.retaken, 1, "and takes the track back")
    H.assertEq(state.quest, 0)
    H.assertTrue(state.waypoint)
    H.assertNil(state.refreshed, "nothing to draw again")
end

-- A press on the world itself (turning the camera) is no pick.
function tests.aPressOnTheWorld_isNoPick()
    local state = { route = {}, quest = 0, waypoint = true, now = 10, over = WORLD }
    local _, fire = Load(state)
    fire("GLOBAL_MOUSE_DOWN")
    state.quest = 369
    fire()
    H.assertNil(state.route.untracked)
    H.assertEq(state.retaken, 1)
end

function tests.nothingChangesWithoutAQuest()
    local state = { route = {}, quest = 0, waypoint = true }
    local _, fire = Load(state)
    fire()
    H.assertNil(state.route.untracked)
    H.assertTrue(state.waypoint)
    H.assertNil(state.retaken)
end

function tests.trackingTheRouteClearsTheQuest()
    local state = { route = {}, quest = 1234 }
    local GPS = Load(state)
    GPS.ClearQuestSuperTrack()
    H.assertEq(state.quest, 0, "the quest's super-track cleared")
end

local pass, fail, failures = H.runSuite("GPSSuperTrack", tests)
return { pass = pass, fail = fail, failures = failures }
