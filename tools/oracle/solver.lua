-- G1LockPickHelper solver: safe W/S/A/D sequence with the fewest A/D moves for the lockpick minigame.
-- Pure Lua 5.4, no UE4SS API.
--
-- Graph: { plates = n, links = { [src] = { {dst, dir}, ... } } }, dir = 1 (with) | -1 (against).
-- Positions are 1..7 per plate (plates numbered front to back), goal is 4 for every plate.
-- A state is encoded as code = sum((pos[i] - 1) * 7^(i-1)); dist is indexed by code + 1.
-- Moves are reversible, so one BFS from the goal gives the distance-to-goal of every state.
local M = {}

local MIN_POS, MAX_POS, GOAL_POS, BASE = 1, 7, 4, 7

local function build_moves(graph, weights)
    local moves = {}
    for i = 1, graph.plates do
        for _, dir in ipairs({ -1, 1 }) do
            local delta = { [i] = dir }
            for _, link in ipairs(graph.links[i] or {}) do
                local dst = link[1]
                delta[dst] = (delta[dst] or 0) + dir * link[2]
            end
            local effects, offset = {}, 0
            for plate = 1, graph.plates do
                local d = delta[plate]
                if d and d ~= 0 then
                    effects[#effects + 1] = { plate, d }
                    offset = offset + d * weights[plate]
                end
            end
            moves[#moves + 1] = { plate = i, dir = dir, effects = effects, offset = offset }
        end
    end
    return moves
end

local function can_move(move, pos)
    local effects = move.effects
    for k = 1, #effects do
        local p = pos[effects[k][1]] + effects[k][2]
        if p < MIN_POS or p > MAX_POS then return false end
    end
    return true
end

local function encode(ctx, positions)
    local code = 0
    for i = 1, ctx.n do code = code + (positions[i] - 1) * ctx.weights[i] end
    return code
end

local function decode(ctx, code, out)
    for i = 1, ctx.n do
        out[i] = code % BASE + 1
        code = code // BASE
    end
    return out
end

-- Signed cursor travel from `from` to `to`: > 0 means press W (toward the back), < 0 means press S.
local function cursor_steps(ctx, from, to)
    if not ctx.cursor_wrap then return to - from end
    local back = (to - from) % ctx.n
    local front = back - ctx.n
    if back <= -front then return back end
    return front
end

local function valid_state(ctx, positions, cursor)
    if type(positions) ~= "table" or #positions ~= ctx.n then return false end
    for i = 1, ctx.n do
        local p = positions[i]
        if math.type(p) ~= "integer" or p < MIN_POS or p > MAX_POS then return false end
    end
    return math.type(cursor) == "integer" and cursor >= 1 and cursor <= ctx.n
end

function M.prepare(graph, opts)
    opts = opts or {}
    local n = graph.plates
    local weights, size = {}, 1
    for i = 1, n do
        weights[i] = size
        size = size * BASE
    end
    local ctx = { graph = graph, n = n, weights = weights, cursor_wrap = opts.cursor_wrap or false }
    ctx.moves = build_moves(graph, weights)

    local dist = {}
    for idx = 1, size do dist[idx] = -1 end
    local goal = {}
    for i = 1, n do goal[i] = GOAL_POS end
    local start = encode(ctx, goal)
    dist[start + 1] = 0

    local queue, head, tail = { start }, 1, 1
    local pos, moves, nmoves = {}, ctx.moves, #ctx.moves
    local yield_every = opts.yield_every
    while head <= tail do
        local code = queue[head]
        head = head + 1
        decode(ctx, code, pos)
        local nd = dist[code + 1] + 1
        for k = 1, nmoves do
            local m = moves[k]
            if can_move(m, pos) then
                local idx = code + m.offset + 1
                if dist[idx] == -1 then
                    dist[idx] = nd
                    tail = tail + 1
                    queue[tail] = idx - 1
                end
            end
        end
        if yield_every and head % yield_every == 0 then coroutine.yield() end
    end
    ctx.dist = dist
    return ctx
end

function M.solve(ctx, positions, cursor)
    if not valid_state(ctx, positions, cursor) then return nil, "bad_state" end
    local code = encode(ctx, positions)
    local d = ctx.dist[code + 1]
    if d < 0 then return nil, "no_safe_path" end

    local keys, pos = {}, {}
    for i = 1, ctx.n do pos[i] = positions[i] end
    while d > 0 do
        local best, best_cost
        for k = 1, #ctx.moves do
            local m = ctx.moves[k]
            if can_move(m, pos) and ctx.dist[code + m.offset + 1] == d - 1 then
                local cost = math.abs(cursor_steps(ctx, cursor, m.plate))
                if best == nil or cost < best_cost then best, best_cost = m, cost end
            end
        end
        local steps = cursor_steps(ctx, cursor, best.plate)
        local nav = steps > 0 and "W" or "S"
        for _ = 1, math.abs(steps) do keys[#keys + 1] = nav end
        keys[#keys + 1] = best.dir < 0 and "A" or "D"
        for _, e in ipairs(best.effects) do pos[e[1]] = pos[e[1]] + e[2] end
        code = code + best.offset
        cursor = best.plate
        d = d - 1
    end
    return keys
end

function M.apply(ctx, positions, cursor, key)
    local pos = {}
    for i = 1, ctx.n do pos[i] = positions[i] end
    if key == "W" or key == "S" then
        local c = cursor + (key == "W" and 1 or -1)
        if c < 1 or c > ctx.n then
            if not ctx.cursor_wrap then return pos, cursor end
            c = (c - 1) % ctx.n + 1
        end
        return pos, c
    end
    local dir
    if key == "A" then dir = -1 elseif key == "D" then dir = 1 else error("unknown key: " .. tostring(key)) end
    for _, m in ipairs(ctx.moves) do
        if m.plate == cursor and m.dir == dir then
            if not can_move(m, pos) then return nil end
            for _, e in ipairs(m.effects) do pos[e[1]] = pos[e[1]] + e[2] end
            return pos, cursor
        end
    end
    error("no move for cursor " .. tostring(cursor))
end

return M
