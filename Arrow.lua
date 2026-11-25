-- EasyFind GPS: the arrow at the character.
--
-- While a route is followed, an arrow under the character points the way
-- on foot as it runs: at a spot a little ahead along the walk, so it turns
-- with every bend, with the step, the yards left on the walk and the times
-- left in the beacon's plate under it. A walk hardly longer than the line
-- to its spot and close beside it is aimed at the spot, past the grid's
-- wiggles; a way round (out along a pier) is followed. A few yards
-- beside the walk it leads alongside it, not back onto it, where nothing
-- stands between. At a ride's boarding spot it points there; on board, and
-- where the game gives no facing (instances), it rests. Shift-drag moves it.
local ns = EasyFind and EasyFind._ns
if not ns or select(2, ...).tooOld then return end
local Arrow = {}
ns.GPSArrow = Arrow

local mmax, mmin, mabs, matan2, mpi = math.max, math.min, math.abs, math.atan2 or math.atan, math.pi
local mfloor, sformat = math.floor, string.format
local SetPortraitTextureFromCreatureDisplayID = _G.SetPortraitTextureFromCreatureDisplayID
local UseCount

local TEX_ARROW = "Interface\\AddOns\\EasyFind\\MapSearch\\Images\\arrow-hq"   -- points down as drawn
local SIZE = 44
local HOME_Y = -130            -- under the character, from the screen's center
local AHEAD = 25               -- yards along the walk the arrow aims at
local NEAR_STRAIGHT = 1.1      -- a walk within this of the straight line is aimed at its spot
local WIGGLE = 10              -- yards it may stray from that line: two or three grid cells
local LANE = 10                -- yards beside the walk still walked alongside it
local AT_RIDE = 60             -- yards from a ride's boarding spot: still pointing at it
local THROTTLE = 0.03

local frame, art, plate, driver
local since = 0
local aimCi                    -- the continent the last aim was taken on

local function DB() return EasyFind and EasyFind.db end
local function Route() local g = ns.GPS return g and g.CurrentRoute and g.CurrentRoute() end
local function Enabled() local db = DB() return not (db and db.gpsArrow == false) end

-- The way from (px, py) to (ax, ay) as the game turns: from north toward west.
local function Bearing(ci, px, py, ax, ay)
    local a = ns.GPSFollow.Axes(ci)
    if not a then return nil end
    local dx, dy = ax - px, ay - py
    return matan2(dx * a[3] + dy * a[4], dx * a[1] + dy * a[2])
end
Arrow._Bearing = Bearing   -- tests

local function Clear(ci, px, py, x, y)
    local Nav = ns.GPSNav
    return Nav and Nav.Straight and Nav.Straight(ci, px, py, x, y, IsIndoors and IsIndoors()) == true
end

-- How far the rest of the walk (from stretch s) strays from the line from
-- (px, py) to its spot d yards off, in yards.
local function Spread(path, s, px, py, tx, ty, d)
    if d < 1 then return 0 end
    local pts, far = path.pts, 0
    local ux, uy = (tx - px) / d, (ty - py) / d
    for v = s + 1, #pts / 2 do
        local off = mabs((pts[2 * v - 1] - px) * uy - (pts[2 * v] - py) * ux)
        if off > far then far = off end
    end
    return far
end
Arrow._Spread = Spread   -- the dev probe

-- Where the arrow points from where the player stands, and the yards left,
-- or nothing to point at.
local function Aim()
    local f = ns.GPSFollow.Now()
    if not f then return nil end
    aimCi = f.ci
    local px, py = f.px, f.py
    if f.ride then
        if f.straight > AT_RIDE then return nil end
        return px, py, f.tx, f.ty, f.straight
    end
    local path = f.path
    if not path then return px, py, f.tx, f.ty, f.straight end
    local left = mmax(0, path.len - f.along)
    -- A walk hardly longer than the line to the spot and never far beside
    -- it bends only round the grid's small blocks (a bush, a post):
    -- straight at the spot. Far off it, the walk is a way round.
    if left <= f.straight * NEAR_STRAIGHT and Spread(path, f.seg, px, py, f.tx, f.ty, f.straight) <= WIGGLE then
        return px, py, f.tx, f.ty, left
    end
    local ax, ay = ns.GPSFollow.PointAt(path, f.along + AHEAD, f.seg)
    -- Beside the walk: alongside it, up to LANE out, closing in on the
    -- last stretch so the spot itself is reached.
    local keep = f.off > 0.5 and mmin(1, LANE / f.off) * mmax(0, mmin(1, (left - AHEAD) / AHEAD)) or 0
    if keep > 0 then
        local sx, sy = (px - f.qx) * keep, (py - f.qy) * keep
        for _ = 1, 2 do
            if Clear(f.ci, px, py, ax + sx, ay + sy) then return px, py, ax + sx, ay + sy, left end
            sx, sy = sx / 2, sy / 2
        end
    end
    return px, py, ax, ay, left
end

Arrow._Aim = Aim   -- tests

local function SavePlace()
    local cx, cy = frame:GetCenter()
    if not (cx and cy) then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    local db = DB()
    if db then db.gpsArrowPos = { x = cx, y = cy } end
end

local function Build()
    frame = CreateFrame("Frame", "EasyFindGPSArrow", UIParent)
    frame:SetSize(SIZE, SIZE)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    local db = DB()
    local pos = db and db.gpsArrowPos
    if pos and pos.x and pos.y then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, HOME_Y)
    end
    art = frame:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints(frame)
    art:SetTexture(TEX_ARROW)
    ns.GPSWorldPin.Tint(art, "arrow", 1)
    plate = ns.GPSWorldPin.NewPlate(frame)
    plate:SetPoint("TOP", frame, "BOTTOM", 0, -7)
    -- Clicks pass through to the world; Shift held, the arrow and a grip
    -- over the plate take them to move it. The plate's right-click stays.
    local grip = CreateFrame("Frame", nil, plate)
    grip:SetAllPoints(plate)
    grip:EnableMouse(false)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnMouseDown", function(_, button) plate:GetScript("OnMouseDown")(plate, button) end)
    grip:SetScript("OnMouseUp", function(_, button) plate:GetScript("OnMouseUp")(plate, button) end)
    -- Unlocked, the grip takes the mouse over the plate: its hover is the
    -- plate's (a cut step read whole), which the plate alone never got.
    grip:SetScript("OnEnter", function()
        local enter = plate:GetScript("OnEnter")
        if enter then enter(plate) end
    end)
    grip:SetScript("OnLeave", function()
        local leave = plate:GetScript("OnLeave")
        if leave then leave(plate) end
    end)
    -- The arrow's own right-click opens the plate's menu, the plate hidden
    -- too; its other clicks pass through to the world.
    local clicker = CreateFrame("Frame", nil, frame)
    clicker:SetAllPoints(frame)
    clicker:EnableMouse(false)
    clicker:SetScript("OnMouseDown", grip:GetScript("OnMouseDown"))
    clicker:SetScript("OnMouseUp", grip:GetScript("OnMouseUp"))
    local passing = false
    -- Unlocked (the plate's menu), it takes a plain drag; locked, Shift held.
    local function Unlocked() local d = DB() return d ~= nil and d.gpsArrowUnlocked == true end
    local function DragStart()
        if not (IsShiftKeyDown() or Unlocked()) then return end
        Arrow.dragging = true
        frame:StartMoving()
    end
    local function DragStop()
        Arrow.dragging = nil
        frame:StopMovingOrSizing()
        SavePlace()
    end
    local function TakeMouse()
        local take = IsShiftKeyDown() or Unlocked()
        frame:EnableMouse(take)
        grip:EnableMouse(take)
        clicker:EnableMouse(passing and not take)
    end
    plate.isArrow = true
    function Arrow.SetUnlocked(on)
        local d = DB()
        if d then d.gpsArrowUnlocked = on or nil end
        TakeMouse()
    end
    function Arrow.ResetPlace()
        local d = DB()
        if d then d.gpsArrowPos = nil end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, HOME_Y)
    end
    -- The game refuses the pass-through in a fight: built in one, the plate
    -- takes no clicks until it ends.
    local function PassClicks()
        local ok, why = ns.Utils.SafeCallMethod(plate, "SetPropagateMouseClicks", true)
        if why == "combat" then return frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        plate:EnableMouse(ok)
        passing = ns.Utils.SafeCallMethod(clicker, "SetPropagateMouseClicks", true) and true or false
        TakeMouse()
    end
    frame:SetScript("OnDragStart", DragStart)
    frame:SetScript("OnDragStop", DragStop)
    grip:SetScript("OnDragStart", DragStart)
    grip:SetScript("OnDragStop", DragStop)
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then PassClicks() else TakeMouse() end
    end)
    frame:SetScript("OnShow", function(self)
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
        TakeMouse()
    end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
        self:EnableMouse(false)
    end)
    plate:EnableMouse(false)
    PassClicks()
    frame:Hide()
end

-- Set below: the buttons under the plate keep their place by the arrow.
local StackFollow

local function Update()
    local px, py, ax, ay, left = Aim()
    local facing = px and GetPlayerFacing and GetPlayerFacing()
    local bearing = facing and not (issecretvalue and issecretvalue(facing)) and Bearing(aimCi, px, py, ax, ay)
    if not bearing then
        if frame then frame:Hide() end
        StackFollow()
        return
    end
    if not frame then Build() end
    -- Facing turns from north toward west too; the art points down at rest.
    art:SetRotation(bearing - facing + mpi)
    local Pin = ns.GPSWorldPin
    local text, line, trip, note = Pin.PlateLines(Route(), left)
    plate:SetShown(text ~= nil)
    if text then Pin.FillPlate(plate, text, line, trip, note) end
    frame:Show()
    StackFollow()
end

local function Tick(_, dt)
    -- Dragged, the buttons under it move every frame, not every tick.
    if Arrow.dragging then StackFollow() end
    since = since + dt
    if since < THROTTLE then return end
    since = 0
    Update()
end

-- Whether the arrow points the way now: the beacon's own edge arrow stays
-- away while it does.
function Arrow:Guiding() return frame ~= nil and frame:IsShown() end

-- Target buttons under the plate: a guide's creatures while it sets them
-- (setTargets), and the NPC a route leads to near its spot. The game
-- targets and marks only on the player's press: a secure macro each. They
-- hang from UIParent at the plate's foot, so a fight locks nothing of the
-- arrow; in one they stay as they were.
local TARGET_YARDS, TARGET_EVERY, TARGET_MAX, ROW_H, ROW_GAP = 40, 0.5, 6, 24, 2
-- Two targets on a row: the gap between them, the widest pair.
local PAIR_GAP, PAIR_MAX_W = 4, 380
-- A thing to use as an icon: its side, the gap to the next, the bubble's rim.
local ICON, ICON_GAP, ICON_PAD = 26, 4, 5
local HILITE_PILL, HILITE_ICON = "Interface\\Buttons\\UI-Common-MouseHilight", "Interface\\Buttons\\ButtonHilight-Square"
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local KIND_ICON = { kill = "Interface\\Cursor\\Attack", talk = "Interface\\GossipFrame\\GossipGossipIcon" }
-- btns, rows, guide (set from outside), npc { dest, name, ci, wx, wy },
-- closed (a route's dest), closedNames (a guide's), ticker, menuAnchor;
-- uses (a guide's things to use), useBtns, closedUses (by row), bubble
-- (behind the icons); x, y (the stack's top as placed), live (buttons
-- shown), events (cooldowns and a fight's end, while any show)
local target = { btns = {}, rows = {}, closedNames = {}, useBtns = {}, closedUses = {}, live = 0 }
Arrow._stack = target   -- tests
local USE_MAX = 4
local USE_KINDS = { item = true, spell = true, macro = true }
local WATCHED = { "PLAYER_REGEN_ENABLED", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED" }
-- Tiles, for a caller that asks for them (list.tiles: the Polestar
-- extension): a face each in a strip, a count or mark in its corner, a bar
-- along its foot by kind, lit while a living one of that name is near; the
-- near one's (else the first's) name, count and loot on a plate under it.
local TILE, TILE_GAP, TILE_BAR, TILE_PAD = 38, 4, 4, 3
local TILE_COLOR = { npc = { 0.35, 0.85, 0.45 }, elite = { 1, 0.78, 0.2 }, mob = { 0.9, 0.3, 0.25 } }
local NEAR_FILL = { 0.25, 0.8, 0.4, 0.22 }
local VERB_MARK = { turnin = "?", accept = "!" }
local CARD_LINE_H, CARD_PAD = 15, 6

-- The things to use as icons in one bubble, and the targets two to a row:
-- each on unless switched off (a guide extension's settings page).
function Arrow.UseIcons()
    local db = DB()
    return not (db and db.gpsUseIcons == false)
end

function Arrow.TargetPairs()
    local db = DB()
    return not (db and db.gpsTargetPairs == false)
end

function Arrow.TargetMark()
    local db = DB()
    local mark = db and db.gpsTargetMark
    if mark == nil then return 8 end
    return mark
end

-- The route's NPC on the walk in (40 yd) until arrival (8 yd beside it),
-- unless closed from its right-click menu.
-- The end of the leg being walked: a trip's next stop, else the route's.
local function LegEnd(route)
    for i = route.active or 1, #(route.steps or {}) do
        local stop = route.steps[i].tripStop
        if stop then return stop end
    end
    return route.dest
end

local function TargetNpc()
    local route = Route()
    -- A ghost on a death skip: the Spirit Healer its step leads to.
    local step = route and route.steps and route.steps[route.active or 1]
    local dest = route and not route.arrived and (step and step.spirit and step or LegEnd(route))
    if dest and dest.npc and dest ~= target.closed and dest.mapID and dest.x and ns.GPS.WorldPos then
        if not (target.npc and target.npc.dest == dest) then
            local ci, wx, wy = ns.GPS.WorldPos(dest.mapID, dest.x, dest.y)
            target.npc = ci and { dest = dest, name = dest.npc, ci = ci, wx = wx, wy = wy } or nil
        end
    else
        target.npc = nil
    end
    return target.npc
end

local function HideButton(btn)
    btn:Hide()
    btn:ClearAllPoints()
    btn:SetAttribute("type", nil)
    btn.macro, btn.label, btn.x, btn.y, btn.row, btn.use = nil, nil, nil, nil, nil, nil
    btn.dx, btn.dy = nil, nil
end

local TargetTick

-- A right-click: a menu at the cursor, as the plate's. Close takes the row
-- it opened on, though the rows moved since: a route's NPC for that route,
-- a guide's creature until the guide's list changes.
local function TargetMenu(btn)
    local row = btn.row
    if not (row and ns.ShowTogglePopup) then return end
    local isUse = btn.isUse
    local dest = row.route and target.npc and target.npc.dest
    local anchor = target.menuAnchor
    if not anchor then
        anchor = CreateFrame("Frame", nil, UIParent)
        anchor:SetSize(1, 1)
        target.menuAnchor = anchor
    end
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    anchor:ClearAllPoints()
    anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    ns.ShowTogglePopup("EasyFindGPSTargetMenu", anchor, {
        { kind = "action", label = _G["CLOSE"] or "Close", onClick = function()
            if isUse then
                target.closedUses[row] = true
            elseif row.route then
                target.closed = dest
            else
                target.closedNames[row.name] = true
            end
            TargetTick()
        end },
    }, {})
end

local function StackButton(pool, i, name)
    -- starts shown: hidden at the end of its setup
    local btn = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    btn:SetFrameStrata("LOW")
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("useOnKeyDown", false)
    -- Right-click runs btn.rowMenu (the template's own-function action;
    -- "menu" is the template's unit menu).
    btn:SetAttribute("type2", "rowMenu")
    btn.rowMenu = TargetMenu
    local look = ns.GPSWorldPin.NewPlate(btn)
    look:SetAllPoints(btn)
    look:EnableMouse(false)
    look.text:ClearAllPoints()
    look.text:SetPoint("CENTER")
    btn.look = look
    btn:SetHighlightTexture(HILITE_PILL, "ADD")
    btn:Hide()
    pool[i] = btn
    return btn
end

local function TargetButton(i)
    return target.btns[i] or StackButton(target.btns, i, i == 1 and "EasyFindGPSTarget" or ("EasyFindGPSTarget" .. i))
end

local function SpellID(use)
    if use.id then return use.id end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(use.name)
    return info and info.spellID or nil
end

-- A thing to use, hovered: the item's or the spell's own tooltip. A macro
-- has none: its name, where the icon alone does not say it.
local function UseEnter(btn)
    local use = btn.use
    if not use then return end
    local spell = use.kind == "spell" and SpellID(use)
    if use.kind == "item" or spell then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        if spell then GameTooltip:SetSpellByID(spell) else GameTooltip:SetItemByID(use.id) end
        GameTooltip:Show()
    elseif btn.worn == "icon" and ns.ShowHintTooltip then
        ns.ShowHintTooltip(btn, "ANCHOR_RIGHT", use.name or _G["USE"] or "Use")
    end
end

local function UseLeave(btn)
    if GameTooltip:IsOwned(btn) then GameTooltip:Hide() end
    if ns.HideHintTooltip then ns.HideHintTooltip(btn) end
end

local function UseButton(i)
    local btn = target.useBtns[i]
    if btn then return btn end
    btn = StackButton(target.useBtns, i, "EasyFindGPSUse" .. i)
    btn.isUse = true
    btn:SetScript("OnEnter", UseEnter)
    btn:SetScript("OnLeave", UseLeave)
    return btn
end

-- A pill's words and its width for them.
local function Words(btn, label)
    if btn.label == label then return end
    btn.label = label
    btn.look.text:SetText(label)
    btn.w = btn.look.text:GetStringWidth() + 20
    btn:SetSize(btn.w, ROW_H)
end

-- A tile's kind for its bar: an elite (rare, boss) gold, a creature to kill red, the rest green.
local function TileKind(row)
    if row.elite then return "elite" end
    return row.kind == "kill" and "mob" or "npc"
end

local function TileBadge(row)
    if row.have and row.need then return row.have .. "/" .. row.need end
    return VERB_MARK[row.verb] or ""
end

-- A creature's model for the face: by its id where the catalog has it
-- (EasyFind 5.8), else by its name.
local function TileDisplay(row)
    local Npcs = ns.Npcs
    if not Npcs then return nil end
    if row.npcID and Npcs.DisplayOfID then
        local display = Npcs.DisplayOfID(row.npcID)
        if display then return display end
    end
    local hit = Npcs.ByName and Npcs.ByName(row.name)
    return hit and hit.displayID or nil
end

local function TileParts(btn)
    if btn.face then return end
    local face = btn:CreateTexture(nil, "ARTWORK")
    face:SetPoint("TOPLEFT", btn, "TOPLEFT", TILE_PAD, -TILE_PAD)
    face:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -TILE_PAD, TILE_PAD + TILE_BAR)
    btn.face = face
    local bar = btn:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", TILE_PAD, TILE_PAD)
    bar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -TILE_PAD, TILE_PAD)
    bar:SetHeight(TILE_BAR)
    btn.bar = bar
    local glow = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetAllPoints(btn)
    glow:SetColorTexture(NEAR_FILL[1], NEAR_FILL[2], NEAR_FILL[3], NEAR_FILL[4])
    btn.glow = glow
    local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", -1, 1)
    btn.badge = badge
end

-- A target button worn as a tile, or back to its pill.
local function WearTile(btn, row)
    TileParts(btn)
    if not btn.tiled then
        btn.tiled, btn.label, btn.display = true, nil, nil
        btn.look.text:SetText("")
        btn.w = TILE
        btn:SetSize(TILE, TILE + TILE_BAR)
        btn:SetHighlightTexture(HILITE_ICON, "ADD")
    end
    for _, part in ipairs({ btn.face, btn.bar, btn.badge }) do part:Show() end
    local display = TileDisplay(row)
    if display ~= btn.display or btn.faceName ~= row.name then
        btn.display, btn.faceName = display, row.name
        if display and SetPortraitTextureFromCreatureDisplayID then
            SetPortraitTextureFromCreatureDisplayID(btn.face, display)
        else
            btn.face:SetTexture(KIND_ICON[row.kind] or NO_ICON)
        end
    end
    local c = TILE_COLOR[TileKind(row)]
    btn.bar:SetColorTexture(c[1], c[2], c[3], 1)
    btn.badge:SetText(TileBadge(row))
end

local function WearPill(btn)
    if not btn.tiled then return end
    btn.tiled, btn.label = nil, nil
    for _, part in ipairs({ btn.face, btn.bar, btn.badge, btn.glow }) do part:Hide() end
    btn:SetHighlightTexture(HILITE_PILL, "ADD")
end

-- Whether a living one of that name is the target or on a nameplate; a
-- name or state the game withholds counts as not.
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function LivingNamed(unit, name)
    if not (UnitExists and UnitExists(unit)) then return false end
    local n, dead = UnitName(unit), UnitIsDead and UnitIsDead(unit)
    return Plain(n) and Plain(dead) and not dead and n == name
end

local function NearNamed(name)
    if LivingNamed("target", name) then return true end
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
    for _, p in ipairs(plates or {}) do
        local unit = p.namePlateUnitToken
        if unit and LivingNamed(unit, name) then return true end
    end
    return false
end

local function CardPlate()
    local card = ns.GPSWorldPin.NewPlate(UIParent)
    card:SetFrameStrata("LOW")
    card:EnableMouse(false)
    card:Hide()
    target.card = card
    return card
end

local function CardText(row)
    local c = TILE_COLOR[TileKind(row)]
    local line = sformat("|cff%02x%02x%02x%s|r", mfloor(c[1] * 255 + 0.5), mfloor(c[2] * 255 + 0.5),
        mfloor(c[3] * 255 + 0.5), row.name)
    if row.have and row.need then line = line .. "  " .. row.have .. "/" .. row.need end
    if row.item then
        line = line .. "\n" .. row.item .. (row.chance and ("  " .. mfloor(row.chance + 0.5) .. "%") or "")
        return line, 2
    end
    return line, 1
end

-- The tiles' plain parts, in a fight too: each one's count from the
-- guide's newest list, its glow, and the plate's words and size. Only the
-- macros and the places wait for a fight's end.
local function CardTick()
    local card = target.card
    if not (target.tiles and card and card:IsShown()) then return end
    local newest = {}
    for _, row in ipairs(target.guide or {}) do newest[row.name] = row end
    local first, near
    for i = 1, #target.rows do
        local btn = target.btns[i]
        local row = btn and btn.tiled and btn.row
        if row then
            local now = newest[row.name] or row
            btn.badge:SetText(TileBadge(now))
            local lit = NearNamed(row.name)
            btn.glow:SetShown(lit)
            first = first or now
            if lit and not near then near = now end
        end
    end
    local show = near or first
    if not show then return end
    local text, lines = CardText(show)
    if card.shown ~= text then
        card.shown = text
        card.text:SetText(text)
        card:SetSize(card.text:GetStringWidth() + 2 * CARD_PAD + 12, lines * CARD_LINE_H + 2 * CARD_PAD)
    end
end

local function UseTexture(use)
    if use.icon then return use.icon end
    local tex
    if use.kind == "item" then
        tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(use.id)
    elseif use.kind == "spell" then
        tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(use.id or use.name)
    end
    return tex or NO_ICON
end

-- An item icon's count in the bags, as an action button shows it.
UseCount = function(btn)
    local use = btn.use
    local count = use and use.kind == "item" and btn.worn == "icon" and C_Item and C_Item.GetItemCount
        and C_Item.GetItemCount(use.id) or nil
    if not count then
        if btn.count then btn.count:Hide() end
        return
    end
    if not btn.count then
        btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end
    btn.count:SetText(count > 1 and count or "")
    btn.count:Show()
end

-- A use button's face: its icon alone, in the bubble, or the pill with
-- its name.
local function Wear(btn, use, icons)
    local face = icons and "icon" or "pill"
    if btn.worn ~= face then
        btn.worn, btn.label, btn.tex = face, nil, nil
        if icons and not btn.icon then
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(btn)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            btn.icon = icon
            local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
            cooldown:SetAllPoints(btn)
            btn.cooldown = cooldown
        end
        btn.look:SetShown(not icons)
        if btn.icon then
            btn.icon:SetShown(icons)
            -- A swipe shows itself when it is set; under a name it stays away.
            if not icons then btn.cooldown:Clear() end
        end
        btn:SetHighlightTexture(icons and HILITE_ICON or HILITE_PILL, "ADD")
        if icons then
            btn.w = ICON
            btn:SetSize(ICON, ICON)
        end
    end
    if not icons then
        if btn.count then btn.count:Hide() end
        return Words(btn, use.label)
    end
    local tex = UseTexture(use)
    if btn.tex ~= tex then
        btn.tex = tex
        btn.icon:SetTexture(tex)
    end
    UseCount(btn)
end

local function Swipe(cooldown, start, duration, enable)
    local secret = issecretvalue
    if not (start and duration) or enable == 0 or (secret and (secret(start) or secret(duration))) then
        return cooldown:Clear()
    end
    if start > 0 and duration > 0 then cooldown:SetCooldown(start, duration) else cooldown:Clear() end
end

-- An icon's cooldown, as an action button shows it. A spell's comes as the
-- client's duration object where it has one (its numbers are withheld in
-- a fight); an item's is plain.
local function UseCooldown(btn)
    local use, cooldown = btn.use, btn.cooldown
    if not (use and cooldown and btn.worn == "icon") then return end
    if use.kind == "item" then
        local read = C_Container and C_Container.GetItemCooldown or GetItemCooldown
        if read then Swipe(cooldown, read(use.id)) end
    elseif use.kind == "spell" then
        local spell, spells = use.id or use.name, C_Spell
        if spells and spells.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject then
            local length = spells.GetSpellCooldownDuration(spell)
            if length then cooldown:SetCooldownFromDurationObject(length) else cooldown:Clear() end
        elseif spells and spells.GetSpellCooldown then
            local info = spells.GetSpellCooldown(spell)
            if info then Swipe(cooldown, info.startTime, info.duration) else cooldown:Clear() end
        else
            -- The classic clients' own call.
            local old = _G["GetSpellCooldown"]
            if old then Swipe(cooldown, old(spell)) end
        end
    end
end

local function UseCooldowns()
    for i = 1, #target.useBtns do
        local btn = target.useBtns[i]
        if btn:IsShown() then
            UseCooldown(btn)
            UseCount(btn)
        end
    end
end

-- The plate's look behind the icons. A frame of its own on UIParent: one
-- that held the buttons would lock with them in a fight.
local function UseBubble()
    local bubble = ns.GPSWorldPin.NewPlate(UIParent)
    bubble:SetFrameStrata("LOW")
    bubble:SetFrameLevel(mmax(0, (UIParent:GetFrameLevel() or 1) - 1))
    bubble:EnableMouse(false)
    bubble:Hide()
    target.bubble = bubble
    return bubble
end

local function Place(f, x, y)
    if f.x == x and f.y == y then return end
    f.x, f.y = x, y
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, y)
end

local function PlacePool(pool, x, y)
    for i = 1, #pool do
        local f = pool[i]
        if f.dx then Place(f, x + f.dx, y + f.dy) end
    end
end

-- Every shown piece at its offset from the stack's top.
local function PlaceStack(x, y)
    target.x, target.y = x, y
    PlacePool(target.btns, x, y)
    PlacePool(target.useBtns, x, y)
    local bubble = target.bubble
    if bubble and bubble.dx then Place(bubble, x + bubble.dx, y + bubble.dy) end
    local card = target.card
    if card and card.dx then Place(card, x + card.dx, y + card.dy) end
end

-- The stack's top on UIParent: under the plate while the arrow shows; at
-- the arrow's own spot once it is gone (arrived, or its setting off).
local function TargetPlace()
    local under = frame and frame:IsShown() and (plate:IsShown() and plate or frame)
    local cx, bottom = under and under:GetCenter(), under and under:GetBottom()
    if cx and bottom then
        local s = under:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return math.floor(cx * s + 0.5), math.floor(bottom * s + 0.5) - 4
    end
    local db = DB()
    local pos = db and db.gpsArrowPos
    if pos and pos.x and pos.y then return pos.x, pos.y end
    local w, h = UIParent:GetSize()
    return w / 2, h / 2 + HOME_Y
end

-- The rows: the guide's creatures, then the route's NPC when near and not
-- one of them.
local function TargetRows()
    local rows = target.rows
    for i = #rows, 1, -1 do rows[i] = nil end
    local named = {}
    for _, t in ipairs(target.guide or {}) do
        if #rows < TARGET_MAX and not named[t.name] and not target.closedNames[t.name] then
            named[t.name] = true
            rows[#rows + 1] = t
        end
    end
    local npc = TargetNpc()
    if npc and not named[npc.name] and #rows < TARGET_MAX then
        local ci, px, py = ns.GPS.PlayerWorldPos()
        if ci == npc.ci and px and (px - npc.wx) ^ 2 + (py - npc.wy) ^ 2 <= TARGET_YARDS * TARGET_YARDS then
            rows[#rows + 1] = { name = npc.name, route = true }
        end
    end
    return rows
end

-- Cooldowns turn in a fight too (a swipe is no secure part); the rows and
-- their places wait for its end, then catch up at once.
local function Watch(on)
    local events = target.events
    if on and not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then TargetTick() else UseCooldowns() end
        end)
        target.events = events
    end
    if not events or events.on == on then return end
    events.on = on
    for i = 1, #WATCHED do
        if on then ns.Utils.RegisterEventIfValid(events, WATCHED[i]) else events:UnregisterEvent(WATCHED[i]) end
    end
end

-- The arrow moved (a drag, a plate grown a line): the stack with it. Its
-- buttons are secure, so never in a fight.
StackFollow = function()
    if target.live == 0 or InCombatLockdown() then return end
    local x, y = TargetPlace()
    if x ~= target.x or y ~= target.y then PlaceStack(x, y) end
end

TargetTick = function()
    if InCombatLockdown() then return end
    local rows = TargetRows()
    local mark = Arrow.TargetMark()
    local markIcon = mark > 0 and ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mark .. ":14|t ") or ""
    local tiles = target.tiles
    for i, row in ipairs(rows) do
        local btn = TargetButton(i)
        btn.row = row
        -- Cleared first: a name not found leaves no other unit to mark. On a
        -- tile whose name the living target has, kept: the press takes the
        -- next one of that name.
        local keep = tiles and LivingNamed("target", row.name)
        local macro = (keep and "" or "/cleartarget\n") .. "/targetexact " .. row.name
        if mark > 0 then macro = macro .. "\n/tm [@target,exists] !" .. mark end
        if btn.macro ~= macro then
            btn.macro = macro
            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macrotext", macro)
        end
        -- The route's NPC alone keeps the plain word; among others, names.
        if tiles then
            WearTile(btn, row)
        else
            WearPill(btn)
            local kind = KIND_ICON[row.kind]
            local label = markIcon .. (kind and ("|T" .. kind .. ":14|t ") or "")
                .. ((row.route and #rows == 1) and (_G["TARGET"] or "Target") or row.name)
            Words(btn, label)
        end
    end
    for i = #rows + 1, #target.btns do
        if target.btns[i]:IsShown() then HideButton(target.btns[i]) end
    end
    -- Two to a row where a pair fits, each its own pill: down counts the
    -- stack's rows from its top.
    local down, i, paired = 0, 1, Arrow.TargetPairs()
    local card = target.card
    if tiles and #rows > 0 then
        local w = #rows * TILE + (#rows - 1) * TILE_GAP
        for n = 1, #rows do
            local btn = target.btns[n]
            btn.dx, btn.dy = -w / 2 + TILE / 2 + (n - 1) * (TILE + TILE_GAP), down
        end
        down = down - (TILE + TILE_BAR + TILE_GAP)
        card = card or CardPlate()
        card.dx, card.dy, card.shown = 0, down, nil
        card:Show()
        CardTick()
        local _, h = card:GetSize()
        down = down - ((h or 0) + ROW_GAP)
        i = #rows + 1
    elseif card then
        card.dx, card.x, card.y = nil, nil, nil
        card:Hide()
    end
    while i <= #rows do
        local a, b = target.btns[i], paired and i < #rows and target.btns[i + 1] or nil
        if b and a.w + PAIR_GAP + b.w <= PAIR_MAX_W then
            local half = (a.w + PAIR_GAP + b.w) / 2
            a.dx, a.dy, b.dx, b.dy = a.w / 2 - half, down, half - b.w / 2, down
            i = i + 2
        else
            a.dx, a.dy = 0, down
            i = i + 1
        end
        down = down - (ROW_H + ROW_GAP)
    end
    -- A guide's things to use, under the targets: the press uses the item,
    -- casts the spell or runs the macro.
    local used, icons = 0, Arrow.UseIcons()
    if target.uses then
        for _, use in ipairs(target.uses) do
            if used < USE_MAX and not target.closedUses[use] then
                used = used + 1
                local btn = UseButton(used)
                local was, face = btn.use, btn.worn
                btn.row = use
                if was ~= use then
                    btn.use = use
                    btn:SetAttribute("type", use.kind)
                    btn:SetAttribute("item", use.kind == "item" and ("item:" .. use.id) or nil)
                    btn:SetAttribute("spell", use.kind == "spell" and (use.name or use.id) or nil)
                    btn:SetAttribute("macrotext", use.kind == "macro" and use.macro or nil)
                end
                Wear(btn, use, icons)
                if was ~= use or face ~= btn.worn then UseCooldown(btn) end
            end
        end
    end
    for n = used + 1, #target.useBtns do
        if target.useBtns[n]:IsShown() then HideButton(target.useBtns[n]) end
    end
    -- As icons, side by side in one bubble; as pills, a row each.
    local bubble = target.bubble
    if icons and used > 0 then
        bubble = bubble or UseBubble()
        local w = used * ICON + (used - 1) * ICON_GAP + 2 * ICON_PAD
        if bubble.w ~= w then
            bubble.w = w
            bubble:SetSize(w, ICON + 2 * ICON_PAD)
        end
        bubble.dx, bubble.dy = 0, down
        for n = 1, used do
            local btn = target.useBtns[n]
            btn.dx, btn.dy = ICON_PAD + ICON / 2 - w / 2 + (n - 1) * (ICON + ICON_GAP), down - ICON_PAD
        end
    else
        if bubble then bubble.dx, bubble.x, bubble.y = nil, nil, nil end
        for n = 1, used do
            local btn = target.useBtns[n]
            btn.dx, btn.dy = 0, down
            down = down - (ROW_H + ROW_GAP)
        end
    end
    target.live = #rows + used
    if target.live > 0 then PlaceStack(TargetPlace()) end
    for n = 1, #rows do target.btns[n]:Show() end
    for n = 1, used do target.useBtns[n]:Show() end
    if bubble then bubble:SetShown(bubble.dx ~= nil) end
    Watch(target.live > 0)
    if not (target.guide or target.npc or target.uses) and target.ticker then
        target.ticker:Cancel()
        target.ticker = nil
    end
end

local function TargetSync()
    if (TargetNpc() or target.guide or target.uses) and not target.ticker then
        target.ticker = C_Timer.NewTicker(TARGET_EVERY, function()
            TargetTick()
            CardTick()
        end)
    end
    TargetTick()
end

function Arrow.SetUseIcons(on)
    local db = DB()
    if not db then return end
    if on then db.gpsUseIcons = nil else db.gpsUseIcons = false end
    TargetTick()
end

function Arrow.SetTargetPairs(on)
    local db = DB()
    if not db then return end
    if on then db.gpsTargetPairs = nil else db.gpsTargetPairs = false end
    TargetTick()
end

-- A guide's creatures, { name, kind = "kill" | "talk" } each, shown while
-- set; nil or none takes them away. A new list opens rows closed before.
-- list.tiles: tiles instead of buttons, each row with npcID, verb, elite,
-- have, need, item, chance where it knows them (the Polestar extension).
function Arrow.SetTargets(list)
    target.guide = type(list) == "table" and #list > 0 and list or nil
    target.tiles = target.guide ~= nil and list.tiles == true or nil
    wipe(target.closedNames)
    TargetSync()
end

-- A guide's things to use for its step, each { kind = "item" | "spell" |
-- "macro", id, name, icon, macro (its text) }: under the target rows while
-- set, as icons in one bubble or a named button each; nil or none takes
-- them away. One with no kind or nothing to press is left out.
function Arrow.SetUses(list)
    local uses
    for _, use in ipairs(type(list) == "table" and list or {}) do
        local ok = type(use) == "table" and USE_KINDS[use.kind]
            and (use.kind == "macro" and type(use.macro) == "string"
                or use.kind == "item" and type(use.id) == "number"
                or use.kind == "spell" and (use.name or use.id) ~= nil)
        if ok then
            use.label = (use.icon and ("|T" .. use.icon .. ":14|t ") or "") .. (use.name or _G["USE"] or "Use")
            uses = uses or {}
            uses[#uses + 1] = use
        end
    end
    target.uses = uses
    wipe(target.closedUses)
    TargetSync()
end

_G["BINDING_HEADER_EASYFIND_GPS"] = "EasyFind GPS"
_G["BINDING_NAME_CLICK EasyFindGPSTarget:LeftButton"] = ns.L["GPS_TARGET_BIND"]

-- A route change or the option flipped: runs only while there is a way to point.
function Arrow:Refresh()
    local route = Route()
    local on = Enabled() and route ~= nil and not route.arrived and not route.untracked
    if on then
        since = 0
        driver:SetScript("OnUpdate", Tick)
        Update()
    else
        driver:SetScript("OnUpdate", nil)
        if frame then frame:Hide() end
    end
    TargetSync()
end

driver = CreateFrame("Frame")
Arrow._driver = driver   -- dev tools
