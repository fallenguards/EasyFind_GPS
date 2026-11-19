-- The box under the arrow or the beacon (the Arrow text setting): its
-- right-click menu's row turns it off and on, the arrow's own right-click
-- opens that menu while the box is hidden, and shown again it says what it
-- said before; extensions reach it as the gps arrowBox action. Hidden with
-- no way back (2026-11-18): the row was a one-way Hide.
local H = require("Harness")

local function Source(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

-- GPS.ArrowBoxShown and GPS.SetArrowBox, from GPS.lua, over db.
local function Box(db)
    local src = Source("GPS.lua")
    local s = assert(src:find("\nfunction GPS.ArrowBoxShown()", 1, true), "ArrowBoxShown")
    local _, e = assert(src:find("\n    Refresh()\nend\n", s, true))
    local refreshed = 0
    local env = setmetatable({ GPS = {}, DB = function() return db end, Refresh = function() refreshed = refreshed + 1 end },
        { __index = _G })
    assert(load(src:sub(s + 1, e), "=GPS.lua ArrowBox", "t", env))()
    return env.GPS, function() return refreshed end
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
    local L = setmetatable({ GPS_PLATE_SHOWN_TT_FMT = "Hidden, the arrow or %s." },
        { __index = function(_, k) return k end })
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

function tests.itsMenuRow_turnsTheBoxOffAndOn()
    local db = {}
    local GPS = Box(db)
    local row
    for _, def in ipairs(assert(MenuOf(GPS), "a menu")) do
        if def.label == "GPS_PLATE_SHOWN" then row = def end
    end
    H.assertNotNil(row, "the box's row")
    H.assertEq(row.kind, "check", "a switch, not a one-way Hide")
    H.assertEq(row.tooltip, "Hidden, the arrow or GPS_ARROW_TEXT.", "the ways back named")
    H.assertTrue(row.get(), "shown")
    row.set(false)
    H.assertFalse(row.get(), "hidden")
    H.assertEq(db.gpsArrowText, "off", "the Arrow text setting, off")
    row.set(true)
    H.assertTrue(row.get(), "and back")
end

-- Shown again, the box says what it said before it was hidden.
function tests.shownAgain_saysWhatItDidBefore()
    local db = { gpsArrowText = "step" }
    local GPS, refreshed = Box(db)
    GPS.SetArrowBox(false)
    H.assertEq(db.gpsArrowText, "off")
    GPS.SetArrowBox(true)
    H.assertEq(db.gpsArrowText, "step", "step only again")
    H.assertNil(db.gpsArrowTextWas, "nothing left over")
    local full = {}
    local G2 = Box(full)
    G2.SetArrowBox(false)
    G2.SetArrowBox(true)
    H.assertNil(full.gpsArrowText, "the full box, the default")
    H.assertEq(refreshed(), 2, "redrawn on each change")
    GPS.SetArrowBox(true)
    H.assertEq(refreshed(), 2, "no change, no redraw")
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
    H.assertTrue(src:find('local mode = db and db.gpsArrowText or "full"%s+if mode == "off" then return nil end') ~= nil,
        "PlateLines: nothing with the setting off")
    H.assertTrue(src:find("plate:SetShown(text ~= nil)", 1, true) ~= nil, "the beacon's box hides on nothing")
    H.assertTrue(Source("Arrow.lua"):find("plate:SetShown(text ~= nil)", 1, true) ~= nil, "and the arrow's")
end

local pass, fail, failures = H.runSuite("GPSArrowBox", tests)
return { pass = pass, fail = fail, failures = failures }
