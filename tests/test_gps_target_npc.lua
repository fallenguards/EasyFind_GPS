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
    env.UIParent.GetSize = function() return 1920, 1080 end
    env.UIParent.GetEffectiveScale = function() return 1 end
    env.GetCursorPosition = function() return 640, 360 end
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
    local menu = {}
    ns.ShowTogglePopup = function(name, anchor, defs) menu.name, menu.anchor, menu.defs = name, anchor, defs end
    H.loadModule("Arrow.lua", env, ns)
    local w = { Arrow = ns.GPSArrow, player = player, state = state, combat = combat, ticks = ticks, db = db,
                menu = menu, frames = frames }
    function w.button(i)
        local name = (i or 1) == 1 and "EasyFindGPSTarget" or ("EasyFindGPSTarget" .. i)
        for _, f in ipairs(frames) do if f.name == name then return f end end
    end
    -- The buttons shown, top first: each one's macro.
    function w.shown()
        local out, i = {}, 1
        while w.button(i) do
            if w.button(i):IsShown() then out[#out + 1] = w.button(i):GetAttribute("macrotext") end
            i = i + 1
        end
        return out
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

-- A right-click opens a menu at the cursor, as the plate's, and its Close
-- closes the NPC for this route; the left click still targets. No hover
-- tooltip (2026-11-19: "get rid of right click to close").
function tests.aRightClick_opensAMenu_whoseCloseClosesItForThisRoute()
    local w = fresh()
    w.near()
    w.Arrow:Refresh()
    local btn = w.button()
    H.assertNil(btn:GetScript("OnEnter"), "no tooltip on hover")
    H.assertEq(btn:GetAttribute("type2"), "rowMenu", "the right button's own action, not the template's unit menu")
    H.assertTrue(type(rawget(btn, "rowMenu")) == "function", "found by the template on the button itself")
    H.assertEq(btn:GetAttribute("type"), "macro", "the left still targets")
    btn.rowMenu(btn)
    H.assertEq(w.menu.name, "EasyFindGPSTargetMenu")
    H.assertEq(#w.menu.defs, 1, "Close alone")
    H.assertEq(w.menu.defs[1].label, "Close")
    H.assertTrue(btn:IsShown(), "open, nothing closed yet")
    w.menu.defs[1].onClick()
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

-- A guide's creatures (setTargets): a button each under the arrow while
-- set, far from any spot, the route's NPC under them when near and not one
-- of them (RestedXP's Active Targets, 2026-11-18).
function tests.aGuidesTargets_aButtonEach_whileSet()
    local w = fresh()
    w.state.route = nil
    w.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" }, { name = "Bareth Dawnstone", kind = "talk" } })
    local shown = w.shown()
    H.assertEq(#shown, 2, "far from any spot, both")
    H.assertTrue(shown[1]:find("/targetexact Scarlet Warrior", 1, true) ~= nil)
    H.assertTrue(shown[2]:find("/targetexact Bareth Dawnstone", 1, true) ~= nil)
    H.assertTrue(w.button(1).look.text:GetText():find("Interface\\Cursor\\Attack", 1, true) ~= nil, "a kill icon")
    H.assertTrue(w.button(1).look.text:GetText():find("Scarlet Warrior", 1, true) ~= nil, "and its name")
    H.assertTrue(w.button(2).look.text:GetText():find("GossipGossipIcon", 1, true) ~= nil, "a talk icon")
    w.Arrow.SetTargets(nil)
    H.assertEq(#w.shown(), 0, "taken away")
    H.assertEq(live(w), 0, "nothing left to watch")
end

function tests.aGuidesTargets_andTheRoutesNpc_once()
    local w = fresh()
    w.near()
    w.Arrow.SetTargets({ { name = "Kelm Hargunth", kind = "talk" } })
    H.assertEq(#w.shown(), 1, "the route's NPC is the guide's: one button")
    w.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" } })
    local shown = w.shown()
    H.assertEq(#shown, 2)
    H.assertTrue(shown[2]:find("Kelm Hargunth", 1, true) ~= nil, "the route's NPC under the guide's")
    H.assertTrue(w.button(2).look.text:GetText():find("Kelm Hargunth", 1, true) ~= nil, "named among others")
end

function tests.aGuidesTarget_closed_staysClosedUntilTheListChanges()
    local w = fresh()
    w.state.route = nil
    local list = { { name = "Scarlet Warrior", kind = "kill" }, { name = "Tirisfal Farmhand", kind = "kill" } }
    w.Arrow.SetTargets(list)
    w.button(1).rowMenu(w.button(1))
    w.menu.defs[1].onClick()
    local shown = w.shown()
    H.assertEq(#shown, 1)
    H.assertTrue(shown[1]:find("Tirisfal Farmhand", 1, true) ~= nil)
    w.tick()
    H.assertEq(#w.shown(), 1, "stays closed")
    w.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" } })
    H.assertEq(#w.shown(), 1, "a new list opens it")
end

-- The rows move while a menu is up (another closed, one walked off): its
-- Close takes the row it opened on, not the one now on that button.
function tests.aMenusClose_takesItsOwnRow_thoughTheRowsMoved()
    local w = fresh()
    w.state.route = nil
    w.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" }, { name = "Tirisfal Farmhand", kind = "kill" },
                         { name = "Bleeding Horror", kind = "kill" } })
    w.button(2).rowMenu(w.button(2))
    local farmhand = w.menu.defs[1]
    w.button(1).rowMenu(w.button(1))
    w.menu.defs[1].onClick()
    H.assertTrue(w.shown()[2]:find("Bleeding Horror", 1, true) ~= nil, "the rows moved up")
    farmhand.onClick()
    local shown = w.shown()
    H.assertEq(#shown, 1)
    H.assertTrue(shown[1]:find("Bleeding Horror", 1, true) ~= nil, "the farmhand closed, the horror kept")
end

function tests.aGuidesTargets_inAFight_stayAsTheyWere()
    local w = fresh()
    w.state.route = nil
    w.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" } })
    w.combat.v = true
    w.Arrow.SetTargets({ { name = "Bareth Dawnstone", kind = "talk" } })
    H.assertTrue(w.shown()[1]:find("Scarlet Warrior", 1, true) ~= nil, "no secure change in a fight")
    w.combat.v = false
    w.tick()
    H.assertTrue(w.shown()[1]:find("Bareth Dawnstone", 1, true) ~= nil, "the new list after it")
end

-- A guide's things to use (setUses): a button each under the target rows,
-- its press the item, the spell or the macro (asked for, 2026-11-21).
local function useButton(w, i)
    for _, f in ipairs(w.frames) do if f.name == "EasyFindGPSUse" .. i then return f end end
end

function tests.aGuidesUses_aButtonEach_underTheTargets()
    local w = fresh()
    w.state.route = nil
    w.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" } })
    w.Arrow.SetUses({
        { kind = "item", id = 1251, name = "Linen Bandage", icon = 133685 },
        { kind = "macro", name = "Linen Bandages", icon = 134400, macro = "/cast Linen Bandage" },
        { kind = "spell", id = 8690, name = "Hearthstone" },
    })
    local item, macro, spell = useButton(w, 1), useButton(w, 2), useButton(w, 3)
    H.assertTrue(item:IsShown() and macro:IsShown() and spell:IsShown(), "one each")
    H.assertEq(item:GetAttribute("type"), "item")
    H.assertEq(item:GetAttribute("item"), "item:1251")
    H.assertEq(item.look.text:GetText(), "|T133685:14|t Linen Bandage", "its icon and name")
    H.assertEq(macro:GetAttribute("type"), "macro")
    H.assertEq(macro:GetAttribute("macrotext"), "/cast Linen Bandage")
    H.assertNil(macro:GetAttribute("item"), "nothing of the row before")
    H.assertEq(spell:GetAttribute("spell"), "Hearthstone")
    H.assertEq(spell.look.text:GetText(), "Hearthstone", "no icon given: the name alone")
    H.assertTrue(item.y < w.button(1).y, "under the target row")
    H.assertTrue(macro.y < item.y and spell.y < macro.y, "stacked down")
    H.assertEq(w.button(1):GetAttribute("type"), "macro", "the Target button and its key are the creature's still")
    w.Arrow.SetUses(nil)
    H.assertFalse(item:IsShown(), "none set: gone")
    H.assertNil(item:GetAttribute("type"), "and its action off")
end

function tests.aGuidesUses_closedFromTheMenu_backWithANewList()
    local w = fresh()
    w.state.route = nil
    local list = { { kind = "item", id = 1251, name = "Linen Bandage" }, { kind = "item", id = 2589, name = "Linen Cloth" } }
    w.Arrow.SetUses(list)
    useButton(w, 1).rowMenu(useButton(w, 1))
    w.menu.defs[1].onClick()
    H.assertEq(useButton(w, 1):GetAttribute("item"), "item:2589", "the bandage closed, the cloth moved up")
    H.assertFalse(useButton(w, 2):IsShown())
    w.Arrow.SetUses({ { kind = "item", id = 1251, name = "Linen Bandage" } })
    H.assertEq(useButton(w, 1):GetAttribute("item"), "item:1251", "a new list opens it again")
end

function tests.aGuidesUses_inAFight_stayAsTheyWere_andBadOnesAreLeftOut()
    local w = fresh()
    w.state.route = nil
    w.Arrow.SetUses({ { kind = "item", id = 1251, name = "Linen Bandage" } })
    w.combat.v = true
    w.Arrow.SetUses({ { kind = "item", id = 2589, name = "Linen Cloth" } })
    H.assertEq(useButton(w, 1):GetAttribute("item"), "item:1251", "no secure change in a fight")
    w.combat.v = false
    w.tick()
    H.assertEq(useButton(w, 1):GetAttribute("item"), "item:2589", "the new list after it")
    w.Arrow.SetUses({ { kind = "macro", name = "No text" }, { kind = "item", name = "No id" }, { kind = "dance", id = 1 },
                      "junk", { kind = "item", id = 4, name = "Kept" } })
    H.assertEq(useButton(w, 1):GetAttribute("item"), "item:4", "only the one that can be pressed")
    H.assertFalse(useButton(w, 2) ~= nil and useButton(w, 2):IsShown())
    w.Arrow.SetUses({ { kind = "item", id = 1 }, { kind = "item", id = 2 }, { kind = "item", id = 3 }, { kind = "item", id = 4 },
                      { kind = "item", id = 5 } })
    H.assertTrue(useButton(w, 4):IsShown(), "four at most")
    H.assertNil(useButton(w, 5))
    H.assertEq(useButton(w, 1).look.text:GetText(), "Use", "no name yet: the game's word")
end

local pass, fail, failures = H.runSuite("GPSTargetNpc", tests)
return { pass = pass, fail = fail, failures = failures }
