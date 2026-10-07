-- G1LockPickHelper tracker: follows the player through the hint. Pure Lua 5.4, no UE4SS API.
--
-- The game shows plate positions but not the cursor, so the cursor is tracked from W/S presses as
-- an interval [lo, hi] of possible plates (lo == hi when known). Key presses update the expected
-- positions at once; settled positions read from the game confirm them. When the game disagrees,
-- the tracker re-reads the state: the cursor is inferred from which plates moved, and if that is
-- impossible the new hint starts with enough S presses to park the cursor on plate 1 (S does not
-- wrap), so the hint never relies on a guessed cursor. A strained move may break the pick, which
-- resets the lock and puts the cursor on plate 1, so strains and returns to the start positions
-- also forget the cursor.
local solver = require("solver")

local M = {}
M.__index = M

local GOAL = 4
local HISTORY_MAX = 512 -- presses kept for the hint's "done" part

local function copy(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function at_goal(positions)
    for i = 1, #positions do
        if positions[i] ~= GOAL then return false end
    end
    return true
end

local function shift(self, key)
    local step = key == "W" and 1 or -1
    self.lo = math.max(1, math.min(self.n, self.lo + step))
    self.hi = math.max(1, math.min(self.n, self.hi + step))
end

-- ctx: solver.prepare result; positions: settled positions when the minigame became playable.
-- opts.cursor_known (default true): false if W/S may have been pressed before the session started.
-- opts.grace_ms (default 1200): how long a press may stay invisible before the game is believed.
function M.new(ctx, positions, opts)
    opts = opts or {}
    local self = setmetatable({}, M)
    self.ctx, self.n = ctx, ctx.n
    self.grace_ms = opts.grace_ms or 1200
    self.start = copy(positions) -- positions the lock returns to when the pick breaks or on R
    self.pos = copy(positions)   -- expected positions after every press so far
    self.seen = copy(positions)  -- last positions confirmed by the game
    self.since = {}              -- presses after `seen` was confirmed
    self.trail = {}              -- { pos = expected positions, count = #since } after each A/D since `seen`
    self.last_move_ms = -math.huge
    self.done = false
    self.history = {}            -- { key, ok } for every W/S/A/D pressed while a hint was shown
    self.misses = 0              -- presses that were not the hinted key (only grows)
    self.pressed = 0             -- presses added to the history (only grows; the history itself is capped)
    if opts.cursor_known == false then
        self.lo, self.hi = 1, self.n
    else
        self.lo, self.hi = 1, 1
    end
    self:replan()
    return self
end

-- New hint from the expected state: index 1, status "ok" | "no_safe_path" | "bad_state".
function M:replan()
    self.index = 1
    local keys, reason = solver.solve(self.ctx, self.pos, self.lo == self.hi and self.lo or 1)
    if not keys then
        self.keys, self.status = {}, reason
        return
    end
    if self.lo ~= self.hi then
        local parked = {}
        for i = 1, self.hi - 1 do parked[i] = "S" end
        table.move(keys, 1, #keys, #parked + 1, parked)
        keys = parked
    end
    self.keys, self.status = keys, "ok"
end

local function confirm(self, positions)
    self.seen = copy(positions)
    self.since, self.trail = {}, {}
end

-- key: "W" | "S" | "A" | "D" | "R" (R resets the lock); now_ms: time of the press.
function M:key(key, now_ms)
    if self.done then return end
    local hinted = self.status == "ok" and self.keys[self.index] -- the key the hint shows now
    if hinted and (key == "W" or key == "S" or key == "A" or key == "D") then
        local h = self.history
        h[#h + 1] = { key = key, ok = key == hinted }
        if #h > HISTORY_MAX then table.remove(h, 1) end
        self.pressed = self.pressed + 1
        if key ~= hinted then self.misses = self.misses + 1 end
    end
    self.since[#self.since + 1] = key
    if key == "W" or key == "S" then
        shift(self, key)
    elseif key == "A" or key == "D" then
        self.last_move_ms = now_ms
        if self.lo == self.hi then
            local p = solver.apply(self.ctx, self.pos, self.lo, key)
            if p then
                self.pos = p
                self.trail[#self.trail + 1] = { pos = p, count = #self.since }
            else
                self.lo, self.hi = 1, self.n -- strain: the pick may break and reset the cursor
            end
        end
    elseif key == "R" then
        self.last_move_ms = now_ms
        self.lo, self.hi = 1, self.n
        self.pos = copy(self.start)
        self.trail = {}
        self.history = {}
        self:replan()
        return
    else
        return
    end
    if self.keys[self.index] == key then
        self.index = self.index + 1
    else
        self:replan()
    end
end

-- The game disagrees with the expected state: take its positions and infer the cursor.
function M:resync(positions)
    local moves, after = 0, {}
    for _, k in ipairs(self.since) do
        if k == "A" or k == "D" then
            moves, after = moves + 1, {}
        elseif k == "R" then
            moves = moves + 2
        else
            after[#after + 1] = k
        end
    end
    local lo, hi
    if moves == 1 and not same(positions, self.start) then
        for c = 1, self.n do
            for _, k in ipairs({ "A", "D" }) do
                local p = solver.apply(self.ctx, self.seen, c, k)
                if p and same(p, positions) then
                    lo, hi = math.min(lo or c, c), math.max(hi or c, c)
                end
            end
        end
    end
    if lo then
        self.lo, self.hi = lo, hi
        for _, k in ipairs(after) do shift(self, k) end
    else
        self.lo, self.hi = 1, self.n
    end
    self.pos = copy(positions)
    confirm(self, positions)
    self:replan()
end

-- positions: settled positions read from the game (integers); now_ms: time of the reading.
function M:observe(positions, now_ms)
    if self.done then return end
    if at_goal(positions) then self.done = true return end
    if same(positions, self.pos) then
        confirm(self, positions)
        return
    end
    if same(positions, self.seen) then
        if now_ms - self.last_move_ms < self.grace_ms then return end
        -- The presses since `seen` did not move the plates: swallowed by the game, or strained. A strain
        -- may break the pick (cursor back on plate 1), and if the game dropped a W/S the tracker counted,
        -- the cursor is wrong as well, so it is forgotten (parking costs at most n - 1 S presses).
        self.lo, self.hi = 1, self.n
        self.pos = copy(positions)
        confirm(self, positions)
        self:replan()
        return
    end
    for i, step in ipairs(self.trail) do
        if same(positions, step.pos) then
            -- The game finished the first i moves; later presses are still animating.
            self.seen = copy(positions)
            self.since = table.move(self.since, step.count + 1, #self.since, 1, {})
            local rest = {}
            for j = i + 1, #self.trail do
                rest[#rest + 1] = { pos = self.trail[j].pos, count = self.trail[j].count - step.count }
            end
            self.trail = rest
            return
        end
    end
    self:resync(positions)
end

-- Moves the game has not confirmed yet: A/D and R (R animates the lock back to the start). 0: the plates show
-- every move so far; the autosolver sends the next key only at 0.
function M:pending()
    if self.done then return 0 end
    local n = 0
    for _, k in ipairs(self.since) do
        if k == "A" or k == "D" or k == "R" then n = n + 1 end
    end
    return n
end

-- { status = "ok" | "solved" | "no_safe_path" | "bad_state", keys = {...}, index = int,
--   history = { { key, ok }, ... }, misses = int, pressed = int }
function M:view()
    local v = { status = self.status, keys = self.keys, index = self.index,
        history = self.history, misses = self.misses, pressed = self.pressed }
    if self.done then v.status, v.keys, v.index = "solved", {}, 1 end
    return v
end

return M
