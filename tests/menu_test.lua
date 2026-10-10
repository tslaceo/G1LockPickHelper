-- Unit tests for menu.lua (Shared Mod Menu bridge). Run from repo root: lua tests/menu_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local menu = require("menu")
local settings = require("settings")
local t = require("testlib")
local test, eq = t.test, t.eq

local M = require("lang.en").text.menu
local I = M.items

local function opts(changes, actions)
    local o = {
        values = settings.defaults(), schema = settings.entry, text = M,
        on_change = function(section, key, value) changes[#changes + 1] = { section, key, value } end,
        actions = actions or {}, logs = {},
    }
    o.log = function(fmt, ...) o.logs[#o.logs + 1] = string.format(fmt, ...) end
    return o
end

local function item(spec, name)
    for _, section in ipairs(spec) do
        for _, it in ipairs(section.items) do
            if it.name == name then return it end
        end
    end
    error("no menu item " .. name)
end

-- A bridge that records register and requestRefresh calls.
local function fake_bridge(record)
    return {
        VERSION = 3,
        register = function(name, spec) record.registered = { name = name, spec = spec } end,
        requestRefresh = function() record.refreshed = (record.refreshed or 0) + 1 end,
    }
end

test("spec has five sections with their items", function()
    local spec = menu.spec(opts({}))
    eq(#spec, 5, "sections")
    eq(spec[1].title, M.sections.general, "general title")
    eq(spec[2].title, M.sections.view, "view title")
    eq(spec[3].title, M.sections.tape, "tape title")
    eq(spec[5].title, M.sections.solve, "solve title")
    eq(#spec[1].items, 2, "general items")
    eq(#spec[2].items, 11, "view items")
    eq(#spec[3].items, 4, "tape items")
    eq(#spec[4].items, 3, "lines items")
    eq(#spec[5].items, 2, "solve items")
    eq(item(spec, I.collapse_min).desc, M.desc.collapse_min, "item hint")
    eq(item(spec, I.solve_auto).desc, M.desc.solve_auto, "auto hint")
end)

test("the language slider maps 0/1/2 to auto/en/ru", function()
    local changes = {}
    local o = opts(changes)
    local language = item(menu.spec(o), I.language)
    eq(language.kind, "num", "kind")
    eq(language.min, 0, "min")
    eq(language.max, 2, "max")
    eq(language.step, 1, "step")
    eq(language.desc, M.desc.language, "hint")
    eq(language.get(), 0, "auto by default")
    o.values.general.language = "ru"
    eq(language.get(), 2, "ru")
    language.set(1)
    language.set(2.4)
    language.set(-3)
    language.set(9)
    local got = {}
    for i, c in ipairs(changes) do got[i] = c[1] .. "." .. c[2] .. "=" .. c[3] end
    eq(table.concat(got, " "), "general.language=en general.language=ru general.language=auto general.language=ru",
        "changes")
end)

test("the auto switch sets [solve] auto", function()
    local changes = {}
    local auto = item(menu.spec(opts(changes)), I.solve_auto)
    eq(auto.kind, "bool", "kind")
    eq(auto.get(), false, "off by default")
    auto.set(true)
    eq(changes[1][1] .. "." .. changes[1][2] .. "=" .. tostring(changes[1][3]), "solve.auto=true", "change")
end)

test("with opts.keys the spec gets a read-only Keys section", function()
    local changes, called = {}, {}
    local o = opts(changes, { preview = function() called[#called + 1] = "preview" end })
    o.keys = { toggle = "F5", solve = "F3", W = "UP", S = "S", A = "A", D = "D" }
    local spec = menu.spec(o)
    eq(#spec, 6, "sections")
    eq(spec[6].title, M.sections.keys, "keys title")
    eq(#spec[6].items, 5, "key items")
    local names = {
        string.format(I.key_toggle, "F5"), string.format(I.key_solve, "F3"),
        string.format(I.key_select, "UP", "S"), string.format(I.key_shift, "A", "D"),
    }
    for i, name in ipairs(names) do
        local it = spec[6].items[i]
        eq(it.name, name, "name " .. i)
        eq(it.kind, "action", "kind " .. i)
        eq(it.desc, M.desc.keys, "desc " .. i)
        it.set(true)
    end
    local double = spec[6].items[5]
    eq(double.name, I.key_double_reset, "double reset name")
    eq(double.kind, "action", "double reset kind")
    eq(double.desc, M.desc.key_double_reset, "double reset hint")
    double.set(true)
    eq(#changes, 0, "no setting changed")
    eq(#called, 0, "no action handler called")
end)

test("a key UE4SS does not know is marked in the Keys section", function()
    local o = opts({})
    o.keys = { toggle = "F99", solve = "F98", W = "W", S = "NOPE", A = "A", D = "D" }
    o.missing_keys = { toggle = true, solve = true, S = true }
    local keys = menu.spec(o)[6].items
    local missing = M.key_missing
    eq(keys[1].name, string.format(I.key_toggle, string.format(missing, "F99")), "toggle")
    eq(keys[2].name, string.format(I.key_solve, string.format(missing, "F98")), "solve")
    eq(keys[3].name, string.format(I.key_select, "W", string.format(missing, "NOPE")), "S")
    eq(keys[4].name, string.format(I.key_shift, "A", "D"), "the known keys stay plain")
end)

test("number items take their limits from the settings schema", function()
    local changes = {}
    local scale = item(menu.spec(opts(changes)), I.scale)
    eq(scale.kind, "num", "kind")
    eq(scale.min, 50, "min")
    eq(scale.max, 200, "max")
    eq(scale.step, 10, "step")
    eq(scale.get(), 100, "get")
    scale.set(120)
    eq(changes[1][1] .. "." .. changes[1][2] .. "=" .. tostring(changes[1][3]), "hint.scale=120", "change")
end)

test("switches map to two-value settings", function()
    local changes = {}
    local o = opts(changes)
    local spec = menu.spec(o)
    local tape, gothic = item(spec, I.tape), item(spec, I.gothic)
    eq(tape.kind, "bool", "kind")
    eq(tape.get(), true, "tape by default")
    eq(gothic.get(), false, "simple by default")
    tape.set(false)
    gothic.set(true)
    eq(changes[1][3], "lines", "layout")
    eq(changes[2][3], "gothic", "style")
    o.values.hint.layout = "lines"
    eq(tape.get(), false, "get reads the current value")
end)

test("plain switches pass booleans", function()
    local changes = {}
    local plate = item(menu.spec(opts(changes)), I.plate)
    eq(plate.get(), false, "get")
    plate.set(true)
    eq(changes[1][1] .. "." .. changes[1][2], "tape.plate", "setting")
    eq(changes[1][3], true, "value")
end)

test("actions call their handlers", function()
    local called = {}
    local spec = menu.spec(opts({}, {
        preview = function() called[#called + 1] = "preview" end,
        reset_position = function() called[#called + 1] = "reset" end,
    }))
    eq(item(spec, I.preview).kind, "action", "kind")
    item(spec, I.preview).set(true)
    item(spec, I.reset_position).set(true)
    eq(table.concat(called, " "), "preview reset", "calls")
end)

test("attach loads the bridge from Shared Mod Menu's folder, registers and returns the bridge", function()
    local o, record = opts({}), {}
    local seen
    o.mods_dir = "X:/Mods"
    local bridge = fake_bridge(record)
    o.loadfile = function(path)
        seen = path
        return function() return bridge end
    end
    eq(menu.attach(o), bridge, "the bridge")
    eq(seen, "X:/Mods/SharedModMenu/Scripts/modmenu.lua", "path")
    eq(record.registered.name, M.name, "name")
    eq(#record.registered.spec, 5, "spec")
    o.keys = { toggle = "F4", solve = "F3", W = "W", S = "S", A = "A", D = "D" }
    menu.attach(o)
    eq(#record.registered.spec, 6, "spec with the keys")
end)

test("update registers again with the new texts and asks the open menu to re-read", function()
    local o, record = opts({}), {}
    local bridge = fake_bridge(record)
    o.text = require("lang.ru").text.menu
    eq(menu.update(bridge, o), true, "updated")
    eq(record.registered.spec[1].title, o.text.sections.general, "Russian titles")
    eq(record.refreshed, 1, "refresh requested")
    local old = { register = function() end } -- a bridge before API 3: no requestRefresh
    eq(menu.update(old, o), true, "works without requestRefresh")
    eq(menu.update({ register = function() error("boom") end }, o), false, "a failing register")
    eq(o.logs[#o.logs]:find("boom", 1, true) ~= nil, true, "logged")
end)

test("without Shared Mod Menu attach logs and returns false", function()
    local o = opts({})
    o.mods_dir = "X:/Mods"
    o.loadfile = function() return nil, "cannot open" end
    eq(menu.attach(o), false, "attached")
    eq(o.logs[1]:find("Shared Mod Menu not found", 1, true) ~= nil, true, "logged")
end)

test("a broken bridge is skipped with a log line", function()
    local o = opts({})
    o.mods_dir = "M"
    o.loadfile = function() return function() error("bad file") end end
    eq(menu.attach(o), false, "failing file")
    o.loadfile = function() return function() return { VERSION = 3 } end end
    eq(menu.attach(o), false, "no register")
    o.loadfile = function() return function() return { register = function() error("boom") end } end end
    eq(menu.attach(o), false, "failing register")
    eq(o.logs[#o.logs]:find("boom", 1, true) ~= nil, true, "error logged")
end)

test("the button icons and icon set sliders map to their choices", function()
    local changes = {}
    local o = opts(changes)
    local spec = menu.spec(o)
    local icons, gamepad = item(spec, I.icons), item(spec, I.gamepad)
    eq(icons.kind .. " " .. icons.min .. " " .. icons.max .. " " .. icons.step, "num 0 2 1", "icons slider")
    eq(gamepad.kind .. " " .. gamepad.min .. " " .. gamepad.max .. " " .. gamepad.step, "num 0 3 1", "set slider")
    eq(icons.desc, M.desc.icons, "icons hint")
    eq(gamepad.desc, M.desc.gamepad, "set hint")
    eq(icons.get(), 0, "icons auto by default")
    o.values.hint.gamepad = "switch"
    eq(gamepad.get(), 3, "switch")
    icons.set(1)
    gamepad.set(1)
    icons.set(2)
    local got = {}
    for i, c in ipairs(changes) do got[i] = c[1] .. "." .. c[2] .. "=" .. c[3] end
    eq(table.concat(got, " "), "hint.icons=keys hint.gamepad=playstation hint.icons=gamepad", "changes")
end)

test("the double reset switch sets [solve] double_reset", function()
    local changes = {}
    local sw = item(menu.spec(opts(changes)), I.double_reset)
    eq(sw.kind, "bool", "kind")
    eq(sw.get(), true, "on by default")
    eq(sw.desc, M.desc.double_reset, "hint")
    sw.set(false)
    eq(changes[1][1] .. "." .. changes[1][2] .. "=" .. tostring(changes[1][3]), "solve.double_reset=false", "change")
end)

-- Shared Mod Menu cuts an item name after about 21 characters, and it counts bytes, not characters: its name
-- column is at most 300 px at 8.5 px per byte, 35 bytes, so a Cyrillic name (2 bytes a letter) fits about 17
-- letters. Every item of the spec is checked in both languages: the settings' names and, with the default keys,
-- the Keys tab.
test("every item name fits Shared Mod Menu (21 characters, 35 bytes)", function()
    local keys = { toggle = "F4", solve = "F3", W = "W", S = "S", A = "A", D = "D" }
    for _, lang in ipairs({ "en", "ru" }) do
        local o = opts({})
        o.text, o.keys = require("lang." .. lang).text.menu, keys
        local spec, count = menu.spec(o), 0
        for _, section in ipairs(spec) do
            for _, it in ipairs(section.items) do
                count = count + 1
                eq((utf8.len(it.name) or 99) <= 21, true, lang .. " " .. section.title .. ": " .. tostring(it.name))
                eq(#it.name <= 35, true, lang .. " bytes " .. #it.name .. ": " .. tostring(it.name))
            end
        end
        eq(count, 22 + 5, lang .. " items checked: 22 settings and 5 keys")
    end
end)

-- Shared Mod Menu cuts a hint by bytes (a Cyrillic letter is 2): measured in game, a tab cut it after 49-55 bytes,
-- so a hint is at most 48 bytes, one line of the menu. Each hint belongs to a menu item (or to the Keys tab) and is
-- picked up by the item on its own: a missing one leaves the item without a hint.
test("every hint fits Shared Mod Menu (48 bytes), belongs to an item and reaches it", function()
    local known = { keys = true, key_double_reset = true }
    for _, section in ipairs(menu.SECTIONS) do
        for _, it in ipairs(section.items) do known[it.id] = true end
    end
    for _, lang in ipairs({ "en", "ru" }) do
        local o = opts({})
        o.text = require("lang." .. lang).text.menu
        for id, text in pairs(o.text.desc) do
            eq(known[id], true, lang .. " hint of an unknown item " .. id)
            eq(#text <= 48, true, lang .. " " .. id .. " (" .. #text .. " bytes): " .. text)
        end
        local spec = menu.spec(o)
        for s, section in ipairs(menu.SECTIONS) do
            for i, it in ipairs(section.items) do
                eq(spec[s].items[i].desc, o.text.desc[it.id], lang .. " hint of " .. it.id)
            end
        end
        for _, id in ipairs({ "offset_x", "offset_y", "counter", "next", "done", "slide" }) do
            eq(type(o.text.desc[id]), "string", lang .. " has a hint for " .. id)
        end
    end
end)

test("the Fix stuck controls switch sets [general] smm_fix", function()
    local changes = {}
    local sw = item(menu.spec(opts(changes)), I.smm_fix)
    eq(sw.kind, "bool", "kind")
    eq(sw.get(), true, "on by default")
    eq(sw.desc, M.desc.smm_fix, "hint")
    sw.set(false)
    eq(changes[1][1] .. "." .. changes[1][2] .. "=" .. tostring(changes[1][3]), "general.smm_fix=false", "change")
end)

t.finish()
