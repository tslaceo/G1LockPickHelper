-- Unit tests for tracker.lua. Run from repo root: lua tests/tracker_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local solver = require("solver")
local tracker = require("tracker")
local t = require("testlib")
local test, eq, str = t.test, t.eq, t.str

local db = dofile("mod/G1LockPickHelper/Scripts/lockgraphs.lua")
local DIGGER = solver.prepare((require("lockdb").new(db).find("OC_Chest_Digger526_Lock")))
local DIGGER_START = { 7, 7, 6, 4, 7 }
local FREE3 = solver.prepare({ plates = 3, links = {} })

-- Fake minigame: applies presses the way the game does (S/W clamp, strained moves change nothing).
local function new_game(ctx, positions, cursor)
    local game = { ctx = ctx, pos = { table.unpack(positions) }, cursor = cursor or 1, strains = 0 }
    function game.press(key)
        local p, c = solver.apply(ctx, game.pos, game.cursor, key)
        if p then
            game.pos, game.cursor = p, c
        else
            game.strains = game.strains + 1
        end
        return p ~= nil
    end
    return game
end

local function moves_key(key)
    return key == "A" or key == "D"
end

-- Presses the hinted keys until the hint is exhausted; the game reports settled plates after every A/D.
local function follow(tr, game, now)
    local guard = 0
    while true do
        local v = tr:view()
        if v.status ~= "ok" or v.index > #v.keys then return now end
        local key = v.keys[v.index]
        game.press(key)
        tr:key(key, now)
        now = now + 300
        if moves_key(key) then
            tr:observe(game.pos, now)
            now = now + 300
        end
        guard = guard + 1
        if guard > 500 then error("hint never ends") end
    end
end

test("first hint is the solver's answer from plate 1", function()
    local tr = tracker.new(DIGGER, DIGGER_START)
    local v = tr:view()
    eq(v.status, "ok", "status")
    eq(v.index, 1, "index")
    eq(str(v.keys), str(solver.solve(DIGGER, DIGGER_START, 1)), "keys")
end)

test("following the hint opens the lock without strain", function()
    local tr, game = tracker.new(DIGGER, DIGGER_START), new_game(DIGGER, DIGGER_START)
    follow(tr, game, 0)
    eq(game.strains, 0, "strains")
    eq(tr:view().status, "solved", "status")
end)

test("solved only once the game shows every plate at 4", function()
    local tr, game = tracker.new(FREE3, { 3, 5, 4 }), new_game(FREE3, { 3, 5, 4 })
    local keys = tr:view().keys
    for _, key in ipairs(keys) do
        game.press(key)
        tr:key(key, 0)
    end
    eq(tr:view().status, "ok", "status before the game confirms")
    eq(tr:view().index, #keys + 1, "index")
    tr:observe(game.pos, 100)
    eq(tr:view().status, "solved", "status after")
end)

test("wrong W replans from the next plate", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    eq(str(tr:view().keys), "D W A", "first hint")
    tr:key("W", 0)
    local v = tr:view()
    eq(v.index, 1, "index")
    eq(str(v.keys), str(solver.solve(FREE3, { 3, 5, 4 }, 2)), "keys")
end)

test("wrong A/D replans from the moved plates", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("A", 0)
    eq(str(tr:view().keys), str(solver.solve(FREE3, { 2, 5, 4 }, 1)), "keys")
    tr:observe({ 2, 5, 4 }, 400)
    eq(str(tr:view().keys), str(solver.solve(FREE3, { 2, 5, 4 }, 1)), "keys after the game confirms")
end)

test("old positions within the grace period are not a mismatch", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("D", 1000)
    tr:observe({ 3, 5, 4 }, 1100)
    local v = tr:view()
    eq(str(v.keys), "D W A", "keys")
    eq(v.index, 2, "index")
end)

test("a press the game swallowed is taken back after the grace period", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("D", 1000)
    tr:observe({ 3, 5, 4 }, 2300)
    local v = tr:view()
    eq(str(v.keys), "S S D W A", "keys (the cursor is forgotten: parked first)")
    eq(v.index, 1, "index")
end)

test("cursor desync is resolved from the plate that moved", function()
    local game = new_game(FREE3, { 3, 5, 4 })
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("W", 0) -- the game swallowed this W: it still has the cursor on plate 1
    eq(str(tr:view().keys), "A S D", "hint for the wrong cursor")
    game.press("A")
    tr:key("A", 300)
    tr:observe(game.pos, 600)
    local v = tr:view()
    eq(str(v.keys), str(solver.solve(FREE3, { 2, 5, 4 }, 1)), "keys from the real cursor")
    follow(tr, game, 900)
    eq(tr:view().status, "solved", "status")
end)

test("W/S pressed after the mismatched move are replayed onto the found cursor", function()
    local game = new_game(FREE3, { 3, 5, 4 })
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("W", 0) -- swallowed
    game.press("A")
    tr:key("A", 300)
    game.press("W")
    tr:key("W", 500)
    tr:observe(game.pos, 900)
    eq(str(tr:view().keys), str(solver.solve(FREE3, { 2, 5, 4 }, 2)), "keys from plate 2")
    follow(tr, game, 1200)
    eq(tr:view().status, "solved", "status")
end)

test("a change no single move explains parks the cursor", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("D", 0)
    tr:observe({ 3, 4, 5 }, 400)
    eq(str(tr:view().keys), "S S " .. str(solver.solve(FREE3, { 3, 4, 5 }, 1)), "keys")
end)

test("back at the start positions parks the cursor (pick broke or R)", function()
    local game = new_game(DIGGER, DIGGER_START)
    local tr = tracker.new(DIGGER, DIGGER_START)
    local keys, i, now = tr:view().keys, 1, 0
    repeat -- follow the hint through its first move and let the game confirm it
        game.press(keys[i])
        tr:key(keys[i], now)
        now = now + 300
        i = i + 1
    until moves_key(keys[i - 1])
    tr:observe(game.pos, now)
    while not moves_key(keys[i]) do tr:key(keys[i], now); i = i + 1 end
    tr:key(keys[i], now)              -- say the pick broke on this move:
    tr:observe(DIGGER_START, now + 1500) -- the lock is back at the start, cursor on plate 1
    eq(str(tr:view().keys), "S S S S " .. str(solver.solve(DIGGER, DIGGER_START, 1)), "keys")
end)

test("a strained move parks the cursor", function()
    local tr = tracker.new(FREE3, { 1, 5, 4 })
    tr:key("A", 0)
    eq(str(tr:view().keys), "S S " .. str(solver.solve(FREE3, { 1, 5, 4 }, 1)), "keys")
end)

test("unknown cursor at the start parks it first", function()
    local tr = tracker.new(DIGGER, DIGGER_START, { cursor_known = false })
    eq(str(tr:view().keys), "S S S S " .. str(solver.solve(DIGGER, DIGGER_START, 1)), "keys")
    local game = new_game(DIGGER, DIGGER_START, 3)
    follow(tr, game, 0)
    eq(game.strains, 0, "strains")
    eq(tr:view().status, "solved", "status")
end)

test("R parks the cursor", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("R", 0)
    eq(str(tr:view().keys), "S S " .. str(solver.solve(FREE3, { 3, 5, 4 }, 1)), "keys")
end)

test("fast presses: an intermediate reading keeps the hint", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    local keys = tr:view().keys
    tr:key("D", 0)
    tr:key("W", 100)
    tr:key("A", 200)
    tr:observe({ 4, 5, 4 }, 700) -- the game finished D, A still animating
    local v = tr:view()
    eq(v.keys, keys, "same hint")
    eq(v.index, 4, "index")
    tr:observe({ 4, 4, 4 }, 1200)
    eq(tr:view().status, "solved", "status")
end)

test("random detours: hinted presses never strain", function()
    math.randomseed(7)
    for _ = 1, 200 do
        local start
        repeat
            start = {}
            for i = 1, 5 do start[i] = math.random(1, 7) end
        until solver.solve(DIGGER, start, 1)
        local tr, game = tracker.new(DIGGER, start), new_game(DIGGER, start)
        local now, presses = 0, 0
        while tr:view().status == "ok" do
            local v = tr:view()
            local key, hinted = v.keys[v.index], true
            if key == nil or math.random() < 0.2 then
                key, hinted = ({ "W", "S", "A", "D" })[math.random(1, 4)], false
            end
            local moved = game.press(key)
            if hinted and moves_key(key) and not moved then
                error("hinted " .. key .. " strained from " .. str(start))
            end
            tr:key(key, now)
            now = now + 300
            tr:observe(game.pos, now)
            now = now + 300
            presses = presses + 1
            if presses > 2000 then error("not solved from " .. str(start)) end
        end
        eq(tr:view().status, "solved", "status")
    end
end)

test("an all-4 reading is solved even off the expected path", function()
    local tr = tracker.new(FREE3, { 4, 5, 4 }, { cursor_known = false })
    tr:key("A", 0)
    tr:observe({ 4, 4, 4 }, 400)
    eq(tr:view().status, "solved", "status")
end)

test("R after progress plans from the start positions", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("D", 0)
    tr:observe({ 4, 5, 4 }, 400)
    tr:key("R", 500)
    local v = tr:view()
    eq(str(v.keys), "S S " .. str(solver.solve(FREE3, { 3, 5, 4 }, 1)), "keys")
end)

-- A key the hint does not show right now (W/S never strain a lock).
local function wrong_key(tr)
    local v = tr:view()
    return v.keys[v.index] == "W" and "S" or "W"
end

test("history keeps hinted presses: ok, misses and the press count", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    local first = tr:view().keys[1]
    tr:key(first, 0)
    tr:key(wrong_key(tr), 100)
    local v = tr:view()
    eq(#v.history, 2, "history")
    eq(v.history[1].key, first, "first key")
    eq(v.history[1].ok, true, "first ok")
    eq(v.history[2].ok, false, "second is a miss")
    eq(v.misses, 1, "misses")
    eq(v.pressed, 2, "pressed")
end)

test("R clears the history; misses and presses stay counted", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key(wrong_key(tr), 0)
    tr:key("R", 100)
    local v = tr:view()
    eq(#v.history, 0, "history cleared")
    eq(v.misses, 1, "misses kept")
    eq(v.pressed, 1, "presses kept")
end)

test("a resync from the game's readings is not a miss", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    eq(tr:view().keys[1], "D", "hint starts with D on plate 1")
    tr:key("D", 0)
    tr:observe({ 3, 6, 4 }, 400) -- the game moved plate 2: the cursor was elsewhere
    local v = tr:view()
    eq(v.misses, 0, "misses")
    eq(#v.history, 1, "history unchanged")
end)

test("a press the game swallowed is not a miss", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key(tr:view().keys[1], 0)
    tr:observe({ 3, 5, 4 }, 2000) -- grace passed, the plates never moved
    eq(tr:view().misses, 0, "misses")
end)

test("no history while there is no hint", function()
    local tr = tracker.new(FREE3, { 9, 4, 4 })
    eq(tr:view().status, "bad_state", "status")
    tr:key("W", 0)
    eq(#tr:view().history, 0, "history")
    eq(tr:view().misses, 0, "misses")
end)

test("history keeps the last 512 presses", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    for i = 1, 600 do tr:key(wrong_key(tr), i) end
    eq(#tr:view().history, 512, "history")
    eq(tr:view().pressed, 600, "pressed")
end)

test("pending counts the A/D the game has not shown yet", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    eq(tr:pending(), 0, "at the start")
    tr:key("W", 0)
    eq(tr:pending(), 0, "W/S do not wait for the plates")
    tr:key("D", 100)
    eq(tr:pending(), 1, "after D")
    tr:observe({ 3, 5, 4 }, 200)
    eq(tr:pending(), 1, "old positions within the grace period")
    tr:observe({ 3, 6, 4 }, 500)
    eq(tr:pending(), 0, "confirmed")
end)

test("pending: the game confirms the first of two moves", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("D", 0)
    tr:key("D", 100)
    eq(tr:pending(), 2, "two moves")
    tr:observe({ 4, 5, 4 }, 400)
    eq(tr:pending(), 1, "one left")
    tr:observe({ 5, 5, 4 }, 700)
    eq(tr:pending(), 0, "both shown")
end)

test("pending: a move the game swallowed is dropped after the grace period", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("D", 1000)
    tr:observe({ 3, 5, 4 }, 2300)
    eq(tr:pending(), 0, "taken back")
end)

test("pending: a mismatched move is dropped by the resync", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("D", 0)
    tr:observe({ 3, 6, 4 }, 400) -- the game moved plate 2: the cursor was not on plate 1
    eq(tr:pending(), 0, "resynced")
end)

test("pending is 0 once the lock is solved", function()
    local tr = tracker.new(FREE3, { 3, 4, 4 })
    tr:key("D", 0)
    eq(tr:pending(), 1, "before the plates show it")
    tr:observe({ 4, 4, 4 }, 300)
    eq(tr:view().status, "solved", "solved")
    eq(tr:pending(), 0, "nothing left to wait for")
end)

test("pending counts an R until the plates show the start again", function()
    local tr = tracker.new(FREE3, { 3, 5, 4 })
    tr:key("D", 0)
    tr:observe({ 4, 5, 4 }, 400)
    tr:key("R", 500)
    eq(tr:pending(), 1, "R in flight")
    tr:observe({ 3, 5, 4 }, 900)
    eq(tr:pending(), 0, "back at the start")
end)

t.finish()
