-- Offline test of main.lua against a fake UE4SS and a fake minigame. Run from repo root: lua tests/main_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local solver = require("solver")
local t = require("testlib")
local test, eq, str = t.test, t.eq, t.str
local config = require("config")
local settings = require("settings")
local EN, EN_INI = require("lang.en").text, require("lang.en").ini
local RU, RU_INI = require("lang.ru").text, require("lang.ru").ini

local db = dofile("mod/G1LockPickHelper/Scripts/lockgraphs.lua")
local LOCKS = require("lockdb").new(db)
-- Model key -> the minigame task's input function, as main.lua hooks them.
local NATIVE = { W = "UpPressed", S = "DownPressed", A = "LeftPressed", D = "RightPressed", R = "ResetPressed" }
local HOOK = "/Script/G1R.AbilityTask_LockPick:"
local HOLE_DX = { -18.50, -12.20, -6.10, 0.00, 6.30, 12.50, 18.70 }
local READY_MS = 2500 -- the fake game ignores presses this long after the minigame opens
local ANIM_MS = 700   -- plates of a move are between holes this long
local FRAME_MS = 10   -- the loop runs every frame

local env -- state of the current test: clock, keybinds, loop, game, overlay calls

local function object(fields)
    fields.IsValid = function(self) return not self.dead end
    return fields
end

-- Fake minigame of `lock` (lockgraphs name) starting at `start` with the cursor on plate 1. Like the game it
-- drops the first `removed` connections of the lock (the player's lockpick skill; nil: none).
local function new_game(lock, start, removed)
    local graph = LOCKS.find(lock, removed) or { plates = #start, links = {} }
    local game = {
        ctx = solver.prepare(graph), pos = { table.unpack(start) }, cursor = 1, strains = 0,
        opened = env.now, moving = {}, anim_end = -1, inputs = {},
    }
    function game.press(key)
        if game.swallow or env.now - game.opened < READY_MS then return end -- not ready (or told to): swallowed
        if key == "R" then return end
        local p, c = solver.apply(game.ctx, game.pos, game.cursor, key)
        if not p then
            game.strains = game.strains + 1
            return
        end
        for i = 1, #p do game.moving[i] = p[i] ~= game.pos[i] or nil end
        if key == "A" or key == "D" then game.anim_end = env.now + ANIM_MS end
        game.pos, game.cursor = p, c
    end
    local function piece(i)
        local dx = 0
        if i <= #game.pos then
            dx = HOLE_DX[game.pos[i]]
            if game.moving[i] and env.now < game.anim_end then dx = dx - 2.0 end
        end
        return {
            m_Plate = object({ bHidden = i > #game.pos, m_RuntimeRootComponent = object({ RelativeLocation = { X = dx } }) }),
            m_Bar = object({ m_RuntimeRootComponent = object({ RelativeLocation = { X = 0 } }) }),
        }
    end
    local pieces = {
        ForEach = function(_, fn)
            env.reads = env.reads + 1
            for i = 1, 7 do fn(i, { get = function() return piece(i) end }) end
        end,
    }
    env.subsystem = object({ m_LockSceneActor = object({ m_LockPieceData = pieces }) })
    game.task = object({ Ability = object({ m_Lock = { ToString = function() return lock end } }) })
    -- The task's input functions: the game calls them for the player's presses (keyboard or gamepad), the
    -- autosolver calls them itself; a registered hook fires inside the call, as in UE4SS.
    for key, native in pairs(NATIVE) do
        game.task[native] = function()
            game.inputs[#game.inputs + 1] = key
            local hook = env.hooks[HOOK .. native]
            if hook then hook() end
            game.press(key)
        end
    end
    return game
end

local real_print = print

local SETTINGS_PATH = "mod/G1LockPickHelper/settings.ini" -- main.lua derives it from its own path
-- Settings of most tests: the detailed log on; lines that hold the whole sequence, one token per key (no runs).
local LINES_INI = "[general]\ndebug = true\n[hint]\nlayout = lines\n[lines]\nper_line = 40\nmax_lines = 12\ncollapse_min = 0\n"
local real_io, real_loadfile = io, loadfile

-- In-memory io for settings.ini (main.lua reads and writes it through the global io).
local function fake_io(files, opened)
    return {
        open = function(path, mode)
            opened[#opened + 1] = path
            if mode:find("r") then
                local content = files[path]
                if content == nil then return nil, path .. ": No such file or directory" end
                return { read = function() return content end, close = function() return true end }
            end
            local parts = {}
            return {
                write = function(self, s) parts[#parts + 1] = s return self end,
                close = function() files[path] = table.concat(parts) return true end,
            }
        end,
    }
end

-- ini: settings.ini content (nil: LINES_INI, false: no file); opts.menu: Shared Mod Menu installed;
-- opts.chunkname: load main.lua under that chunk name (one without a file path: it cannot find its folder);
-- opts.unknown_keys: { name = true } for key names missing from the fake Key table;
-- opts.hooks == false: this UE4SS build has no RegisterHook; opts.failing_hook: the input function RegisterHook
-- cannot find; opts.precision: the player's LockpickPrecision (nil: no attribute set; env.precision changes it).
-- opts.culture: the game's culture ("ru", "en", ...; nil: unreadable); opts.ue4ss: UE4SS.GetVersion exists.
-- opts.pad: { input_type, button_graphics, gamepad_name } of CommonInputSubsystem and the game's settings (nil: no
-- such objects; env.pad changes them); opts.cursor: a player controller with this bShowMouseCursor (env.cursor);
-- opts.pc: a player controller even when cursor is nil (its bShowMouseCursor reads nil); env.finds[class]: how
-- many times FindFirstOf looked for it. opts.widgets: what FindAllOf("UserWidget") returns (user_widget below;
-- "error": it raises); env.widget_scans counts the calls.
local function load_main(ini, opts)
    opts = opts or {}
    env = {
        now = 0, binds = {}, calls = {}, logs = {}, configured = {}, frames = 0, reads = 0, files = {}, opened = {},
        hooks = {}, precision = opts.precision, icons = {}, game_only = {}, pad = opts.pad, pad_reads = 0,
        has_pc = opts.cursor ~= nil or opts.pc, cursor = opts.cursor, finds = {}, widgets = opts.widgets,
        widget_scans = 0,
    }
    if ini == nil then ini = LINES_INI end
    if ini then env.files[SETTINGS_PATH] = ini end
    io = fake_io(env.files, env.opened)
    loadfile = function(path)
        if opts.menu and path == "mod/SharedModMenu/Scripts/modmenu.lua" then
            return function()
                return {
                    VERSION = 3,
                    register = function(name, spec) env.menu = { name = name, spec = spec } end,
                    requestRefresh = function() env.refreshed = (env.refreshed or 0) + 1 end,
                }
            end
        end
        return nil, path .. ": No such file or directory"
    end
    print = function(s, ...)
        if type(s) == "string" and s:find("^%[G1LockPickHelper%]") then
            env.logs[#env.logs + 1] = s
        else
            real_print(s, ...)
        end
    end
    local unknown = opts.unknown_keys or {} -- key names this UE4SS build does not know
    Key = setmetatable({}, { __index = function(_, k) if not unknown[k] then return "KEY_" .. k end end })
    RegisterKeyBind = function(key, fn) env.binds[key] = fn end
    if opts.hooks == false then
        RegisterHook = nil
    else
        RegisterHook = function(path, fn)
            if opts.failing_hook and path == HOOK .. opts.failing_hook then error("no UFunction " .. path) end
            env.hooks[path] = fn
            return 1, 2
        end
    end
    ExecuteInGameThread = function() error("ExecuteInGameThread must not be used") end
    LoopAsync = function() error("LoopAsync must not be used") end
    ExecuteWithDelay = function() error("ExecuteWithDelay must not be used") end
    LoopInGameThreadWithDelay = function(delay, fn)
        env.loop_delay, env.loop = delay, fn
        return 1
    end
    NotifyOnNewObject = function(_, fn) env.notify = fn end
    FindFirstOf = function(name)
        env.finds[name] = (env.finds[name] or 0) + 1
        if name == "LockPickSubsystem" then return env.subsystem end
        if name == "AttributeSet_Lockpicking" and env.precision then
            return object({ LockpickPrecision = { BaseValue = env.precision, CurrentValue = env.precision } })
        end
        if name == "CommonInputSubsystem" and env.pad then
            return object({
                GetCurrentInputType = function()
                    env.pad_reads = env.pad_reads + 1
                    return env.pad.input_type
                end,
                GetCurrentGamepadName = function()
                    return { ToString = function() return env.pad.gamepad_name end }
                end,
            })
        end
        if name == "GothicGameUserSettings" and env.pad then
            return setmetatable(object({}), { __index = function(_, k)
                if k == "ButtonGraphics" then return env.pad.button_graphics end
            end })
        end
        if name == "PlayerController" and env.has_pc then
            -- One controller until a test drops it (env.pc = nil; mark it dead first): the next find makes a new one.
            env.pc = env.pc or setmetatable(object({ name = "pc" }), { __index = function(_, k)
                if k == "bShowMouseCursor" then return env.cursor end
            end })
            return env.pc
        end
    end
    FindAllOf = function(name)
        if name ~= "UserWidget" then return nil end
        env.widget_scans = env.widget_scans + 1
        if env.widgets == "error" then error("FindAllOf failed") end
        return env.widgets
    end
    -- The game's culture (KismetInternationalizationLibrary); env.culture changes it, nil: unreadable.
    env.culture, env.culture_reads = opts.culture, 0
    StaticFindObject = function(path)
        if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then
            return object({ SetInputMode_GameOnly = function(_, pc, flush)
                env.game_only[#env.game_only + 1] = { pc = pc, flush = flush }
            end })
        end
        if path ~= "/Script/Engine.Default__KismetInternationalizationLibrary" or not env.culture then return nil end
        return object({ GetCurrentCulture = function()
            env.culture_reads = env.culture_reads + 1
            return { ToString = function() return env.culture end }
        end })
    end
    UE4SS = opts.ue4ss and { GetVersion = function() return 3, 0, 1 end } or nil
    os.clock = function() return env.now / 1000 end
    package.loaded["overlay"] = {
        init = function() end,
        configure = function(v) env.configured[#env.configured + 1] = v end,
        set_icons = function(mode) env.icons[#env.icons + 1] = mode end,
        show = function(model, now) env.calls[#env.calls + 1] = { "show", model = model, now = now } end,
        message = function(text) env.calls[#env.calls + 1] = { "message", text = text } end,
        hide = function() env.calls[#env.calls + 1] = { "hide" } end,
        animate = function() env.frames = env.frames + 1 end,
    }
    -- Timings the assertions below rely on, independent of the shipped defaults.
    config.poll_ms, config.ready_delay_ms, config.grace_ms, config.ready_frames = 50, 3000, 1200, 30
    if opts.chunkname then
        local f = real_io.open("mod/G1LockPickHelper/Scripts/main.lua", "rb")
        local source = f:read("a")
        f:close()
        assert(load(source, opts.chunkname))()
    else
        dofile("mod/G1LockPickHelper/Scripts/main.lua")
    end
end

local function open(lock, start, removed)
    env.game = new_game(lock, start, removed)
    env.notify(env.game.task)
    return env.game
end

local function run(ms)
    local stop = env.now + ms
    while env.now < stop do
        env.now = env.now + FRAME_MS
        env.loop()
    end
end

-- The player presses a minigame key: the game calls the task's input function (the hooks see it), and the
-- key bind fires where the key is bound (only without hooks).
local function press(key)
    local task = env.game.task
    task[NATIVE[key]](task)
    local bind = env.binds["KEY_" .. key]
    if bind then bind() end
end

local function last()
    return env.calls[#env.calls] or {}
end

-- The rest of the plan in a lines model (one token per key): the current key and the keys after it.
local function plan(call)
    local out, on = {}, false
    for _, line in ipairs(call.model.lines) do
        for _, tok in ipairs(line) do
            if tok.role == "current" then on = true end
            if on then out[#out + 1] = tok.text end
        end
    end
    return out
end

local function current(call)
    return plan(call)[1]
end

local DIGGER, DIGGER_START = "OC_Chest_Digger526_Lock", { 7, 7, 6, 4, 7 }

test("the loop runs every frame and the overlay gets the settings first", function()
    load_main()
    eq(env.loop_delay, 0, "loop delay")
    run(FRAME_MS)
    eq(#env.configured, 1, "configured once")
    eq(env.configured[1].hint.layout, "lines", "settings passed")
    eq(env.frames, 1, "animate called every frame")
end)

test("hint appears after the ready delay and opens the lock", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(2900)
    eq(#env.calls, 0, "overlay calls before ready")
    run(300)
    eq(last()[1], "show", "call")
    local keys = solver.solve(game.ctx, DIGGER_START, 1)
    eq(str(plan(last())), str(keys), "keys")
    eq(last().model.counter, "0/" .. #keys, "counter")
    local presses = 0
    while last()[1] == "show" do
        press(current(last()))
        run(800)
        presses = presses + 1
        if presses > 200 then error("lock not opened") end
    end
    eq(last()[1], "hide", "call after the lock opened")
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(game.strains, 0, "strains")
end)

test("a press is shown in the next frame", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    local total = #plan(last())
    press(current(last()))
    run(FRAME_MS)
    eq(last().model.counter, "1/" .. total, "counter after one frame")
end)

test("a wrong key is a miss", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    press(current(last()) == "W" and "S" or "W")
    run(FRAME_MS)
    eq(last().model.misses, 1, "misses")
end)

test("plates are read once per poll_ms, not every frame", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    local reads, frames = env.reads, env.frames
    run(500)
    eq(env.frames - frames, 50, "frames")
    if env.reads - reads > 11 then error("plates read " .. (env.reads - reads) .. " times in 500 ms") end
end)

test("unknown lock shows a message", function()
    load_main()
    open("Nope_Lock", { 4, 4, 4, 4 })
    run(100)
    eq(last().text, string.format(EN.not_in_db, "Nope_Lock"), "message")
end)

test("toggle key hides and shows the hint", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    eq(last()[1], "show", "hint shown")
    env.binds["KEY_F4"]()
    run(50)
    eq(last()[1], "message", "the note after the first toggle")
    eq(last().text, string.format(EN.hint_off, "F4"), "off note")
    run(config.toggle_note_ms)
    eq(last()[1], "hide", "hidden after the note")
    env.binds["KEY_F4"]()
    run(50)
    eq(last()[1], "message", "the note after the second toggle")
    eq(last().text, string.format(EN.hint_on, "F4"), "on note")
    run(config.toggle_note_ms)
    eq(last()[1], "show", "the hint is back after the note")
end)

test("a toggle outside a minigame shows the note and then hides it", function()
    load_main()
    run(100)
    eq(#env.calls, 0, "nothing shown")
    env.binds["KEY_F4"]()
    run(50)
    eq(last()[1], "message", "note")
    eq(last().text, string.format(EN.hint_off, "F4"), "off note")
    run(config.toggle_note_ms)
    eq(last()[1], "hide", "hidden after the note")
    env.binds["KEY_F4"]()
    run(50)
    eq(last().text, string.format(EN.hint_on, "F4"), "on note")
    run(config.toggle_note_ms)
    eq(last()[1], "hide", "hidden again")
end)

test("a failing overlay call during the note is not retried every frame", function()
    load_main()
    run(FRAME_MS)
    local messages = 0
    package.loaded["overlay"].message = function()
        messages = messages + 1
        error("the widget is gone")
    end
    env.binds["KEY_F4"]()
    run(FRAME_MS * 5)
    eq(messages, 1, "message calls in the first frames")
    run(config.toggle_note_ms)
    eq(messages, 1, "no message calls after the failure")
end)

test("W pressed before the hint parks the cursor", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(1000)
    press("W") -- the game is not ready and swallows it
    run(2200)
    eq(str(plan(last())), "S S S S " .. str(solver.solve(game.ctx, DIGGER_START, 1)), "keys")
end)

test("closing the minigame hides the hint", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    eq(last()[1], "show", "hint shown")
    game.task.Ability.dead = true
    run(100)
    eq(last()[1], "hide", "call")
    local calls = #env.calls
    run(500)
    eq(#env.calls, calls, "no calls after the session ended")
end)

test("plate count different from the database shows a message", function()
    load_main()
    open(DIGGER, { 7, 7, 6, 4 })
    run(3200)
    eq(last().text, EN.bad_state, "message")
end)

test("seven-plate lock is prepared over several ticks", function()
    load_main()
    local name
    for n, g in pairs(db.locks) do
        if g.plates == 7 then name = n break end
    end
    local start = { 1, 2, 3, 4, 5, 6, 7 }
    local game = open(name, start)
    local keys = solver.solve(game.ctx, start, 1)
    run(3200)
    eq(last()[1], keys and "show" or "message", "call")
    if keys then eq(str(plan(last())), str(keys), "keys") end
    local prepared
    for _, line in ipairs(env.logs) do
        local ms = line:match("solver ready after (%d+) ms")
        if ms then prepared = tonumber(ms) end
    end
    if not prepared or prepared < 100 then error("prepare finished in one tick: " .. tostring(prepared)) end
end)

test("a partial plate reading never counts as solved", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    eq(last()[1], "show", "hint shown")
    game.pos = { 4, 4, 4, 4 } -- one plate missing from the reading
    run(300)
    eq(last()[1], "show", "still the hint")
end)

test("solver cache keeps the two most recently used locks", function()
    load_main()
    local real, calls = solver.prepare, 0
    solver.prepare = function(...)
        if coroutine.isyieldable() then calls = calls + 1 end -- count only main's (it prepares inside a coroutine)
        return real(...)
    end
    local function visit(lock, start)
        local game = open(lock, start)
        run(3200)
        game.task.Ability.dead = true
        run(100)
    end
    local ok, err = pcall(function()
        visit("OC_Chest_Digger526_Lock", { 7, 7, 6, 4, 7 })
        visit("OC_Chest_Shadow316_Lock", { 3, 4, 2, 3, 1 })
        visit("OC_Chest_Digger526_Lock", { 7, 7, 6, 4, 7 })
        visit("OC_Chest_Digger514_Lock", { 7, 7, 3, 5 })
        visit("OC_Chest_Digger526_Lock", { 7, 7, 6, 4, 7 })
    end)
    solver.prepare = real
    if not ok then error(err, 0) end
    eq(calls, 3, "prepares (Digger526 stays cached: used after Shadow316)")
end)

test("key binds only record presses; the game-thread loop handles them", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    local calls = #env.calls
    env.binds["KEY_F4"]()
    eq(#env.calls, calls, "nothing happens on the key-bind thread")
    run(50)
    eq(last()[1], "message", "handled by the loop")
    eq(last().text, string.format(EN.hint_off, "F4"), "the note")
    run(config.toggle_note_ms)
    eq(last()[1], "hide", "hidden after the note")
end)

test("presses while no minigame is open are ignored", function()
    load_main()
    env.hooks[HOOK .. "UpPressed"]()
    env.hooks[HOOK .. "LeftPressed"]()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    eq(str(plan(last())), str(solver.solve(game.ctx, DIGGER_START, 1)), "hint starts from plate 1 (no parking)")
end)

test("without LoopInGameThreadWithDelay the mod stays inactive", function()
    env = { now = 0, binds = {}, calls = {}, logs = {}, configured = {}, frames = 0, reads = 0 }
    LoopInGameThreadWithDelay = nil
    NotifyOnNewObject = function(_, fn) env.notify = fn end
    RegisterKeyBind = function(key, fn) env.binds[key] = fn end
    dofile("mod/G1LockPickHelper/Scripts/main.lua")
    eq(env.notify, nil, "no minigame hook")
    local found = false
    for _, line in ipairs(env.logs) do
        if line:find("stays inactive") then found = true end
    end
    eq(found, true, "error logged")
end)

local function menu_item(name)
    for _, section in ipairs(env.menu.spec) do
        for _, it in ipairs(section.items) do
            if it.name == name then return it end
        end
    end
    error("no menu item " .. name)
end

local function logged(text)
    for _, line in ipairs(env.logs) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function count_logged(text)
    local n = 0
    for _, line in ipairs(env.logs) do
        if line:find(text, 1, true) then n = n + 1 end
    end
    return n
end

local ITEMS = EN.menu.items

test("a missing settings.ini is written on the first frame, in the resolved language", function()
    load_main(false)
    eq(env.files[SETTINGS_PATH], nil, "not written while loading")
    run(FRAME_MS)
    eq(env.files[SETTINGS_PATH], settings.serialize(settings.defaults(), EN_INI), "file")
    eq(logged("created"), true, "logged")
end)

test("the default hint is the tape", function()
    load_main(false)
    open(DIGGER, DIGGER_START)
    run(3200)
    eq(last().model.kind, "tape", "kind")
    eq(#last().model.cells, 9, "cells")
end)

test("settings problems are logged", function()
    load_main("[tape]\nnext = 50\n")
    eq(logged("out of range"), true, "logged")
end)

test("keys come from settings.ini: labels with hooks, key binds without", function()
    load_main(LINES_INI .. "[keys]\nW = UP\nS = DOWN\nA = LEFT\nD = RIGHT\ntoggle = F5\n")
    eq(env.binds["KEY_F5"] ~= nil, true, "toggle on F5")
    eq(env.binds["KEY_UP"], nil, "with hooks the minigame keys are not bound")
    eq(env.binds["KEY_W"], nil, "nor the default ones")
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    local labels = { W = "UP", S = "DOWN", A = "LEFT", D = "RIGHT" }
    local expected = {}
    for i, k in ipairs(solver.solve(game.ctx, DIGGER_START, 1)) do expected[i] = labels[k] end
    eq(str(plan(last())), str(expected), "the hint shows the labels")
    load_main("[keys]\nW = UP\n", { hooks = false })
    eq(env.binds["KEY_UP"] ~= nil, true, "without hooks W is bound to UP")
    eq(env.binds["KEY_W"], nil, "W key not bound")
end)

test("without Shared Mod Menu the mod works on settings.ini alone", function()
    load_main()
    eq(logged("Shared Mod Menu not found"), true, "logged")
    open(DIGGER, DIGGER_START)
    run(3200)
    eq(last()[1], "show", "hint")
end)

test("a menu change reaches the overlay at once and settings.ini a second later", function()
    load_main(nil, { menu = true })
    eq(env.menu.name, EN.menu.name, "registered")
    run(FRAME_MS)
    eq(#env.configured, 1, "configured at start")
    menu_item(ITEMS.scale).set(120)
    run(FRAME_MS)
    eq(#env.configured, 2, "configured again")
    eq(env.configured[2].hint.scale, 120, "new scale")
    eq(env.files[SETTINGS_PATH]:find("scale = 120", 1, true), nil, "not saved yet")
    run(config.save_delay_ms)
    eq(env.files[SETTINGS_PATH]:find("scale = 120", 1, true) ~= nil, true, "saved")
end)

test("the menu's Keys tab shows the configured keys", function()
    load_main(nil, { menu = true })
    eq(#env.menu.spec, 6, "sections")
    eq(env.menu.spec[6].title, EN.menu.sections.keys, "title")
    eq(env.menu.spec[6].items[1].name, string.format(ITEMS.key_toggle, "F4"), "default toggle key")
    eq(env.menu.spec[6].items[2].name, string.format(ITEMS.key_solve, "F3"), "default solve key")
    eq(env.menu.spec[6].items[3].name, string.format(ITEMS.key_select, "W", "S"), "default W / S")
    load_main("[hint]\nlayout = lines\n[keys]\ntoggle = F5\n", { menu = true })
    eq(env.menu.spec[6].items[1].name, string.format(ITEMS.key_toggle, "F5"), "toggle key from settings.ini")
end)

test("the Keys tab marks a key UE4SS does not know", function()
    load_main("[keys]\nW = NOPE\ntoggle = F99\nsolve = F98\n",
        { menu = true, unknown_keys = { NOPE = true, F99 = true, F98 = true } })
    local missing = EN.menu.key_missing
    eq(env.menu.spec[6].items[1].name, string.format(ITEMS.key_toggle, string.format(missing, "F99")), "toggle")
    eq(env.menu.spec[6].items[2].name, string.format(ITEMS.key_solve, string.format(missing, "F98")), "solve")
    eq(env.menu.spec[6].items[3].name, string.format(ITEMS.key_select, string.format(missing, "NOPE"), "S"), "W")
    eq(env.menu.spec[6].items[4].name, string.format(ITEMS.key_shift, "A", "D"), "known keys stay plain")
end)

test("the menu's example is shown for preview_ms when no lock is open", function()
    load_main(nil, { menu = true })
    run(FRAME_MS)
    menu_item(ITEMS.preview).set(true)
    run(FRAME_MS)
    eq(last()[1], "show", "example shown")
    eq(last().model.misses, 1, "the example has a miss")
    run(config.preview_ms)
    eq(last()[1], "hide", "hidden after preview_ms")
end)

test("a UE error in the menu's example is logged once and stops the example", function()
    load_main(nil, { menu = true })
    run(FRAME_MS)
    local shows = 0
    package.loaded["overlay"].show = function()
        shows = shows + 1
        error("the widget is gone")
    end
    menu_item(ITEMS.preview).set(true)
    run(FRAME_MS * 5)
    eq(shows, 1, "show calls in the first frames")
    eq(count_logged("frame failed"), 1, "logged once, not every frame")
    run(config.preview_ms)
    eq(shows, 1, "no show calls after the failure")
    eq(count_logged("frame failed"), 1, "still logged once")
end)

test("without the mod folder settings.ini and the menu are not used, the defaults apply", function()
    load_main(false, { menu = true, chunkname = "=main.lua" })
    eq(count_logged("cannot find the mod folder"), 1, "one log line")
    eq(env.menu, nil, "no settings menu")
    for _, path in ipairs(env.opened) do
        eq(path:find("settings.ini", 1, true), nil, "settings.ini opened: " .. path)
    end
    eq(next(env.files), nil, "no file written")
    open(DIGGER, DIGGER_START)
    run(3200)
    eq(last().model.kind, "tape", "default layout")
    eq(#env.configured, 1, "configured once")
    eq(env.configured[1].hint.layout, "tape", "default settings")
    eq(count_logged("cannot find the mod folder"), 1, "still one log line")
end)

test("the example is not shown during a minigame", function()
    load_main(nil, { menu = true })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    menu_item(ITEMS.preview).set(true)
    run(FRAME_MS)
    eq(str(plan(last())), str(solver.solve(game.ctx, DIGGER_START, 1)), "the real hint")
end)

test("reset position restores the size and the offsets", function()
    load_main("[hint]\nlayout = lines\nscale = 150\noffset_x = 0\noffset_y = 40\n", { menu = true })
    menu_item(ITEMS.reset_position).set(true)
    run(config.save_delay_ms + FRAME_MS)
    local file = env.files[SETTINGS_PATH]
    eq(file:find("scale = 100", 1, true) ~= nil, true, "scale")
    eq(file:find("offset_x = -760", 1, true) ~= nil, true, "offset_x")
    eq(file:find("offset_y = 0", 1, true) ~= nil, true, "offset_y")
end)

test("minigame input comes through hooks on the task's input functions", function()
    load_main()
    for _, native in pairs(NATIVE) do
        eq(env.hooks[HOOK .. native] ~= nil, true, "hook " .. native)
    end
    for _, key in ipairs({ "W", "S", "A", "D", "R" }) do
        eq(env.binds["KEY_" .. key], nil, "no key bind for " .. key)
    end
end)

test("a press no key bind sees (a gamepad) moves the hint", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    local total = #plan(last())
    local task = env.game.task
    task[NATIVE[current(last())]](task) -- the game's own call, no key bind involved
    run(FRAME_MS)
    eq(last().model.counter, "1/" .. total, "counter")
    eq(last().model.misses, 0, "misses")
end)

test("without RegisterHook the keys from settings.ini are bound and open the lock", function()
    load_main(nil, { hooks = false })
    eq(logged("hooks unavailable"), true, "logged")
    for _, key in ipairs({ "W", "S", "A", "D", "R" }) do
        eq(env.binds["KEY_" .. key] ~= nil, true, "key bind for " .. key)
    end
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    local presses = 0
    while last()[1] == "show" do
        press(current(last()))
        run(800)
        presses = presses + 1
        if presses > 200 then error("lock not opened") end
    end
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(game.strains, 0, "strains")
end)

test("when one hook fails the key binds listen and the hooks that did register are ignored", function()
    load_main(nil, { failing_hook = "RightPressed" })
    eq(logged("RightPressed"), true, "logged")
    eq(env.hooks[HOOK .. "UpPressed"] ~= nil, true, "an earlier hook did register")
    eq(env.binds["KEY_W"] ~= nil, true, "W bound")
    open(DIGGER, DIGGER_START)
    run(3200)
    local total = #plan(last())
    press(current(last())) -- a registered hook fires and the key bind fires
    run(FRAME_MS)
    eq(last().model.counter, "1/" .. total, "counted once")
end)

local SHADOW, SHADOW_START = "OC_Chest_Shadow316_Lock", { 3, 4, 2, 3, 1 }

test("the hint plans on the graph without the connections the lockpick skill removes", function()
    load_main(nil, { precision = 1 })
    local game = open(SHADOW, SHADOW_START, 1)
    run(3200)
    local keys = solver.solve(game.ctx, SHADOW_START, 1)
    eq(#keys, 34, "34 keys at skill 1 (46 on the full graph)")
    eq(str(plan(last())), str(keys), "keys from the pruned graph")
    eq(logged("lock OC_Chest_Shadow316_Lock (5 plates, precision 1, 1 connections removed)"), true, "logged")
    local presses = 0
    while last()[1] == "show" do
        press(current(last()))
        run(800)
        presses = presses + 1
        if presses > 200 then error("lock not opened") end
    end
    eq(game.strains, 0, "strains")
    eq(str(game.pos), "4 4 4 4 4", "plates")
end)

test("an unreadable lockpick skill counts as 0 and is logged", function()
    load_main()
    local game = open(SHADOW, SHADOW_START)
    run(3200)
    eq(logged("lockpick skill: no lockpick skill, assuming 0"), true, "logged")
    eq(logged("precision unknown, 0 connections removed"), true, "lock line")
    eq(str(plan(last())), str(solver.solve(game.ctx, SHADOW_START, 1)), "keys from the full graph")
end)

test("the solver cache keys on the lock and the skill", function()
    load_main()
    local real, calls = solver.prepare, 0
    solver.prepare = function(...)
        if coroutine.isyieldable() then calls = calls + 1 end -- count only main's (it prepares inside a coroutine)
        return real(...)
    end
    local function visit(precision)
        env.precision = precision
        local game = open(SHADOW, SHADOW_START, precision and 1 or 0)
        run(3200)
        game.task.Ability.dead = true
        run(100)
    end
    local ok, err = pcall(function()
        visit(nil)
        visit(1)
        visit(nil)
    end)
    solver.prepare = real
    if not ok then error(err, 0) end
    eq(calls, 2, "prepares: skill 0 and skill 1; skill 0 again comes from the cache")
end)

local function lock_open(game)
    for _, p in ipairs(game.pos) do
        if p ~= 4 then return false end
    end
    return true
end

-- Runs frames until the fake lock is open (then until the last move has finished animating and the mod has
-- seen the open lock) or `ms` passed.
local function run_until_open(game, ms)
    local stop = env.now + ms
    while env.now < stop and not lock_open(game) do run(FRAME_MS) end
    run(ANIM_MS + 300)
end

test("F3 opens the lock: the autosolver presses the hint without strain", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    local keys = solver.solve(game.ctx, DIGGER_START, 1)
    env.binds["KEY_F3"]()
    run(FRAME_MS * 2)
    eq(last().model.counter, EN.solving, "the counter says the autosolver runs")
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(game.strains, 0, "strains")
    eq(str(game.inputs), str(keys), "pressed exactly the hint")
    eq(last()[1], "hide", "the hint is gone")
    eq(logged("autosolve stopped"), false, "no stop")
    eq(logged("autosolve: lock opened"), true, "logged")
end)

test("F3 again stops the autosolver; the hint stays", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    local total = #solver.solve(game.ctx, DIGGER_START, 1)
    env.binds["KEY_F3"]()
    run(1500)
    local pressed = #game.inputs
    eq(pressed > 0, true, "it pressed")
    env.binds["KEY_F3"]()
    run(3000)
    eq(#game.inputs, pressed, "no presses after the second F3")
    eq(last()[1], "show", "the hint")
    eq(last().model.counter, string.format("%d/%d", pressed, total), "the counter is back")
end)

test("F3 before the minigame is ready waits for the lock, then solves it", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(500)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, EN.solve_armed, "waiting")
    eq(#game.inputs, 0, "nothing pressed before the game is ready")
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(game.strains, 0, "strains")
end)

test("with [solve] auto every lock is solved as it opens", function()
    load_main(LINES_INI .. "[solve]\nauto = true\n")
    local game = open(DIGGER, DIGGER_START)
    eq(last().text, EN.solve_armed, "armed at the start")
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(game.strains, 0, "strains")
end)

test("the menu's auto switch arms the autosolver for the next lock", function()
    load_main(nil, { menu = true })
    menu_item(ITEMS.solve_auto).set(true)
    run(FRAME_MS)
    local game = open(DIGGER, DIGGER_START)
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "plates")
end)

test("a player press stops the autosolver and the hint follows the player", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F3"]()
    run(1500)
    local pressed = #game.inputs
    press(current(last()))
    run(FRAME_MS)
    eq(logged("autosolve: cancelled by a player press"), true, "logged")
    run(3000)
    eq(#game.inputs, pressed + 1, "only the player's press after it")
    eq(last()[1], "show", "the hint stays")
    eq(game.strains, 0, "strains")
end)

test("presses the game swallows stop the autosolver with a note", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.swallow = true
    env.binds["KEY_F3"]()
    local noted = false
    for _ = 1, 1000 do
        run(FRAME_MS)
        if last()[1] == "message" and last().text == EN.solve_stopped then
            noted = true
            break
        end
    end
    eq(noted, true, "note shown")
    eq(logged("autosolve stopped: replans"), true, "logged")
    eq(str(game.pos), str(DIGGER_START), "nothing moved")
    run(config.toggle_note_ms)
    eq(last()[1], "show", "the hint after the note")
end)

test("with the hint hidden the autosolver solves with a short note only", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F4"]()
    run(config.toggle_note_ms + 50)
    eq(last()[1], "hide", "hidden")
    local calls = #env.calls
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, string.format(EN.solve_on, "F3"), "the note")
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(#env.calls, calls + 2, "the note and its end only")
    eq(last()[1], "hide", "hidden")
end)

test("F3 again with the hint hidden notes the stop", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F4"]()
    run(config.toggle_note_ms + 50)
    env.binds["KEY_F3"]()
    run(1000)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, string.format(EN.solve_off, "F3"), "the note")
    run(config.toggle_note_ms)
    eq(last()[1], "hide", "hidden again")
end)

test("an autosolver stop of its own is noted even with the hint hidden", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F4"]()
    run(config.toggle_note_ms + 50)
    for _, native in pairs(NATIVE) do game.task[native] = function() error("gone") end end
    env.binds["KEY_F3"]()
    run(FRAME_MS * 2)
    eq(last().text, EN.solve_stopped, "note")
end)

test("F3 outside a minigame with the hint hidden notes the wait", function()
    load_main()
    env.binds["KEY_F4"]()
    run(config.toggle_note_ms + 50)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, string.format(EN.solve_on, "F3"), "the note")
end)

test("a failing input call stops the autosolver with a note", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    for _, native in pairs(NATIVE) do game.task[native] = function() error("gone") end end
    env.binds["KEY_F3"]()
    run(FRAME_MS * 2)
    eq(last().text, EN.solve_stopped, "note")
    eq(logged("failed: "), true, "logged")
    eq(count_logged("autosolve stopped"), 1, "stopped once")
end)

test("a hook that does not fire for our own call stops the autosolver", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    local total = #solver.solve(game.ctx, DIGGER_START, 1)
    env.hooks = {} -- the fake task looks the hooks up on every call: from now on none fires
    env.binds["KEY_F3"]()
    run(FRAME_MS * 2)
    eq(logged("hook did not fire"), true, "logged")
    eq(#game.inputs, 1, "one press")
    run(config.toggle_note_ms)
    eq(last().model.counter, "1/" .. total, "the tracker still got that press")
end)

test("without hooks the autosolver stays off: F3 notes it, nothing is pressed", function()
    load_main(nil, { hooks = false })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, EN.solve_unavailable, "note")
    eq(logged("autosolver needs input hooks"), true, "logged")
    run(3000)
    eq(#game.inputs, 0, "nothing pressed")
    eq(last()[1], "show", "the hint after the note")
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(count_logged("autosolver needs input hooks"), 1, "logged once")
end)

test("without hooks [solve] auto does not arm either", function()
    load_main(LINES_INI .. "[solve]\nauto = true\n", { hooks = false })
    local game = open(DIGGER, DIGGER_START)
    eq(last().text, EN.solve_unavailable, "note at the start")
    run(6000)
    eq(#game.inputs, 0, "nothing pressed")
end)

test("the autosolver key comes from settings.ini", function()
    load_main(LINES_INI .. "[keys]\nsolve = F6\n")
    eq(env.binds["KEY_F6"] ~= nil, true, "F6 bound")
    eq(env.binds["KEY_F3"], nil, "F3 not bound")
end)

test("F3 just before a minigame opens arms it: the lock is solved", function()
    load_main()
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, EN.solve_armed, "waiting for the lock")
    eq(logged("autosolve: armed for the next minigame"), true, "logged")
    run(1500) -- the hero sits down
    local game = open(DIGGER, DIGGER_START)
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(game.strains, 0, "strains")
end)

test("F3 outside a minigame waits solve_early_ms; F3 again cancels", function()
    load_main()
    env.binds["KEY_F3"]()
    run(config.solve_early_ms + 50)
    eq(last()[1], "hide", "the wait is over")
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    eq(#game.inputs, 0, "a minigame after the wait is not solved")
    eq(last()[1], "show", "just the hint")
    game.task.Ability.dead = true
    run(100)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(logged("autosolve: the next minigame as set"), true, "cancelled")
    eq(last()[1], "hide", "no wait shown")
    game = open(DIGGER, DIGGER_START)
    run(3200)
    eq(#game.inputs, 0, "not solved after the cancel")
end)

test("F3 on a lock without a hint: autosolve unavailable, then the message again", function()
    load_main()
    open("Nope_Lock", { 4, 4, 4, 4 })
    run(100)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, EN.solve_unavailable, "note")
    eq(logged("autosolve unavailable: no hint for this lock"), true, "logged")
    run(config.toggle_note_ms)
    eq(last().text, string.format(EN.not_in_db, "Nope_Lock"), "the message is back")
end)

test("closing the minigame during an autosolve: no more calls into the task", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F3"]()
    run(4640) -- a W press is due in 10 ms; the poll that sees the close comes 50 ms later
    local pressed = #game.inputs
    game.task.Ability.dead = true
    run(500)
    eq(#game.inputs, pressed, "no presses after the minigame closed")
    eq(last()[1], "hide", "the hint is gone")
    eq(logged("autosolve stopped"), false, "closing is not a stop of its own")
end)

test("the menu's language switch changes the texts at once; settings.ini follows", function()
    load_main(nil, { menu = true })
    run(FRAME_MS)
    eq(env.menu.spec[1].title, EN.menu.sections.general, "English at first")
    menu_item(EN.menu.items.language).set(2)
    run(FRAME_MS)
    eq(env.menu.spec[1].title, RU.menu.sections.general, "the menu is Russian")
    eq(env.refreshed, 1, "the open menu re-reads it")
    eq(logged("language: ru"), true, "logged")
    env.binds["KEY_F4"]()
    run(FRAME_MS)
    eq(last().text, string.format(RU.hint_off, "F4"), "notes in Russian")
    run(config.save_delay_ms)
    local file = env.files[SETTINGS_PATH]
    eq(file:find("language = ru", 1, true) ~= nil, true, "saved")
    eq(file:find(RU_INI.header[1], 1, true) ~= nil, true, "Russian comments")
end)

test("[general] language = ru in settings.ini: Russian texts from the start", function()
    load_main(LINES_INI .. "[general]\nlanguage = ru\n")
    open("Nope_Lock", { 4, 4, 4, 4 })
    run(100)
    eq(last().text, string.format(RU.not_in_db, "Nope_Lock"), "message")
end)

test("with debug = false the detailed log is silent", function()
    load_main("[hint]\nlayout = lines\n")
    open(DIGGER, DIGGER_START)
    run(3200)
    eq(logged("tracking from"), false, "no detailed lines")
    eq(logged("lock OC_Chest_Digger526_Lock"), true, "the plain log stays")
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    eq(logged("tracking from"), true, "detailed lines with debug = true")
end)

test("auto takes the game's culture on the first frame", function()
    load_main(nil, { menu = true, culture = "ru-RU" })
    eq(env.menu.spec[1].title, EN.menu.sections.general, "English while loading (the culture is read on the game thread)")
    run(FRAME_MS)
    eq(env.menu.spec[1].title, RU.menu.sections.general, "Russian from the first frame")
    env.binds["KEY_F4"]()
    run(FRAME_MS)
    eq(last().text, string.format(RU.hint_off, "F4"), "notes in Russian")
end)

test("auto follows the game's language while playing", function()
    load_main(nil, { menu = true, culture = "en" })
    run(FRAME_MS)
    eq(env.menu.spec[1].title, EN.menu.sections.general, "English")
    env.culture = "ru"
    run(config.language_poll_ms + FRAME_MS)
    eq(env.menu.spec[1].title, RU.menu.sections.general, "Russian after the game's switch")
    eq(env.refreshed, 1, "the open menu re-reads it")
    eq(logged("language: ru"), true, "logged")
end)

test("one failed culture read keeps the last good language", function()
    load_main(nil, { menu = true, culture = "ru" })
    run(FRAME_MS)
    eq(env.menu.spec[1].title, RU.menu.sections.general, "Russian")
    env.culture = nil
    run(config.language_poll_ms * 2)
    eq(env.menu.spec[1].title, RU.menu.sections.general, "still Russian")
    eq(logged("language: en"), false, "no flip back")
end)

test("a set language ignores the culture, which is read once", function()
    load_main(LINES_INI .. "[general]\nlanguage = en\n", { culture = "ru" })
    run(config.language_poll_ms * 3)
    eq(env.culture_reads, 1, "read once, for the start line")
    env.binds["KEY_F4"]()
    run(FRAME_MS)
    eq(last().text, string.format(EN.hint_off, "F4"), "English")
end)

test("a missing settings.ini is written in the game's language", function()
    load_main(false, { culture = "ru" })
    run(FRAME_MS)
    eq(env.files[SETTINGS_PATH], settings.serialize(settings.defaults(), RU_INI), "Russian file")
end)

test("the start line tells the version, the game, the language, the hooks and UE4SS", function()
    load_main(nil, { culture = "ru", ue4ss = true })
    run(FRAME_MS)
    eq(logged(string.format("G1LockPickHelper 1.1.1: game unknown (lock db %s), language ru (auto, culture ru), "
        .. "input hooks yes, UE4SS 3.0.1", db.build)), true, "start line")
    load_main(nil, { hooks = false })
    run(FRAME_MS)
    eq(logged("language en (auto, culture unknown), input hooks no, UE4SS unknown"), true, "without them")
    run(5000)
    eq(count_logged("G1LockPickHelper 1.1.1:"), 1, "once")
end)

test("the hint waits for ready_frames frames even when the clock jumps (a loading freeze)", function()
    load_main()
    open(DIGGER, DIGGER_START)
    for _ = 1, 10 do
        env.now = env.now + 1000
        env.loop()
    end
    eq(#env.calls, 0, "nothing after 10 long frames")
    run(FRAME_MS * 25)
    eq(last()[1], "show", "the hint once enough frames passed")
end)

test("F3 on an opened lock: autosolve unavailable, nothing pressed", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F3"]()
    run_until_open(game, 60000)
    local pressed = #game.inputs
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, EN.solve_unavailable, "note")
    eq(logged("autosolve unavailable: the lock is already open"), true, "logged")
    run(1000)
    eq(#game.inputs, pressed, "no presses")
end)

test("the autosolver's text shows even with the counter off", function()
    load_main(LINES_INI .. "[hint]\ncounter = false\n")
    open(DIGGER, DIGGER_START)
    run(3200)
    eq(last().model.counter_always, nil, "the plain hint keeps the setting")
    env.binds["KEY_F3"]()
    run(FRAME_MS * 2)
    eq(last().model.counter, EN.solving, "text")
    eq(last().model.counter_always, true, "shown whatever the setting")
end)

test("an armed autosolver on a lock not in the database logs its stop", function()
    load_main(LINES_INI .. "[solve]\nauto = true\n")
    open("Nope_Lock", { 4, 4, 4, 4 })
    run(100)
    eq(logged("autosolve stopped: not_in_db"), true, "logged")
    eq(last().text, string.format(EN.not_in_db, "Nope_Lock"), "the message, no stop note")
end)

test("an armed autosolver on a lock with another plate count logs its stop", function()
    load_main(LINES_INI .. "[solve]\nauto = true\n")
    open(DIGGER, { 7, 7, 6, 4 })
    run(3200)
    eq(logged("autosolve stopped: bad_state"), true, "logged")
    eq(last().text, EN.bad_state, "the message")
end)

test("with [solve] auto F3 outside a minigame skips the next one; F3 twice goes back to the setting", function()
    load_main(LINES_INI .. "[solve]\nauto = true\n")
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, string.format(EN.solve_off, "F3"), "note: off")
    eq(logged("autosolve: the next minigame is skipped"), true, "logged")
    run(1000)
    local game = open(DIGGER, DIGGER_START)
    run(5000)
    eq(#game.inputs, 0, "the next minigame is not solved")
    eq(last()[1], "show", "just the hint")
    game.task.Ability.dead = true
    run(100)
    game = open(DIGGER, DIGGER_START)
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "the one after it is solved, as set")
    game.task.Ability.dead = true
    run(100)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    env.binds["KEY_F3"]()
    run(FRAME_MS)
    eq(last().text, string.format(EN.solve_on, "F3"), "note: back to auto-pick")
    eq(logged("autosolve: the next minigame as set"), true, "logged")
    game = open(DIGGER, DIGGER_START)
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "solved, as set")
end)

local function shows()
    local n = 0
    for _, c in ipairs(env.calls) do
        if c[1] == "show" then n = n + 1 end
    end
    return n
end

test("the hint draws the gamepad icons the game shows, letters on the keyboard", function()
    load_main(nil, { pad = { input_type = 0, button_graphics = 1, gamepad_name = "Generic" } })
    run(FRAME_MS)
    eq(#env.icons, 0, "keyboard: letters, nothing to change")
    env.pad.input_type = 1
    run(FRAME_MS)
    eq(env.icons[#env.icons], "xbox", "a gamepad, the game's Auto with a generic pad")
    env.pad.gamepad_name = "PS5"
    run(config.language_poll_ms + FRAME_MS)
    eq(env.icons[#env.icons], "ps", "Auto with a PS5 pad")
    env.pad.button_graphics = 4
    run(config.language_poll_ms + FRAME_MS)
    eq(env.icons[#env.icons], "switch", "the game's Switch option")
    env.pad.button_graphics = 0
    run(config.language_poll_ms + FRAME_MS)
    eq(env.icons[#env.icons], "keys", "'do not use': letters")
    env.pad.button_graphics = 2
    run(config.language_poll_ms + FRAME_MS)
    eq(env.icons[#env.icons], "xbox", "the Xbox option")
    env.pad.input_type = 0
    run(FRAME_MS)
    eq(env.icons[#env.icons], "keys", "back on the keyboard")
end)

test("[hint] icons = keys reads nothing and keeps the letters", function()
    load_main(LINES_INI .. "[hint]\nicons = keys\n", { pad = { input_type = 1, button_graphics = 3 } })
    run(3000)
    eq(#env.icons, 0, "letters")
    eq(env.pad_reads, 0, "the input type is not read")
end)

test("[hint] icons = gamepad and gamepad = playstation: PS icons on the keyboard too", function()
    load_main(LINES_INI .. "[hint]\nicons = gamepad\ngamepad = playstation\n",
        { pad = { input_type = 0, button_graphics = 2 } })
    run(FRAME_MS)
    eq(env.icons[#env.icons], "ps", "ps")
end)

test("without CommonInputSubsystem the hint keeps the letters", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    eq(last()[1], "show", "hint")
    eq(#env.icons, 0, "letters")
end)

test("a switch of the device redraws the shown hint", function()
    load_main(nil, { pad = { input_type = 0, button_graphics = 3 } })
    open(DIGGER, DIGGER_START)
    run(3200)
    local before = shows()
    env.pad.input_type = 1
    run(FRAME_MS)
    eq(env.icons[#env.icons], "ps", "icons")
    eq(shows(), before + 1, "shown again")
end)

test("a switch of the icons logs what it was decided from", function()
    load_main(nil, { pad = { input_type = 1, button_graphics = 1, gamepad_name = "PS5" } })
    run(FRAME_MS)
    eq(logged("icons: ps (input 1, option 1, pad PS5)"), true, "logged")
end)

test("a switch of the device reads the game's option and the pad name in the same frame", function()
    load_main(nil, { pad = { input_type = 0, button_graphics = 1, gamepad_name = "Generic" } })
    run(FRAME_MS * 3) -- the first poll is done; the next one is language_poll_ms away
    eq(#env.icons, 0, "keyboard: letters")
    env.pad.input_type, env.pad.gamepad_name = 1, "PS5"
    run(FRAME_MS)
    eq(#env.icons, 1, "one change, no stale set before it")
    eq(env.icons[1], "ps", "the new pad's set at once")
end)

test("a missing CommonInputSubsystem logs one line, 10 s after the first frame (config.pad_missing_log_ms)", function()
    load_main("[general]\ndebug = false\n")
    local text = "CommonInputSubsystem not found: the hint keeps the letters"
    run(9500)
    eq(count_logged(text), 0, "not yet")
    run(1000)
    eq(count_logged(text), 1, "logged (not only traced)")
    run(5000)
    eq(count_logged(text), 1, "once per load")
end)

test("no line about CommonInputSubsystem with [hint] icons = keys or when it is there", function()
    load_main("[general]\ndebug = false\n[hint]\nicons = keys\n")
    run(15000)
    eq(count_logged("CommonInputSubsystem"), 0, "icons = keys")
    load_main("[general]\ndebug = false\n", { pad = { input_type = 0, button_graphics = 1 } })
    run(15000)
    eq(count_logged("CommonInputSubsystem"), 0, "found")
end)

test("CommonInputSubsystem is looked for at most once a second", function()
    load_main()
    run(3500)
    local n = env.finds.CommonInputSubsystem
    eq(n ~= nil and n >= 1 and n <= 4, true, "FindFirstOf calls in 3.5 s: " .. tostring(n))
end)

test("two resets within double_reset_ms start the autosolver; it opens the lock", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    press("R")
    run(200)
    press("R")
    run(FRAME_MS * 2)
    eq(last().model.counter, EN.solving, "the autosolver runs")
    eq(logged("autosolve: double reset"), true, "logged")
    run_until_open(game, 60000)
    eq(str(game.pos), "4 4 4 4 4", "plates")
    eq(game.strains, 0, "strains")
end)

test("resets further apart do not start the autosolver", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    press("R")
    run(config.double_reset_ms + 100)
    press("R")
    local inputs = #game.inputs
    run(2000)
    eq(#game.inputs, inputs, "the autosolver presses nothing")
    eq(logged("autosolve: double reset"), false, "not logged")
end)

test("[solve] double_reset = false turns the double reset off", function()
    load_main(LINES_INI .. "[solve]\ndouble_reset = false\n")
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    press("R")
    run(100)
    press("R")
    local inputs = #game.inputs
    run(2000)
    eq(#game.inputs, inputs, "the autosolver presses nothing")
    eq(logged("autosolve: double reset"), false, "not logged")
end)

test("a reset that stops the autosolver starts no pair", function()
    load_main()
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F3"]()
    run(1000)
    press("R")
    run(100)
    press("R")
    local inputs = #game.inputs
    run(2000)
    eq(logged("autosolve: cancelled by a player press (R)"), true, "the first reset stopped it")
    eq(logged("autosolve: double reset"), false, "the second did not start it")
    eq(#game.inputs, inputs, "the autosolver presses nothing")
end)

test("a double reset with the hint hidden notes it", function()
    load_main()
    open(DIGGER, DIGGER_START)
    run(3200)
    env.binds["KEY_F4"]()
    run(config.toggle_note_ms + 50)
    press("R")
    run(100)
    press("R")
    run(FRAME_MS)
    eq(last().text, string.format(EN.solve_on, EN.double_reset), "the note")
end)

test("with Shared Mod Menu the input goes back to the game once the cursor hides after a minigame", function()
    load_main(nil, { menu = true, cursor = true })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    run(1200)
    eq(#env.game_only, 0, "not while the cursor is shown")
    env.cursor = false
    run(150)
    eq(#env.game_only, 0, "not before settle_ms")
    run(100)
    eq(#env.game_only, 1, "handed back")
    eq(env.game_only[1].flush, false, "held keys are not flushed")
    eq(env.game_only[1].pc.name, "pc", "the player controller")
    run(5000)
    eq(#env.game_only, 1, "once")
end)

-- A UMG widget for FindAllOf("UserWidget"): its name ("UserWidget_7": Shared Mod Menu's plain UserWidget,
-- "G1LPH_Overlay_…": ours), on screen or not (w.shown), and its class (default "UserWidget").
local function user_widget(name, shown, class)
    local w = object({ shown = shown })
    w.IsInViewport = function(self) return self.shown end
    w.GetFName = function() return { ToString = function() return name end } end
    w.GetClass = function()
        return { GetFName = function() return { ToString = function() return class or "UserWidget" end } end }
    end
    return w
end

-- A minigame with Shared Mod Menu installed that closes with the cursor hidden at once. widgets: what
-- FindAllOf("UserWidget") returns, from the minigame's start on.
local function close_hidden(widgets)
    load_main(nil, { menu = true, cursor = true, widgets = widgets })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    env.cursor = false
end

local HOLD = config.smm_fix.menu_hold_ms + 300 -- a closed menu: the hold runs out, then settle_ms

test("Shared Mod Menu opened after the minigame holds the input fix until it closes", function()
    local smm = user_widget("UserWidget_7", false)
    close_hidden({ smm })
    smm.shown = true
    run(3000)
    eq(#env.game_only, 0, "not under the open menu")
    eq(count_logged("input fix waits: UserWidget_7 is on screen"), 1, "traced once, with its name")
    eq(env.widget_scans <= 3000 / 400 + 2, true, "a check about every menu_hold_ms + settle_ms: " .. env.widget_scans)
    smm.shown = false
    run(HOLD)
    eq(#env.game_only, 1, "after it closed")
end)

test("no menu: one check when the minigame opens, one before the call", function()
    close_hidden({ user_widget("UserWidget_7", false) })
    run(300)
    eq(#env.game_only, 1, "handed back")
    eq(env.widget_scans, 2, "two checks")
end)

test("widgets on screen when the minigame opened, ours and the game's do not hold the input fix", function()
    close_hidden({ user_widget("UserWidget_2", true), user_widget("G1LPH_Overlay_1_1", true),
        user_widget("W_HUD_C_3", true, "W_HUD_C") })
    run(300)
    eq(#env.game_only, 1, "handed back")
end)

test("a menu opened right before the call holds it", function()
    local smm = user_widget("UserWidget_7", false)
    close_hidden({ smm })
    run(150)
    smm.shown = true
    run(100)
    eq(#env.game_only, 0, "checked right before the call")
    smm.shown = false
    run(HOLD)
    eq(#env.game_only, 1, "after it closed")
end)

test("a menu open longer than window_ms still gets the call after it closes", function()
    local smm = user_widget("UserWidget_7", false)
    close_hidden({ smm })
    smm.shown = true
    run(config.smm_fix.window_ms + 5000)
    eq(#env.game_only, 0, "held")
    smm.shown = false
    run(HOLD)
    eq(#env.game_only, 1, "after it closed")
end)

test("a menu open past hold_max_ms: the fix gives up, logged once with its name", function()
    local smm = user_widget("UserWidget_7", false)
    close_hidden({ smm })
    smm.shown = true
    run(config.smm_fix.hold_max_ms + 1000)
    smm.shown = false
    run(HOLD)
    eq(#env.game_only, 0, "no call")
    eq(count_logged("input fix gave up: UserWidget_7 stayed on screen"), 1, "logged once")
end)

test("a widget that cannot be read is skipped", function()
    local broken = user_widget("UserWidget_3", true)
    broken.IsValid = function() error("stale object") end
    local smm = user_widget("UserWidget_7", false)
    close_hidden({ broken, smm })
    smm.shown = true
    run(1000)
    eq(#env.game_only, 0, "the open menu still holds the fix")
    smm.shown = false
    run(HOLD)
    eq(#env.game_only, 1, "the unreadable widget does not")
end)

test("a failing widget check hands the input back as before, logged once", function()
    close_hidden("error")
    run(300)
    eq(#env.game_only, 1, "handed back")
    eq(count_logged("cannot check for Shared Mod Menu"), 1, "logged once")
end)

test("without Shared Mod Menu the input is left alone", function()
    load_main(nil, { cursor = true })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    env.cursor = false
    run(2000)
    eq(#env.game_only, 0, "no call")
end)

test("a cursor shown after the minigame through window_ms (a chest window) gets no call", function()
    load_main(nil, { menu = true, cursor = true })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    run(config.smm_fix.window_ms + 200)
    env.cursor = false
    run(1000)
    eq(#env.game_only, 0, "no call")
end)

test("[general] smm_fix = false turns the fix off", function()
    load_main(LINES_INI .. "[general]\nsmm_fix = false\n", { menu = true, cursor = true })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    env.cursor = false
    run(2000)
    eq(#env.game_only, 0, "no call")
    eq(logged("SMM input fix off"), true, "the start line says so")
end)

-- With Shared Mod Menu installed the minigame closes with the controller's cursor reading `opts` (load_main's
-- opts.cursor / opts.pc); 2 s later.
local function close_with_cursor(opts)
    opts.menu = true
    load_main(nil, opts)
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    run(2000)
end

test("a cursor that does not read as a boolean counts as shown: no call", function()
    close_with_cursor({ pc = true })
    eq(#env.game_only, 0, "nil")
    close_with_cursor({ cursor = 1 })
    eq(#env.game_only, 0, "1")
    close_with_cursor({ cursor = 0 })
    eq(#env.game_only, 0, "0")
end)

test("the input fix belongs to the controller of the close: a new one gets no call", function()
    load_main(nil, { menu = true, cursor = true })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    run(1200)
    eq(#env.game_only, 0, "the cursor is shown")
    env.pc.dead = true -- a level loads: the old controller is gone, the new one has its cursor hidden
    env.pc = nil
    env.cursor = false
    run(2000)
    eq(#env.game_only, 0, "no call for the new controller")
end)

test("no controller found at the close: the first one found is kept", function()
    load_main(nil, { menu = true, cursor = true })
    env.has_pc = false
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    run(1500)
    env.has_pc = true
    run(1500)
    eq(#env.game_only, 0, "found, the cursor is shown")
    env.cursor = false
    run(500)
    eq(#env.game_only, 1, "handed back through the one found")
    eq(env.game_only[1].pc, env.pc, "the controller")
end)

test("a minigame that opens within the window cancels the pending fix; its own close starts a new one", function()
    load_main(nil, { menu = true, cursor = true })
    local game = open(DIGGER, DIGGER_START)
    run(3200)
    game.task.Ability.dead = true
    run(500) -- closed, the cursor is still shown
    game = open(DIGGER, DIGGER_START)
    run(1000)
    env.cursor = false -- the first close's wait would hand the input back now
    run(500)
    eq(#env.game_only, 0, "not while the second minigame is open")
    env.cursor = true
    run(2200)
    game.task.Ability.dead = true
    run(1200)
    eq(#env.game_only, 0, "the second close: the cursor is shown")
    env.cursor = false
    run(400)
    eq(#env.game_only, 1, "one call, after the second close")
    run(5000)
    eq(#env.game_only, 1, "once")
end)

test("a settings.ini from 1.0 keeps working and stays as it is until a menu change rewrites it with the new keys", function()
    local old = "[general]\ndebug = true\n[hint]\nlayout = lines\n[solve]\nauto = false\n"
    load_main(old, { menu = true })
    run(config.save_delay_ms * 3)
    eq(env.files[SETTINGS_PATH], old, "not rewritten by the start")
    eq(env.configured[1].hint.icons, "auto", "icons: the default")
    eq(env.configured[1].hint.gamepad, "auto", "gamepad: the default")
    eq(env.configured[1].solve.double_reset, true, "double_reset: the default")
    menu_item(ITEMS.reset_position).set(true)
    run(config.save_delay_ms + FRAME_MS)
    local file = env.files[SETTINGS_PATH]
    for _, key in ipairs({ "hint.icons", "hint.gamepad", "solve.double_reset" }) do
        local name = key:match("%.(.+)$")
        eq(file:find(name .. " = ", 1, true) ~= nil, true, key .. " written")
        eq(file:find(EN_INI.comments[key], 1, true) ~= nil, true, key .. " with its comment")
    end
end)

test("the start line tells the icons and the Shared Mod Menu input fix", function()
    load_main(nil, { menu = true })
    run(FRAME_MS)
    eq(logged("UE4SS unknown, icons auto/auto, SMM input fix on"), true, "with Shared Mod Menu")
    load_main(LINES_INI .. "[hint]\nicons = gamepad\ngamepad = xbox\n")
    run(FRAME_MS)
    eq(logged("icons gamepad/xbox, SMM input fix off"), true, "without it")
end)

io, loadfile = real_io, real_loadfile
print = real_print
t.finish()
