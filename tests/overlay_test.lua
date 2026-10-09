-- Offline test of overlay.lua against fake UMG objects (no game). Run from repo root: lua tests/overlay_test.lua
-- Checks the widget tree it builds, texts, colours, fonts and animations; how it looks is checked in game.
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local t = require("testlib")
local test, eq = t.test, t.eq
local config = require("config")
local settings = require("settings")
local view = require("view")
local pad = require("pad")

local objects, logs, find_all_of_calls = {}, {}, 0
local no_brush, missing_fonts, missing_textures = false, false, false
local real_print = print

-- Fake UObject: records method calls; AddChildTo*/SetContent return a fake slot; keeps texts, visibility,
-- colours and render translations. Fields the overlay writes into (Font, Background) are plain tables.
local function fake(class, name)
    local obj = {
        class = class, name = name, calls = {}, children = {}, Font = {}, visibility = 0, in_viewport = false,
        removed = false, text = false, color = false, brush_color = false, translation = false,
        Background = not no_brush and { OutlineSettings = {} } or false,
    }
    objects[#objects + 1] = obj
    return setmetatable(obj, {
        __index = function(_, method)
            return function(self, ...)
                local args = { ... }
                self.calls[#self.calls + 1] = { method, args }
                if method:find("^AddChildTo") or method == "SetContent" then
                    self.children[#self.children + 1] = args[1]
                    local slot = fake("Slot", "slot")
                    slot.owner = self
                    return slot
                elseif method == "SetText" then
                    self.text = args[1]
                elseif method == "SetVisibility" then
                    self.visibility = args[1]
                elseif method == "AddToViewport" then
                    self.in_viewport = true
                elseif method == "IsValid" then
                    return true
                elseif method == "IsInViewport" then
                    return self.in_viewport
                elseif method == "RemoveFromParent" then
                    self.removed, self.in_viewport = true, false
                elseif method == "GetFName" then
                    return { ToString = function() return self.name end }
                elseif method == "SetColorAndOpacity" then
                    self.color = args[1].SpecifiedColor or args[1] -- a TextBlock takes an FSlateColor, an Image a colour
                elseif method == "SetBrushFromTexture" then
                    self.brush = args[1]
                elseif method == "SetBrushColor" then
                    self.brush_color = args[1]
                elseif method == "SetRenderTranslation" then
                    self.translation = args[1]
                end
            end
        end,
    })
end

local function setup(find_all_of_result)
    objects, logs, find_all_of_calls = {}, {}, 0
    no_brush, missing_fonts, missing_textures = false, false, false
    FText = function(s) return s end
    FName = function(s) return s end
    LoadAsset = nil
    StaticFindObject = function(path)
        if missing_textures and path:find("HotkeysIcons", 1, true) then return nil end
        if missing_fonts and path:find("^/Game/UI/Fonts/") then return nil end
        return fake("Class", path)
    end
    StaticConstructObject = function(class, _, name) return fake(class.name, name) end
    FindFirstOf = function(name) return fake(name, name) end
    FindAllOf = function()
        find_all_of_calls = find_all_of_calls + 1
        return find_all_of_result
    end
    print = function(s, ...)
        if type(s) == "string" and s:find("^%[G1LockPickHelper%]") then
            logs[#logs + 1] = s
        else
            real_print(s, ...)
        end
    end
    package.loaded["overlay"] = nil
    local overlay = require("overlay")
    overlay.init(config.overlay)
    return overlay
end

-- Settings with changes: { ["hint.style"] = "gothic", ... }.
local function values(changes)
    local v = settings.defaults()
    for path, value in pairs(changes or {}) do
        local section, key = path:match("^(%w+)%.([%w_]+)$")
        v[section][key] = value
    end
    return v
end

local function built(class)
    local out = {}
    for _, o in ipairs(objects) do
        if o.class == "/Script/UMG." .. class then out[#out + 1] = o end
    end
    return out
end

local function named(kind)
    local out = {}
    for _, o in ipairs(objects) do
        if type(o.name) == "string" and o.name:find("^G1LPH_" .. kind .. "_") then out[#out + 1] = o end
    end
    return out
end

-- Keys in build order: { box, frame, text, icon_row, image, tail } of every UMG Overlay (one per key).
local function tokens()
    local out = {}
    for _, o in ipairs(built("Overlay")) do
        local row = o.children[3]
        out[#out + 1] = { box = o, frame = o.children[1], text = o.children[2], icon_row = row,
            image = row and row.children[1] and row.children[1].children[1], tail = row and row.children[2] }
    end
    return out
end

local function calls_of(method)
    local n = 0
    for _, o in ipairs(objects) do
        for _, c in ipairs(o.calls) do
            if c[1] == method then n = n + 1 end
        end
    end
    return n
end

local function count_logs(text)
    local n = 0
    for _, l in ipairs(logs) do
        if l:find(text, 1, true) then n = n + 1 end
    end
    return n
end

local function set_text_calls()
    local n = 0
    for _, o in ipairs(objects) do
        for _, c in ipairs(o.calls) do
            if c[1] == "SetText" then n = n + 1 end
        end
    end
    return n
end

local SAMPLE = {
    keys = { "W", "S", "A", "D", "D", "A", "W", "S" }, index = 3,
    history = { { key = "D", ok = true }, { key = "A", ok = false }, { key = "W", ok = true }, { key = "S", ok = true } },
    pressed = 4, misses = 1,
}
local V0 = { keys = SAMPLE.keys, index = 1, history = {}, pressed = 0, misses = 0 }
local V1 = { keys = SAMPLE.keys, index = 2, history = { { key = "W", ok = true } }, pressed = 1, misses = 0 }
local V_MISS = { keys = SAMPLE.keys, index = 1, history = { { key = "D", ok = false } }, pressed = 1, misses = 1 }

local function tape(v) return view.tape(v or SAMPLE, { next = 5, done = 3 }) end
local function lines(v, o) return view.lines(v or SAMPLE, o or { per_line = 16, max_lines = 6, collapse_min = 3 }) end

test("tape: one cell per position, texts and frames from the model", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(), 0)
    eq(#built("UserWidget"), 1, "user widgets")
    eq(built("UserWidget")[1].in_viewport, true, "in viewport")
    eq(built("UserWidget")[1].visibility, 3, "shown (HitTestInvisible)")
    eq(#named("Cell"), 9, "cells")
    local tk = tokens()
    local texts = {}
    for i, k in ipairs(tk) do texts[i] = k.text.text end
    eq(table.concat(texts, " "), "A W S A D D A W S", "texts")
    eq(tk[4].frame.visibility, 3, "current framed")
    eq(tk[3].frame.visibility, 1, "done not framed")
end)

test("tape colours: miss red, done green, next fading, current in the style colour", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(), 0)
    local tk, c = tokens(), config.overlay.colors
    eq(tk[1].text.color.R, c.miss.R, "miss")
    eq(string.format("%.3f", tk[1].text.color.A), "0.280", "furthest done alpha")
    eq(tk[2].text.color.G, c.done.G, "done")
    eq(string.format("%.3f", tk[3].text.color.A), "0.750", "nearest done alpha")
    eq(tk[4].text.color.R, c.simple.current.R, "current")
    eq(string.format("%.3f", tk[5].text.color.A), "0.850", "first next alpha")
    eq(string.format("%.3f", tk[9].text.color.A), "0.150", "last next alpha")
end)

test("fonts: simple letters in Boucherie, gothic in Noto Serif Bold, the counter in Noto Serif", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(), 0)
    local tk, fonts = tokens(), config.overlay.fonts
    eq(tk[1].text.Font.FontObject.name, fonts.simple.path, "letters")
    eq(tk[1].text.Font.TypefaceFontName, "Default", "letters typeface")
    eq(tk[1].text.Font.Size, 26, "letter size")
    eq(tk[4].text.Font.Size, 34, "current letter is larger")
    eq(built("TextBlock")[1].Font.FontObject.name, fonts.text.path, "counter")
    overlay.configure(values({ ["hint.style"] = "gothic" }))
    overlay.show(tape(), 0)
    local gk = tokens()
    eq(gk[#gk].text.Font.FontObject.name, fonts.gothic.path, "gothic letters")
    eq(gk[#gk].text.Font.TypefaceFontName, "Bold", "gothic typeface")
end)

test("missing game fonts fall back to the engine font, logged once per font", function()
    local overlay = setup()
    missing_fonts = true
    overlay.configure(values())
    overlay.show(tape(), 0)
    eq(tokens()[1].text.Font.FontObject, nil, "no font object")
    eq(count_logs("font not found"), 2, "letters and text fonts")
end)

test("a LoadAsset that raises for a missing font: engine font, one log line per font, no second load", function()
    local overlay = setup()
    missing_fonts = true
    local load_calls = 0
    LoadAsset = function(path)
        load_calls = load_calls + 1
        error("no such asset " .. path)
    end
    overlay.configure(values())
    overlay.show(tape(), 0)
    eq(#tokens(), 9, "hint built")
    eq(built("UserWidget")[1].visibility, 3, "hint shown")
    eq(tokens()[1].text.Font.FontObject, nil, "letters: no font object")
    eq(built("TextBlock")[1].Font.FontObject, nil, "counter: no font object")
    eq(count_logs("font not found"), 2, "one line per font path")
    eq(count_logs("no such asset"), 2, "the error text is logged")
    eq(load_calls, 2, "one load per font path")
    overlay.configure(values({ ["hint.scale"] = 150 }))
    overlay.show(tape(), 0)
    eq(#built("UserWidget"), 2, "rebuilt")
    eq(tokens()[10].text.Font.FontObject, nil, "rebuilt letters: no font object")
    eq(load_calls, 2, "no second load after the rebuild")
    eq(count_logs("font not found"), 2, "still logged once per font path")
end)

test("lines: max_lines rows of per_line keys; unused rows and keys collapsed", function()
    local overlay = setup()
    overlay.configure(values({ ["hint.layout"] = "lines", ["lines.per_line"] = 4, ["lines.max_lines"] = 3 }))
    overlay.show(lines(nil, { per_line = 4, max_lines = 3, collapse_min = 0 }), 0)
    local rows, tk = named("Row"), tokens()
    eq(#rows, 3, "rows")
    eq(#tk, 12, "keys")
    eq(tk[1].text.text, "D", "first key")
    eq(tk[5].text.text, "A", "current key")
    eq(tk[5].frame.visibility, 3, "current framed")
    eq(tk[11].box.visibility, 1, "unused key collapsed")
    eq(rows[3].visibility, 3, "third row shown")
end)

test("lines: a run is one key with its count", function()
    local overlay = setup()
    overlay.configure(values({ ["hint.layout"] = "lines" }))
    local v = { keys = { "D", "A", "A", "A", "A", "A", "W" }, index = 2, history = { { key = "D", ok = true } }, pressed = 1, misses = 0 }
    overlay.show(lines(v), 0)
    eq(tokens()[2].text.text, "A×5", "run")
    eq(tokens()[2].frame.visibility, 3, "run is current")
end)

test("the counter follows its setting", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(), 0)
    local counter = built("TextBlock")[1]
    eq(counter.text, "2/8", "counter text")
    eq(counter.visibility, 3, "shown")
    overlay.configure(values({ ["hint.counter"] = false }))
    overlay.show(tape(), 0)
    eq(counter.visibility, 1, "hidden")
end)

test("a model's counter_always shows the counter with the counter setting off", function()
    local overlay = setup()
    overlay.configure(values({ ["hint.counter"] = false }))
    local m = tape()
    m.counter, m.counter_always = "Autosolving…", true
    overlay.show(m, 0)
    local counter = built("TextBlock")[1]
    eq(counter.text, "Autosolving…", "text")
    eq(counter.visibility, 3, "shown")
end)

test("the plate is dark only for the tape with plate on, with a gold outline", function()
    local overlay = setup()
    overlay.configure(values({ ["tape.plate"] = true }))
    overlay.show(tape(), 0)
    local plate, gold = named("Plate")[1], config.overlay.colors.plate_frame
    eq(plate.Background.DrawAs, 4, "tape with plate: rounded box")
    eq(plate.Background.TintColor.SpecifiedColor.A, config.overlay.plate_alpha, "tape with plate: fill alpha")
    local outline = plate.Background.OutlineSettings.Color.SpecifiedColor
    eq(outline.R, gold.R, "outline R")
    eq(outline.G, gold.G, "outline G")
    eq(outline.B, gold.B, "outline B")
    eq(plate.Background.OutlineSettings.Width, 1.5, "outline width")
    overlay.configure(values({ ["tape.plate"] = true, ["hint.layout"] = "lines" }))
    overlay.show(lines(), 0)
    local plates = named("Plate")
    eq(plates[#plates].brush_color.A, 0, "lines: no plate")
    eq(plates[#plates].Background.DrawAs, nil, "lines: not a rounded box")
    overlay.configure(values({ ["tape.plate"] = false }))
    overlay.show(tape(), 0)
    plates = named("Plate")
    eq(plates[#plates].brush_color.A, 0, "tape without plate")
    eq(plates[#plates].Background.DrawAs, nil, "tape without plate: not a rounded box")
end)

test("tape cells set a minimum height, not a fixed one: a tall font grows the cell", function()
    local overlay = setup()
    overlay.configure(values({ ["hint.style"] = "gothic" }))
    overlay.show(tape(), 0)
    local boxes = named("Cell")
    eq(#boxes, 9, "cells")
    for i, box in ipairs(boxes) do
        local min_height, height_override, width_override = 0, 0, 0
        for _, c in ipairs(box.calls) do
            if c[1] == "SetMinDesiredHeight" then min_height = min_height + 1 end
            if c[1] == "SetHeightOverride" then height_override = height_override + 1 end
            if c[1] == "SetWidthOverride" then width_override = width_override + 1 end
        end
        eq(min_height, 1, "cell " .. i .. ": minimum height")
        eq(height_override, 0, "cell " .. i .. ": no fixed height")
        eq(width_override, 1, "cell " .. i .. ": fixed width")
    end
end)

test("an offset change moves the hint; a new shape rebuilds it", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(), 0)
    overlay.configure(values({ ["hint.offset_x"] = -500 }))
    eq(#built("UserWidget"), 1, "no rebuild for an offset")
    local slot
    for _, o in ipairs(objects) do
        if o.class == "Slot" and o.owner and o.owner.class == "/Script/UMG.CanvasPanel" then slot = o end
    end
    local x
    for _, c in ipairs(slot.calls) do
        if c[1] == "SetPosition" then x = c[2][1].X end
    end
    eq(x, -500, "moved")
    overlay.configure(values({ ["hint.scale"] = 150 }))
    eq(built("UserWidget")[1].removed, true, "old widget removed")
    overlay.show(tape(), 0)
    eq(#built("UserWidget"), 2, "rebuilt")
    local tk = tokens()
    eq(tk[#tk].text.Font.Size, 39, "letter size at 150 %")
end)

test("only changed texts are set again", function()
    local overlay = setup()
    overlay.configure(values())
    local m = tape()
    overlay.show(m, 0)
    local before = set_text_calls()
    overlay.show(m, 0)
    eq(set_text_calls(), before, "identical show")
end)

test("tape slide: a press moves the tape one cell right, back to 0 within slide_ms", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(V0), 1000)
    overlay.animate(1000)
    local body = built("HorizontalBox")[1]
    eq(body.translation, false, "no slide before a press")
    overlay.show(tape(V1), 2000)
    overlay.animate(2000)
    local step = math.floor(26 * 1.4 + 0.5)
    eq(body.translation.X, step, "starts one cell right")
    overlay.animate(2000 + config.overlay.slide_ms / 2)
    if not (body.translation.X > 0 and body.translation.X < step) then error("mid-slide X = " .. body.translation.X) end
    overlay.animate(2000 + config.overlay.slide_ms)
    eq(body.translation.X, 0, "settled")
end)

test("no slide when slide is off", function()
    local overlay = setup()
    overlay.configure(values({ ["tape.slide"] = false }))
    overlay.show(tape(V0), 1000)
    overlay.show(tape(V1), 2000)
    overlay.animate(2010)
    eq(built("HorizontalBox")[1].translation, false, "no slide")
end)

test("a miss shakes the plate and it settles after shake_ms; no shake when off", function()
    local overlay = setup()
    overlay.configure(values({ ["tape.slide"] = false }))
    overlay.show(tape(V0), 1000)
    overlay.show(tape(V_MISS), 2000)
    local plate = named("Plate")[1]
    overlay.animate(2000 + config.overlay.shake_ms / 4)
    if plate.translation.X == 0 then error("not shaking") end
    overlay.animate(2000 + config.overlay.shake_ms)
    eq(plate.translation.X, 0, "settled")
    overlay = setup()
    overlay.configure(values({ ["hint.shake"] = false }))
    overlay.show(tape(V0), 1000)
    overlay.show(tape(V_MISS), 2000)
    overlay.animate(2075)
    eq(named("Plate")[1].translation, false, "no shake")
end)

test("message hides the keys and the counter; hide hides the widget", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(), 0)
    overlay.message("Замок не в базе: X")
    local texts = built("TextBlock")
    eq(texts[2].text, "Замок не в базе: X", "message text")
    eq(texts[2].visibility, 3, "message shown")
    eq(texts[1].visibility, 1, "counter collapsed")
    eq(built("HorizontalBox")[1].visibility, 1, "keys collapsed")
    overlay.show(tape(), 0)
    eq(texts[2].visibility, 1, "message collapsed again")
    overlay.hide()
    eq(built("UserWidget")[1].visibility, 1, "widget collapsed")
end)

test("init does not touch the game until the first show", function()
    local overlay = setup()
    overlay.configure(values())
    eq(find_all_of_calls, 0, "FindAllOf not called before a show")
    overlay.show(tape(), 0)
    eq(find_all_of_calls, 1, "called on the first show")
    overlay.show(tape(), 0)
    eq(find_all_of_calls, 1, "only once")
end)

test("widgets of a previous load are removed on the first show", function()
    local stale = fake("/Script/UMG.UserWidget", "G1LPH_Overlay_1_1")
    local other = fake("/Script/UMG.UserWidget", "Other_Widget")
    local overlay = setup({ stale, other })
    overlay.configure(values())
    overlay.show(tape(), 0)
    eq(stale.removed, true, "stale widget removed")
    eq(other.removed, false, "other widget kept")
end)

test("a failing stale cleanup is logged and does not block the hint", function()
    local overlay = setup()
    FindAllOf = function() error("boom") end
    overlay.configure(values())
    overlay.show(tape(), 0)
    eq(#built("UserWidget"), 1, "widget built anyway")
    eq(count_logs("cannot remove widgets of a previous load"), 1, "logged")
end)

test("a key frame that cannot be drawn is logged once; the hint still shows", function()
    local overlay = setup()
    no_brush = true
    overlay.configure(values())
    overlay.show(tape(), 0)
    eq(#tokens(), 9, "keys built")
    eq(count_logs("cannot draw the key frame"), 1, "logged once")
end)

test("a plate frame that cannot be drawn is logged once; the hint and a dark plate still show", function()
    local overlay = setup()
    no_brush = true
    overlay.configure(values({ ["tape.plate"] = true }))
    overlay.show(tape(), 0)
    eq(#tokens(), 9, "keys built")
    eq(built("UserWidget")[1].visibility, 3, "hint shown")
    eq(named("Plate")[1].brush_color.A, config.overlay.plate_alpha, "plain dark plate")
    eq(count_logs("cannot draw the plate frame"), 1, "logged once")
    overlay.configure(values({ ["tape.plate"] = true, ["hint.scale"] = 150 }))
    overlay.show(tape(), 0)
    eq(#named("Plate"), 2, "rebuilt")
    eq(count_logs("cannot draw the plate frame"), 1, "still logged once")
end)

test("tape: empty cells keep their width (hidden, not collapsed)", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(V0), 0) -- no presses yet: the three done cells are empty
    local tk = tokens()
    eq(tk[1].box.visibility, 2, "empty done cell hidden")
    eq(tk[4].box.visibility, 3, "current shown")
    overlay.show(tape({ keys = { "W" }, index = 1, history = {}, pressed = 0, misses = 0 }), 0)
    eq(tk[5].box.visibility, 2, "empty next cell hidden")
end)

test("icons: set_icons draws the game's icon in place of the letter, tinted like the letter", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.set_icons("ps")
    overlay.show(tape(), 0)
    local tk, c = tokens(), config.overlay.colors
    eq(#built("UserWidget"), 1, "no rebuild")
    eq(tk[4].icon_row.visibility, 3, "current: icon shown")
    eq(tk[4].text.visibility, 1, "current: letter collapsed")
    eq(tk[4].image.brush.name, pad.key_texture("ps", "A"), "current: the A icon")
    eq(tk[2].image.brush.name, pad.key_texture("ps", "W"), "done: the W icon")
    eq(tk[4].image.color.R, c.simple.current.R, "current colour")
    eq(tk[1].image.color.R, c.miss.R, "miss red")
    eq(tk[2].image.color.G, c.done.G, "done green")
    eq(string.format("%.3f", tk[9].image.color.A), "0.150", "last next alpha")
    eq(tk[4].frame.visibility, 3, "the current icon keeps the frame")
    eq(tk[4].tail.visibility, 1, "no tail on the tape")
end)

test("icons: back to letters without a rebuild; a brush is set only when the key changes", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.set_icons("xbox")
    overlay.show(tape(), 0)
    eq(calls_of("SetBrushFromTexture"), 9, "one brush per shown key")
    overlay.show(tape(), 0)
    eq(calls_of("SetBrushFromTexture"), 9, "an identical show sets none")
    overlay.set_icons("keys")
    overlay.show(tape(), 0)
    local tk = tokens()
    eq(#built("UserWidget"), 1, "no rebuild")
    eq(tk[4].text.visibility, 3, "letter shown")
    eq(tk[4].icon_row.visibility, 1, "icon collapsed")
    eq(tk[4].text.text, "A", "the letter")
    eq(tk[4].text.color.R, config.overlay.colors.simple.current.R, "the letter's colour")
end)

test("icons in lines: a run is the icon and its count", function()
    local overlay = setup()
    overlay.configure(values({ ["hint.layout"] = "lines" }))
    overlay.set_icons("switch")
    local v = { keys = { "D", "A", "A", "A", "A", "A", "W" }, index = 2, history = { { key = "D", ok = true } }, pressed = 1, misses = 0 }
    overlay.show(lines(v), 0)
    local tk = tokens()
    eq(tk[2].image.brush.name, pad.key_texture("switch", "A"), "the run's icon")
    eq(tk[2].tail.text, "×5", "count")
    eq(tk[2].tail.visibility, 3, "tail shown")
    eq(tk[1].tail.visibility, 1, "a single key has no tail")
    eq(tk[2].frame.visibility, 3, "the run is current")
end)

test("a missing icon texture leaves the letter, logged once per texture", function()
    local overlay = setup()
    missing_textures = true
    overlay.configure(values())
    overlay.set_icons("ps")
    overlay.show(tape(), 0)
    local tk = tokens()
    eq(tk[4].text.visibility, 3, "letter shown")
    eq(tk[4].icon_row.visibility, 1, "no icon")
    eq(tk[4].text.text, "A", "the letter")
    eq(count_logs("icon not found"), 4, "A, W, S, D")
    overlay.show(tape(V1), 0)
    eq(count_logs("icon not found"), 4, "still once per texture")
end)

test("the icon is a square of the token's letter size times icon_scale", function()
    local overlay = setup()
    overlay.configure(values())
    overlay.show(tape(), 0)
    local function width(box)
        for _, c in ipairs(box.calls) do
            if c[1] == "SetWidthOverride" then return c[2][1] end
        end
    end
    local function height(box)
        for _, c in ipairs(box.calls) do
            if c[1] == "SetHeightOverride" then return c[2][1] end
        end
    end
    local boxes, scale = named("IconBox"), config.overlay.icon_scale
    eq(#boxes, 9, "one per cell")
    eq(width(boxes[4]), math.floor(34 * scale + 0.5), "current: 1.3 x letter size")
    eq(height(boxes[4]), math.floor(34 * scale + 0.5), "square")
    eq(width(boxes[1]), math.floor(26 * scale + 0.5), "other cells")
end)

print = real_print
t.finish()
