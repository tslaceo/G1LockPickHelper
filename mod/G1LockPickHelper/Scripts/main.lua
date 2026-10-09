-- G1LockPickHelper: shows the key sequence that opens the current lock and follows the player through it; on
-- F3 (or by itself with the auto-pick setting) the autosolver presses those keys for the player.
-- Flow: minigame opens -> lock name and the player's lockpick skill -> the lock's graph without the connections
-- that skill removes -> solver context (prepared over several ticks) -> wait until the game accepts presses and
-- the plates are still -> tracker follows presses and readings -> view -> overlay.
-- The player's presses (keyboard and gamepad) come from hooks on the minigame's input functions; the autosolver
-- calls those functions itself (autosolve.lua decides what and when).
-- The player's settings: settings.ini in the mod folder (settings.lua), also in Shared Mod Menu (menu.lua); the
-- texts in the player's language: lang/<id>.lua (i18n.lua).
-- Threading: everything runs on the game thread (see "Threading" below).
local config = require("config")
local settings = require("settings")
local menu = require("menu")
local view = require("view")
local overlay = require("overlay")
local reader = require("lock_reader")
local lockdb = require("lockdb")
local solver = require("solver")
local tracker = require("tracker")
local autosolve = require("autosolve")
local i18n = require("i18n")
local pad = require("pad")
local input_fix = require("input_fix")

local TAG = "[G1LockPickHelper] "
local VERSION = "1.0.0" -- also in README.txt and CHANGELOG.md; scripts/package.ps1 names the archive after it

local function log(fmt, ...)
    print(TAG .. string.format(fmt, ...) .. "\n")
end

local values -- the player's settings (settings.lua), loaded below

-- The detailed log: only with [general] debug = true in settings.ini.
local function trace(fmt, ...)
    if values and values.general.debug then log(fmt, ...) end
end

local function now_ms()
    return os.clock() * 1000 -- wall-clock milliseconds on Windows (MSVC clock())
end

local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

if not LoopInGameThreadWithDelay then
    log("ERROR: this UE4SS build has no LoopInGameThreadWithDelay - the mod stays inactive")
    return
end

-- <Mods>\G1LockPickHelper\Scripts\main.lua: settings.ini is in the mod folder, Shared Mod Menu in Mods. When
-- this path cannot be derived (another UE4SS build), mods_dir stays nil and there is no file or menu I/O at all:
-- a guessed path would put a stray settings.ini into the game's working directory.
local scripts_dir = debug.getinfo(1, "S").source:match("^@(.+)[/\\][^/\\]+$")
local mod_dir = scripts_dir and scripts_dir:match("^(.+)[/\\][^/\\]+$")
local mods_dir = mod_dir and mod_dir:match("^(.+)[/\\][^/\\]+$")
local SETTINGS_PATH = mods_dir and (mod_dir .. "/settings.ini") -- nil: the mod folder is unknown

local creating = false -- settings.ini is missing: the first frame writes it, in the language chosen by then
if SETTINGS_PATH then
    local problems
    values, problems, creating = settings.load(SETTINGS_PATH)
    for _, p in ipairs(problems) do log("settings.ini: %s", p) end
else
    log("cannot find the mod folder; settings.ini and the settings menu are not used, defaults apply")
    values = settings.defaults()
end
-- Labels of the keys in the hint. Keys are bound once at load, so both follow settings.ini after a restart.
local labels = { W = values.keys.W, S = values.keys.S, A = values.keys.A, D = values.keys.D }

-- Texts of the current language (lang/<id>.lua): T for the hint, the notes and the menu, INI for settings.ini.
local lang, T, INI
local function set_language(id)
    local L = i18n.load(id)
    lang, T, INI = id, L.text, L.ini
end
set_language(i18n.resolve(values.general.language))

local db = lockdb.new(require("lockgraphs"))
local session -- the open minigame: { task, started, phase, name, key, graph, ctx, tracker, auto, message, ... }
local enabled = true
local contexts, context_order = {}, {} -- solver contexts of the two most recent locks, by lock name and skill
local HIDDEN = "hidden" -- render signature of "nothing shown"
local last_sig, last_keys = HIDDEN, nil
local version, applied = 1, 0 -- settings version (bumped on every change) and the one the overlay has
local save_at = creating and 0 or nil -- when to write settings.ini (ms); nil: nothing to write
local save_failed = false
local preview_until           -- end of the menu's example hint (ms)
local note, note_until        -- a short note (hint on/off, autosolver on/off while the hint is hidden, autosolver stopped) and when it ends (ms)
local early                   -- F3 outside a minigame: { until_ms, solve } for the minigame that opens before until_ms
-- Model key -> the minigame task's input function ("Input" in docs/TECHNICAL.md).
local NATIVE = { W = "UpPressed", S = "DownPressed", A = "LeftPressed", D = "RightPressed", R = "ResetPressed" }
local SOLVE_OPTS = { ws_gap_ms = config.solve_ws_gap_ms, timeout_ms = config.solve_timeout_ms,
    max_replans = config.solve_max_replans }
local hooked = false   -- the input functions are hooked; otherwise the keys from settings.ini are bound
local own_call = false -- true while the autosolver calls an input function
local own_seen = false -- a hook saw that call
local menu_bridge             -- Shared Mod Menu's bridge once the settings are registered there (set at load, below)
local icon_mode = "keys"      -- what the hint draws: "keys" (letters) or an icon set (pad.lua)

local function guarded(what, fn)
    local ok, err = pcall(fn)
    if not ok then
        log("%s failed: %s", what, tostring(err))
        session = nil
        preview_until = nil -- a failing example must not be retried every frame
        note_until = nil    -- nor a failing note
        pcall(overlay.hide)
        last_sig = nil
    end
end

-- The overlay's model of a tracker view for the configured layout (view.lua).
local function model_of(v)
    if values.hint.layout == "tape" then
        return view.tape(v, { next = values.tape.next, done = values.tape.done, labels = labels })
    end
    return view.lines(v, { per_line = values.lines.per_line, max_lines = values.lines.max_lines,
        collapse_min = values.lines.collapse_min, labels = labels })
end

-- Shows what the note, the session or the menu's example wants (in this order); calls the overlay only when
-- that changes. While the autosolver runs, its text replaces the counter, shown even with the counter off.
local function render(now)
    local kind, a
    local s = session
    local running = s ~= nil and s.auto.state == "running"
    if note_until and now >= note_until then note_until = nil end
    if early and now >= early.until_ms then early = nil end
    if note_until then
        kind, a = "message", note -- the note replaces whatever is shown, enabled or not
    elseif enabled and s then
        if s.message then
            kind, a = "message", s.message
        elseif s.tracker then
            local v = s.tracker:view()
            if v.status == "ok" then
                kind, a = "hint", v
            elseif v.status ~= "solved" then
                kind, a = "message", T[v.status] or v.status
            end
        elseif s.auto.state == "armed" then
            kind, a = "message", T.solve_armed
        end
    elseif enabled and early and early.solve then
        kind, a = "message", T.solve_armed
    elseif enabled and preview_until then
        if now < preview_until then
            kind, a = "hint", view.SAMPLE
        else
            preview_until = nil
        end
    end
    -- The signature uses the identity of the tracker's keys table (it changes exactly when the tracker
    -- replans), the settings version (a settings change redraws) and whether the autosolver runs.
    local sig = HIDDEN
    if kind == "hint" then
        sig = string.format("hint|%s|%d|%d|%d|%d|%d|%s|%s", tostring(a.keys), a.index, #a.history, a.pressed,
            a.misses, applied, tostring(running), icon_mode)
    elseif kind == "message" then
        sig = "message|" .. a .. "|" .. applied
    end
    if sig == last_sig then return end
    last_sig = sig
    if kind == "hint" then
        if a.keys ~= last_keys and a ~= view.SAMPLE then
            last_keys = a.keys
            trace("hint (%d keys): %s", #a.keys, table.concat(a.keys, " "))
        end
        local model = model_of(a)
        if running then model.counter, model.counter_always = T.solving, true end
        overlay.show(model, now)
    elseif kind == "message" then
        overlay.message(a)
    else
        overlay.hide()
    end
end

-- Runs solver.prepare for the session's lock a chunk at a time. True once s.ctx is ready. Contexts are cached
-- by s.key (the lock and the connections the skill removed: another skill is another graph).
local function step_prepare(s)
    local cached = contexts[s.key]
    if cached then
        for i, key in ipairs(context_order) do
            if key == s.key then
                table.remove(context_order, i)
                break
            end
        end
        context_order[#context_order + 1] = s.key
        s.ctx = cached
        return true
    end
    s.prep = s.prep or coroutine.create(function()
        return solver.prepare(s.graph, { yield_every = config.prepare_chunk })
    end)
    local ok, result = coroutine.resume(s.prep)
    if not ok then error("prepare failed: " .. tostring(result)) end
    if coroutine.status(s.prep) ~= "dead" then return false end
    contexts[s.key] = result
    context_order[#context_order + 1] = s.key
    if #context_order > 2 then contexts[table.remove(context_order, 1)] = nil end
    s.ctx = result
    return true
end

-- The lock cannot be solved: a waiting autosolver goes off, logged like its other stops.
local function drop_auto(s, reason)
    if s.auto.state ~= "off" then log("autosolve stopped: %s", reason) end
    s.auto:stop()
end

-- A game object found with FindFirstOf and kept; a missing one is looked for again at most once a second
-- (FindFirstOf walks all objects).
local function finder(class)
    local obj, next_try = nil, 0
    return function(now)
        if obj and obj:IsValid() then return obj end
        obj = nil
        if now < next_try then return nil end
        next_try = now + 1000
        local ok, found = pcall(FindFirstOf, class)
        if ok and found and found:IsValid() then obj = found end
        return obj
    end
end
local input_subsystem = finder("CommonInputSubsystem")
local game_settings = finder("GothicGameUserSettings")
local player_controller = finder("PlayerController")

-- Letters or the game's gamepad icons (pad.lua). The input type is read every frame (the player switches devices
-- any time), the game's "Button icons" option and the gamepad name every language_poll_ms; with [hint] icons =
-- keys nothing is read. A change reaches the overlay at once and redraws the hint (render's signature).
local pad_state = {} -- { input_type, button_graphics, gamepad_name } for pad.resolve
local next_pad_read = 0

local function read_pad(now)
    if values.hint.icons ~= "keys" then
        local cis = input_subsystem(now)
        local input_type
        if cis then
            local ok, v = pcall(function() return cis:GetCurrentInputType() end)
            if ok then input_type = v end
        end
        pad_state.input_type = input_type
        if now >= next_pad_read then
            next_pad_read = now + config.language_poll_ms
            local gs = game_settings(now)
            local graphics, name
            if gs then
                local ok, v = pcall(function() return gs.ButtonGraphics end)
                if ok then graphics = v end
            end
            if cis then
                local ok, v = pcall(function() return cis:GetCurrentGamepadName():ToString() end)
                if ok then name = v end
            end
            pad_state.button_graphics, pad_state.gamepad_name = graphics, name
        end
    end
    local mode = pad.resolve(values.hint.icons, values.hint.gamepad, pad_state)
    if mode ~= icon_mode then
        icon_mode = mode
        overlay.set_icons(mode)
        trace("icons: %s", mode)
    end
end

-- Shared Mod Menu closed over the minigame leaves the input on its UI; after the minigame the game hides the cursor
-- but does not take the input back (the hero cannot walk). With Shared Mod Menu installed, once the cursor stays
-- hidden after a minigame (input_fix.lua) the input goes back to the game: SetInputMode_GameOnly, held keys kept.
local fixer = input_fix.new(config.smm_fix)
local widget_lib -- WidgetBlueprintLibrary's default object, found once

local function smm_fix_on()
    return menu_bridge ~= nil and config.fix_smm_input
end

local function step_fix(now)
    if not (smm_fix_on() and fixer:waiting()) then return end
    local pc = player_controller(now)
    local visible
    if pc then
        local ok, v = pcall(function() return pc.bShowMouseCursor end)
        if ok then visible = v == true end
    end
    if not fixer:frame(now, visible) then return end
    local ok, err = pcall(function()
        if not (widget_lib and widget_lib:IsValid()) then
            widget_lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        end
        widget_lib:SetInputMode_GameOnly(pc, false)
    end)
    if ok then
        trace("input handed back to the game after the minigame (Shared Mod Menu fix)")
    else
        log("input fix failed: %s", tostring(err))
    end
end

local function tick()
    local s = session
    if not s then return end
    local now = now_ms()
    if not reader.active(s.task) then
        if s.phase == "name" and now - s.started < 2000 then return end -- ability not attached yet
        trace("minigame closed")
        session = nil
        if smm_fix_on() then fixer:ended(now) end
        return
    end
    if s.phase == "name" then
        local name, err = reader.lock_name(s.task)
        if not name then
            if err ~= s.read_error then s.read_error = err; trace("lock name: %s", tostring(err)) end
            return
        end
        local precision, perr = reader.precision()
        if not precision then log("lockpick skill: %s, assuming 0", tostring(perr)) end
        local graph, stored, removed = db.find(name, reader.connections_removed(precision))
        if not graph then
            log("lock not in database: %s", name)
            s.message, s.phase = string.format(T.not_in_db, name), "idle"
            drop_auto(s, "not_in_db")
            return
        end
        log("lock %s (%d plates, precision %s, %d connections removed)", stored, graph.plates,
            precision and string.format("%g", precision) or "unknown", removed)
        s.name, s.key, s.graph, s.phase = stored, stored .. "|" .. removed, graph, "prepare"
    end
    if s.phase == "prepare" then
        if not step_prepare(s) then return end
        trace("solver ready after %.0f ms", now - s.started)
        s.phase = "ready"
    end
    if s.phase == "idle" then return end
    local positions, err = reader.positions()
    if err and err ~= s.read_error then s.read_error = err; trace("plates: %s", tostring(err)) end
    local settled = positions ~= nil and s.last_positions ~= nil and same(positions, s.last_positions)
    s.last_positions = positions
    if not settled then return end
    if s.phase == "ready" then
        if now - s.started < config.ready_delay_ms or s.frames < config.ready_frames then return end
        if #positions ~= s.graph.plates then
            log("lock %s: %d visible plates, database has %d", s.name, #positions, s.graph.plates)
            s.message, s.phase = T.bad_state, "idle"
            drop_auto(s, "bad_state")
            return
        end
        s.tracker = tracker.new(s.ctx, positions, { cursor_known = not s.early_nav, grace_ms = config.grace_ms })
        s.phase = "track"
        trace("tracking from %s, cursor %s", table.concat(positions, " "), s.early_nav and "unknown" or "1")
        s.reading = positions
    elseif s.phase == "track" then
        if #positions ~= s.graph.plates then return end -- partial reading (pieces being torn down): skip it
        if not same(positions, s.reading) then
            s.reading = positions
            trace("plates %s", table.concat(positions, " "))
        end
        s.tracker:observe(positions, now)
    end
end

local function on_key(key)
    local s = session
    if not s then return end
    if s.tracker then
        trace("key %s", key)
        s.tracker:key(key, now_ms())
    elseif key == "W" or key == "S" then
        s.early_nav = true
        trace("key %s before tracking: the hint will park the cursor first", key)
    end
end

local toggle_solve -- F3's action, defined below; two resets in a row call it too

-- Two resets of the player in a row (within double_reset_ms) start the autosolver like F3: the gamepad has no
-- button of its own in the minigame. A reset while the autosolver runs only stops it and starts no pair.
local function double_reset(s, was_off)
    if not values.solve.double_reset then return end
    local now = now_ms()
    if was_off and s.reset_at and now - s.reset_at <= config.double_reset_ms then
        s.reset_at = nil
        log("autosolve: double reset")
        toggle_solve(T.double_reset)
    else
        s.reset_at = was_off and now or nil
    end
end

-- A press of the player: it stops the autosolver, then the tracker takes it; a reset may be half of a double reset.
local function player_key(key)
    local s = session
    if not s then return end
    local was_off = s.auto.state == "off"
    if s.auto:player_pressed() then log("autosolve: cancelled by a player press (%s)", key) end
    on_key(key)
    if key == "R" then double_reset(s, was_off) end
end

-- Hook on one of the minigame's input functions (game thread): a press of the player (keyboard or gamepad)
-- or the autosolver's own call.
local function on_input(key)
    if not hooked then return end -- some hooks registered, one failed: the key binds listen instead
    if own_call then
        own_seen = true
        on_key(key)
    else
        player_key(key)
    end
end

-- The autosolver stopped by itself: a log line and, unless the lock opened, a note.
local function auto_stopped(reason)
    if reason == "solved" then
        trace("autosolve: lock opened")
        return
    end
    log("autosolve stopped: %s", reason)
    note, note_until = T.solve_stopped, now_ms() + config.toggle_note_ms
end

-- A short note on what F3 (or a double reset) did, whatever the hint's state. source: the key name for the note
-- (nil: the F3 key).
local function solve_note_always(on, source)
    note = string.format(on and T.solve_on or T.solve_off, tostring(source or values.keys.solve))
    note_until = now_ms() + config.toggle_note_ms
end

-- F3 while the hint is hidden: a short note says what the key did (a shown hint tells it by itself).
local function solve_note(on, source)
    if enabled then return end
    solve_note_always(on, source)
end

-- F3 with nothing the autosolver could do: a short note (shown with the hint hidden too), the reason in the log.
local function unavailable(reason)
    if reason then log("autosolve unavailable: %s", reason) end
    note, note_until = T.solve_unavailable, now_ms() + config.toggle_note_ms
end

-- Without the input hooks the autosolver cannot tell its own presses from the player's and does not see the
-- gamepad: it stays off (logged once).
local hooks_noted = false
local function no_hooks()
    if not hooks_noted then
        hooks_noted = true
        log("autosolver needs input hooks; it stays off")
    end
    unavailable(nil)
end

-- F3 outside a minigame (right after using the chest, while the hero sits down): the minigame that opens within
-- solve_early_ms is solved or not - the opposite of the auto-pick setting; F3 again within that time goes back
-- to the setting.
local function toggle_early()
    local now = now_ms()
    if early and now < early.until_ms then
        early = nil
        log("autosolve: the next minigame as set (%s)", values.solve.auto and "solve" or "no autosolve")
        if values.solve.auto then solve_note_always(true) else solve_note(false) end
        return
    end
    early = { until_ms = now + config.solve_early_ms, solve = not values.solve.auto }
    if early.solve then
        log("autosolve: armed for the next minigame")
        solve_note(true)
    else
        log("autosolve: the next minigame is skipped")
        solve_note_always(false)
    end
end

-- F3: starts (or arms, before the minigame is ready) or stops the autosolver of the open minigame; outside a
-- minigame see toggle_early. Nothing to solve (no hint, the lock already open) or no input hooks: a note.
-- source: the note's key name (nil: the F3 key; T.double_reset for two resets).
toggle_solve = function(source)
    if not hooked then return no_hooks() end
    local s = session
    if not s then return toggle_early() end
    if s.auto.state == "off" then
        if s.phase == "idle" then return unavailable("no hint for this lock") end
        local status = s.tracker and s.tracker:view().status
        if status == "solved" then return unavailable("the lock is already open") end
        if status and status ~= "ok" then return unavailable("no hint for this lock") end
    end
    local state = s.auto:toggle(s.tracker ~= nil)
    log("autosolve: %s", state)
    solve_note(state ~= "off", source)
end

-- One autosolver step: the key it wants goes to the game through the task's input function. The hook inside
-- that call hands the press to the tracker (the autosolver runs only with the hooks); if the hook stays silent we
-- hand it ourselves and stop.
local function step_auto(now)
    local s = session
    if not s then return end
    local tr = s.tracker
    local key, reason = s.auto:step(tr and tr:view(), tr and tr:pending() or 0, now)
    if reason then auto_stopped(reason) end
    if not key then return end
    if not reader.active(s.task) then return end -- closed (Esc): tick drops the session; no call into an ended task
    trace("autosolve: %s at +%.0f ms", key, now - s.started)
    own_call, own_seen = true, false
    local ok, err = pcall(function() s.task[NATIVE[key]](s.task) end)
    own_call = false
    if not ok then
        s.auto:stop()
        auto_stopped(string.format("%s failed: %s", NATIVE[key], tostring(err)))
        return
    end
    if not own_seen then
        on_key(key) -- the press reached the game: the tracker must know it
        s.auto:stop()
        auto_stopped(NATIVE[key] .. " hook did not fire")
    end
end

-- Settings changes from the menu. The bridge calls these from its own game-thread loop, between our
-- frames; they only change Lua tables, and the next frame hands the new settings to the overlay.
local function changed()
    version = version + 1
    save_at = now_ms() + config.save_delay_ms
end

local function on_setting(section, key, value)
    local _, problem = settings.set(values, section, key, value)
    if problem then log("menu: %s", problem) end
    changed()
end

local actions = {
    preview = function()
        if session == nil then preview_until = now_ms() + config.preview_ms end
    end,
    reset_position = function()
        local d = settings.defaults()
        values.hint.scale, values.hint.offset_x, values.hint.offset_y = d.hint.scale, d.hint.offset_x, d.hint.offset_y
        changed()
    end,
}

local function save()
    if not SETTINGS_PATH then return end
    local ok, err = settings.save(SETTINGS_PATH, values, INI)
    if ok then
        if creating then
            creating = false
            log("created %s with the default settings", SETTINGS_PATH)
        else
            trace("settings saved")
        end
    elseif not save_failed then
        save_failed = true
        log("cannot write %s: %s", SETTINGS_PATH, tostring(err))
    end
end

-- Threading. In UE4SS c838a8ac game-thread actions (ExecuteInGameThread, LoopInGameThreadWithDelay)
-- and LoopAsync run Lua without the mod's lock, and key binds run on UE4SS's event-loop thread, all in
-- this mod's Lua state; Lua running on two threads at once corrupts it (the likely cause of one crash
-- in game). So all work happens on the game thread: one loop that runs every frame, NotifyOnNewObject, the
-- hooks on the minigame's input functions (called from the game's input handling or from inside the
-- autosolver's calls) and Shared Mod Menu's bridge. A key bind (the toggle and solve keys, and the minigame
-- keys when the hooks are unavailable) only stores an integer in a preallocated ring buffer (no allocation, no
-- calls) and the loop drains it. The minigame's keys are invisible to PlayerController:IsInputKeyDown, so key
-- binds cannot be replaced by polling.
local KEY_NAMES = { "W", "S", "A", "D", "R", "toggle", "solve" } -- key code -> model key or action
local KEY_CODES = { W = 1, S = 2, A = 3, D = 4, R = 5, toggle = 6, solve = 7 }
local RING_SIZE = 64
local ring, written, drained = {}, 0, 0
for i = 1, RING_SIZE do ring[i] = 0 end

-- Runs on UE4SS's event-loop thread: integer stores only.
local function key_bind(code)
    local always = code == KEY_CODES.toggle or code == KEY_CODES.solve -- these work outside a minigame too
    return function()
        if session == nil and not always then return end
        local n = written + 1
        ring[(n - 1) % RING_SIZE + 1] = code
        written = n
    end
end

-- Handles the presses stored by the key binds since the last loop iteration, in order.
local function drain_keys()
    local stop = written
    if stop - drained > RING_SIZE then drained = stop - RING_SIZE end -- overrun: the oldest presses are lost
    while drained < stop do
        drained = drained + 1
        local name = KEY_NAMES[ring[(drained - 1) % RING_SIZE + 1]]
        if name == "toggle" then
            enabled = not enabled
            log("hint %s", enabled and "on" or "off")
            note = string.format(enabled and T.hint_on or T.hint_off, tostring(values.keys.toggle))
            note_until = now_ms() + config.toggle_note_ms
        elseif name == "solve" then
            toggle_solve()
        elseif name then
            player_key(name) -- the minigame keys are bound only without hooks
        end
    end
end

NotifyOnNewObject("/Script/G1R.AbilityTask_LockPick", function(task)
    guarded("minigame start", function()
        reader.reset()
        preview_until = nil
        fixer:cancel()
        local now = now_ms()
        local solve = values.solve.auto
        if early and now < early.until_ms then solve = early.solve end
        early = nil
        session = { task = task, started = now, frames = 0, phase = "name", auto = autosolve.new(SOLVE_OPTS) }
        if solve then
            if hooked then session.auto:arm() else no_hooks() end
        end
        trace("minigame opened%s", session.auto.state == "armed" and ", autosolve armed" or "")
        render(now)
    end)
end)

-- Configured key names UE4SS does not know (marked in the menu): "toggle", "solve", "W", ... -> true.
local missing_keys = {}
for _, id in ipairs({ "toggle", "solve", "W", "S", "A", "D" }) do
    if not Key[values.keys[id]] then
        missing_keys[id] = true
        log("settings.ini [keys] %s: unknown key %s", id, tostring(values.keys[id]))
    end
end

-- Binds a key (a UE4SS key name) to the ring buffer code of `id`; an unknown name binds nothing.
local function bind(id, key_name)
    if Key[key_name] then RegisterKeyBind(Key[key_name], key_bind(KEY_CODES[id])) end
end

-- Hooks on the minigame task's input functions: they see every press, keyboard and gamepad, and the
-- autosolver's own calls. True when all of them are hooked; otherwise false and the reason.
local function hook_input()
    if not RegisterHook then return false, "this UE4SS build has no RegisterHook" end
    for _, key in ipairs({ "W", "S", "A", "D", "R" }) do
        local ok, err = pcall(RegisterHook, "/Script/G1R.AbilityTask_LockPick:" .. NATIVE[key], function()
            guarded("input", function() on_input(key) end)
        end)
        if not ok then return false, NATIVE[key] .. ": " .. tostring(err) end
    end
    return true
end

bind("toggle", values.keys.toggle)
bind("solve", values.keys.solve)
local hook_err
hooked, hook_err = hook_input()
if hooked then
    trace("minigame input through hooks")
else
    log("minigame input hooks unavailable (%s); listening to the keys from settings.ini", tostring(hook_err))
    for _, key in ipairs({ "W", "S", "A", "D" }) do bind(key, values.keys[key]) end
    bind("R", "R")
end

-- The menu is optional: a failure while attaching it must not stop the mod from loading. It needs the Mods folder.
local function menu_opts()
    return {
        mods_dir = mods_dir, values = values, schema = settings.entry, text = T.menu, on_change = on_setting,
        actions = actions, log = log, keys = values.keys, missing_keys = missing_keys,
    }
end
if mods_dir then
    local menu_ok, result = pcall(menu.attach, menu_opts())
    if not menu_ok then
        log("settings menu failed: %s", tostring(result))
    elseif result then
        menu_bridge = result
    end
end

-- Warn when lockgraphs.lua was extracted from another game build (G1R\Version\version.txt).
local game_build -- the game's build from version.txt; nil when unreadable
local function check_build()
    local file = scripts_dir and io.open(scripts_dir .. "/../../../../../../Version/version.txt", "rb")
    if not file then
        log("cannot read the game build; lock database is for %s", tostring(db.build))
        return
    end
    game_build = lockdb.parse_build(file:read("a"))
    file:close()
    if game_build ~= db.build then
        log("WARNING: lock database is for %s, the game is %s - rerun tools/extract_lockgraphs.py",
            tostring(db.build), tostring(game_build))
    else
        trace("lock database matches the game build %s", game_build)
    end
end

-- The game's language. KismetInternationalizationLibrary.GetCurrentCulture() follows the game's language menu at
-- once; it is read on the game thread only and takes no parameters (a Lua string passed for an FName parameter
-- crashes UE4SS).
local culture          -- the game's culture ("ru", "en", ...); the last good read, nil until there is one
local intl             -- KismetInternationalizationLibrary's default object, found once
local next_culture = 0 -- when the culture is read again (ms), while [general] language = auto

local function read_culture()
    local ok, c = pcall(function()
        if not (intl and intl:IsValid()) then
            intl = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
            if not (intl and intl:IsValid()) then return nil end
        end
        return intl:GetCurrentCulture():ToString()
    end)
    if ok and type(c) == "string" and c ~= "" then return c end
    return nil
end

-- Switches the texts when the setting or the game's culture asks for another language; the menu follows (an open
-- one at once).
local function apply_language()
    local want = i18n.resolve(values.general.language, culture)
    if want == lang then return end
    set_language(want)
    log("language: %s", want)
    last_sig = nil -- redraw the hint in the new language; texts already formatted (a session message, a note)
                   -- keep the old one until they end
    if menu_bridge then menu.update(menu_bridge, menu_opts()) end
end

-- New settings (the start, the menu): the overlay gets them, a new language switches the texts.
local function apply_settings()
    overlay.configure(values)
    apply_language()
end

local function ue4ss_version()
    local ok, major, minor, hotfix = pcall(function() return UE4SS.GetVersion() end)
    if ok and major then return string.format("%s.%s.%s", tostring(major), tostring(minor), tostring(hotfix)) end
    return "unknown"
end

-- One line that answers the first questions of a bug report.
local function log_start()
    log("G1LockPickHelper %s: game %s (lock db %s), language %s (%s, culture %s), input hooks %s, UE4SS %s, "
        .. "icons %s/%s, SMM input fix %s",
        VERSION, game_build or "unknown", tostring(db.build), lang, values.general.language, culture or "unknown",
        hooked and "yes" or "no", ue4ss_version(), values.hint.icons, values.hint.gamepad,
        smm_fix_on() and "on" or "off")
end

-- The first frame reads the game's culture and logs the start line; while [general] language = auto the culture
-- is read again every language_poll_ms (the player may switch the game's language while playing); a failed
-- read keeps the last good culture.
local started = false
local function follow_language(now)
    if started and (values.general.language ~= "auto" or now < next_culture) then return end
    next_culture = now + config.language_poll_ms
    culture = read_culture() or culture
    apply_language()
    if not started then
        started = true
        log_start()
    end
end

local next_tick = 0

-- One game-thread frame: the language, the icons, presses at once, the settings, the plates every poll_ms, the autosolver, the input fix, the hint, the animations.
local function frame()
    local now = now_ms()
    follow_language(now)
    read_pad(now)
    drain_keys()
    if session then session.frames = session.frames + 1 end
    if applied ~= version then
        applied = version
        apply_settings()
    end
    if save_at and now >= save_at then
        save_at = nil
        save()
    end
    if now >= next_tick then
        next_tick = now + config.poll_ms
        tick()
    end
    step_auto(now)
    step_fix(now)
    render(now)
    overlay.animate(now)
end

overlay.init(config.overlay)
pcall(check_build)
-- Registered last, so everything above is ready when the first frame runs.
LoopInGameThreadWithDelay(0, function()
    guarded("frame", frame)
end)
log("loaded")
