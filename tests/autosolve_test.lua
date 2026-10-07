-- Unit tests for autosolve.lua. Run from repo root: lua tests/autosolve_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local autosolve = require("autosolve")
local solver = require("solver")
local tracker = require("tracker")
local lockdb = require("lockdb")
local t = require("testlib")
local test, eq, str = t.test, t.eq, t.str

local OPTS = { ws_gap_ms = 60, timeout_ms = 2500, max_replans = 3 }

-- A tracker view; every call makes a new keys table, as a tracker replan does.
local function view(keys, index, status)
    return { status = status or "ok", keys = keys, index = index or 1 }
end

test("off by default: no key", function()
    local a = autosolve.new(OPTS)
    eq(a.state, "off", "state")
    eq(a:step(view({ "A" }), 0, 0), nil, "key")
end)

test("F3 while tracking runs and presses the hint's current key", function()
    local a = autosolve.new(OPTS)
    eq(a:toggle(true), "running", "state")
    eq(a:step(view({ "W", "A" }, 2), 0, 0), "A", "the current key")
end)

test("F3 before the minigame is ready arms; the tracker starts it", function()
    local a = autosolve.new(OPTS)
    eq(a:toggle(false), "armed", "state")
    eq(a:step(nil, 0, 0), nil, "no tracker: nothing")
    eq(a.state, "armed", "still armed")
    eq(a:step(view({ "D" }), 0, 100), "D", "first key once the tracker exists")
    eq(a.state, "running", "running")
end)

test("F3 again stops it, armed or running", function()
    local a = autosolve.new(OPTS)
    a:toggle(false)
    eq(a:toggle(false), "off", "armed -> off")
    a:toggle(true)
    eq(a:toggle(true), "off", "running -> off")
    eq(a:step(view({ "D" }), 0, 0), nil, "no key when off")
end)

test("arm starts from off only", function()
    local a = autosolve.new(OPTS)
    a:arm()
    eq(a.state, "armed", "armed")
    a:toggle(true) -- armed -> off
    a:toggle(true) -- off -> running
    a:arm()
    eq(a.state, "running", "arm does not demote a running autosolver")
end)

test("after a W/S it waits ws_gap_ms", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    local keys = { "W", "W", "A" }
    local v = { status = "ok", keys = keys, index = 1 }
    eq(a:step(v, 0, 1000), "W", "first")
    v.index = 2
    eq(a:step(v, 0, 1030), nil, "within the pause")
    eq(a:step(v, 0, 1060), "W", "after the pause")
end)

test("after an A/D it waits until the plates confirm it", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    local v = { status = "ok", keys = { "A", "W" }, index = 1 }
    eq(a:step(v, 0, 0), "A", "A")
    v.index = 2
    eq(a:step(v, 1, 100), nil, "unconfirmed")
    eq(a:step(v, 1, 2000), nil, "still unconfirmed, before the timeout")
    eq(a:step(v, 0, 2050), "W", "confirmed: the next key at once")
end)

test("it never presses while a move is unconfirmed, even one it did not make", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    local v = view({ "A" })
    eq(a:step(v, 1, 0), nil, "the player's move is still animating")
    eq(a:step(v, 0, 300), "A", "then the key")
end)

test("an A/D unconfirmed for timeout_ms stops it", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    local v = { status = "ok", keys = { "A", "W" }, index = 1 }
    a:step(v, 0, 0)
    v.index = 2
    local key, reason = a:step(v, 1, 2501)
    eq(key, nil, "key")
    eq(reason, "timeout", "reason")
    eq(a.state, "off", "state")
end)

test("a move it did not make that never shows also stops it after timeout_ms", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    local v = view({ "A" })
    eq(a:step(v, 1, 0), nil, "waits")
    local key, reason = a:step(v, 1, 2501)
    eq(key, nil, "key")
    eq(reason, "timeout", "reason")
end)

test("max_replans replans in a row stop it", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    eq(a:step(view({ "A" }), 0, 0), "A", "first plan")
    eq(a:step(view({ "A" }), 0, 400), "A", "replan 1")
    eq(a:step(view({ "A" }), 0, 800), "A", "replan 2")
    local key, reason = a:step(view({ "A" }), 0, 1200)
    eq(key, nil, "key")
    eq(reason, "replans", "reason after replan 3")
end)

test("a move confirmed as planned resets the replan count", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    a:step(view({ "A" }), 0, 0)
    local plan = { status = "ok", keys = { "A", "D" }, index = 1 }
    eq(a:step(plan, 0, 400), "A", "replan 1")
    plan.index = 2
    eq(a:step(plan, 0, 800), "D", "the A was confirmed as planned")
    eq(a:step(view({ "A" }), 0, 1200), "A", "replan 1 again")
    eq(a:step(view({ "A" }), 0, 1600), "A", "replan 2: still running")
    eq(a.state, "running", "state")
end)

test("a solved lock stops it; no hint stops it with the tracker's status", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    local key, reason = a:step(view({}, 1, "solved"), 0, 0)
    eq(key, nil, "key")
    eq(reason, "solved", "solved")
    for _, status in ipairs({ "no_safe_path", "bad_state" }) do
        a:toggle(true)
        key, reason = a:step(view({}, 1, status), 0, 0)
        eq(reason, status, status)
        eq(a.state, "off", "state after " .. status)
    end
end)

test("a player press stops it", function()
    local a = autosolve.new(OPTS)
    eq(a:player_pressed(), false, "off: nothing to stop")
    a:toggle(true)
    eq(a:player_pressed(), true, "running: stopped")
    eq(a.state, "off", "state")
    a:arm()
    eq(a:player_pressed(), true, "armed: stopped")
end)

test("nothing to press after the last key", function()
    local a = autosolve.new(OPTS)
    a:toggle(true)
    eq(a:step(view({ "A" }, 2), 0, 0), nil, "key")
    eq(a.state, "running", "still running until the plates show the open lock")
end)

local DB = lockdb.new(dofile("mod/G1LockPickHelper/Scripts/lockgraphs.lua"))
local DIGGER = solver.prepare((DB.find("OC_Chest_Digger526_Lock")))
local DIGGER_START = { 7, 7, 6, 4, 7 }

-- Drives a real tracker with the autosolver against a fake minigame: an A/D shows on the plates 300 ms after
-- the press, the plates are read every 50 ms. opts.swallow(n, key) -> true: the game ignores the n-th press;
-- opts.blind: the plates are never read. Returns the stop reason, the game, the presses and the time.
local function drive(ctx, start, opts)
    opts = opts or {}
    local tr = tracker.new(ctx, start, { grace_ms = 1200 })
    local a = autosolve.new(OPTS)
    a:toggle(true)
    local game = { pos = { table.unpack(start) }, cursor = 1, strains = 0 }
    local shown, shown_at = game.pos, 0
    local presses = {}
    for now = 0, 120000, 10 do
        if now >= shown_at then shown = game.pos end
        if now % 50 == 0 and not opts.blind then tr:observe(shown, now) end
        local key, reason = a:step(tr:view(), tr:pending(), now)
        if reason then return reason, game, presses, now end
        if key then
            presses[#presses + 1] = key
            if not (opts.swallow and opts.swallow(#presses, key)) then
                local p, c = solver.apply(ctx, game.pos, game.cursor, key)
                if p then
                    if key == "A" or key == "D" then shown_at = now + 300 end
                    game.pos, game.cursor = p, c
                else
                    game.strains = game.strains + 1
                end
            end
            tr:key(key, now)
        end
    end
    return "running", game, presses
end

test("it opens a lock without strain, pressing exactly the hint", function()
    local reason, game, presses = drive(DIGGER, DIGGER_START)
    eq(reason, "solved", "reason")
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(game.strains, 0, "strains")
    eq(str(presses), str(solver.solve(DIGGER, DIGGER_START, 1)), "presses")
end)

test("a swallowed A/D is redone after the tracker gives up on it", function()
    local swallowed = false
    local reason, game = drive(DIGGER, DIGGER_START, { swallow = function(_, key)
        if (key == "A" or key == "D") and not swallowed then
            swallowed = true
            return true
        end
    end })
    eq(swallowed, true, "one A/D swallowed")
    eq(reason, "solved", "reason")
    eq(game.strains, 0, "strains")
end)

test("A/D the game keeps swallowing stop it after max_replans", function()
    local reason, game = drive(DIGGER, DIGGER_START, { swallow = function() return true end })
    eq(reason, "replans", "reason")
    eq(str(game.pos), str(DIGGER_START), "nothing moved")
end)

test("plates that are never read stop it after timeout_ms", function()
    local reason, _, presses = drive(DIGGER, DIGGER_START, { blind = true })
    eq(reason, "timeout", "reason")
    local last = presses[#presses]
    eq(last == "A" or last == "D", true, "the last press is the unconfirmed A/D")
end)

t.finish()
