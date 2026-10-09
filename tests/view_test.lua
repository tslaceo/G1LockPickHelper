-- Unit tests for view.lua. Run from repo root: lua tests/view_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local view = require("view")
local t = require("testlib")
local test, eq = t.test, t.eq

-- "D+ A- W+" -> history { {D, ok}, {A, miss}, {W, ok} }
local function H(spec)
    local out = {}
    for key, mark in (spec or ""):gmatch("(%a)([+-])") do out[#out + 1] = { key = key, ok = mark == "+" } end
    return out
end

-- Tracker view: keys as a string ("WSAD"), current index, history spec.
local function V(keys, index, history)
    local list = {}
    for k in keys:gmatch("%a") do list[#list + 1] = k end
    return { keys = list, index = index, history = H(history), pressed = 0, misses = 0 }
end

local function cells(m)
    local out = {}
    for i, c in ipairs(m.cells) do out[i] = (c.text ~= "" and c.text or "_") .. ":" .. c.role end
    return table.concat(out, " ")
end

local MARK = { done = "+", miss = "-", current = "*", todo = "" }
local function lines(m)
    local out = {}
    for _, line in ipairs(m.lines) do
        local l = {}
        for _, tok in ipairs(line) do l[#l + 1] = tok.text .. MARK[tok.role] end
        out[#out + 1] = table.concat(l, " ")
    end
    return table.concat(out, " / ")
end

local function a3(x) return string.format("%.3f", x) end
local TAPE = { next = 5, done = 3 }
local RUNS = { per_line = 16, max_lines = 6, collapse_min = 3 }
local FLAT = { per_line = 16, max_lines = 6, collapse_min = 0 }

test("tape: last presses, the current key, the next keys", function()
    local m = view.tape(V("WSADDAWSA", 3, "D+ A- W+ S+"), TAPE)
    eq(m.kind, "tape", "kind")
    eq(cells(m), "A:miss W:done S:done A:current D:next D:next A:next W:next S:next", "cells")
    eq(a3(m.cells[1].alpha), "0.280", "furthest done")
    eq(a3(m.cells[3].alpha), "0.750", "nearest done")
    eq(m.cells[4].alpha, 1, "current")
    eq(a3(m.cells[5].alpha), "0.850", "first next")
    eq(a3(m.cells[7].alpha), "0.500", "middle next")
    eq(a3(m.cells[9].alpha), "0.150", "last next")
    eq(m.counter, "2/9", "counter")
end)

test("tape: missing history and plan leave empty cells; the current key keeps its place", function()
    eq(cells(view.tape(V("WS", 1), TAPE)), "_:empty _:empty _:empty W:current S:next _:empty _:empty _:empty _:empty", "cells")
end)

test("tape: one next and one done key use the first alphas; done = 0 starts at the current key", function()
    local m = view.tape(V("WSA", 2, "W+"), { next = 1, done = 1 })
    eq(cells(m), "W:done S:current A:next", "cells")
    eq(a3(m.cells[1].alpha), "0.750", "done alpha")
    eq(a3(m.cells[3].alpha), "0.850", "next alpha")
    eq(cells(view.tape(V("WSA", 1), { next = 2, done = 0 })), "W:current S:next A:next", "no done cells")
end)

test("tape: after the last key the current cell is empty", function()
    local m = view.tape(V("WS", 3, "W+ S+"), { next = 2, done = 2 })
    eq(cells(m), "W:done S:done _:empty _:empty _:empty", "cells")
    eq(m.counter, "2/2", "counter")
end)

test("labels replace key names", function()
    local m = view.tape(V("WS", 1), { next = 1, done = 0, labels = { W = "UP", S = "DOWN" } })
    eq(cells(m), "UP:current DOWN:next", "cells")
    local l = view.lines(V("WS", 1), { per_line = 4, max_lines = 1, collapse_min = 0, labels = { W = "UP", S = "DOWN" } })
    eq(lines(l), "UP* DOWN", "lines")
end)

test("press and miss counts pass through", function()
    local v = V("W", 1)
    v.pressed, v.misses = 7, 2
    local m = view.tape(v, TAPE)
    eq(m.pressed, 7, "tape pressed")
    eq(m.misses, 2, "tape misses")
    m = view.lines(v, FLAT)
    eq(m.pressed, 7, "lines pressed")
    eq(m.misses, 2, "lines misses")
end)

test("lines: history then the rest of the plan", function()
    local m = view.lines(V("WSADD", 3, "D+ A- W+ S+"), FLAT)
    eq(lines(m), "D+ A- W+ S+ A* D D", "tokens")
    eq(m.counter, "2/5", "counter")
end)

test("lines: the window follows the current line", function()
    local m = view.lines(V(string.rep("W", 20), 14, string.rep("W+ ", 13)), { per_line = 4, max_lines = 2, collapse_min = 0 })
    eq(lines(m), "W+ W+ W+ W+ / W+ W* W W", "lines 3 and 4 of 5")
    m = view.lines(V(string.rep("W", 20), 2, "W+"), { per_line = 4, max_lines = 2, collapse_min = 0 })
    eq(lines(m), "W+ W* W W / W W W W", "lines 1 and 2")
end)

test("lines: a run counts down while it is pressed", function()
    local keys = "DAAAAAW"
    eq(lines(view.lines(V(keys, 1), RUNS)), "D* A×5 W", "start")
    eq(lines(view.lines(V(keys, 2, "D+"), RUNS)), "D+ A×5* W", "after D")
    eq(lines(view.lines(V(keys, 3, "D+ A+"), RUNS)), "D+ A×4* W", "after one A")
    eq(lines(view.lines(V(keys, 6, "D+ A+ A+ A+ A+"), RUNS)), "D+ A×1* W", "one left")
    eq(lines(view.lines(V(keys, 7, "D+ A+ A+ A+ A+ A+"), RUNS)), "D+ A×5+ W*", "run done")
end)

test("lines: runs shorter than collapse_min stay single keys; 0 and 1 turn runs off", function()
    eq(lines(view.lines(V("DAAW", 1), RUNS)), "D* A A W", "two A")
    eq(lines(view.lines(V("DAAAW", 1), { per_line = 16, max_lines = 6, collapse_min = 1 })), "D* A A A W", "collapse_min 1")
    eq(lines(view.lines(V("DAAAW", 1), FLAT)), "D* A A A W", "collapse_min 0")
end)

test("lines: a miss splits a run", function()
    eq(lines(view.lines(V("AAAW", 1, "A+ A+ D-"), RUNS)), "A+ A+ D- A×3* W", "short pressed part")
    eq(lines(view.lines(V("AAW", 1, "A+ A+ A+ D-"), RUNS)), "A×3+ D- A* A W", "long pressed part")
end)

test("the menu's example renders in both layouts", function()
    local m = view.tape(view.SAMPLE, TAPE)
    eq(m.cells[4].text, "A", "current")
    eq(m.misses, 1, "misses")
    local l = view.lines(view.SAMPLE, RUNS)
    eq(lines(l):find("A×3*", 1, true) ~= nil, true, "run in progress")
    eq(l.counter, "2/20", "counter")
end)

test("tape cells carry the model key; empty cells have none", function()
    local labels = { W = "UP", S = "DN", A = "LT", D = "RT" }
    local m = view.tape(V("WSADDAWSA", 3, "D+ A- W+ S+"), { next = 5, done = 3, labels = labels })
    local keys = {}
    for i, c in ipairs(m.cells) do keys[i] = c.key or "_" end
    eq(table.concat(keys, " "), "A W S A D D A W S", "keys")
    eq(m.cells[4].text, "LT", "the text is still the label")
    local e = view.tape(V("WS", 1), TAPE)
    eq(e.cells[1].key, nil, "empty done cell")
    eq(e.cells[6].key, nil, "empty next cell")
end)

test("lines tokens carry the key and, for a run, its count", function()
    local function kc(m)
        local out = {}
        for _, tok in ipairs(m.lines[1]) do out[#out + 1] = tok.key .. ":" .. tostring(tok.count) end
        return table.concat(out, " ")
    end
    eq(kc(view.lines(V("DAAAAAW", 2, "D+"), RUNS)), "D:nil A:5 W:nil", "a run in the plan")
    eq(kc(view.lines(V("DAAAAAW", 4, "D+ A+ A+"), RUNS)), "D:nil A:3 W:nil", "the current run counts down")
    eq(kc(view.lines(V("DAAAAAW", 2, "D+"), FLAT)), "D:nil A:nil A:nil A:nil A:nil A:nil W:nil", "no folding")
    eq(kc(view.lines(V("WWWWD", 5, "W+ W+ W+ W+"), RUNS)), "W:4 D:nil", "a pressed run")
end)

t.finish()
