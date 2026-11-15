-- Close the window on arrival (GPS.lua Arrive): with the option on, the
-- window closes when the arrived route clears; off, or a new route
-- started meanwhile, it stays.
local H = require("Harness")

local function Source()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local function Slice(src, head)
    local s = assert(src:find(head, 1, true), head .. " not in GPS.lua")
    local _, e = src:find("\nend\r?\n", s)
    return src:sub(s, e)
end

local function World(db)
    local w = { db = db, cleared = 0, closed = 0, open = true }
    local env = setmetatable({
        ARRIVED_LINGER = 8,
        EasyFind = { API = { Fire = function() end }, db = {} },
        ns = {},
        StopTicker = function() end, LiftPin = function() end, Refresh = function() end,
        DB = function() return w.db end,
        Route = function() return w.route end,
        Utils = { SafeAfter = function(_, fn) w.later = fn end },
        GPS = {
            Clear = function() w.cleared = w.cleared + 1 w.route = nil end,
            IsWindowOpen = function() return w.open end,
            CloseWindow = function() w.closed = w.closed + 1 w.open = false end,
        },
    }, { __index = _G })
    w.Arrive = assert(load(Slice(Source(), "local function Arrive(route)") .. "\nreturn Arrive",
        "=GPS.lua Arrive", "t", env))()
    function w.Reach()
        w.route = { dest = {} }
        w.Arrive(w.route)
    end
    return w
end

local tests = {}

function tests.on_closesWithTheRoute()
    local w = World({ gpsAutoClose = true })
    w.Reach()
    H.assertEq(w.closed, 0, "the arrival line shows first")
    w.later()
    H.assertEq(w.cleared, 1)
    H.assertEq(w.closed, 1, "the window goes when the route clears")
end

function tests.off_staysOpen()
    local w = World({})
    w.Reach()
    w.later()
    H.assertEq(w.cleared, 1)
    H.assertEq(w.closed, 0)
end

function tests.aNewRouteMeanwhile_keepsIt()
    local w = World({ gpsAutoClose = true })
    w.Reach()
    w.route = { dest = {} }
    w.later()
    H.assertEq(w.cleared, 0, "the new route is not cleared")
    H.assertEq(w.closed, 0, "nor its window closed")
end

function tests.alreadyClosed_notClosedAgain()
    local w = World({ gpsAutoClose = true })
    w.open = false
    w.Reach()
    w.later()
    H.assertEq(w.closed, 0)
end

local pass, fail, failures = H.runSuite("GPSAutoClose", tests)
return { pass = pass, fail = fail, failures = failures }
