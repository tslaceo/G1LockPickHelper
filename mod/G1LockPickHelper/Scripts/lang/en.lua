-- English texts of G1LockPickHelper: the hint and its notes, Shared Mod Menu, the comments of settings.ini.
-- lang/ru.lua has exactly the same keys and format specifiers (tests/lang_test.lua). Another language needs a file
-- with these keys, and its id in i18n.resolve, the settings.lua choices, the menu.lua choices, the language hint
-- text (desc.language) and scripts/package.ps1.
-- The player-facing name of the autosolver is "auto-pick" (log lines and code keep "autosolve").
return {
    text = {
        not_in_db = "Lock not in the database: %s",
        no_safe_path = "Can't open without risking the pick",
        bad_state = "Can't read the lock",
        hint_on = "Hint shown (%s)",                     -- after the toggle key; %s is the key name
        hint_off = "Hint hidden (%s)",
        solving = "Auto-picking…",                       -- instead of the counter while the autosolver presses
        solve_armed = "Auto-pick: waiting for the lock", -- F3 or auto-pick before the minigame is ready
        solve_stopped = "Auto-pick stopped",             -- the autosolver stopped by itself (reason in UE4SS.log)
        -- F3 with nothing to solve or without input hooks; also a minigame that opens without them (auto-pick on)
        solve_unavailable = "Auto-pick unavailable",
        -- F3 while the hint is hidden; also F3 outside a minigame with auto-pick on, hint shown or not. %s is the
        -- key name, or double_reset when two resets started the autosolver
        solve_on = "Auto-pick on (%s)",
        solve_off = "Auto-pick off (%s)",
        double_reset = "double reset",
        -- Shared Mod Menu (F2): mod tab, sections, item names and hints (menu.lua). The menu cuts item names after
        -- about 21 characters; the hints are kept within 60 characters (tests/menu_test.lua checks both).
        menu = {
            name = "LockPick Helper",
            sections = {
                general = "General", view = "View", tape = "Tape", lines = "Lines", solve = "Auto-pick", keys = "Keys",
            },
            key_missing = "%s (unknown)", -- a configured key name UE4SS does not know
            items = {
                language = "Language", smm_fix = "Fix stuck controls",
                tape = "Tape layout", gothic = "Gothic style", scale = "Size, %", offset_x = "Position X",
                icons = "Letters or icons", gamepad = "Gamepad icon set",
                offset_y = "Position Y", counter = "Counter", shake = "Shake on a miss",
                preview = "Show example", reset_position = "Reset position",
                next = "Upcoming keys", done = "Pressed keys", slide = "Smooth scroll", plate = "Dark background",
                per_line = "Keys per line", max_lines = "Lines on screen", collapse_min = "Fold repeats from",
                solve_auto = "Always auto-pick",
                double_reset = "Double reset",
                key_toggle = "%s: show/hide hint",
                key_solve = "%s: auto-pick",
                key_select = "%s / %s: select plate",
                key_shift = "%s / %s: move plate",
                key_double_reset = "△△/YY: auto-pick",
            },
            desc = {
                language = "0 as in the game, 1 English, 2 Русский",
                smm_fix = "frees the controls after F2 in a minigame",
                keys = "change in settings.ini [keys] and restart the game",
                tape = "off: all keys in lines",
                gothic = "golden letter in a frame; off: simple key",
                icons = "0 auto (by device), 1 letters, 2 gamepad icons",
                gamepad = "0 as in the game, 1 PlayStation, 2 Xbox, 3 Switch",
                preview = "sample hint for 5 s, outside a minigame",
                reset_position = "back to the default size and position",
                offset_x = "from the right screen edge; smaller moves it left",
                offset_y = "bigger moves it down",
                counter = "keys done / total",
                next = "how many keys show after the current one",
                done = "how many pressed keys stay on the left",
                slide = "the tape slides after each press",
                collapse_min = "fold N or more same keys in a row; 0 or 1: never",
                solve_auto = "picks every lock for you; F3 cancels",
                double_reset = "two quick resets (△/Y or R) start auto-pick",
                key_double_reset = "R R on the keyboard; on/off in the Auto-pick tab",
            },
        },
    },
    -- settings.ini: the header and one comment per setting ("section.key"; the minigame keys S, A, D go without
    -- one, the comment of W covers them).
    ini = {
        header = {
            "; G1LockPickHelper settings.",
            "; Edit the values after \"=\", then press Ctrl+R (UE4SS mod reload) or restart the game.",
            "; Keys in [keys] change only after a game restart.",
            "; With Shared Mod Menu (F2) most settings can be changed in game.",
            "; Any change in the menu rewrites this file, and comments you added are lost.",
        },
        comments = {
            ["general.language"] = "auto: as in the game; en: English; ru: Russian",
            ["general.debug"] = "detailed log in UE4SS.log (for a bug report)",
            ["general.smm_fix"] = "give the controls back after a minigame where Shared Mod Menu (F2) was opened",
            ["hint.layout"] = "tape: the current key and the next ones; lines: all keys in lines",
            ["hint.style"] = "simple: a key as in the game's controls menu; gothic: a golden letter in a frame",
            ["hint.icons"] = "auto: icons while you play with a gamepad, else letters (always letters with the game's \"Button icons: Do not use\"); keys: letters; gamepad: icons",
            ["hint.gamepad"] = "icon set: auto (as the game's \"Button icons\"), playstation, xbox, switch",
            ["hint.scale"] = "hint size in %, 50–200",
            ["hint.offset_x"] = "position from the right screen edge, UI units; smaller moves it left",
            ["hint.offset_y"] = "vertical position, UI units; bigger moves it down",
            ["hint.counter"] = "counter of keys: done / total",
            ["hint.shake"] = "shake the hint on a miss (a key other than the hinted one)",
            ["tape.next"] = "how many next keys the tape shows, 1–10",
            ["tape.done"] = "how many pressed keys stay on the left, 0–6",
            ["tape.slide"] = "the tape slides smoothly after each press",
            ["tape.plate"] = "dark translucent background under the tape",
            ["lines.per_line"] = "keys per line, 4–40",
            ["lines.max_lines"] = "how many lines are shown, 1–12",
            ["lines.collapse_min"] = "N or more same keys in a row show as \"A×N\"; 0 or 1: never",
            ["solve.auto"] = "auto-pick every lock as soon as its minigame starts",
            ["solve.double_reset"] = "two quick resets in a minigame start auto-pick (gamepad Triangle / Y, keyboard R)",
            ["keys.toggle"] = "show/hide the hint",
            ["keys.solve"] = "start / stop auto-pick",
            ["keys.W"] = "W, S, A, D: the names the hint shows, and the keys the mod listens to if input hooks are unavailable (UE4SS key names)",
        },
    },
}
