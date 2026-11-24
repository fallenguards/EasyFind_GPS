-- A route's last step to a quest in the log tracks the quest itself
-- (GPS.EndQuest, TrackStep): the game's waypoint pin, set on each step's
-- end, drew over the quest's own icon after the map reopened (Forever,
-- 2026-11-10). The beacon stands on the tracked quest, and the watch that
-- lets go of the route when the player picks a quest leaves this one be.
-- Any step whose end has a log quest's icon on it tracks that quest too:
-- our dot, the game's pin and the quest's icon stood on one spot
-- (2026-11-24).
local H = require("Harness")

local function Read(path)
    local f = assert(io.open(H.Path(path), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

-- onMap: the quests the map shows, { questID, x, y } each; a map is 1000
-- yards a side.
local function LoadEndQuest(inLog, superTrack, onMap)
    local src = Read("GPS.lua")
    local s = assert(src:find("GPS.QUEST_AT_YARDS = ", 1, true))
    local _, e = assert(src:find("\nend\n", src:find("function GPS.EndQuest(route, index)", 1, true), true))
    local env = setmetatable({
        GPS = {},
        C_SuperTrack = superTrack ~= false and { SetSuperTrackedQuestID = function() end } or nil,
        C_QuestLog = { GetLogIndexForQuestID = function(id) return inLog[id] end,
                       GetQuestsOnMap = function() return onMap or {} end },
        WorldPos = function(_, x, y) return 0, x * 1000, y * 1000 end,
    }, { __index = _G })
    assert(load(src:sub(s, e), "=GPS.lua EndQuest", "t", env))()
    return env.GPS.EndQuest
end

local function Route(questID, n)
    local steps = {}
    for i = 1, n do steps[i] = { kind = "travel" } end
    return { dest = { name = "Turn in", questID = questID }, steps = steps }
end

local tests = {}

function tests.theLastStepToALogQuest_tracksTheQuest()
    local EndQuest = LoadEndQuest({ [42] = 3 })
    H.assertEq(EndQuest(Route(42, 3), 3), 42)
    H.assertNil(EndQuest(Route(42, 3), 2), "earlier steps keep the game's pin")
end

function tests.aQuestNotInTheLog_orNoQuestTracking_keepsThePin()
    H.assertNil(LoadEndQuest({})(Route(42, 1), 1), "a quest to take: our button, the pin under it")
    H.assertNil(LoadEndQuest({ [42] = 1 }, false)(Route(42, 1), 1), "a client without quest tracking")
    H.assertNil(LoadEndQuest({ [42] = 1 })(Route(nil, 1), 1), "no quest")
end

-- A walk step ending where the map shows a log quest's icon.
local function StepRoute(n, index, x, y)
    local route = Route(nil, n)
    route.dest = { name = "Somewhere" }
    route.steps[index] = { kind = "travel", mapID = 1411, x = x, y = y }
    return route
end

function tests.aStepEndingOnALogQuestsIcon_tracksThatQuest()
    local EndQuest = LoadEndQuest({}, nil, { { questID = 77, x = 0.5, y = 0.505 } })
    H.assertEq(EndQuest(StepRoute(3, 2, 0.5, 0.5), 2), 77, "5 yards off: the icon is the step's mark")
end

function tests.aQuestIconFurtherOff_keepsThePin()
    local EndQuest = LoadEndQuest({}, nil, { { questID = 77, x = 0.5, y = 0.53 } })
    H.assertNil(EndQuest(StepRoute(3, 2, 0.5, 0.5), 2), "30 yards off: another spot")
end

function tests.theLastStepWithoutAQuest_looksForAnIconToo()
    local EndQuest = LoadEndQuest({}, nil, { { questID = 77, x = 0.5, y = 0.5 } })
    H.assertEq(EndQuest(StepRoute(3, 3, 0.5, 0.5), 3), 77)
end

function tests.trackStep_theWatch_andTheBeacon_takeTheQuest()
    local gps = Read("GPS.lua")
    H.assertTrue(gps:find("local quest = GPS.EndQuest(route, index)", 1, true) ~= nil)
    H.assertTrue(gps:find("if step.inside or quest then GPS.DropPin(route) end", 1, true) ~= nil,
        "the pin a step before set goes")
    H.assertTrue(gps:find("if not route.untracked then GPS.TrackQuest(quest) end", 1, true) ~= nil)
    H.assertTrue(gps:find("ST.GetSuperTrackedQuestID() == route.questTracked then\n                return", 1, true) ~= nil,
        "the watch leaves the route's own quest be")
    H.assertTrue(gps:find("questID = data.questID", 1, true) ~= nil and gps:find("questID = dest.questID", 1, true) ~= nil,
        "the quest kept from the row and on a new plan")
    local pin = Read("WorldPin.lua")
    H.assertTrue(pin:find("return ST.GetSuperTrackedQuestID() == route.questTracked", 1, true) ~= nil,
        "the beacon stands on the tracked quest")
    H.assertTrue(Read("QuestDirections.lua"):find("questID = questID }", 1, true) ~= nil)
end

local pass, fail, failures = H.runSuite("GPSEndQuest", tests)
return { pass = pass, fail = fail, failures = failures }
