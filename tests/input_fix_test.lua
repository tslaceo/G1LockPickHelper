-- Unit tests for input_fix.lua. Run from repo root: lua tests/input_fix_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local input_fix = require("input_fix")
local t = require("testlib")
local test, eq = t.test, t.eq

local OPTS = { settle_ms = 200, settle_frames = 5, window_ms = 10000 }
local FRAME = 10

-- Frames from `from` to `to` (ms, every FRAME) with the cursor `visible`; the times frame() said true.
local function frames(fix, from, to, visible)
    local fired = {}
    for now = from, to, FRAME do
        if fix:frame(now, visible) then fired[#fired + 1] = now end
    end
    return fired
end

test("nothing happens without a closed minigame", function()
    local fix = input_fix.new(OPTS)
    eq(fix:waiting(), false, "not waiting")
    eq(#frames(fix, 0, 1000, false), 0, "no fix")
end)

test("a cursor hidden at once: true once, settle_ms after the first hidden frame", function()
    local fix = input_fix.new(OPTS)
    fix:ended(1000)
    eq(fix:waiting(), true, "waiting")
    local fired = frames(fix, 1010, 3000, false)
    eq(#fired, 1, "once")
    eq(fired[1], 1210, "200 ms after the first hidden frame")
    eq(fix:waiting(), false, "done")
end)

test("slow frames: it also waits for settle_frames frames", function()
    local fix = input_fix.new(OPTS)
    fix:ended(0)
    eq(fix:frame(100, false), false, "frame 1")
    eq(fix:frame(400, false), false, "frame 2: 300 ms, 2 frames")
    eq(fix:frame(700, false), false, "frame 3")
    eq(fix:frame(1000, false), false, "frame 4")
    eq(fix:frame(1300, false), true, "frame 5")
end)

test("the game hides the cursor late (a low frame rate): the fix waits for it", function()
    local fix = input_fix.new(OPTS)
    fix:ended(0)
    eq(#frames(fix, 10, 2900, true), 0, "cursor shown")
    eq(frames(fix, 2910, 4000, false)[1], 3110, "200 ms after it hid")
end)

test("a cursor shown again restarts the count", function()
    local fix = input_fix.new(OPTS)
    fix:ended(0)
    eq(#frames(fix, 10, 150, false), 0, "hidden 140 ms")
    eq(fix:frame(160, true), false, "shown")
    eq(frames(fix, 170, 1000, false)[1], 370, "200 ms from the new start")
end)

test("an unreadable cursor counts as shown", function()
    local fix = input_fix.new(OPTS)
    fix:ended(0)
    eq(#frames(fix, 10, 150, false), 0, "hidden 140 ms")
    eq(fix:frame(160, nil), false, "unreadable")
    eq(frames(fix, 170, 1000, false)[1], 370, "the count restarted")
end)

test("a cursor shown the whole window (a chest window): nothing, not even after it hides", function()
    local fix = input_fix.new(OPTS)
    fix:ended(0)
    eq(#frames(fix, 10, 10000, true), 0, "shown 10 s")
    eq(#frames(fix, 10010, 12000, false), 0, "hidden after the window")
    eq(fix:waiting(), false, "gave up")
end)

test("a new minigame cancels the wait; its close starts a new one", function()
    local fix = input_fix.new(OPTS)
    fix:ended(0)
    fix:cancel()
    eq(fix:waiting(), false, "cancelled")
    eq(#frames(fix, 10, 1000, false), 0, "no fix")
    fix:ended(2000)
    eq(frames(fix, 2010, 3000, false)[1], 2210, "after the next close")
end)

t.finish()
