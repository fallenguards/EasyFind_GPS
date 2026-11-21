-- Tests for a death on the way (GPS.lua): a ghost's plans start
-- at its corpse, where it rises; risen, the route carries on from there,
-- or starts over from where the player rose when that is off its way.
local H = require("Harness")

local function Cut(src, from, to)
    local s = assert(src:find(from, 1, true), from .. " not in GPS.lua")
    local e = assert(src:find(to, s, true), to .. " not found")
    return src:sub(s, e - 1)
end

-- The ghost stands on zone map 10 (in continent 1); its corpse shows on
-- the continent map only.
local function Load()
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a")
    f:close()
    local chunk = Cut(src, "-- A ghost's corpse as a world point", "-- The start as a world point")
        .. Cut(src, "-- The steps changed under the route", "GPS.LeadToCorpse, GPS.Risen = LeadToCorpse, Risen")
    local state = { ghost = false, px = 0.5, py = 0.5, corpse = { 0.3, 0.4 } }
    local GPS = {}
    local env = setmetatable({
        GPS = GPS, L = { GPS_STEP_CORPSE = "Return to your corpse", GPS_STEP_SPIRIT_HEALER_FMT = "Talk to %s to come back to life" },
        -- The catalog's Spirit Healer nearest the ghost, as SpotOfID gives it (on map 10).
        ns = { Npcs = { SpotOfID = function(id) state.askedID = id return state.healer end } },
        UnitIsGhost = function() return state.ghost end,
        WorldPos = function(_, x, y) return 1, x * 1000, y * 1000 end,
        PlayerWorldPos = function() return 1, state.px * 1000, state.py * 1000 end,
        C_Map = {
            GetBestMapForUnit = function() return 10 end,
            GetPlayerMapPosition = function() return { GetXY = function() return state.px, state.py end } end,
            GetMapInfo = function(m) return { parentMapID = m == 10 and 1 or nil } end,
        },
        C_DeathInfo = {
            GetCorpseMapPosition = function(m)
                if m ~= 1 or not state.corpse then return nil end
                return { GetXY = function() return state.corpse[1], state.corpse[2] end }
            end,
        },
        Route = function() return state.route end,
        TrackStep = function(i) state.route.active = i end,
        Arrive = function() state.arrived = true end,
        OffRoute = function() return state.off end,
        Reroute = function() state.rerouted = (state.rerouted or 0) + 1 end,
    }, { __index = _G })
    local LeadToCorpse, Risen = assert(load(chunk .. "\nreturn LeadToCorpse, Risen", "=GPS.lua corpse", "t", env))()
    return GPS, LeadToCorpse, Risen, state
end

local function Walk(text) return { kind = "travel", text = text, arrive = { ci = 1, wx = 0, wy = 0 } } end

local tests = {}

function tests.playerStart_aGhostStartsAtItsCorpse()
    local GPS, _, _, state = Load()
    local p = GPS.PlayerStart()
    H.assertEq(p.wx, 500, "alive: where the player stands")
    state.ghost = true
    p = GPS.PlayerStart()
    H.assertEq(p.m, 1, "the corpse found on the map above the ghost's")
    H.assertEq(p.wx, 300)
    H.assertEq(p.wy, 400)
    state.corpse = nil
    H.assertEq(GPS.PlayerStart().wx, 500, "no corpse to be found: where the ghost stands")
end

function tests.ghost_isLedToItsCorpseBeforeTheStepItWasOn()
    local _, LeadToCorpse, _, state = Load()
    state.route = { steps = { Walk("a"), Walk("b") }, active = 2 }
    state.ghost = true
    LeadToCorpse()
    H.assertEq(#state.route.steps, 3)
    H.assertTrue(state.route.steps[2].corpse, "the corpse step in front of the one it was on")
    H.assertEq(state.route.active, 2)
    H.assertEq(state.route.steps[2].from.wx, 500, "from where the ghost stands")
    LeadToCorpse()
    H.assertEq(#state.route.steps, 3, "led there once")
end

function tests.risen_onTheWayTheRouteCarriesOn()
    local _, LeadToCorpse, Risen, state = Load()
    state.route = { steps = { Walk("a"), Walk("b") }, active = 2 }
    state.ghost = true
    LeadToCorpse()
    state.ghost = false
    Risen()
    H.assertEq(#state.route.steps, 2, "the corpse step goes")
    H.assertEq(state.route.steps[2].text, "b")
    H.assertEq(state.route.active, 2)
    H.assertNil(state.rerouted, "nothing planned again")
end

function tests.risen_awayFromTheWayItStartsOverFromThere()
    local _, LeadToCorpse, Risen, state = Load()
    state.route = { steps = { Walk("a"), Walk("b") }, active = 1 }
    state.ghost = true
    LeadToCorpse()
    state.ghost, state.off = false, true
    Risen()
    H.assertEq(state.rerouted, 1, "the route again from where the player rose")
end

function tests.risen_withNothingLeftArrives()
    local _, _, Risen, state = Load()
    state.route = { steps = { { kind = "travel", corpse = true } }, active = 1 }
    Risen()
    H.assertTrue(state.arrived)
    H.assertNil(state.rerouted)
end

-- A guide's death skip (the deathSkip action): the ghost is led to the
-- Spirit Healer beside it, named on the step (its Target button reads it),
-- not back to its corpse; one too far off, the corpse after all.
function tests.deathSkip_theSpiritHealer_notTheCorpse()
    local GPS, LeadToCorpse, _, state = Load()
    state.route = { steps = { Walk("a"), Walk("b") }, active = 2 }
    state.ghost = true
    state.healer = { name = "Spirit Healer", mapID = 10, x = 0.52, y = 0.5 }
    GPS.deathSkip = true
    LeadToCorpse()
    local step = state.route.steps[2]
    H.assertTrue(step.corpse and step.spirit, "a ghost's step, to the healer")
    H.assertEq(state.askedID, 6491, "the graveyards' Spirit Healer")
    H.assertEq(step.text, "Talk to Spirit Healer to come back to life")
    H.assertEq(step.npc, "Spirit Healer", "for the Target button")
    H.assertEq(step.arrive.wx, 520, "at the healer, 20 yards off")
end

function tests.deathSkip_aHealerTooFar_theCorpse()
    local GPS, LeadToCorpse, _, state = Load()
    state.route = { steps = { Walk("a"), Walk("b") }, active = 2 }
    state.ghost = true
    state.healer = { name = "Spirit Healer", mapID = 10, x = 0.9, y = 0.5 }   -- 400 yards off
    GPS.deathSkip = true
    LeadToCorpse()
    H.assertNil(state.route.steps[2].spirit, "too far: not this ghost's graveyard")
    H.assertEq(state.route.steps[2].text, "Return to your corpse")
end

-- Zephras Isle's Spirit Healers are in no catalog: its ghosts were led
-- back to their corpses on a guide's death skip (2026-11-21). The guide's
-- step says where its healer stands; that spot is taken, however far.
function tests.deathSkip_theGuidesOwnSpot_whereTheCatalogHasNoneNear()
    local GPS, LeadToCorpse, _, state = Load()
    state.route = { steps = { Walk("a"), Walk("b") }, active = 2 }
    state.ghost = true
    state.healer = nil
    GPS.SetDeathSkip({ mapID = 10, x = 0.9, y = 0.5, name = "Spirit Healer" })
    local step = state.route.steps[2]
    H.assertTrue(step.corpse and step.spirit, "to the healer the guide names, 400 yards off")
    H.assertEq(step.arrive.wx, 900)
    H.assertEq(step.npc, "Spirit Healer", "named by the guide where the catalog has none")
    GPS.SetDeathSkip({ mapID = 10, x = 0.9, y = 0.5, name = "Spirit Healer" })
    H.assertEq(#state.route.steps, 3, "the same spot again: nothing")
    GPS.SetDeathSkip({ mapID = 10, x = 0.7, y = 0.5, name = "Spirit Healer" })
    H.assertEq(#state.route.steps, 3, "another spot: swapped, not added")
    H.assertEq(state.route.steps[2].arrive.wx, 700)
    GPS.SetDeathSkip(true)
    H.assertNil(state.route.steps[2].spirit, "no spot and none in the catalog: the corpse")
    GPS.SetDeathSkip(false)
    state.healer = { name = "Geistheiler", mapID = 10, x = 0.52, y = 0.5 }
    GPS.SetDeathSkip({ mapID = 10, x = 0.9, y = 0.5, name = "Spirit Healer" })
    H.assertEq(state.route.steps[2].npc, "Geistheiler", "the catalog's name for it, in the client's language")
    H.assertEq(state.route.steps[2].arrive.wx, 900, "at the guide's spot still")
    LeadToCorpse()
    H.assertEq(#state.route.steps, 3)
end

-- The guide's step coming up or going while the ghost walks: the one way
-- is swapped for the other, once.
function tests.deathSkip_switchedWhileAGhost_swapsTheWay()
    local GPS, LeadToCorpse, _, state = Load()
    state.route = { steps = { Walk("a"), Walk("b") }, active = 2 }
    state.ghost = true
    state.healer = { name = "Spirit Healer", mapID = 10, x = 0.52, y = 0.5 }
    LeadToCorpse()
    H.assertNil(state.route.steps[2].spirit, "no death skip: the corpse")
    GPS.SetDeathSkip(true)
    H.assertEq(#state.route.steps, 3, "swapped, not added")
    H.assertTrue(state.route.steps[2].spirit, "now the healer")
    GPS.SetDeathSkip(true)
    H.assertEq(#state.route.steps, 3, "the same again: nothing")
    GPS.SetDeathSkip(false)
    H.assertEq(#state.route.steps, 3)
    H.assertNil(state.route.steps[2].spirit, "the corpse again")
end

local pass, fail, failures = H.runSuite("GPSCorpse", tests)
return { pass = pass, fail = fail, failures = failures }
