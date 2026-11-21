-- What a guide extension lays over the GPS (2026-11-18): a line in the
-- box under the step (setStatus: a grind's XP), and a farm circuit drawn
-- closed on the world map and the minimap (setCircuit).
local H = require("Harness")

local function Source(rel)
    local f = assert(io.open(H.Path(rel), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

local function Cut(src, from, to)
    local s = assert(src:find(from, 1, true), from)
    local found, e = src:find(to, s, true)
    assert(found, to)
    return src:sub(s, e)
end

-- GPS.SetStatus and GPS.SetCircuit, from GPS.lua: map 10 is continent 1,
-- map 20 continent 2, a map 1000 yards a side.
local function Setters()
    local chunk = Cut(Source("GPS.lua"), "function GPS.SetStatus(text)", "\nend\n")
        .. Cut(Source("GPS.lua"), "function GPS.SetCircuit(list)", "\nend\n")
    local redraws = { map = 0, mini = 0 }
    local GPS = {}
    local env = setmetatable({
        GPS = GPS,
        WorldPos = function(m, x, y) if m == 10 or m == 20 then return m / 10, x * 1000, y * 1000 end end,
        ns = { GPSPreview = { Redraw = function() redraws.map = redraws.map + 1 end },
               GPSMinimap = { Redraw = function() redraws.mini = redraws.mini + 1 end } },
    }, { __index = _G })
    assert(load(chunk, "=GPS.lua setters", "t", env))()
    return GPS, redraws
end

-- WorldPin.PlateLines and FillPlate, from WorldPin.lua, over db and GPS.
local function Plate(db, gps)
    gps.ArrowBoxShown = function() return db.gpsArrowBox ~= false end
    gps.BoxLineShown = function(key) return db[key] ~= false end
    local src = Source("WorldPin.lua")
    local chunk = Cut(src, "local function StackLine(p, fs, s, above, h)", "\nend\n")
        .. "\n" .. Cut(src, "function WorldPin.FillPlate(p, text, sub, sub2, note)", "\nend\n")
        .. "\n" .. Cut(src, "function WorldPin.PlateLines(route, yards)", "\nend\n")
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
    function fs:SetWordWrap() end
    function fs:SetMaxLines() end
    function fs:SetShown(on) self.shown = on end
    function fs:ClearAllPoints() self.under = nil end
    function fs:SetPoint(_, rel) self.under = rel end
    return fs
end

local tests = {}

function tests.aStatusLine_isTextOrNothing()
    local GPS = Setters()
    GPS.SetStatus("XP 642 / 895 (72%)")
    H.assertEq(GPS.status, "XP 642 / 895 (72%)")
    GPS.SetStatus("")
    H.assertNil(GPS.status, "empty: none")
    GPS.SetStatus(42)
    H.assertNil(GPS.status, "not text: none")
end

-- The box says it under the step whatever lines are on, and nothing with
-- the box off.
function tests.theBox_saysTheStatusUnderTheStep()
    local gps = { status = "XP 642 / 895 (72%)", StepText = function(step) return step.text end }
    local route = { steps = { { text = "Grind to 895+/1400xp" } }, active = 1 }
    local db = { gpsBoxThisStep = false, gpsBoxTotal = false }
    local Pin = Plate(db, gps)
    local text, sub, sub2, note = Pin.PlateLines(route, 50)
    H.assertEq(text, "Grind to 895+/1400xp")
    H.assertEq(note, "XP 642 / 895 (72%)", "the description alone: the status too")
    H.assertEq(sub .. sub2, "")
    db.gpsArrowBox = false
    H.assertNil(Pin.PlateLines(route, 50), "the box off: none")
    local p = { text = Line(), note = Line(), sub = Line(), sub2 = Line() }
    function p:SetSize(w, h) self.w, self.h = w, h end
    Pin.FillPlate(p, text, "This step: 50 yd", "", note)
    H.assertTrue(p.note.shown, "the status shows")
    H.assertTrue(p.sub.under == p.note, "the distance under it")
    local tall = p.h
    Pin.FillPlate(p, text, "This step: 50 yd", "", nil)
    H.assertFalse(p.note.shown, "gone")
    H.assertTrue(p.sub.under == p.text, "the distance back under the step")
    H.assertTrue(p.h < tall, "the box shorter")
end

function tests.aCircuit_isItsSpotsInWorldYards_closedWhenDrawn()
    local GPS, redraws = Setters()
    GPS.SetCircuit({ { mapID = 10, x = 0.1, y = 0.2 }, { mapID = 10, x = 0.3, y = 0.2 }, { mapID = 10, x = 0.2, y = 0.4 } })
    local c = GPS.circuit
    H.assertNotNil(c, "set")
    H.assertEq(c.ci, 1)
    H.assertEq(#c.pts, 6)
    H.assertEq(c.pts[3], 300)
    H.assertEq(redraws.map, 1, "the world map drawn again")
    H.assertEq(redraws.mini, 1, "and the minimap")
    GPS.SetCircuit({ { mapID = 10, x = 0.1, y = 0.2 }, { mapID = 10, x = 0.3, y = 0.2 } })
    H.assertNil(GPS.circuit, "two spots: no loop")
    GPS.SetCircuit({ { mapID = 10, x = 0.1, y = 0.2 }, { mapID = 20, x = 0.3, y = 0.2 }, { mapID = 10, x = 0.2, y = 0.4 } })
    H.assertNil(GPS.circuit, "across continents: none")
    GPS.SetCircuit(nil)
    H.assertNil(GPS.circuit)
end

-- Both maps draw it after the way, back to its first spot, on its continent.
function tests.bothMaps_drawTheCircuitClosed()
    local map = Source("Preview.lua")
    H.assertTrue(map:find("local circuit = ns.GPS and ns.GPS.circuit", 1, true) ~= nil, "the world map reads it")
    H.assertTrue(map:find("PenTo(Frac(affine, pts[1], pts[2]))", 1, true) ~= nil, "closed")
    local mini = Source("Minimap.lua")
    H.assertTrue(mini:find("if circuit and circuit.ci == ci then", 1, true) ~= nil, "the minimap, on its continent")
    H.assertTrue(mini:find("To(pts[1], pts[2])", 1, true) ~= nil, "closed")
end

function tests.theActions_areRegistered()
    local src = Source("GPS.lua")
    for _, name in ipairs({ "deathSkip", "setStatus", "setCircuit" }) do
        H.assertTrue(src:find('EasyFind.API.RegisterAction("gps", "' .. name .. '"', 1, true) ~= nil, name)
    end
end

local pass, fail, failures = H.runSuite("GPSGuideOverlays", tests)
return { pass = pass, fail = fail, failures = failures }
