-- Unit tests for solver.lua. Run from repo root: lua tests/solver_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;" .. package.path
local solver = require("solver")

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function str(keys)
    return keys and table.concat(keys, " ") or "nil"
end

local function count_moves(keys)
    local n = 0
    for _, k in ipairs(keys) do
        if k == "A" or k == "D" then n = n + 1 end
    end
    return n
end

-- Applies keys one by one; fails on any strain or if the lock is not solved at the end.
local function replay(ctx, positions, cursor, keys)
    for i, k in ipairs(keys) do
        local p, c = solver.apply(ctx, positions, cursor, k)
        if not p then error("strain at step " .. i .. " (" .. k .. ")", 2) end
        positions, cursor = p, c
    end
    for i, v in ipairs(positions) do
        if v ~= 4 then error("plate " .. i .. " ended at " .. v, 2) end
    end
end

-- Independent reference: plain BFS over positions with string keys.
local function naive_distance(graph, start)
    local n = graph.plates
    local function key(p) return table.concat(p, ",") end
    local goal = string.rep("4,", n - 1) .. "4"
    local seen = { [key(start)] = 0 }
    local queue, head = { start }, 1
    while queue[head] do
        local cur = queue[head]
        head = head + 1
        local d = seen[key(cur)]
        if key(cur) == goal then return d end
        for i = 1, n do
            for _, dir in ipairs({ -1, 1 }) do
                local nxt = { table.unpack(cur) }
                nxt[i] = nxt[i] + dir
                for _, l in ipairs(graph.links[i] or {}) do
                    nxt[l[1]] = nxt[l[1]] + dir * l[2]
                end
                local ok = true
                for j = 1, n do
                    if nxt[j] < 1 or nxt[j] > 7 then ok = false end
                end
                if ok and seen[key(nxt)] == nil then
                    seen[key(nxt)] = d + 1
                    queue[#queue + 1] = nxt
                end
            end
        end
    end
    return nil
end

local function random_graph(n)
    local links = {}
    for src = 1, n do
        for dst = 1, n do
            if src ~= dst and math.random() < 0.3 then
                links[src] = links[src] or {}
                table.insert(links[src], { dst, math.random() < 0.5 and 1 or -1 })
            end
        end
    end
    return { plates = n, links = links }
end

test("already solved lock needs no keys", function()
    local ctx = solver.prepare({ plates = 3, links = {} })
    eq(str(solver.solve(ctx, { 4, 4, 4 }, 1)), "", "keys")
end)

test("single plate moves right", function()
    local ctx = solver.prepare({ plates = 1, links = {} })
    eq(str(solver.solve(ctx, { 2 }, 1)), "D D", "keys")
end)

test("cursor travels back to the plate", function()
    local ctx = solver.prepare({ plates = 3, links = {} })
    eq(str(solver.solve(ctx, { 4, 4, 5 }, 1)), "W W A", "keys")
end)

test("with-link moves both plates", function()
    local ctx = solver.prepare({ plates = 2, links = { [1] = { { 2, 1 } } } })
    eq(str(solver.solve(ctx, { 3, 3 }, 1)), "D", "keys")
end)

test("against-link moves plates oppositely", function()
    local ctx = solver.prepare({ plates = 2, links = { [1] = { { 2, -1 } } } })
    eq(str(solver.solve(ctx, { 3, 5 }, 1)), "D", "keys")
end)

test("links are directional", function()
    local ctx = solver.prepare({ plates = 2, links = { [1] = { { 2, 1 } } } })
    eq(str(solver.solve(ctx, { 4, 3 }, 1)), "W D", "keys")
end)

test("never pushes a linked plate past the edge", function()
    local ctx = solver.prepare({ plates = 2, links = { [1] = { { 2, 1 } } } })
    local keys = solver.solve(ctx, { 3, 7 }, 1)
    eq(str(keys), "W A A A A S D", "keys")
    replay(ctx, { 3, 7 }, 1, keys)
end)

test("reports no safe path", function()
    local ctx = solver.prepare({ plates = 2, links = { [1] = { { 2, 1 } }, [2] = { { 1, 1 } } } })
    local keys, reason = solver.solve(ctx, { 3, 5 }, 1)
    eq(keys, nil, "keys")
    eq(reason, "no_safe_path", "reason")
end)

test("rejects malformed state", function()
    local ctx = solver.prepare({ plates = 3, links = {} })
    local _, r1 = solver.solve(ctx, { 4, 4 }, 1)
    local _, r2 = solver.solve(ctx, { 4, 4, 8 }, 1)
    local _, r3 = solver.solve(ctx, { 4, 4, 4 }, 0)
    eq(r1, "bad_state", "short positions")
    eq(r2, "bad_state", "position out of range")
    eq(r3, "bad_state", "cursor out of range")
end)

test("apply returns nil on strain", function()
    local ctx = solver.prepare({ plates = 2, links = { [1] = { { 2, 1 } } } })
    eq(solver.apply(ctx, { 3, 7 }, 1, "D"), nil, "strain")
end)

test("apply moves cursor without wrap", function()
    local ctx = solver.prepare({ plates = 3, links = {} })
    local p, c = solver.apply(ctx, { 4, 4, 4 }, 1, "S")
    eq(c, 1, "cursor stays at front")
    eq(str(p), "4 4 4", "positions unchanged")
    _, c = solver.apply(ctx, { 4, 4, 4 }, 3, "W")
    eq(c, 3, "cursor stays at back")
end)

test("cursor wrap takes the short way", function()
    local ctx = solver.prepare({ plates = 5, links = {} }, { cursor_wrap = true })
    local _, c = solver.apply(ctx, { 4, 4, 4, 4, 4 }, 1, "S")
    eq(c, 5, "wrapped cursor")
    eq(str(solver.solve(ctx, { 4, 4, 4, 4, 5 }, 1)), "S A", "keys")
end)

test("matches reference BFS on random small locks", function()
    math.randomseed(42)
    for case = 1, 150 do
        local n = 2 + case % 3
        local graph = random_graph(n)
        local start = {}
        for i = 1, n do start[i] = math.random(1, 7) end
        local cursor = math.random(1, n)
        local ctx = solver.prepare(graph)
        local keys = solver.solve(ctx, start, cursor)
        local expected = naive_distance(graph, start)
        if expected == nil then
            eq(keys, nil, "case " .. case .. " solvability")
        else
            if keys == nil then error("case " .. case .. ": solver found no path, reference found " .. expected) end
            eq(count_moves(keys), expected, "case " .. case .. " move count")
            replay(ctx, start, cursor, keys)
        end
    end
end)

test("prepare can yield inside a coroutine", function()
    local graph = { plates = 4, links = { [1] = { { 2, 1 } } } }
    local co = coroutine.create(function() return solver.prepare(graph, { yield_every = 100 }) end)
    local resumes, ok, ctx = 0, nil, nil
    repeat
        ok, ctx = coroutine.resume(co)
        if not ok then error(ctx) end
        resumes = resumes + 1
    until coroutine.status(co) == "dead"
    if resumes < 2 then error("expected several resumes, got " .. resumes) end
    local plain = solver.prepare(graph)
    eq(str(solver.solve(ctx, { 1, 2, 7, 4 }, 1)), str(solver.solve(plain, { 1, 2, 7, 4 }, 1)), "same keys")
end)

test("prepare for 7 independent plates fits time budget", function()
    local t0 = os.clock()
    local ctx = solver.prepare({ plates = 7, links = {} })
    local elapsed = os.clock() - t0
    print(string.format("  prepare(7 plates, no links) took %.2f s", elapsed))
    if elapsed > 10 then error("too slow: " .. elapsed .. " s") end
    eq(count_moves(solver.solve(ctx, { 1, 1, 1, 1, 1, 1, 1 }, 1)), 21, "move count")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
