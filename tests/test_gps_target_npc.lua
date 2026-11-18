-- Tests for Arrow.lua's Target button: near the NPC a route leads to, a
-- secure button under the arrow's plate targets it by name and marks it.
-- The game targets and marks only on the player's press (TargetUnit,
-- SetRaidTarget restricted): a secure macro.
local H = require("Harness")

local NPC_SPOT = { ci = 1, wx = 500, wy = 500 }

local function fresh(opts)
    opts = opts or {}
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    local combat = { v = false }
    env.InCombatLockdown = function() return combat.v end
    local frames = {}
    env.CreateFrame = function(_, name)
        local f = H.newFrame()
        local size = { 0, 0 }
        f.name = name
        f.SetSize = function(_, w, h) size = { w, h } end
        f.GetSize = function() return size[1], size[2] end
        f.SetFrameStrata = function() end
        f.RegisterForClicks = function() end
        f.SetHighlightTexture = function() end
        frames[#frames + 1] = f
        return f
    end
    env.UIParent = H.newFrame()
    local ticks = {}
    env.C_Timer = {
        After = function() end,
        NewTicker = function(_, fn)
            local t = { fn = fn }
            function t.Cancel() t.cancelled = true end
            ticks[#ticks + 1] = t
            return t
        end,
    }
    local player = { ci = 1, x = 0, y = 0 }
    local db = { gpsTargetMark = opts.mark }
    env.EasyFind.db = db
    local route = { dest = { name = "Kelm Hargunth", npc = "Kelm Hargunth", mapID = 1413, x = 0.5, y = 0.6 },
                    steps = { { kind = "travel" } }, active = 1 }
    local state = { route = route }
    ns.GPS = {
        CurrentRoute = function() return state.route end,
        PlayerWorldPos = function() return player.ci, player.x, player.y end,
        WorldPos = function() return NPC_SPOT.ci, NPC_SPOT.wx, NPC_SPOT.wy end,
    }
    ns.GPSWorldPin = {
        NewPlate = function()
            local p = H.newFrame()
            local text = H.newFrame()
            local shown = ""
            text.SetText = function(_, s) shown = s end
            text.GetText = function() return shown end
            text.GetStringWidth = function() return #shown * 6 end
            p.text = text
            return p
        end,
    }
    ns.GPSFollow = { Now = function() return nil end }
    H.loadModule("Arrow.lua", env, ns)
    local w = { Arrow = ns.GPSArrow, player = player, state = state, combat = combat, ticks = ticks, db = db }
    function w.button()
        for _, f in ipairs(frames) do if f.name == "EasyFindGPSTarget" then return f end end
    end
    function w.tick()
        for _, t in ipairs(ticks) do if not t.cancelled then t.fn() end end
    end
    function w.near() player.x, player.y = 480, 490 end
    function w.far() player.x, player.y = 0, 0 end
    return w
end

local tests = {}

function tests.nearTheNpc_aTargetButtonTargetsAndSkullsIt()
    local w = fresh()
    w.Arrow:Refresh()
    H.assertNil(w.button(), "far off: no button yet")
    w.near()
    w.tick()
    local btn = assert(w.button(), "near: the button")
    H.assertTrue(btn:IsShown())
    H.assertEq(btn:GetAttribute("type"), "macro")
    H.assertEq(btn:GetAttribute("macrotext"),
        "/cleartarget\n/targetexact Kelm Hargunth\n/tm [@target,exists] !8", "cleared first, then the skull kept if it has one")
    w.far()
    w.tick()
    H.assertFalse(btn:IsShown(), "walked off: gone")
    H.assertNil(btn:GetAttribute("type"), "and its macro off")
end

function tests.theMarkOption_noneTargetsOnly()
    local w = fresh({ mark = 0 })
    w.near()
    w.Arrow:Refresh()
    H.assertEq(w.button():GetAttribute("macrotext"), "/cleartarget\n/targetexact Kelm Hargunth")
    local star = fresh({ mark = 1 })
    star.near()
    star.Arrow:Refresh()
    H.assertTrue(star.button():GetAttribute("macrotext"):find("!1", 1, true) ~= nil)
end

function tests.inAFight_theButtonIsNeverTouched()
    local w = fresh()
    w.near()
    w.Arrow:Refresh()
    local btn = w.button()
    w.combat.v = true
    w.far()
    w.tick()
    H.assertTrue(btn:IsShown(), "no secure change in a fight")
    w.combat.v = false
    w.tick()
    H.assertFalse(btn:IsShown())
end

local function live(w)
    local n = 0
    for _, t in ipairs(w.ticks) do if not t.cancelled then n = n + 1 end end
    return n
end

-- Shown on the walk in, gone at the arrival message, the player still
-- standing there (it stayed through the arrival's linger, and before that
-- for good with no way to close it, 2026-11-17).
function tests.arrival_takesTheButton_standingThere()
    local w = fresh()
    w.near()
    w.Arrow:Refresh()
    H.assertTrue(w.button():IsShown(), "near, on the way")
    w.state.route.arrived = true
    w.Arrow:Refresh()
    H.assertFalse(w.button():IsShown(), "arrived: gone")
    w.tick()
    H.assertFalse(w.button():IsShown(), "and stays gone")
    H.assertEq(live(w), 0, "nothing left to watch: the ticker stops")
    w.state.route = nil
    w.Arrow:Refresh()
    H.assertFalse(w.button():IsShown(), "nor back when the route clears")
end

-- A right-click closes it for this route; the left click still targets.
function tests.aRightClick_closesItForThisRoute()
    local w = fresh()
    w.near()
    w.Arrow:Refresh()
    local btn = w.button()
    H.assertEq(btn:GetAttribute("type2"), "dismiss", "the right button's own action")
    H.assertTrue(type(rawget(btn, "dismiss")) == "function", "found by the template on the button itself")
    H.assertEq(btn:GetAttribute("type"), "macro", "the left still targets")
    btn.dismiss(btn)
    H.assertFalse(btn:IsShown(), "closed")
    w.tick()
    H.assertFalse(btn:IsShown(), "stays closed while near")
    H.assertEq(live(w), 0)
    w.state.route = { dest = { name = "Kelm Hargunth", npc = "Kelm Hargunth", mapID = 1413, x = 0.5, y = 0.6 },
                      steps = {}, active = 1 }
    w.Arrow:Refresh()
    H.assertTrue(btn:IsShown(), "a new route brings it back")
end

-- On a trip the NPC is the leg's stop, not the trip's last.
function tests.aTrip_targetsTheStopOfTheLegWalked()
    local w = fresh()
    local first = { name = "Farmer Furlbrow", npc = "Farmer Furlbrow", mapID = 1436, x = 0.6, y = 0.19 }
    local last = { name = "Gryan Stoutmantle", npc = "Gryan Stoutmantle", mapID = 1436, x = 0.56, y = 0.47 }
    w.state.route = { dest = last, steps = { { kind = "travel", tripStop = first }, { kind = "travel", tripStop = last } },
                      active = 1 }
    w.near()
    w.Arrow:Refresh()
    H.assertTrue(w.button():GetAttribute("macrotext"):find("Farmer Furlbrow", 1, true) ~= nil, "the first leg's")
    w.state.route.active = 2
    w.Arrow:Refresh()
    H.assertTrue(w.button():GetAttribute("macrotext"):find("Gryan Stoutmantle", 1, true) ~= nil, "then the next")
end

function tests.aRouteToAPlace_hasNoButton()
    local w = fresh()
    w.state.route = { dest = { name = "Orgrimmar", mapID = 1454, x = 0.5, y = 0.5 }, steps = {}, active = 1 }
    w.near()
    w.Arrow:Refresh()
    H.assertNil(w.button())
    H.assertEq(#w.ticks, 0, "no ticker without an NPC")
end

local pass, fail, failures = H.runSuite("GPSTargetNpc", tests)
return { pass = pass, fail = fail, failures = failures }
