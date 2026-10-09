-- G1LockPickHelper internals. The player's settings (language, keys, look, size, position) live in settings.ini
-- in the mod folder, written on the first start (settings.lua); the texts in lang/<id>.lua. After editing this
-- file: Ctrl+R (UE4SS hot reload) or restart the game.
return {
    poll_ms = 50,            -- how often the plates are read while a minigame is open
    ready_delay_ms = 2000,   -- the game ignores presses right after the minigame opens; no hint before this
    ready_frames = 30,       -- and at least this many frames since the start (a loading freeze stops frames, not the clock)
    grace_ms = 1200,         -- how long a move may stay invisible before the game is believed
    prepare_chunk = 20000,   -- solver states per tick while preparing a lock (spreads ~1 s over ticks)
    save_delay_ms = 1000,    -- settings.ini is written this long after the last change from the menu
    preview_ms = 5000,       -- how long the menu's example hint stays
    toggle_note_ms = 1500,   -- how long the on/off note stays after the toggle key
    language_poll_ms = 2000, -- how often the game's language is read while settings.ini [general] language = auto
    solve_ws_gap_ms = 60,    -- autosolver: pause after its W/S
    solve_timeout_ms = 2500, -- autosolver: stops when its A/D does not show on the plates in this time
    solve_max_replans = 3,   -- autosolver: stops after this many hint replans in a row (model and game disagree)
    solve_early_ms = 5000,   -- autosolver: F3 outside a minigame arms the one that opens within this time (the hero sits down first)
    double_reset_ms = 500,   -- two resets of the player within this time start the autosolver ([solve] double_reset)
    fix_smm_input = true,    -- after a minigame hand the input back to the game (Shared Mod Menu leaves it on its UI)
    smm_fix = { settle_ms = 200, settle_frames = 5, window_ms = 10000 }, -- input_fix.lua: the cursor hidden this long
                             -- and this many frames in a row, within window_ms after the minigame closed
    overlay = {
        -- Placement in fractions of the screen, so it works on any aspect ratio (16:9, 21:9 ultrawide):
        -- the hint's `pivot` point (fractions of the hint box) sits at `anchor` (fractions of the screen),
        -- shifted by settings.ini offset_x/offset_y (UI units; default: 760 left of the right edge - the game
        -- draws the lock at a fixed UI distance from that edge on every aspect ratio, checked on 21:9 and 16:9).
        anchor = { X = 1.0, Y = 0.45 },
        pivot = { X = 1.0, Y = 0.5 },
        z_order = 100,
        base_font_size = 26, -- letter size at scale 100 %
        icon_scale = 1.15,   -- a gamepad icon is a square of the letter size times this (pad.lua, [hint] icons)
        plate_alpha = 0.45,  -- the dark plate under the tape (settings.ini [tape] plate)
        slide_ms = 120,      -- tape slide after a press
        shake_ms = 300,      -- shake after a miss
        shake_px = 8,        -- shake amplitude at scale 100 %
        -- Game fonts; a missing font falls back to the engine font.
        fonts = {
            simple = { path = "/Game/UI/Fonts/Boucherie-Block_Font.Boucherie-Block_Font", typeface = "Default" },
            gothic = { path = "/Game/UI/Fonts/NotoSerif-Regular_Font.NotoSerif-Regular_Font", typeface = "Bold" },
            text = { path = "/Game/UI/Fonts/NotoSerif-Regular_Font.NotoSerif-Regular_Font", typeface = "Default" },
        },
        colors = {
            done = { R = 0.43, G = 0.78, B = 0.37, A = 1.0 },
            miss = { R = 0.92, G = 0.29, B = 0.24, A = 1.0 },
            message = { R = 1.0, G = 0.55, B = 0.35, A = 1.0 },
            counter = { R = 0.84, G = 0.59, B = 0.43, A = 1.0 },
            -- outline of the dark plate: the gold of the gothic frame
            plate_frame = { R = 1.0, G = 0.78, B = 0.1, A = 1.0 },
            -- simple: the key looks like a key in the game's key binding menu (dark box, beige frame)
            simple = {
                current = { R = 0.95, G = 0.86, B = 0.78, A = 1.0 },
                next = { R = 0.95, G = 0.86, B = 0.78, A = 1.0 },
                frame = { R = 0.91, G = 0.76, B = 0.65, A = 1.0 },
                fill = { R = 0.07, G = 0.07, B = 0.07, A = 1.0 },
            },
            -- gothic: a golden letter in a golden frame
            gothic = {
                current = { R = 1.0, G = 0.78, B = 0.1, A = 1.0 },
                next = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 },
                frame = { R = 1.0, G = 0.78, B = 0.1, A = 1.0 },
                fill = { R = 0.0, G = 0.0, B = 0.0, A = 0.0 },
            },
        },
    },
}
