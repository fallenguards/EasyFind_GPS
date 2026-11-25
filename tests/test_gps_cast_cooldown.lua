-- A route step's cast button under the arrow (a mage's teleport): its
-- swipe never hands SetCooldown a secret number. In a fight the game
-- withholds a cooldown's numbers and refuses them back from an addon:
-- "bad argument #1 to 'SetCooldown' ... Secret values are only allowed
-- during untainted execution", thousands of times a dungeon run
-- (a player's report, 2026-11-25).
local H = require("Harness")

local function UpdateCooldown(env)
    local f = assert(io.open(H.Path("GPS.lua"), "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local a = assert(src:find("local function UpdateCooldown(btn)", 1, true))
    local b = assert(src:find("\nlocal castButtons = {}", a, true))
    return assert(load(src:sub(a, b) .. "\nreturn UpdateCooldown", "UpdateCooldown", "t",
        setmetatable(env, { __index = _G })))()
end

local SECRET = setmetatable({}, { __lt = function() error("compared a secret") end })

local function Cooldown()
    local cd = { calls = {} }
    function cd:SetCooldown(start, duration)
        if start == SECRET or duration == SECRET then error("Secret values are only allowed during untainted execution") end
        self.calls[#self.calls + 1] = "set " .. start .. " " .. duration
    end
    function cd:Clear() self.calls[#self.calls + 1] = "clear" end
    return cd
end

local function secret(v) return v == SECRET end

local tests = {}

function tests.aSecretCooldown_inAFight_clears_neverSetsIt()
    local update = UpdateCooldown({
        issecretvalue = secret,
        C_Spell = { GetSpellCooldown = function() return { startTime = SECRET, duration = SECRET, modRate = SECRET } end },
        C_Container = { GetItemCooldown = function() return SECRET, SECRET end },
    })
    for _, btn in ipairs({ { spellID = 3567, cd = Cooldown() }, { itemID = 6948, cd = Cooldown() } }) do
        H.assertTrue(pcall(update, btn), "no error")
        H.assertEq(table.concat(btn.cd.calls, ","), "clear")
    end
end

function tests.aSpell_drawsFromTheClientsDurationObject()
    local length, asked = {}, nil
    local update = UpdateCooldown({
        issecretvalue = secret,
        C_Spell = { GetSpellCooldownDuration = function(id, ignoreGCD) asked = { id, ignoreGCD } return length end,
                    GetSpellCooldown = function() error("not read: the duration object stands") end },
    })
    local btn = { spellID = 3567, cd = Cooldown() }
    function btn.cd:SetCooldownFromDurationObject(d) self.calls[#self.calls + 1] = d == length and "object" or "other" end
    update(btn)
    H.assertEq(table.concat(btn.cd.calls, ","), "object")
    H.assertEq(asked[1], 3567)
    H.assertTrue(asked[2] == true, "the global cooldown left out, as before")
end

function tests.aPlainCooldown_isDrawn_aShortOneIsNot()
    local now = { 100, 30 }
    local update = UpdateCooldown({
        issecretvalue = secret,
        C_Container = { GetItemCooldown = function() return now[1], now[2] end },
    })
    local btn = { itemID = 6948, cd = Cooldown() }
    update(btn)
    now = { 100, 1 }
    update(btn)
    H.assertEq(table.concat(btn.cd.calls, ","), "set 100 30,clear")
end

-- Every function of ours that draws a swipe asks issecretvalue first.
function tests.everySwipe_asksIssecretvalue()
    local bad = {}
    local p = io.popen('cd "' .. H.Path("") .. '" && ls *.lua')
    for rel in p:lines() do
        if not rel:match("^Walk_") and not rel:match("^Data") and not rel:match("^Floors_") then
            local f = assert(io.open(H.Path(rel), "rb"))
            local src = f:read("*a")
            f:close()
            local at = 1
            while true do
                local s = src:find(":SetCooldown(", at, true)
                if not s then break end
                local head = src:sub(1, s)
                local fn = 1
                for q in head:gmatch("()function[%s%w_.:]*%(") do fn = q end
                if not src:sub(fn, s):find("issecretvalue", 1, true) then
                    bad[#bad + 1] = rel .. ":" .. (select(2, head:gsub("\n", "")) + 1)
                end
                at = s + 1
            end
        end
    end
    p:close()
    H.assertEq(table.concat(bad, ", "), "", "a swipe drawn without asking issecretvalue")
end

local pass, fail, failures = H.runSuite("GPSCastCooldown", tests)
return { pass = pass, fail = fail, failures = failures }
