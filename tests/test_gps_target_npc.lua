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

-- Arrived, the route lingers then clears: the button stays while the
-- player stands there, and goes once they leave.
function tests.afterArrival_itStaysUntilThePlayerLeaves()
    local w = fresh()
    w.near()
    w.Arrow:Refresh()
    w.state.route = nil
    w.Arrow:Refresh()
    H.assertTrue(w.button():IsShown(), "the route cleared, the NPC still there")
    w.far()
    w.tick()
    H.assertFalse(w.button():IsShown())
    local live = 0
    for _, t in ipairs(w.ticks) do if not t.cancelled then live = live + 1 end end
    H.assertEq(live, 0, "nothing left to watch: the ticker stops")
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
