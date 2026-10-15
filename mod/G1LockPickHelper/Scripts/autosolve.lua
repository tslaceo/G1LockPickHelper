-- G1LockPickHelper autosolver: presses the hint's keys for the player. Pure Lua 5.4, no UE4SS API.
--
-- States: "off" -> "armed" (waits for the tracker: the minigame is not ready yet) -> "running" -> "off".
-- Every frame step() gets the tracker's view and how many A/D the plates have not shown yet, and says which key
-- to press now: the hint's current key. After a W/S it waits ws_gap_ms; after an A/D, until the tracker has
-- confirmed it from the plates. The press itself goes through the game (main.lua), so the tracker follows it
-- like any press and a replan is simply picked up. It never presses R and never presses while an A/D is
-- unconfirmed. It stops by itself when the lock is open, when there is no hint (no_safe_path / bad_state), when
-- an A/D stays unconfirmed for timeout_ms, and after max_replans hint replans in a row (the model and the game
-- disagree).
local M = {}
M.__index = M

-- opts: { ws_gap_ms, timeout_ms, max_replans }.
function M.new(opts)
    local self = setmetatable({}, M)
    self.ws_gap_ms, self.timeout_ms, self.max_replans = opts.ws_gap_ms, opts.timeout_ms, opts.max_replans
    self:stop()
    return self
end

function M:stop()
    self.state = "off"
    self.keys = nil    -- the hint's keys table seen last (a new table: the tracker replanned)
    self.replans = 0   -- replans since the last A/D the plates confirmed as planned
    self.ad_at = nil   -- when our last A/D was pressed, while it waits for the plates
    self.ad_ok = false -- no replan since that A/D
    self.next_at = 0   -- no press before this time (the pause after a W/S)
end

-- From off: wait for the tracker (the auto-pick setting at the minigame start).
function M:arm()
    if self.state == "off" then self.state = "armed" end
end

-- F3. tracking: the tracker exists (the minigame is ready). Returns the new state.
function M:toggle(tracking)
    if self.state ~= "off" then
        self:stop()
    else
        self.state = tracking and "running" or "armed"
    end
    return self.state
end

-- A press the autosolver did not make (the player's). Returns true when it stopped the autosolver.
function M:player_pressed()
    if self.state == "off" then return false end
    self:stop()
    return true
end

-- How long the autosolver needs for keys[from..]: each A/D waits for the plates (ad_ms), each W/S for its gap
-- (ws_ms). Milliseconds.
function M.eta_ms(keys, from, ad_ms, ws_ms)
    local ms = 0
    for i = from, #keys do
        ms = ms + ((keys[i] == "A" or keys[i] == "D") and ad_ms or ws_ms)
    end
    return ms
end

local function halt(self, reason)
    self:stop()
    return nil, reason
end

-- v: the tracker's view (nil while there is no tracker); pending: tracker:pending(); now: ms.
-- Returns the key to press now ("W" | "S" | "A" | "D") or nil; nil plus a reason when it has just stopped
-- itself: "solved" | "no_safe_path" | "bad_state" | "timeout" | "replans".
function M:step(v, pending, now)
    if self.state == "off" or not v then return nil end
    self.state = "running"
    if v.status == "solved" then return halt(self, "solved") end
    if v.status ~= "ok" then return halt(self, v.status) end
    if v.keys ~= self.keys then
        if self.keys then
            self.replans = self.replans + 1
            self.ad_ok = false
            if self.replans >= self.max_replans then return halt(self, "replans") end
        end
        self.keys = v.keys
    end
    if pending > 0 then
        self.ad_at = self.ad_at or now -- a move it did not make (in flight at F3) waits under the same timeout
        if now - self.ad_at > self.timeout_ms then return halt(self, "timeout") end
        return nil
    end
    if self.ad_at then
        if self.ad_ok then self.replans = 0 end
        self.ad_at = nil
    end
    if now < self.next_at then return nil end
    local key = v.keys[v.index]
    if not key then return nil end
    if key == "A" or key == "D" then
        self.ad_at, self.ad_ok = now, true
    else
        self.next_at = now + self.ws_gap_ms
    end
    return key
end

return M
