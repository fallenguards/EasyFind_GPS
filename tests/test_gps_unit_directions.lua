-- Directions on a unit's right-click menu (QuestDirections.lua): an NPC
-- routes to the spot its search row shows, as typing its name and taking
-- its GPS button would; a party or raid member is followed, the route
-- planned again once it is 25 yards from the route's end. Players outside
-- the group and creatures the catalog lacks get no entry.
local H = require("Harness")

local function Load()
    local env = H.newEnv()
    local ns = H.newNs(env)
    env.EasyFind._ns = ns
    local t = { mods = {}, navigated = {}, units = {}, route = nil, planning = false, tickers = {} }
    ns.GPS = {
        IsPlanning = function() return t.planning end,
        CurrentRoute = function() return t.route end,
    }
    ns.Npcs = { SpotOfID = function(id)
        if id == 448 then return { name = "Hogger", npcID = 448, mapID = 1429, x = 0.3, y = 0.4, category = "npc" } end
    end }
    env.EasyFind.API = { CallAction = function(id, name, dest, opts)
        if id == "gps" and name == "navigate" then t.navigated[#t.navigated + 1] = { dest = dest, opts = opts } end
    end }
    env.Menu = { ModifyMenu = function(tag, fn) t.mods[tag] = fn end }
    local function U(unit) return t.units[unit] end
    env.UnitExists = function(u) return U(u) ~= nil end
    env.UnitIsPlayer = function(u) return U(u) and U(u).player or false end
    env.UnitIsUnit = function(a, b) return a == b end
    env.UnitInParty = function(u) return U(u) and U(u).party or false end
    env.UnitInRaid = function() return nil end
    env.UnitGUID = function(u) return U(u) and U(u).guid end
    env.UnitName = function(u) return U(u) and U(u).name end
    env.IsInRaid = function() return false end
    env.GetNumGroupMembers = function() return 2 end
    env.strsplit = function(sep, s)
        local out = {}
        for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
        return table.unpack(out)
    end
    local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
    env.CreateVector2D = vec
    env.C_Map = {
        GetBestMapForUnit = function(u) return U(u) and U(u).map end,
        -- On every map unless the unit names the maps that hold it.
        GetPlayerMapPosition = function(m, u)
            local d = U(u)
            if not (d and d.pos) or (d.onMaps and not d.onMaps[m]) then return nil end
            return vec(d.pos[1], d.pos[2])
        end,
        -- A map 1000 yards across.
        GetWorldPosFromMapPos = function(_, v) return 0, vec(v.x * 1000, v.y * 1000) end,
    }
    env.C_Timer = { NewTicker = function(sec, fn)
        local tk = { sec = sec, fn = fn, Cancel = function(self) self.cancelled = true end }
        t.tickers[#t.tickers + 1] = tk
        return tk
    end }
    env.C_QuestLog, env.GetQuestUiMapID = {}, nil   -- no quest placing: the search rows part returns early
    -- The world map, its canvas 1000 by 600, opened through EasyFind's
    -- OpenMap (refused in a fight); the map search's highlight frames.
    local canvas = { GetWidth = function() return 1000 end, GetHeight = function() return 600 end }
    local map = { shown = false, ScrollContainer = { Child = canvas } }
    function map:IsShown() return self.shown end
    function map:GetMapID() return self.map end
    env.WorldMapFrame, t.map = map, map
    env.EasyFind.API.OpenMap = function(m)
        t.opened = m
        if t.inFight then return false end
        map.shown, map.map = true, m
        return true
    end
    env.EasyFind.db = {}
    local function Mark(parent)
        local f = { shown = true }
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:IsShown() return self.shown end
        function f:SetSize(w) self.size = w end
        function f:ClearAllPoints() self.at = nil end
        function f:SetPoint(_, rel, _, x, y) self.at = { rel = rel, x = x, y = y } end
        function f:GetParent() return parent end
        function f:EnableMouse(on) self.mouse = on end
        function f:SetPassThroughButtons(...) self.passes = { ... } end
        function f:SetScript(name, fn) self[name] = fn end
        return f
    end
    ns.ShowHintTooltip = function(owner, side, title, body) t.hint = { owner = owner, side = side, title = title, body = body } end
    ns.HideHintTooltip = function() t.hint = nil end
    ns.MapSearchFrames = {
        CreateHighlightBox = function(_, parent, opts)
            t.box = Mark(parent)
            if opts.hidden then t.box:Hide() end
            return t.box
        end,
        CreateIndicatorFrame = function(_, parent)
            t.ind = Mark(parent)
            t.ind.glow = { SetSize = function() end }
            return t.ind
        end,
    }
    ns.MapSearch = { ResizeHighlightBorders = function() end,
                     ApplyHighlightStyle = function() t.styled = (t.styled or 0) + 1 end }
    ns.UIToCanvas = function(v) return v end
    ns.HIGHLIGHT_SIZE, ns.ICON_SIZE, ns.ICON_GLOW_SIZE, ns.YELLOW_HIGHLIGHT = 30, 48, 68, { 1, 0.82, 0 }
    H.loadModule("QuestDirections.lua", env, ns)
    t.ns = ns
    return t
end

local function Menu(t, which, unit)
    local rows = {}
    local root = {}
    function root:CreateDivider() rows[#rows + 1] = "divider" end
    function root:CreateButton(label, fn) rows[#rows + 1] = { label = label, fn = fn } end
    function root:CreateCheckbox(label, checked, fn) rows[#rows + 1] = { label = label, fn = fn, checked = checked } end
    t.mods["MENU_UNIT_" .. which](nil, root, { unit = unit })
    return rows
end

local tests = {}

function tests.anNpcsPortrait_routesToTheSpotItsRowShows()
    local t = Load()
    t.units.target = { guid = "Creature-0-1-2-3-448-0000ABCD", name = "Hogger" }
    local rows = Menu(t, "TARGET", "target")
    H.assertEq(rows[2].label, "GPS_MENU_EASYFIND_DIRECTIONS")
    rows[2].fn()
    H.assertEq(t.navigated[1].dest.name, "Hogger")
    H.assertEq(t.navigated[1].dest.x, 0.3)
    H.assertTrue(t.navigated[1].opts.popout, "as a search row's GPS button")
end

function tests.aCreatureTheCatalogLacks_orAPlayerOutsideTheGroup_getsNone()
    local t = Load()
    t.units.target = { guid = "Creature-0-1-2-3-99999-0000ABCD", name = "Nobody" }
    H.assertEq(#Menu(t, "TARGET", "target"), 0)
    t.units.target = { guid = "Player-1-0ABC", name = "Stranger", player = true, map = 1429, pos = { 0.5, 0.5 } }
    H.assertEq(#Menu(t, "TARGET", "target"), 0, "the client gives no spot for them")
end

function tests.aGroupMember_isFollowed_aNewRouteOnceFarFromItsEnd()
    local t = Load()
    local friend = { guid = "Player-1-0FED", name = "Friend", player = true, party = true, map = 1429, pos = { 0.5, 0.5 } }
    t.units.party1, t.units.party = friend, friend
    local rows = Menu(t, "PARTY", "party1")
    rows[2].fn()
    H.assertEq(t.navigated[1].dest.followGUID, "Player-1-0FED")
    local ticker = t.tickers[1]
    H.assertEq(ticker.sec, 3)
    t.route = { dest = { name = "Friend", mapID = 1429, x = 0.5, y = 0.5, followGUID = "Player-1-0FED" } }
    friend.pos = { 0.51, 0.5 }   -- 10 yards: the route stands
    ticker.fn()
    H.assertEq(#t.navigated, 1)
    friend.pos = { 0.55, 0.5 }   -- 50 yards: planned again, quietly
    ticker.fn()
    H.assertEq(#t.navigated, 2)
    H.assertTrue(t.navigated[2].opts.quiet)
    H.assertEq(t.navigated[2].dest.x, 0.55)
end

function tests.followingEnds_whenTheRouteIsAnothers_orTheMemberLeft()
    local t = Load()
    local friend = { guid = "Player-1-0FED", name = "Friend", player = true, party = true, map = 1429, pos = { 0.5, 0.5 } }
    t.units.party1 = friend
    Menu(t, "PARTY", "party1")[2].fn()
    t.route = { dest = { name = "Inn", mapID = 1429, x = 0.1, y = 0.1 } }
    t.tickers[1].fn()
    H.assertTrue(t.tickers[1].cancelled, "another route took over")
    Menu(t, "PARTY", "party1")[2].fn()
    t.route = { dest = { name = "Friend", mapID = 1429, x = 0.5, y = 0.5, followGUID = "Player-1-0FED" } }
    t.units.party1 = nil
    t.tickers[2].fn()
    H.assertTrue(t.tickers[2].cancelled, "left the group")
end

function tests.everyUnitMenuThatShowsANpcOrAMember_getsIt()
    local t = Load()
    for _, which in ipairs({ "TARGET", "FOCUS", "BOSS", "PARTY", "RAID_PLAYER", "RAID" }) do
        H.assertTrue(t.mods["MENU_UNIT_" .. which] ~= nil, which)
    end
end

-- Show on map beside Directions (2026-11-19): the member's zone on the
-- world map, EasyFind's highlight and indicator on them, moving with them
-- while the map stays open.
local function Member(t)
    local friend = { guid = "Player-1-0FED", name = "Friend", player = true, party = true, map = 1429, pos = { 0.5, 0.5 } }
    t.units.party1 = friend
    return friend
end

function tests.aMember_hasShowOnMap_besideDirections()
    local t = Load()
    Member(t)
    local rows = Menu(t, "PARTY", "party1")
    H.assertEq(#rows, 3)
    H.assertEq(rows[2].label, "GPS_MENU_EASYFIND_DIRECTIONS")
    H.assertEq(rows[3].label, "GPS_MENU_SHOW_ON_MAP")
end

function tests.showOnMap_opensTheirZone_andMarksThem_movingWithThem()
    local t = Load()
    local friend = Member(t)
    Menu(t, "PARTY", "party1")[3].fn()
    H.assertEq(t.opened, 1429, "their zone")
    H.assertTrue(t.box.shown and t.ind.shown, "marked")
    H.assertEq(t.box.at.x, 500)
    H.assertEq(t.box.at.y, -300)
    H.assertTrue(t.ind.at.rel == t.box, "the indicator over the box")
    H.assertEq(t.styled, 1, "in the player's highlight style")
    local ticker = t.tickers[#t.tickers]
    H.assertEq(ticker.sec, 0.1)
    friend.pos = { 0.6, 0.5 }
    ticker.fn()
    H.assertEq(t.box.at.x, 600, "moved with them")
    friend.onMaps = { [1429] = true }
    t.map.map = 1453   -- turned to a map that does not hold them
    ticker.fn()
    H.assertFalse(t.box.shown or t.ind.shown, "hidden there")
    H.assertFalse(ticker.cancelled == true, "still watching")
    t.map.map = 1429
    ticker.fn()
    H.assertTrue(t.box.shown, "back on theirs")
    H.assertEq(t.styled, 2, "styled again as it shows")
    t.map.shown = false
    ticker.fn()
    H.assertTrue(ticker.cancelled, "the map closed: done")
    H.assertFalse(t.box.shown or t.ind.shown)
end

-- "why no way to right click clear the tracking after show on map"
-- (2026-11-23): the mark took no clicks at all.
function tests.showOnMap_aRightClickOnThemClearsIt()
    local t = Load()
    Member(t)
    Menu(t, "PARTY", "party1")[3].fn()
    local ticker = t.tickers[#t.tickers]
    H.assertTrue(t.box.mouse, "the mark takes the mouse")
    H.assertEq(table.concat(t.box.passes or {}, " "), "LeftButton MiddleButton", "the map's own clicks pass: a drag still pans it")
    t.box.OnEnter(t.box)
    -- The game's own tooltip names them, right of their dot: ours covered
    -- it (snip 221718, 2026-11-22).
    H.assertNil(t.hint.title, "no name of ours over the game's")
    H.assertEq(t.hint.body, "WP_DISMISS", "only how it goes")
    H.assertEq(t.hint.side, "ANCHOR_LEFT", "on the other side from the game's tooltip")
    t.box.OnMouseUp(t.box, "LeftButton")
    H.assertTrue(t.box.shown and not ticker.cancelled, "a left-click leaves it")
    t.box.OnMouseUp(t.box, "RightButton")
    H.assertFalse(t.box.shown or t.ind.shown, "cleared")
    H.assertTrue(ticker.cancelled, "no longer watched")
    H.assertNil(t.hint, "its tooltip goes with it")
    Menu(t, "PARTY", "party1")[3].fn()
    H.assertTrue(t.box.shown, "shown again from the menu")
end

-- "im still confused how to stop map tracking a party member"
-- (2026-11-22): the row that starts it wears a check while their mark is
-- up, and takes it away.
function tests.showOnMap_isASwitch_onTheMembersMenu()
    local t = Load()
    Member(t)
    local row = Menu(t, "PARTY", "party1")[3]
    H.assertFalse(row.checked(), "no mark yet")
    row.fn()
    H.assertTrue(t.box.shown)
    row = Menu(t, "PARTY", "party1")[3]
    H.assertTrue(row.checked(), "checked while their mark is up")
    row.fn()
    H.assertFalse(t.box.shown or t.ind.shown, "the same row takes it away")
    H.assertFalse(Menu(t, "PARTY", "party1")[3].checked())
end

function tests.showOnMap_inAFight_marksNothing()
    local t = Load()
    Member(t)
    t.inFight = true
    Menu(t, "PARTY", "party1")[3].fn()
    H.assertEq(t.opened, 1429, "asked")
    H.assertNil(t.box, "the map refused: no mark")
    H.assertEq(#t.tickers, 0)
end

local pass, fail, failures = H.runSuite("GPSUnitDirections", tests)
return { pass = pass, fail = fail, failures = failures }
