-- Tests for the language files (lang/*.lua) and i18n.lua. Run from repo root: lua tests/lang_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local i18n = require("i18n")
local t = require("testlib")
local test, eq = t.test, t.eq

local EN, RU = require("lang.en"), require("lang.ru")

-- { ["a.b.c"] = leaf } of a language table; a list (the settings.ini header) is one leaf.
local function leaves(tbl, prefix, out)
    out = out or {}
    for k, v in pairs(tbl) do
        local path = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
        if type(v) == "table" and v[1] == nil then
            leaves(v, path, out)
        else
            out[path] = v
        end
    end
    return out
end

-- "%s %d" -> the format specifiers in order.
local function specifiers(s)
    local out = {}
    for spec in s:gmatch("%%.") do out[#out + 1] = spec end
    return table.concat(out, " ")
end

test("ru has exactly the keys of en", function()
    local en, ru = leaves(EN), leaves(RU)
    for path in pairs(en) do eq(ru[path] ~= nil, true, "ru lacks " .. path) end
    for path in pairs(ru) do eq(en[path] ~= nil, true, "ru has an extra " .. path) end
end)

test("every ru text keeps the format specifiers of en, in order", function()
    local en, ru = leaves(EN), leaves(RU)
    for path, v in pairs(en) do
        if type(v) == "string" then
            eq(type(ru[path]), "string", path .. " type")
            eq(specifiers(ru[path]), specifiers(v), path)
        end
    end
end)

test("the settings.ini header is a list of comment lines", function()
    for name, L in pairs({ en = EN, ru = RU }) do
        eq(#L.ini.header > 0, true, name .. " header")
        for i, line in ipairs(L.ini.header) do eq(line:sub(1, 1), ";", name .. " header line " .. i) end
    end
end)

test("resolve: en/ru as set; auto follows a Russian culture; everything else is English", function()
    eq(i18n.resolve("en", "ru"), "en", "en")
    eq(i18n.resolve("ru", "en-US"), "ru", "ru")
    eq(i18n.resolve("auto", "ru"), "ru", "auto ru")
    eq(i18n.resolve("auto", "RU-ru"), "ru", "auto RU-ru")
    eq(i18n.resolve("auto", "ru_RU"), "ru", "auto ru_RU")
    eq(i18n.resolve("auto", "rus"), "en", "auto rus is not a culture we know")
    eq(i18n.resolve("auto", "en"), "en", "auto en")
    eq(i18n.resolve("auto", "de-DE"), "en", "auto de-DE")
    eq(i18n.resolve("auto", nil), "en", "auto, culture unknown")
    eq(i18n.resolve("auto"), "en", "auto, no culture given")
    eq(i18n.resolve("fr", "ru"), "en", "unknown setting")
end)

test("load: en as is, another language with anything missing taken from en", function()
    local fake = {
        ["lang.en"] = { text = { a = "A", b = "B %s", menu = { x = "X" } }, ini = { header = { "; e1", "; e2" } } },
        ["lang.ru"] = { text = { a = "А", menu = {} }, ini = { header = { "; р1" } } },
    }
    local function req(name)
        local v = fake[name]
        if not v then error("module '" .. name .. "' not found") end
        return v
    end
    eq(i18n.load("en", req).text.a, "A", "en")
    local ru = i18n.load("ru", req)
    eq(ru.text.a, "А", "ru text")
    eq(ru.text.b, "B %s", "a missing text comes from en")
    eq(ru.text.menu.x, "X", "a missing nested text comes from en")
    eq(#ru.ini.header, 1, "a list is taken whole")
    eq(i18n.load("xx", req).text.a, "A", "an unknown language is en")
end)

test("the shipped languages load", function()
    eq(i18n.load("en").text.solving, EN.text.solving, "en")
    eq(i18n.load("ru").text.solving, RU.text.solving, "ru")
    eq(i18n.LANGS[1], "en", "en first: the fallback")
end)

local settings = require("settings")

test("settings.ini comments: one per setting except the minigame key labels S, A, D", function()
    for name, L in pairs({ en = EN, ru = RU }) do
        local known = {}
        for _, e in ipairs(settings.SCHEMA) do
            local id = e.section .. "." .. e.key
            local quiet = e.section == "keys" and (e.key == "S" or e.key == "A" or e.key == "D")
            eq(L.ini.comments[id] ~= nil, not quiet, name .. " comment for " .. id)
            known[id] = true
        end
        for id in pairs(L.ini.comments) do eq(known[id], true, name .. " comment for an unknown setting " .. id) end
    end
end)

t.finish()
