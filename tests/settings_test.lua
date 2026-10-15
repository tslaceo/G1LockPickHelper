-- Unit tests for settings.lua. Run from repo root: lua tests/settings_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local settings = require("settings")
local t = require("testlib")
local test, eq = t.test, t.eq

local EN_INI, RU_INI = require("lang.en").ini, require("lang.ru").ini

-- In-memory io: files[path] = content; files.readonly makes every write fail; files.closeFailure triggers close error.
local function fake_io(files)
    return {
        open = function(path, mode)
            if mode:find("r") then
                local content = files[path]
                if content == nil then return nil, path .. ": No such file or directory" end
                return { read = function() return content end, close = function() return true end }
            end
            if files.readonly then return nil, path .. ": Permission denied" end
            local parts = {}
            return {
                write = function(self, s) parts[#parts + 1] = s return self end,
                close = function()
                    if files.closeFailure then
                        return nil, files.closeFailure
                    end
                    files[path] = table.concat(parts)
                    return true
                end,
            }
        end,
    }
end

local function has(list, text)
    for _, s in ipairs(list) do
        if s:find(text, 1, true) then return true end
    end
    return false
end

test("defaults match the spec", function()
    local v = settings.defaults()
    eq(v.general.language, "auto", "language")
    eq(v.general.debug, false, "debug")
    eq(v.general.smm_fix, true, "smm_fix")
    eq(v.hint.layout, "tape", "layout")
    eq(v.hint.style, "simple", "style")
    eq(v.hint.scale, 100, "scale")
    eq(v.hint.offset_x, -760, "offset_x")
    eq(v.hint.offset_y, 0, "offset_y")
    eq(v.hint.counter, true, "counter")
    eq(v.hint.shake, true, "shake")
    eq(v.tape.next, 5, "next")
    eq(v.tape.done, 3, "done")
    eq(v.tape.slide, true, "slide")
    eq(v.tape.plate, false, "plate")
    eq(v.lines.per_line, 16, "per_line")
    eq(v.lines.max_lines, 6, "max_lines")
    eq(v.lines.collapse_min, 3, "collapse_min")
    eq(v.lines.plate, false, "lines plate")
    eq(v.keys.toggle, "F4", "toggle")
    eq(v.keys.W, "W", "W")
    eq(v.keys.D, "D", "D")
    eq(v.solve.auto, false, "auto")
    eq(v.keys.solve, "F3", "solve key")
    eq(v.hint.icons, "auto", "icons")
    eq(v.hint.gamepad, "auto", "gamepad")
    eq(v.solve.double_reset, true, "double_reset")
    eq(v.solve.timer, true, "timer")
end)

test("the schema holds no texts", function()
    for _, e in ipairs(settings.SCHEMA) do
        eq(e.comment, nil, e.section .. "." .. e.key)
    end
end)

test("parse reads sections, spaces, comments, CRLF and a BOM", function()
    local text = "\239\187\191; header\r\n[hint]\r\n  layout =  lines  ; comment\r\n# other\r\nscale=120\r\n\r\n[ tape ]\r\nnext = 7 # comment\r\n"
    local v, problems = settings.parse(text)
    eq(#problems, 0, "problems")
    eq(v.hint.layout, "lines", "layout")
    eq(v.hint.scale, 120, "scale")
    eq(v.tape.next, 7, "next")
    eq(v.tape.done, 3, "a missing key keeps its default")
end)

test("parse handles section headers with trailing comments", function()
    local text = "[hint] ; comment\nstyle = gothic\n[tape]   # c\nnext = 7\n"
    local v, problems = settings.parse(text)
    eq(#problems, 0, "problems")
    eq(v.hint.style, "gothic", "style")
    eq(v.tape.next, 7, "next")
end)

test("[general] language and debug are read; a bad language falls back to auto", function()
    local v, problems = settings.parse("[general]\nlanguage = RU\ndebug = yes\n")
    eq(#problems, 0, "problems")
    eq(v.general.language, "ru", "language")
    eq(v.general.debug, true, "debug")
    v, problems = settings.parse("[general]\nlanguage = de\n")
    eq(v.general.language, "auto", "bad language -> default")
    eq(#problems, 1, "one problem")
end)

test("booleans accept true/false, 1/0, yes/no, on/off in any case", function()
    local v = settings.parse("[hint]\ncounter = OFF\nshake = 0\n[tape]\nslide = No\nplate = yes\n")
    eq(v.hint.counter, false, "OFF")
    eq(v.hint.shake, false, "0")
    eq(v.tape.slide, false, "No")
    eq(v.tape.plate, true, "yes")
end)

test("numbers are rounded, clamped to their range, or reset when unreadable", function()
    local v, problems = settings.parse("[hint]\nscale = 500\noffset_y = 12.6\n[tape]\nnext = 0\ndone = many\n")
    eq(v.hint.scale, 200, "scale clamped")
    eq(v.hint.offset_y, 13, "rounded")
    eq(math.type(v.hint.offset_y), "integer", "integer")
    eq(v.tape.next, 1, "next clamped")
    eq(v.tape.done, 3, "unreadable -> default")
    eq(#problems, 3, "problems: scale, next, done")
    eq(has(problems, "out of range 50..200"), true, "range message")
end)

test("choices ignore case; key names are upper-cased; bad values fall back", function()
    local v, problems = settings.parse("[hint]\nstyle = GOTHIC\nlayout = grid\n[keys]\ntoggle = num_five\nW = F 4\ns = up\n")
    eq(v.hint.style, "gothic", "style")
    eq(v.hint.layout, "tape", "bad layout -> default")
    eq(v.keys.toggle, "NUM_FIVE", "toggle")
    eq(v.keys.W, "W", "bad key -> default")
    eq(v.keys.S, "UP", "key names ignore case")
    eq(#problems, 2, "problems")
end)

test("unknown keys, sections and unreadable lines are reported and ignored", function()
    local v, problems = settings.parse("scale = 120\n[hint]\nfoo = 1\n[extra]\nbar = 2\nnonsense\n")
    eq(v.hint.scale, 100, "a key before any section is ignored")
    eq(#problems, 4, "problems")
    eq(has(problems, "unknown setting [hint] foo"), true, "unknown key")
    eq(has(problems, "cannot read"), true, "unreadable line")
end)

test("serialize then parse gives the same values", function()
    local v = settings.defaults()
    v.general.language, v.general.debug = "ru", true
    v.hint.layout, v.hint.style, v.hint.scale, v.hint.offset_x = "lines", "gothic", 130, -900
    v.tape.plate, v.lines.collapse_min, v.lines.plate, v.keys.toggle = true, 0, true, "F6"
    v.solve.timer = false
    local text = settings.serialize(v, EN_INI)
    local back, problems = settings.parse(text)
    eq(#problems, 0, "problems")
    for _, e in ipairs(settings.SCHEMA) do
        eq(back[e.section][e.key], v[e.section][e.key], e.section .. "." .. e.key)
    end
    eq(text:find("[lines]", 1, true) ~= nil, true, "sections written")
    eq(text:sub(1, 1), ";", "starts with the header comment")
end)

test("the header and the comments come from the language", function()
    local en = settings.serialize(settings.defaults(), EN_INI)
    local ru = settings.serialize(settings.defaults(), RU_INI)
    eq(en:find(EN_INI.header[1], 1, true), 1, "English header")
    eq(ru:find(RU_INI.header[1], 1, true), 1, "Russian header")
    eq(en:find("layout = tape  ; " .. EN_INI.comments["hint.layout"], 1, true) ~= nil, true, "English comment")
    eq(ru:find("layout = tape  ; " .. RU_INI.comments["hint.layout"], 1, true) ~= nil, true, "Russian comment")
    eq(en:find("\nS = S\n", 1, true) ~= nil, true, "a setting without a comment")
end)

test("the file starts with [general] and lists [solve] before [keys]", function()
    local text = settings.serialize(settings.defaults(), EN_INI)
    local first = text:find("\n[", 1, true)
    eq(text:sub(first + 1, first + 9), "[general]", "first section")
    eq(text:find("language = auto", 1, true) ~= nil, true, "language")
    eq(text:find("debug = false", 1, true) ~= nil, true, "debug")
    eq(text:find("[solve]\nauto = false", 1, true) ~= nil, true, "solve section")
    eq(text:find("solve = F3", 1, true) ~= nil, true, "solve key")
    eq(text:find("\n[solve]\n", 1, true) < text:find("\n[keys]\n", 1, true), true, "order of the section headers")
end)

test("load reports a missing file without writing it", function()
    local files = {}
    local v, problems, missing = settings.load("x/settings.ini", fake_io(files))
    eq(missing, true, "missing")
    eq(#problems, 0, "problems")
    eq(files["x/settings.ini"], nil, "nothing written")
    eq(v.hint.layout, "tape", "defaults")
end)

test("load reads an existing file", function()
    local files = { ["x/settings.ini"] = "[hint]\nstyle = gothic\n" }
    local v, _, missing = settings.load("x/settings.ini", fake_io(files))
    eq(missing, false, "missing")
    eq(v.hint.style, "gothic", "style")
end)

test("save writes the file in the given language", function()
    local files = {}
    local ok = settings.save("x/settings.ini", settings.defaults(), RU_INI, fake_io(files))
    eq(ok, true, "saved")
    eq(files["x/settings.ini"], settings.serialize(settings.defaults(), RU_INI), "content")
end)

test("a file that cannot be written is reported, not raised", function()
    local files = { readonly = true }
    local ok, err = settings.save("x/settings.ini", settings.defaults(), EN_INI, fake_io(files))
    eq(ok, false, "save")
    eq(tostring(err):find("Permission denied", 1, true) ~= nil, true, "error")
end)

test("save reports close failures", function()
    local files = { closeFailure = "x: No space left on device" }
    local ok, err = settings.save("x/settings.ini", settings.defaults(), EN_INI, fake_io(files))
    eq(ok, false, "save")
    eq(tostring(err), "x: No space left on device", "error")
end)

test("set takes typed values from the menu", function()
    local v = settings.defaults()
    eq(settings.set(v, "hint", "scale", 120.0), true, "known setting")
    eq(v.hint.scale, 120, "scale")
    eq(math.type(v.hint.scale), "integer", "integer")
    settings.set(v, "tape", "slide", false)
    eq(v.tape.slide, false, "bool")
    settings.set(v, "general", "language", "ru")
    eq(v.general.language, "ru", "choice")
    local _, problem = settings.set(v, "hint", "scale", 999)
    eq(v.hint.scale, 200, "clamped")
    eq(problem ~= nil, true, "problem")
    eq(settings.set(v, "hint", "nope", 1), false, "unknown setting")
end)

test("[solve] auto and the solve key are read", function()
    local v, problems = settings.parse("[solve]\nauto = on\n[keys]\nsolve = f6\n")
    eq(#problems, 0, "problems")
    eq(v.solve.auto, true, "auto")
    eq(v.keys.solve, "F6", "solve key")
end)

test("[hint] icons and gamepad, [solve] double_reset are read; bad values fall back", function()
    local v, problems = settings.parse("[hint]\nicons = Gamepad\ngamepad = playstation\n[solve]\ndouble_reset = off\n")
    eq(v.hint.icons, "gamepad", "icons")
    eq(v.hint.gamepad, "playstation", "gamepad")
    eq(v.solve.double_reset, false, "double_reset")
    eq(#problems, 0, "no problems")
    v, problems = settings.parse("[hint]\nicons = big\ngamepad = sega\n")
    eq(v.hint.icons, "auto", "bad icons")
    eq(v.hint.gamepad, "auto", "bad gamepad")
    eq(#problems, 2, "two problems")
end)

test("icons and gamepad follow style in [hint]; double_reset follows auto in [solve]", function()
    local text = settings.serialize(settings.defaults(), EN_INI)
    local style, icons, gamepad = text:find("\nstyle = ", 1, true), text:find("\nicons = auto", 1, true),
        text:find("\ngamepad = auto", 1, true)
    eq(style < icons and icons < gamepad, true, "[hint] order")
    local auto, double = text:find("\nauto = false", 1, true), text:find("\ndouble_reset = true", 1, true)
    eq(auto < double, true, "[solve] order")
end)

t.finish()
