-- G1LockPickHelper input fix: when to hand the input back to the game after a minigame. Shared Mod Menu closed over
-- the minigame leaves the input on its UI, and the game does not switch it back when the minigame ends: the hero
-- cannot walk. After the minigame closes the game hides the cursor (in 1.2 s, up to ~3 s at a low frame rate); once
-- it has stayed hidden settle_ms and settle_frames frames in a row, frame() says so once and main.lua hands the input
-- back (SetInputMode_GameOnly). A cursor shown through window_ms after the close (a chest window, a menu - they hand
-- the input back themselves when they close): nothing is done. Pure Lua 5.4.
local M = {}
M.__index = M

-- opts: { settle_ms, settle_frames, window_ms }.
function M.new(opts)
    local self = setmetatable({
        settle_ms = opts.settle_ms, settle_frames = opts.settle_frames, window_ms = opts.window_ms,
    }, M)
    self:cancel()
    return self
end

-- Stop waiting (a minigame opened, or the window passed).
function M:cancel()
    self.ended_at, self.hidden_at, self.frames = nil, nil, 0
end

-- The minigame closed at `now` (ms): wait for the cursor to hide.
function M:ended(now)
    self.ended_at, self.hidden_at, self.frames = now, nil, 0
end

-- True while waiting: the caller reads the cursor only then.
function M:waiting()
    return self.ended_at ~= nil
end

-- One frame. cursor_visible: true, false, or nil (unreadable: counts as shown). True once: hand the input back now.
function M:frame(now, cursor_visible)
    if not self.ended_at then return false end
    if now - self.ended_at > self.window_ms then
        self:cancel()
        return false
    end
    if cursor_visible ~= false then
        self.hidden_at, self.frames = nil, 0
        return false
    end
    self.hidden_at = self.hidden_at or now
    self.frames = self.frames + 1
    if now - self.hidden_at >= self.settle_ms and self.frames >= self.settle_frames then
        self:cancel()
        return true
    end
    return false
end

return M
