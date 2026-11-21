-- The box under the arrow or the beacon: its right-click menu's row turns
-- it off and on, the arrow's own right-click opens that menu while the box
-- is hidden, and its lines (the step's description, this step, the total
-- left) are switches of their own, in that menu and the GPS settings
-- (2026-11-19: "as much/little as ppl want"); extensions reach the box as
-- the gps arrowBox action. Hidden with no way back (2026-11-18): the row
-- was a one-way Hide.
local H = require("Harness")

local function Source(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

local function Cut(src, from, to)
    local s = assert(src:find(from, 1, true), from)
    local _, e = assert(src:find(to, s, true))
    return src:sub(s, e)
end

local KEYED_L = setmetatable({}, { __index = function(_, k) return k end })

-- The box's switches and the old choice's conversion, from GPS.lua, over db.
local function Box(db)
    local refreshed = 0
    local env = setmetatable({ GPS = {}, DB = function() return db end, L = KEYED_L,
                               Refresh = function() refreshed = refreshed + 1 end,
                               Utils = { OffOrNil = function(on) if on then return nil end return false end } },
        { __index = _G })
    local chunk = Cut(Source("GPS.lua"), "GPS.BOX_LINES = {", "db.gpsArrowText, db.gpsArrowTextWas = nil, nil\nend\n")
    assert(load(chunk, "=GPS.lua ArrowBox", "t", env))()
    return env.GPS, function() return refreshed end
end

-- The plate's lines and their stacking, from WorldPin.lua, over gps.
local function Plate(gps)
    local src = Source("WorldPin.lua")
    local chunk = Cut(src, "local function StackLine(p, fs, s, above, h)", "\nend\n")
        .. Cut(src, "function WorldPin.FillPlate(p, text, sub, sub2, note)", "\nend\n")
        .. Cut(src, "function WorldPin.PlateLines(route, yards)", "\nend\n")
    local env = setmetatable({
        WorldPin = {}, mmax = math.max, mmin = math.min, PLATE_MAX_W = 240, sformat = string.format,
        WRAP_LINES = 4, Natural = function(fs) return fs:GetStringWidth() end,
        ns = { L = setmetatable({}, { __index = function(_, k) return k .. " %s" end }), GPS = gps },
    }, { __index = _G })
    assert(load(chunk, "=WorldPin.lua plate", "t", env))()
    return env.WorldPin
end

local function Line()
    local fs = { shown = true }
    function fs:SetText(t) self.text = t end
    function fs:GetStringWidth() return #(self.text or "") * 6 end
    function fs:GetStringHeight() return (self.text or "") ~= "" and 10 or 0 end
    function fs:SetWidth() end
    function fs:SetWordWrap(on) self.wraps = on end
    function fs:SetMaxLines(n) self.maxLines = n end
    function fs:SetShown(on) self.shown = on end
    function fs:ClearAllPoints() self.under = nil end
    function fs:SetPoint(_, rel) self.under = rel end
    return fs
end

-- A plate built with stand-ins, right-clicked: the menu's rows.
local function MenuOf(gps)
    local src = Source("WorldPin.lua")
    local s = assert(src:find("\nfunction WorldPin.NewPlate(parent)", 1, true), "NewPlate")
    local _, e = assert(src:find("\n    return p\nend\n", s, true))
    local function Frame()
        local fr = { scripts = {} }
        function fr:SetScript(k, fn) self.scripts[k] = fn end
        function fr:GetScript(k) return self.scripts[k] end
        for _, m in ipairs({ "SetSize", "EnableMouse", "ClearAllPoints", "SetPoint", "SetJustifyH", "SetWordWrap",
                             "SetShadowColor" }) do
            fr[m] = function() end
        end
        function fr:CreateFontString() return Frame() end
        return fr
    end
    local shown
    local L = KEYED_L
    -- GPS.lua's own: a flyout row ticked while on, a click flips it.
    gps.CheckFlyoutRow = gps.CheckFlyoutRow or function(d)
        return { text = d.label, check = d, keepOpen = true, onClick = function() d.set(not d.get()) end }
    end
    local env = setmetatable({
        WorldPin = { ApplyPlateBorder = function() end },
        ns = { L = L, GPS = gps, ShowTogglePopup = function(_, _, defs) shown = defs end },
        CreateFrame = function() return Frame() end,
        PaintPlate = function() end,
        plates = {},
        DB = function() return {} end,
        GetCursorPosition = function() return 100, 100 end,
        UIParent = { GetEffectiveScale = function() return 1 end },
    }, { __index = _G })
    assert(load(src:sub(s + 1, e), "=WorldPin.NewPlate", "t", env))()
    local p = env.WorldPin.NewPlate(Frame())
    p.scripts.OnMouseDown(p, "RightButton")
    p.scripts.OnMouseUp(p, "RightButton")
    return shown
end

local tests = {}

-- A step cut to fit the box is read whole on hover (asked for,
-- 2026-11-21); one that fits says nothing more.
function tests.aCutStep_isReadWholeOnHover()
    local src = Source("WorldPin.lua")
    local s = assert(src:find("\nfunction WorldPin.NewPlate(parent)", 1, true), "NewPlate")
    local _, e = assert(src:find("\n    return p\nend\n", s, true))
    local cut = false
    local function Frame()
        local fr = { scripts = {} }
        function fr:SetScript(k, fn) self.scripts[k] = fn end
        function fr:GetScript(k) return self.scripts[k] end
        for _, m in ipairs({ "SetSize", "EnableMouse", "ClearAllPoints", "SetPoint", "SetJustifyH", "SetWordWrap",
                             "SetShadowColor" }) do
            fr[m] = function() end
        end
        function fr:CreateFontString() return Frame() end
        function fr:IsTruncated() return cut end
        return fr
    end
    local resolve
    local env = setmetatable({
        WorldPin = { ApplyPlateBorder = function() end },
        ns = { L = KEYED_L, Utils = { AttachDelayedTooltip = function(_, _, fn) resolve = fn end } },
        CreateFrame = function() return Frame() end,
        PaintPlate = function() end,
        plates = {},
        DB = function() return {} end,
    }, { __index = _G })
    assert(load(src:sub(s, e), "=WorldPin.NewPlate", "t", env))()
    local plate = env.WorldPin.NewPlate(Frame())
    H.assertNotNil(resolve, "the box takes a hover")
    plate.shownText = "Press the Macro in the Active Items Frame to craft Linen Bandages."
    H.assertNil(resolve(plate), "it fits: nothing more to say")
    cut = true
    H.assertEq(resolve(plate), plate.shownText, "cut: all of it")
end

-- The arrow unlocked, a grip over the box takes the mouse and the box
-- under it never heard the hover (2026-11-21, his arrow unlocked): the
-- grip passes its hover on to the box.
function tests.theArrowUnlocked_theGripsHoverIsTheBoxs()
    local chunk = Cut(Source("Arrow.lua"), '    local grip = CreateFrame("Frame", nil, plate)',
        "        if leave then leave(plate) end\n    end)\n")
    local function Frame()
        local fr = { scripts = {} }
        function fr:SetScript(k, fn) self.scripts[k] = fn end
        function fr:GetScript(k) return self.scripts[k] end
        for _, m in ipairs({ "SetAllPoints", "EnableMouse", "RegisterForDrag" }) do fr[m] = function() end end
        return fr
    end
    local plate, grip = Frame(), nil
    local heard = {}
    plate:SetScript("OnEnter", function(self) heard[#heard + 1] = { "enter", self } end)
    plate:SetScript("OnLeave", function(self) heard[#heard + 1] = { "leave", self } end)
    local env = setmetatable({ plate = plate, CreateFrame = function()
        grip = Frame()
        return grip
    end }, { __index = _G })
    assert(load(chunk, "=Arrow.lua grip", "t", env))()
    grip.scripts.OnEnter(grip)
    grip.scripts.OnLeave(grip)
    H.assertEq(#heard, 2)
    H.assertEq(heard[1][1], "enter")
    H.assertTrue(heard[1][2] == plate and heard[2][2] == plate, "as the box itself, for its tooltip's owner")
    H.assertEq(heard[2][1], "leave")
    plate.scripts = {}
    grip.scripts.OnEnter(grip)
    H.assertEq(#heard, 2, "a box with no hover of its own: nothing, no error")
end

-- Most of a guide's steps were cut with an ellipsis (2026-11-21, "make
-- room for it"): a long step runs onto more lines, four at most, and a
-- switch among the box's own cuts it to one line again, at once.
function tests.aLongStep_runsOntoMoreLines_unlessSwitchedOff()
    local db = {}
    local GPS = Box(db)
    local WorldPin = Plate(GPS)
    local plate = { text = Line(), note = Line(), sub = Line(), sub2 = Line(), SetSize = function() end }
    local long = "Jump off the mountain and use Walk on Air to fly towards the waypoint location."
    WorldPin.FillPlate(plate, long, "This step: 364 yd")
    H.assertTrue(plate.text.wraps, "wrapped")
    H.assertEq(plate.text.maxLines, 4, "four lines at most; past that, the hover")
    local wrap
    for _, line in ipairs(GPS.BOX_LINES) do
        if line.key == "gpsBoxWrap" then wrap = line end
    end
    H.assertNotNil(wrap, "its switch among the box's own")
    GPS.SetBoxLine("gpsBoxWrap", false)
    H.assertEq(db.gpsBoxWrap, false, "off, stored")
    WorldPin.FillPlate(plate, long, "This step: 364 yd")
    H.assertFalse(plate.text.wraps, "the same words filled again: one line now")
    H.assertEq(plate.text.maxLines, 1)
    GPS.SetBoxLine("gpsBoxWrap", true)
    H.assertNil(db.gpsBoxWrap, "on, nothing stored")
end

function tests.itsMenuRow_turnsTheBoxOffAndOn()
    local db = {}
    local GPS = Box(db)
    local row
    for _, def in ipairs(assert(MenuOf(GPS), "a menu")) do
        if def.label == "GPS_PLATE_SHOWN" then row = def end
    end
    H.assertNotNil(row, "the box's row")
    H.assertEq(row.kind, "check", "a switch, not a one-way Hide")
    H.assertEq(type(row.rows), "function", "its border and lines in a flyout beside it")
    H.assertTrue(row.get(), "shown")
    row.set(false)
    H.assertFalse(row.get(), "hidden")
    H.assertEq(db.gpsArrowBox, false, "stored only while off")
    row.set(true)
    H.assertTrue(row.get(), "and back")
    H.assertNil(db.gpsArrowBox)
end

-- The box's own switches sit in the flyout off its row, the menu's top
-- level one row for the box (2026-11-19: "surely this could be a
-- flyout?", five switches about the box had stood in the menu).
function tests.theBoxsSwitches_areInTheFlyoutOffItsRow()
    local db = {}
    local GPS, refreshed = Box(db)
    local defs, box, checks = assert(MenuOf(GPS), "a menu"), nil, 0
    for _, def in ipairs(defs) do
        if def.kind == "check" then checks = checks + 1 end
        if def.label == "GPS_PLATE_SHOWN" then box = def end
    end
    H.assertEq(checks, 1, "one switch at the top level: the box's")
    local rows, labels = box.rows(), {}
    for _, r in ipairs(rows) do labels[#labels + 1] = r.isSeparator and "-" or r.text end
    H.assertEq(table.concat(labels, ","), "GPS_PLATE_BORDER_MENU,-,Description,GPS_BOX_THIS_STEP,GPS_BOX_TOTAL,GPS_BOX_WRAP")
    local total = rows[5]
    H.assertTrue(total.keepOpen, "a click leaves the flyout open")
    H.assertTrue(total.check.get())
    total.onClick()
    H.assertEq(db.gpsBoxTotal, false, "off, stored")
    H.assertFalse(box.rows()[5].check.get(), "listed anew, unticked")
    H.assertNil(db.gpsBoxStep, "the others as they were")
    box.rows()[5].onClick()
    H.assertNil(db.gpsBoxTotal, "on, nothing stored")
    H.assertEq(refreshed(), 2, "redrawn on each change")
end

-- Hidden and shown again, the box keeps the lines it was set to.
function tests.theBoxHiddenAndBack_keepsItsLines()
    local db = { gpsBoxTotal = false }
    local GPS = Box(db)
    GPS.SetArrowBox(false)
    GPS.SetArrowBox(true)
    H.assertTrue(GPS.ArrowBoxShown())
    H.assertEq(db.gpsBoxTotal, false)
    H.assertTrue(GPS.BoxLineShown("gpsBoxStep"))
end

-- The Arrow text choice the switches replaced, read once at login.
function tests.theOldArrowTextChoice_becomesTheSwitches()
    local cases = {
        { old = { gpsArrowText = "range" }, box = nil, this = nil, total = false },
        { old = { gpsArrowText = "step" }, box = nil, this = false, total = false },
        { old = { gpsArrowText = "off", gpsArrowTextWas = "step" }, box = false, this = false, total = false },
        { old = { gpsArrowText = "off" }, box = false, this = nil, total = nil },
    }
    for _, c in ipairs(cases) do
        local GPS = Box(c.old)
        GPS.MigrateArrowText(c.old)
        local name = tostring(c.old.gpsArrowText) .. "/" .. tostring(c.old.gpsArrowTextWas)
        H.assertEq(c.old.gpsArrowBox, c.box, name .. ": the box")
        H.assertEq(c.old.gpsBoxThisStep, c.this, name .. ": this step")
        H.assertEq(c.old.gpsBoxTotal, c.total, name .. ": the total")
        H.assertNil(c.old.gpsBoxStep, name .. ": the description always kept")
        H.assertNil(c.old.gpsArrowText, name .. ": the old choice gone")
        H.assertNil(c.old.gpsArrowTextWas)
    end
end

-- A line switched off takes no room: the next shown one moves up to the
-- top; every line off and no extension's line, no box at all.
function tests.aLineOff_theNextMovesUp_allOff_noBox()
    local db = { gpsBoxStep = false }
    local gps = { StepText = function(step) return step.text end, EtaText = function(s) return s .. " s" end,
                  DistanceText = function(y) return y .. " yd" end,
                  ArrowBoxShown = function() return db.gpsArrowBox ~= false end,
                  BoxLineShown = function(k) return db[k] ~= false end }
    local route = { steps = { { text = "Talk to Johaan", sec = 30 }, { text = "Talk to Zygand" } }, active = 1, eta = 60 }
    local Pin = Plate(gps)
    local text, sub, sub2, note = Pin.PlateLines(route, 50)
    H.assertEq(text, "", "no description")
    H.assertEq(sub, "GPS_PLATE_STEP_BOTH_FMT 50 yd", "this step")
    H.assertEq(sub2, "GPS_PLATE_TRIP_FMT 60 s", "the total")
    local p = { text = Line(), note = Line(), sub = Line(), sub2 = Line() }
    function p:SetSize(w, h) self.w, self.h = w, h end
    Pin.FillPlate(p, text, sub, sub2, note)
    H.assertFalse(p.text.shown, "the description's line hidden")
    H.assertTrue(p.sub.under == p, "this step at the top")
    H.assertTrue(p.sub2.under == p.sub, "the total under it")
    H.assertEq(p.h, 6 + 10 + 2 + 10 + 6, "two lines' room")
    db.gpsBoxThisStep, db.gpsBoxTotal = false, false
    H.assertNil(Pin.PlateLines(route, 50), "every line off: no box")
    gps.status = "XP 642 / 895"
    H.assertEq(select(4, Pin.PlateLines(route, 50)), "XP 642 / 895", "an extension's line alone still shows")
    db.gpsArrowBox = false
    H.assertNil(Pin.PlateLines(route, 50), "the box off: none")
end

-- The arrow's own right-click reaches the box's menu, the box hidden too;
-- Shift held or unlocked, it stands aside for the drag.
function tests.theArrowsRightClick_opensTheBoxsMenu()
    local src = Source("Arrow.lua")
    H.assertTrue(src:find('local clicker = CreateFrame%("Frame", nil, frame%)%s+clicker:SetAllPoints%(frame%)') ~= nil,
        "a layer over the arrow")
    H.assertTrue(src:find('clicker:SetScript("OnMouseUp", grip:GetScript("OnMouseUp"))', 1, true) ~= nil,
        "its clicks go to the box's menu, as the grip's do")
    H.assertTrue(src:find("clicker:EnableMouse(passing and not take)", 1, true) ~= nil, "aside for a drag")
    H.assertTrue(src:find('passing = ns.Utils.SafeCallMethod(clicker, "SetPropagateMouseClicks", true)', 1, true) ~= nil,
        "only while its clicks pass through to the world")
end

function tests.extensionsReachIt_asTheArrowBoxAction()
    local src = Source("GPS.lua")
    H.assertTrue(src:find('EasyFind.API.RegisterAction("gps", "arrowBox", function(on)', 1, true) ~= nil, "the action")
    H.assertTrue(src:find("if on == nil then return GPS.ArrowBoxShown() end", 1, true) ~= nil, "no argument: shown or not")
end

-- Off, both boxes say nothing, so neither shows.
function tests.offTheBoxSaysNothing()
    local src = Source("WorldPin.lua")
    H.assertTrue(src:find("if not (GPS and GPS.ArrowBoxShown()) then return nil end", 1, true) ~= nil,
        "PlateLines: nothing with the box off")
    H.assertTrue(src:find("plate:SetShown(text ~= nil)", 1, true) ~= nil, "the beacon's box hides on nothing")
    H.assertTrue(Source("Arrow.lua"):find("plate:SetShown(text ~= nil)", 1, true) ~= nil, "and the arrow's")
end

local pass, fail, failures = H.runSuite("GPSArrowBox", tests)
return { pass = pass, fail = fail, failures = failures }
