-- English texts of G1LockPickHelper: the hint and its notes, Shared Mod Menu, the comments of settings.ini.
-- lang/ru.lua has exactly the same keys and format specifiers (tests/lang_test.lua). Another language needs a file
-- with these keys, and its id in i18n.resolve, the settings.lua choices, the menu.lua choices, the language hint
-- text (desc.language) and scripts/package.ps1.
return {
    text = {
        not_in_db = "Lock not in the database: %s",
        no_safe_path = "No safe solution",
        bad_state = "Cannot read the lock",
        hint_on = "Hint shown (%s)",                     -- after the toggle key; %s is the key name
        hint_off = "Hint hidden (%s)",
        solving = "Autosolving…",                        -- instead of the counter while the autosolver presses
        solve_armed = "Autosolve: waiting for the lock", -- F3 or auto-pick before the minigame is ready
        solve_stopped = "Autosolve stopped",             -- the autosolver stopped by itself (reason in UE4SS.log)
        -- F3 with nothing to solve or without input hooks; also a minigame that opens without them (auto-pick on)
        solve_unavailable = "Autosolve unavailable",
        -- F3 while the hint is hidden; also F3 outside a minigame with auto-pick on, hint shown or not. %s is the
        -- key name
        solve_on = "Autosolve on (%s)",
        solve_off = "Autosolve off (%s)",
        -- Shared Mod Menu (F2): mod tab, sections, item names and hints (menu.lua). The menu cuts item names after
        -- about 21 characters.
        menu = {
            name = "LockPick Helper",
            sections = {
                general = "General", view = "View", tape = "Tape", lines = "Lines", solve = "Auto", keys = "Keys",
            },
            key_missing = "%s (unknown)", -- a configured key name UE4SS does not know
            items = {
                language = "Language",
                tape = "Tape", gothic = "Gothic style", scale = "Size, %", offset_x = "Offset X",
                offset_y = "Offset Y", counter = "Counter", shake = "Shake on a miss",
                preview = "Show an example", reset_position = "Reset position",
                next = "Keys ahead", done = "Pressed keys shown", slide = "Slide", plate = "Plate",
                per_line = "Keys per line", max_lines = "Lines", collapse_min = "Collapse from",
                solve_auto = "Auto-pick",
                key_toggle = "%s: show/hide",
                key_solve = "%s: autosolve",
                key_select = "%s / %s: select plate",
                key_shift = "%s / %s: move plate",
            },
            desc = {
                language = "0 auto (game), 1 English, 2 Русский",
                keys = "change in settings.ini [keys], then restart the game",
                tape = "off: the whole sequence in lines",
                gothic = "off: simple",
                preview = "an example hint for 5 s",
                reset_position = "default size and offsets",
                collapse_min = "0: never collapse",
                solve_auto = "solve each lock as it opens",
            },
        },
    },
    -- settings.ini: the header and one comment per setting ("section.key"; the minigame keys S, A, D go without
    -- one, the comment of W covers them).
    ini = {
        header = {
            "; G1LockPickHelper settings.",
            "; Change the values after \"=\". They apply after Ctrl+R (UE4SS mod reload) or a game restart;",
            "; the keys in [keys] only after a game restart.",
            "; With Shared Mod Menu installed (F2) the settings can be changed in game; then this file is",
            "; rewritten as a whole and your own comments in it are lost.",
        },
        comments = {
            ["general.language"] = "auto: the game's language; en: English; ru: Russian",
            ["general.debug"] = "detailed log in UE4SS.log (for a bug report)",
            ["hint.layout"] = "tape: the current key and the next ones; lines: the whole sequence in lines",
            ["hint.style"] = "simple: a key like in the game's menu; gothic: a golden letter in a frame",
            ["hint.scale"] = "size, %",
            ["hint.offset_x"] = "X offset from the anchor at the right screen edge, UI units",
            ["hint.offset_y"] = "Y offset",
            ["hint.counter"] = "done/total counter of the current sequence",
            ["hint.shake"] = "shake the hint on a miss",
            ["tape.next"] = "keys ahead",
            ["tape.done"] = "pressed keys on the left",
            ["tape.slide"] = "slide the tape on each step",
            ["tape.plate"] = "dark translucent plate under the tape",
            ["lines.per_line"] = "keys per line",
            ["lines.max_lines"] = "lines on screen",
            ["lines.collapse_min"] = "a run of N same keys shows as \"A×N\"; 0 or 1: never collapse",
            ["solve.auto"] = "solve each lock by itself as it opens",
            ["keys.toggle"] = "show/hide the hint",
            ["keys.solve"] = "autosolve: solve the lock / stop",
            ["keys.W"] = "key labels in the hint and the keys of the fallback input path (UE4SS key names)",
        },
    },
}
