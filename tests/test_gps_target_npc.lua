-- Tests for Arrow.lua's Target button: near the NPC a route leads to, a
-- secure button under the arrow's plate targets it by name and marks it.
-- The game targets and marks only on the player's press (TargetUnit,
-- SetRaidTarget restricted): a secure macro.
local H = require("Harness")
local unpack = table.unpack or unpack

local NPC_SPOT = { ci = 1, wx = 500, wy = 500 }

local function fresh(opts)
    opts = opts or {}
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    local combat = { v = false }
    env.InCombatLockdown = function() return combat.v end
    local frames = {}
    local function sized(f)
        local size = { 0, 0 }
        f.SetSize = function(_, w, h) size = { w, h } end
        f.GetSize = function() return size[1], size[2] end
        f.SetFrameStrata = function() end
        return f
    end
    env.CreateFrame = function(kind, name)
        local f = sized(H.newFrame())
        f.kind, f.name = kind, name
        f.RegisterForClicks = function() end
        f.SetHighlightTexture = function(_, tex) f.hilite = tex end
        f.CreateTexture = function()
            local t = H.newFrame()
            t.SetTexture = function(_, tex) t.tex = tex end
            t.SetColorTexture = function(_, r, g, b, a) t.color = { r, g, b, a } end
            return t
        end
        f.CreateFontString = function()
            local t = H.newFrame()
            local said = ""
            t.SetText = function(_, v) said = v == nil and "" or tostring(v) end
            t.GetText = function() return said end
            return t
        end
        f.SetCooldown = function(_, start, duration) f.swipe = { start, duration } end
        f.SetCooldownFromDurationObject = function(_, length) f.swipe = length end
        f.Clear = function() f.swipe = nil end
        local heard = {}
        f.RegisterEvent = function(_, event) heard[event] = true end
        f.UnregisterEvent = function(_, event) heard[event] = nil end
        f.hears = function(event) return heard[event] == true end
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
    -- The switches of 2026-11-22, off: a named button each, a row each.
    if opts.names then db.gpsUseIcons = false end
    if opts.single then db.gpsTargetPairs = false end
    env.EasyFind.db = db
    local tip = { calls = {} }
    env.GameTooltip = {
        SetOwner = function(_, owner) tip.owner = owner end,
        SetItemByID = function(_, id) tip.calls[#tip.calls + 1] = "item " .. id end,
        SetSpellByID = function(_, id) tip.calls[#tip.calls + 1] = "spell " .. id end,
        Show = function() tip.shown = true end,
        Hide = function() tip.shown = false end,
        IsOwned = function(_, owner) return tip.owner == owner end,
    }
    local cooldowns = { item = {}, spell = {} }
    env.C_Container = { GetItemCooldown = function(id) return unpack(cooldowns.item[id] or { 0, 0, 1 }) end }
    env.C_Spell = {
        GetSpellInfo = function(name) return name == "Hearthstone" and { spellID = 8690 } or nil end,
        GetSpellTexture = function() return 134414 end,
        GetSpellCooldownDuration = function(spell) return cooldowns.spell[spell] end,
    }
    -- The units the game knows: the target and the nameplates, by name.
    local units = { target = nil, plates = {} }
    env.UnitExists = function(u)
        if u == "target" then return units.target ~= nil end
        return units.plates[u] ~= nil
    end
    env.UnitName = function(u) if u == "target" then return units.target end return units.plates[u] end
    env.UnitIsDead = function() return false end
    env.C_NamePlate = { GetNamePlates = function()
        local out = {}
        for unit in pairs(units.plates) do out[#out + 1] = { namePlateUnitToken = unit } end
        return out
    end }
    local bags = {}
    env.C_Item = { GetItemCount = function(id) return bags[id] or 0 end }
    local faces = {}
    env.SetPortraitTextureFromCreatureDisplayID = function(tex, display) faces[tex] = display end
    env._G = env
    ns.Npcs = { DisplayOfID = function(id) return id == 589 and 2345 or nil end,
                ByName = function(name) return name == "Marshal McBride" and { displayID = 1100 } or nil end }
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
            local p = sized(H.newFrame())
            local text = H.newFrame()
            local shown = ""
            text.SetText = function(_, s) shown = s end
            text.GetText = function() return shown end
            -- Six pixels a letter; an icon in the text is not letters.
            text.GetStringWidth = function() return #(shown:gsub("|T.-|t ?", "")) * 6 end
            p.text = text
            return p
        end,
    }
    ns.GPSFollow = { Now = function() return nil end }
    local menu = {}
    ns.ShowTogglePopup = function(name, anchor, defs) menu.name, menu.anchor, menu.defs = name, anchor, defs end
    local hint = {}
    ns.ShowHintTooltip = function(owner, _, title) hint.owner, hint.title = owner, title end
    ns.HideHintTooltip = function() hint.owner = nil end
    H.loadModule("Arrow.lua", env, ns)
    local w = { Arrow = ns.GPSArrow, player = player, state = state, combat = combat, ticks = ticks, db = db,
                menu = menu, frames = frames, tip = tip, hint = hint, cooldowns = cooldowns, units = units,
                bags = bags, faces = faces }
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

function tests.aGuidesUses_asNames_aButtonEach_underTheTargets()
    local w = fresh({ names = true })
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
    local w = fresh({ names = true })
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

-- As icons (the default since 2026-11-22: "just have the icons instead of
-- the names ... like in one bubble"): side by side on one row, the plate's
-- look behind them, each still its own press.
function tests.aGuidesUses_asIcons_sideBySideInOneBubble()
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
    H.assertEq(item.y, macro.y, "one row")
    H.assertEq(macro.y, spell.y)
    H.assertTrue(item.x < macro.x and macro.x < spell.x, "left to right as the guide gave them")
    H.assertEq(macro.x - item.x, 30, "an icon and the gap apart")
    H.assertTrue(item.y < w.button(1).y, "under the target row")
    H.assertEq(item.icon.tex, 133685, "the icon the guide gave")
    H.assertEq(spell.icon.tex, 134414, "none given: the spell's own")
    H.assertFalse(item.look:IsShown(), "no name pill")
    H.assertEq(item:GetSize(), 26)
    H.assertEq(item:GetAttribute("item"), "item:1251", "the press is the item's still")
    H.assertEq(macro:GetAttribute("macrotext"), "/cast Linen Bandage")
    local bubble = w.Arrow._stack.bubble
    H.assertTrue(bubble:IsShown(), "one bubble behind them")
    H.assertEq(bubble:GetSize(), 3 * 26 + 2 * 4 + 2 * 5, "as wide as its icons")
    H.assertEq(bubble.x, macro.x, "centered on the middle icon")
    H.assertTrue(bubble.y > item.y, "its rim above the icons")
    w.Arrow.SetUses({ { kind = "item", id = 1251, name = "Linen Bandage", icon = 133685 } })
    H.assertEq(bubble:GetSize(), 26 + 2 * 5, "one left: the bubble shrinks to it")
    H.assertEq(item.x, bubble.x)
    w.Arrow.SetUses(nil)
    H.assertFalse(bubble:IsShown(), "none: the bubble goes too")
    H.assertFalse(item:IsShown())
end

-- The switch flipped while they show: the same buttons change face.
function tests.theIconsSwitch_changesTheFace_ofButtonsShowing()
    local w = fresh()
    w.state.route = nil
    w.Arrow.SetUses({ { kind = "item", id = 1251, name = "Linen Bandage", icon = 133685 },
                      { kind = "item", id = 2589, name = "Linen Cloth", icon = 132889 } })
    local first, second = useButton(w, 1), useButton(w, 2)
    H.assertTrue(w.Arrow.UseIcons(), "on by default")
    H.assertEq(first.y, second.y)
    w.Arrow.SetUseIcons(false)
    H.assertEq(w.db.gpsUseIcons, false, "saved off")
    H.assertTrue(first.look:IsShown(), "the name pill back")
    H.assertEq(first.look.text:GetText(), "|T133685:14|t Linen Bandage")
    H.assertFalse(first.icon:IsShown())
    H.assertTrue(second.y < first.y, "a row each")
    H.assertFalse(w.Arrow._stack.bubble:IsShown(), "no bubble")
    w.Arrow.SetUseIcons(true)
    H.assertNil(w.db.gpsUseIcons, "on is the default: nothing saved")
    H.assertEq(first.y, second.y, "side by side again")
    H.assertTrue(first.icon:IsShown() and not first.look:IsShown())
end

-- "have the icons show tooltips on hover": the item's or the spell's own.
function tests.aUseButtonsHover_isTheItemsOwnTooltip()
    local w = fresh()
    w.state.route = nil
    w.Arrow.SetUses({
        { kind = "item", id = 1251, name = "Linen Bandage", icon = 133685 },
        { kind = "spell", name = "Hearthstone" },
        { kind = "macro", name = "Linen Bandages", icon = 134400, macro = "/cast Linen Bandage" },
    })
    local item, spell, macro = useButton(w, 1), useButton(w, 2), useButton(w, 3)
    item:GetScript("OnEnter")(item)
    H.assertEq(w.tip.calls[1], "item 1251")
    H.assertTrue(w.tip.shown and w.tip.owner == item)
    item:GetScript("OnLeave")(item)
    H.assertFalse(w.tip.shown, "gone with the mouse")
    spell:GetScript("OnEnter")(spell)
    H.assertEq(w.tip.calls[2], "spell 8690", "a spell given by name: found by it")
    macro:GetScript("OnEnter")(macro)
    H.assertEq(#w.tip.calls, 2, "a macro has no tooltip of the game's")
    H.assertEq(w.hint.title, "Linen Bandages", "its name, which the icon alone does not say")
    macro:GetScript("OnLeave")(macro)
    H.assertNil(w.hint.owner)
    local named = fresh({ names = true })
    named.state.route = nil
    named.Arrow.SetUses({ { kind = "macro", name = "Linen Bandages", macro = "/cast Linen Bandage" } })
    useButton(named, 1):GetScript("OnEnter")(useButton(named, 1))
    H.assertNil(named.hint.title, "as a named button it says so already")
end

-- "show cd, etc.. like a regular icon": the swipe, turned in a fight too.
function tests.anIconsCooldown_isTheGames_inAFightToo()
    local w = fresh()
    w.state.route = nil
    w.cooldowns.item[1251] = { 100, 30, 1 }
    local length = {}
    w.cooldowns.spell[8690] = length
    w.Arrow.SetUses({ { kind = "item", id = 1251, name = "Linen Bandage", icon = 133685 },
                      { kind = "spell", id = 8690, name = "Hearthstone" },
                      { kind = "item", id = 2589, name = "Linen Cloth", icon = 132889 } })
    local item, spell, cloth = useButton(w, 1), useButton(w, 2), useButton(w, 3)
    H.assertEq(item.cooldown.swipe[1], 100, "the item's cooldown as it stands")
    H.assertEq(item.cooldown.swipe[2], 30)
    H.assertTrue(spell.cooldown.swipe == length, "a spell's as the client's own duration object")
    H.assertNil(cloth.cooldown.swipe, "none running: none shown")
    local events = w.Arrow._stack.events
    H.assertTrue(events.hears("BAG_UPDATE_COOLDOWN") and events.hears("SPELL_UPDATE_COOLDOWN"), "heard while they show")
    w.combat.v = true
    w.cooldowns.item[2589] = { 200, 60, 1 }
    w.cooldowns.item[1251] = { 0, 0, 1 }
    events:GetScript("OnEvent")(events, "BAG_UPDATE_COOLDOWN")
    H.assertEq(cloth.cooldown.swipe[1], 200, "a swipe is no secure part: started in a fight")
    H.assertNil(item.cooldown.swipe, "and ended in one")
    w.combat.v = false
    w.Arrow.SetUses(nil)
    H.assertFalse(events.hears("BAG_UPDATE_COOLDOWN"), "nothing showing: nothing heard")
end

-- "allow up to two monster targets on 1 row too (but separate bubbles)".
function tests.twoTargets_shareARow_eachItsOwnPill()
    local w = fresh()
    w.state.route = nil
    w.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" }, { name = "Bareth Dawnstone", kind = "talk" },
                         { name = "Tirisfal Farmhand", kind = "kill" } })
    local a, b, c = w.button(1), w.button(2), w.button(3)
    H.assertEq(a.y, b.y, "the first two on one row")
    local wa, wb = a:GetSize(), b:GetSize()
    H.assertEq((b.x - wb / 2) - (a.x + wa / 2), 4, "a gap between their pills")
    H.assertEq((a.x - wa / 2) + (b.x + wb / 2), 2 * c.x, "the pair centered under the arrow")
    H.assertEq(c.y, a.y - 26, "the third on the next row, alone and centered")
    H.assertEq(w.shown()[1]:find("Scarlet Warrior", 1, true) ~= nil, true, "the first is still the bound Target button")
    local single = fresh({ single = true })
    single.state.route = nil
    single.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" }, { name = "Bareth Dawnstone", kind = "talk" } })
    H.assertEq(single.button(1).x, single.button(2).x, "the switch off: a row each")
    H.assertEq(single.button(2).y, single.button(1).y - 26)
    single.Arrow.SetTargetPairs(true)
    H.assertEq(single.button(1).y, single.button(2).y, "on: paired at once")
    H.assertNil(single.db.gpsTargetPairs)
end

function tests.aPairTooWideForARow_takesTwo()
    local w = fresh({ mark = 0 })
    w.state.route = nil
    local long = string.rep("Long Name ", 4)
    w.Arrow.SetTargets({ { name = long .. "One", kind = "kill" }, { name = long .. "Two", kind = "kill" } })
    H.assertEq(w.button(1).x, w.button(2).x, "each centered")
    H.assertTrue(w.button(2).y < w.button(1).y, "one under the other")
end

-- The stack hangs from UIParent (a fight must lock nothing of the arrow),
-- so it is moved with the arrow: at once, not at the next half-second
-- ("trail and glitch behind when nav moved", 2026-11-22).
function tests.theStack_movesWithTheArrow_atOnce()
    local w = fresh()
    w.db.gpsArrowPos = { x = 500, y = 400 }
    w.Arrow:Refresh()
    w.Arrow.SetTargets({ { name = "Scarlet Warrior", kind = "kill" } })
    w.Arrow.SetUses({ { kind = "item", id = 1251, name = "Linen Bandage", icon = 133685 } })
    local btn, use, bubble = w.button(1), useButton(w, 1), w.Arrow._stack.bubble
    H.assertEq(btn.x, 500)
    H.assertEq(btn.y, 400)
    local frame = w.Arrow._driver:GetScript("OnUpdate")
    w.db.gpsArrowPos = { x = 620, y = 300 }
    frame(nil, 1)
    H.assertEq(btn.x, 620, "the arrow's next update, no half-second tick")
    H.assertEq(btn.y, 300)
    H.assertEq(use.x, 620, "the icons with it")
    H.assertEq(bubble.y, 300 - 26, "and their bubble")
    -- Dragged: every frame, inside the arrow's own throttle.
    w.Arrow.dragging = true
    w.db.gpsArrowPos = { x = 700, y = 350 }
    frame(nil, 0)
    H.assertEq(btn.x, 700, "mid-drag, the same frame")
    w.Arrow.dragging = nil
    -- A fight: secure buttons cannot be moved; the moment it ends they are.
    w.combat.v = true
    w.db.gpsArrowPos = { x = 800, y = 500 }
    frame(nil, 1)
    H.assertEq(btn.x, 700, "left where they were in a fight")
    H.assertEq(bubble.x, 700, "the bubble stays with its icons")
    w.combat.v = false
    local events = w.Arrow._stack.events
    events:GetScript("OnEvent")(events, "PLAYER_REGEN_ENABLED")
    H.assertEq(btn.x, 800, "caught up as the fight ends")
    H.assertEq(use.y, 500 - 26 - 5)
end

-- ==== tiles (a caller that asks for them: the Polestar extension) ===========

local PILLAGER = { name = "Defias Pillager", kind = "kill", npcID = 589, verb = "kill", have = 3, need = 8,
                   item = "Linen Cloth", chance = 35 }
local MCBRIDE = { name = "Marshal McBride", kind = "talk", verb = "turnin" }
local RUFFIAN = { name = "Grimtotem Ruffian", kind = "kill", elite = true, have = 0, need = 1 }

local function Tiles(rows)
    local list = { tiles = true }
    for i, r in ipairs(rows) do
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        list[i] = copy
    end
    return list
end

function tests.tiles_onlyWhereTheCallerAsks_aGuidesPlainRowsKeepTheirButtons()
    local w = fresh()
    w.Arrow.SetTargets({ { name = "Defias Pillager", kind = "kill" } })
    H.assertNil(w.button(1).tiled, "a guide's plain list (RestedXP): its buttons as before")
    w.Arrow.SetTargets(Tiles({ PILLAGER }))
    H.assertTrue(w.button(1).tiled == true, "asked for: a tile")
    H.assertEq(w.button(1).badge:GetText(), "3/8", "its count in the corner")
    H.assertEq(w.faces[w.button(1).face], 2345, "its face, the creature's model by its id")
    H.assertEq(w.button(1).bar.color[1], 0.9, "a creature to kill: the red bar")
end

function tests.tiles_markTheirVerbs_andColorByKind()
    local w = fresh()
    w.Arrow.SetTargets(Tiles({ MCBRIDE, RUFFIAN }))
    H.assertEq(w.button(1).badge:GetText(), "?", "a hand-in: the question mark")
    H.assertEq(w.faces[w.button(1).face], 1100, "no id: the face by its name")
    H.assertEq(w.button(1).bar.color[2], 0.85, "an NPC: green")
    H.assertEq(w.button(2).badge:GetText(), "0/1")
    H.assertEq(w.button(2).bar.color[1], 1, "an elite: gold")
end

function tests.aFight_turnsTheCountsAndTheGlow_theMacroWaits()
    local w = fresh()
    w.Arrow.SetTargets(Tiles({ PILLAGER, MCBRIDE }))
    local macro = w.button(1):GetAttribute("macrotext")
    H.assertTrue(macro:find("/cleartarget", 1, true) ~= nil, "nothing of that name targeted: cleared first")
    w.combat.v = true
    w.units.plates.nameplate3 = "Defias Pillager"
    local now = Tiles({ PILLAGER, MCBRIDE })
    now[1].have = 4
    w.Arrow.SetTargets(now)
    w.tick()
    H.assertEq(w.button(1).badge:GetText(), "4/8", "the count turned in the fight")
    H.assertTrue(w.button(1).glow:IsShown(), "one of that name near: lit")
    H.assertFalse(w.button(2).glow:IsShown())
    H.assertEq(w.button(1):GetAttribute("macrotext"), macro, "the macro waits for the fight's end")
end

function tests.thePlate_saysTheNearOne_elseTheFirst()
    local w = fresh()
    w.Arrow.SetTargets(Tiles({ MCBRIDE, PILLAGER }))
    local card = w.Arrow._stack.card
    H.assertTrue(card ~= nil and card:IsShown(), "a plate under the strip")
    H.assertTrue(card.text:GetText():find("Marshal McBride", 1, true) ~= nil, "none near: the first")
    w.units.target = "Defias Pillager"
    w.tick()
    local said = card.text:GetText()
    H.assertTrue(said:find("Defias Pillager", 1, true) and said:find("3/8", 1, true) and said:find("Linen Cloth  35%", 1, true),
        "the near one: its name, count and loot: " .. said)
end

function tests.aLivingTarget_ofThatName_isKept_thePressTakesTheNext()
    local w = fresh()
    w.units.target = "Defias Pillager"
    w.Arrow.SetTargets(Tiles({ PILLAGER }))
    H.assertEq(w.button(1):GetAttribute("macrotext"):sub(1, 12), "/targetexact", "no /cleartarget first")
end

function tests.anItemToUse_showsHowManyAreInTheBags()
    local w = fresh()
    w.bags[6948] = 5
    w.Arrow.SetUses({ { kind = "item", id = 6948, name = "Hearthstone" } })
    local btn
    for _, f in ipairs(w.frames) do if f.name == "EasyFindGPSUse1" then btn = f end end
    H.assertEq(btn.count and btn.count:GetText(), "5")
end

function tests.theCapability_isAskedByName()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    H.assertTrue(src:find('RegisterAction("gps", "targetCards"', 1, true) ~= nil)
end

local pass, fail, failures = H.runSuite("GPSTargetNpc", tests)
return { pass = pass, fail = fail, failures = failures }
