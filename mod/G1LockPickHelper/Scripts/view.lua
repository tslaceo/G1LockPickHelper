-- G1LockPickHelper view: turns the tracker's view into what the overlay draws - a tape (the current key
-- with fading neighbours) or lines (the whole sequence, long runs folded into "A×N"). Pure Lua 5.4.
local M = {}

local NEXT_FIRST, NEXT_LAST = 0.85, 0.15 -- alpha of the first and the last next key on the tape
local DONE_FIRST, DONE_LAST = 0.75, 0.28 -- alpha of the nearest and the furthest pressed key

local function fade(i, n, first, last)
    if n <= 1 then return first end
    return first - (i - 1) * (first - last) / (n - 1)
end

local function label(labels, key)
    return labels and labels[key] or key
end

local function counter(v)
    local total = #v.keys
    return string.format("%d/%d", math.min(v.index - 1, total), total)
end

-- v: tracker view { keys, index, history = { { key, ok }, ... }, pressed, misses }.
-- opts: { next = int, done = int, labels = { W = "W", ... } (optional) }.
-- Returns { kind = "tape", counter, pressed, misses, cells }: #cells == done + 1 + next and the current key
-- is always cells[done + 1]. Cell: { text, role = "done"|"miss"|"current"|"next"|"empty", alpha }.
function M.tape(v, opts)
    local cells = {}
    local history = v.history or {}
    for j = opts.done, 1, -1 do -- j: how many presses back
        local h = history[#history - j + 1]
        if h then
            cells[#cells + 1] = { text = label(opts.labels, h.key), role = h.ok and "done" or "miss",
                alpha = fade(j, opts.done, DONE_FIRST, DONE_LAST) }
        else
            cells[#cells + 1] = { text = "", role = "empty", alpha = 0 }
        end
    end
    local current = v.keys[v.index]
    if current then
        cells[#cells + 1] = { text = label(opts.labels, current), role = "current", alpha = 1 }
    else
        cells[#cells + 1] = { text = "", role = "empty", alpha = 0 }
    end
    for i = 1, opts.next do
        local k = v.keys[v.index + i]
        if k then
            cells[#cells + 1] = { text = label(opts.labels, k), role = "next", alpha = fade(i, opts.next, NEXT_FIRST, NEXT_LAST) }
        else
            cells[#cells + 1] = { text = "", role = "empty", alpha = 0 }
        end
    end
    return { kind = "tape", counter = counter(v), pressed = v.pressed or 0, misses = v.misses or 0, cells = cells }
end

-- The whole sequence: the history, then the plan from the current key.
local function items(v)
    local list = {}
    for _, h in ipairs(v.history or {}) do
        list[#list + 1] = { key = h.key, role = h.ok and "done" or "miss" }
    end
    for i = v.index, #v.keys do
        list[#list + 1] = { key = v.keys[i], role = i == v.index and "current" or "todo" }
    end
    return list
end

-- Folds the sequence into tokens. Runs of one key with one role become "K×N" when N >= min. The run of the
-- current key (its pressed part at the end of the history + the rest in the plan) is one current token
-- "K×left" - left counts down to 1 - when the whole run is long enough.
local function tokens_of(list, cur_at, min, labels)
    local run_from, run_to
    if list[cur_at] and list[cur_at].role == "current" then
        local key = list[cur_at].key
        local a, b = cur_at, cur_at
        while a > 1 and list[a - 1].role == "done" and list[a - 1].key == key do a = a - 1 end
        while list[b + 1] and list[b + 1].key == key do b = b + 1 end
        if b - a + 1 >= min then run_from, run_to = a, b end
    end
    local tokens, cur_token = {}, nil
    local i = 1
    while i <= #list do
        local it = list[i]
        if i == run_from then
            tokens[#tokens + 1] = { text = label(labels, it.key) .. "×" .. (run_to - cur_at + 1), role = "current" }
            cur_token = #tokens
            i = run_to + 1
        else
            local j = i
            while list[j + 1] and j + 1 ~= run_from and list[j + 1].key == it.key and list[j + 1].role == it.role do
                j = j + 1
            end
            if j - i + 1 >= min then
                tokens[#tokens + 1] = { text = label(labels, it.key) .. "×" .. (j - i + 1), role = it.role }
            else
                for k = i, j do
                    tokens[#tokens + 1] = { text = label(labels, list[k].key), role = list[k].role }
                end
            end
            if it.role == "current" then cur_token = #tokens end
            i = j + 1
        end
    end
    return tokens, cur_token
end

-- v: tracker view; opts: { per_line, max_lines, collapse_min (0 or 1: no folding), labels (optional) }.
-- Returns { kind = "lines", counter, pressed, misses, lines }: at most max_lines lines of tokens
-- { text, role = "done"|"miss"|"current"|"todo" }; the window keeps the current token's line in view and
-- starts one line above it when it can.
function M.lines(v, opts)
    local list = items(v)
    local min = opts.collapse_min >= 2 and opts.collapse_min or math.huge
    local tokens, cur_token = tokens_of(list, #(v.history or {}) + 1, min, opts.labels)
    local model = { kind = "lines", counter = counter(v), pressed = v.pressed or 0, misses = v.misses or 0, lines = {} }
    local per, max_lines = opts.per_line, opts.max_lines
    local count = (#tokens + per - 1) // per
    if count == 0 then return model end
    local cur_line = cur_token and (cur_token - 1) // per + 1 or count
    local first = math.max(1, cur_line - max_lines + 1, math.min(cur_line - 1, count - max_lines + 1))
    local last = math.min(count, first + max_lines - 1)
    for l = first, last do
        local line = {}
        for k = (l - 1) * per + 1, math.min(l * per, #tokens) do line[#line + 1] = tokens[k] end
        model.lines[#model.lines + 1] = line
    end
    return model
end

-- The example hint of the menu's "show example": a miss, a run in progress, a long plan.
M.SAMPLE = {
    status = "ok",
    keys = { "D", "A", "A", "A", "A", "W", "D", "D", "S", "A", "D", "D", "D", "W", "A", "S", "D", "A", "A", "W" },
    index = 3,
    history = { { key = "S", ok = true }, { key = "W", ok = false }, { key = "D", ok = true }, { key = "A", ok = true } },
    pressed = 4,
    misses = 1,
}

return M
