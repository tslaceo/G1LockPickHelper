-- G1LockPickHelper overlay: the hint drawn with UMG widgets built at runtime (UE4SS).
-- Call every function on the game thread. What to draw comes from view.lua, the shape and placement from
-- the player's settings (configure). A new shape rebuilds the widget: a font can only be set before a text
-- is first shown (SetFont on a shown text changes only the size; measured in game).
local M = {}

-- ESlateVisibility: HitTestInvisible (drawn, never takes input), Collapsed, Hidden (invisible, keeps its space)
local SHOWN, COLLAPSED, HIDDEN = 3, 1, 2
local FILL, CENTER = 0, 2      -- EHorizontalAlignment / EVerticalAlignment
local ROUNDED_BOX = 4          -- ESlateBrushDrawType::RoundedBox
local CORNER_RADIUS = 3        -- of the key frame and of the plate
local NO_PAD = { Left = 0, Top = 0, Right = 0, Bottom = 0 }
local cfg                      -- config.overlay
local opts                     -- shape and placement from the settings, see configure
local ui                       -- the built widget tree, see build
local serial = 0
local text_lib
local load_stamp = math.floor(os.clock() * 1000)
local stale_pending = false
local fonts = {}               -- font path -> font object, or false when the game has no such font
local frame_warned = false
local plate_warned = false
local anim = { pressed = 0, misses = 0 } -- counts seen last; slide/shake: start times of running animations

local function log(fmt, ...)
    print("[G1LockPickHelper] " .. string.format(fmt, ...) .. "\n")
end

local function round(x)
    return math.floor(x + 0.5)
end

local function to_text(s)
    if FText then return FText(s) end
    text_lib = text_lib or StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
    return text_lib:Conv_StringToText(s)
end

local function construct(class_path, outer, kind)
    local class = StaticFindObject(class_path)
    if not (class and class:IsValid()) then error("class not found: " .. class_path) end
    serial = serial + 1
    return StaticConstructObject(class, outer, FName(string.format("G1LPH_%s_%d_%d", kind, load_stamp, serial)))
end

-- The game's font at spec.path (loaded with the game's UI), or nil: the engine font is used then. Both lookups
-- run under pcall (LoadAsset may raise for a missing asset); a failure is cached and logged once per path.
local function find_font(spec)
    local path = spec.path
    local f = fonts[path]
    if f == false then return nil end
    if f and f:IsValid() then return f end
    local ok, found = pcall(function()
        local obj = StaticFindObject(path)
        if not (obj and obj:IsValid()) and LoadAsset then obj = LoadAsset(path) end
        if obj and obj:IsValid() then return obj end
    end)
    if ok and found then
        fonts[path] = found
        return found
    end
    fonts[path] = false
    if ok then
        log("font not found, using the engine font: %s", path)
    else
        log("font not found, using the engine font: %s (%s)", path, tostring(found))
    end
    return nil
end

-- A text block; its font is written in place before the first show (the only way that works).
local function new_text(tree, font, size, color)
    local text = construct("/Script/UMG.TextBlock", tree, "Text")
    local f = find_font(font)
    if f then
        text.Font.FontObject = f
        text.Font.TypefaceFontName = FName(font.typeface)
    end
    text.Font.Size = size
    text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    text:SetShadowOffset({ X = 1.5, Y = 1.5 })
    text:SetShadowColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.9 })
    return text
end

-- Draws a Border as a rounded box: `fill` inside, an outline of `width` px in `outline`. Returns pcall's
-- result (false and the error when the brush cannot be written); the caller decides how to fall back.
local function rounded(border, fill, outline, width)
    return pcall(function()
        local brush = border.Background
        brush.DrawAs = ROUNDED_BOX
        brush.TintColor = { SpecifiedColor = fill, ColorUseRule = 0 }
        brush.OutlineSettings.Width = width
        brush.OutlineSettings.Color = { SpecifiedColor = outline, ColorUseRule = 0 }
        brush.OutlineSettings.RoundingType = 0 -- FixedRadius
        local r = CORNER_RADIUS
        brush.OutlineSettings.CornerRadii = { X = r, Y = r, Z = r, W = r }
        border:SetBrushColor({ R = 1, G = 1, B = 1, A = 1 })
    end)
end

-- A Border drawn as a rounded box: style.fill inside, a 2 px outline in style.frame. Without the brush the
-- frame stays invisible (logged once).
local function new_frame(tree, style)
    local frame = construct("/Script/UMG.Border", tree, "Frame")
    local ok, err = rounded(frame, style.fill, style.frame, 2.0)
    if not ok then
        if not frame_warned then
            frame_warned = true
            log("cannot draw the key frame: %s", tostring(err))
        end
        frame:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
    end
    return frame
end

-- One key: a UMG Overlay with the frame (shown for the current key only) under the text.
local function new_token(tree, style, font, size, pad)
    local box = construct("/Script/UMG.Overlay", tree, "Token")
    local frame = new_frame(tree, style)
    local frame_slot = box:AddChildToOverlay(frame)
    frame_slot:SetHorizontalAlignment(FILL)
    frame_slot:SetVerticalAlignment(FILL)
    local text = new_text(tree, font, size, style.next)
    text:SetJustification(1) -- ETextJustify::Center
    local text_slot = box:AddChildToOverlay(text)
    text_slot:SetHorizontalAlignment(CENTER)
    text_slot:SetVerticalAlignment(CENTER)
    text_slot:SetPadding(pad)
    frame:SetVisibility(COLLAPSED)
    return { box = box, frame = frame, text = text, framed = false }
end

-- A cell of the tape with a fixed width, known without measuring (GetCachedGeometry gives zeros); the tape
-- slide relies on it. The height is only a minimum: the gothic font has a taller line box than the simple
-- one, and a fixed height would let its letter stick out of the frame. The row stretches every cell to the
-- tallest one, so the frame of the current cell (slot alignment Fill) encloses the text.
local function new_cell(tree, content, w, h)
    local cell = construct("/Script/UMG.SizeBox", tree, "Cell")
    cell:SetWidthOverride(w)
    cell:SetMinDesiredHeight(h)
    local slot = cell:SetContent(content)
    slot:SetHorizontalAlignment(FILL)
    slot:SetVerticalAlignment(FILL)
    return cell
end

local function build()
    local outer = FindFirstOf("GameInstance")
    if not (outer and outer:IsValid()) then error("no GameInstance") end
    local style, letters, f = cfg.colors[opts.style], cfg.fonts[opts.style], opts.size
    local widget = construct("/Script/UMG.UserWidget", outer, "Overlay")
    local tree = construct("/Script/UMG.WidgetTree", widget, "Tree")
    widget.WidgetTree = tree
    local canvas = construct("/Script/UMG.CanvasPanel", tree, "Canvas")
    tree.RootWidget = canvas
    local plate = construct("/Script/UMG.Border", tree, "Plate")
    local dark = opts.layout == "tape" and opts.plate
    if dark then
        local fill = { R = 0, G = 0, B = 0, A = cfg.plate_alpha }
        local ok, err = rounded(plate, fill, cfg.colors.plate_frame, 1.5)
        if not ok then
            if not plate_warned then
                plate_warned = true
                log("cannot draw the plate frame: %s", tostring(err))
            end
            plate:SetBrushColor(fill)
        end
    else
        plate:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
    end
    plate:SetPadding({ Left = round(f * 0.4), Top = round(f * 0.2), Right = round(f * 0.4), Bottom = round(f * 0.2) })
    local slot = canvas:AddChildToCanvas(plate)
    slot:SetAnchors({ Minimum = cfg.anchor, Maximum = cfg.anchor })
    slot:SetAlignment(cfg.pivot)
    slot:SetPosition(opts.offset)
    slot:SetAutoSize(true)
    local column = construct("/Script/UMG.VerticalBox", tree, "Column")
    plate:SetContent(column)
    local built = { widget = widget, slot = slot, plate = plate, cells = {}, rows = {}, texts = {} }
    built.counter = new_text(tree, cfg.fonts.text, math.max(10, round(f * 0.6)), cfg.colors.counter)
    column:AddChildToVerticalBox(built.counter)
    built.message = new_text(tree, cfg.fonts.text, f, cfg.colors.message)
    column:AddChildToVerticalBox(built.message)
    if opts.layout == "tape" then
        built.body = construct("/Script/UMG.HorizontalBox", tree, "Tape")
        local w, h = round(f * 1.4), round(f * 1.8)
        built.step_px = w
        for i = 1, opts.done + 1 + opts.next do
            local current = i == opts.done + 1
            local tok = new_token(tree, style, letters, current and round(f * 1.3) or f, NO_PAD)
            tok.keep_space = true -- empty tape cells stay hidden to keep their width; lines tokens stay collapsed
            built.body:AddChildToHorizontalBox(new_cell(tree, tok.box, current and round(f * 2.0) or w, h))
            built.cells[i] = tok
        end
    else
        built.body = construct("/Script/UMG.VerticalBox", tree, "Lines")
        local pad = { Left = round(f * 0.25), Top = round(f * 0.1), Right = round(f * 0.25), Bottom = round(f * 0.1) }
        for r = 1, opts.max_lines do
            local row = { box = construct("/Script/UMG.HorizontalBox", tree, "Row"), tokens = {} }
            built.body:AddChildToVerticalBox(row.box)
            for c = 1, opts.per_line do
                local tok = new_token(tree, style, letters, f, pad)
                local s = row.box:AddChildToHorizontalBox(tok.box)
                s:SetPadding({ Left = 0, Top = 0, Right = round(f * 0.15), Bottom = 0 })
                row.tokens[c] = tok
            end
            built.rows[r] = row
        end
    end
    column:AddChildToVerticalBox(built.body)
    widget:SetVisibility(COLLAPSED)
    widget:AddToViewport(cfg.z_order)
    return built
end

-- Widgets left in the viewport by a previous load of the mod (UE4SS hot reload).
local function remove_stale()
    local widgets = FindAllOf("UserWidget")
    if not widgets then return end
    for _, w in ipairs(widgets) do
        if w:IsValid() and w:GetFName():ToString():find("^G1LPH_Overlay_") then
            pcall(function() w:RemoveFromParent() end)
        end
    end
end

-- Builds the widget on first use, after a shape change and after the engine dropped it (level change).
local function ensure()
    if not opts then return false end
    if stale_pending then
        stale_pending = false
        local ok, err = pcall(remove_stale)
        if not ok then log("overlay: cannot remove widgets of a previous load: %s", tostring(err)) end
    end
    if ui and ui.widget:IsValid() then
        if not ui.widget:IsInViewport() then ui.widget:AddToViewport(cfg.z_order) end
        return true
    end
    local ok, result = pcall(build)
    if not ok then
        log("overlay: cannot build the widget: %s", tostring(result))
        ui = nil
        return false
    end
    ui = result
    return true
end

-- overlay_cfg: config.overlay.
function M.init(overlay_cfg)
    cfg, ui, opts = overlay_cfg, nil, nil
    anim = { pressed = 0, misses = 0 }
    stale_pending = true
end

-- values: the player's settings (settings.lua). A new shape rebuilds the widget on the next show; a new
-- offset moves the shown widget at once.
function M.configure(values)
    local h = values.hint
    local new = {
        layout = h.layout, style = h.style, size = math.max(8, round(cfg.base_font_size * h.scale / 100)),
        counter = h.counter, shake = h.shake, slide = values.tape.slide, plate = values.tape.plate,
        next = values.tape.next, done = values.tape.done,
        per_line = values.lines.per_line, max_lines = values.lines.max_lines,
        offset = { X = h.offset_x, Y = h.offset_y },
    }
    new.shape = table.concat({ new.layout, new.style, new.size, new.next, new.done, new.per_line,
        new.max_lines, tostring(new.plate) }, "|")
    if ui and opts.shape ~= new.shape then
        local old = ui.widget
        pcall(function() old:RemoveFromParent() end)
        ui = nil
    end
    opts = new
    if ui then
        local slot, offset = ui.slot, opts.offset
        pcall(function() slot:SetPosition(offset) end)
    end
end

-- A counter/message text: SetText only when it changed; the FText stays referenced from Lua.
local function set_text(key, block, s)
    local shown = ui.texts[key]
    if shown and shown.s == s then return end
    local text = to_text(s)
    block:SetText(text)
    ui.texts[key] = { s = s, text = text }
end

local function color_of(role, alpha)
    local style = cfg.colors[opts.style]
    local c = (role == "done" or role == "miss") and cfg.colors[role] or role == "current" and style.current or style.next
    return { R = c.R, G = c.G, B = c.B, A = c.A * alpha }
end

-- One key of the model; UE is called only for what changed.
local function set_token(tok, text, role, alpha)
    local shown = text ~= ""
    if tok.shown ~= shown then
        if shown then
            tok.box:SetVisibility(SHOWN)
        elseif tok.keep_space then
            tok.box:SetVisibility(HIDDEN)
        else
            tok.box:SetVisibility(COLLAPSED)
        end
        tok.shown = shown
    end
    if not shown then return end
    if tok.s ~= text then
        local t = to_text(text)
        tok.text:SetText(t)
        tok.s, tok.ftext = text, t
    end
    local c = color_of(role, alpha)
    local sig = string.format("%.3f %.3f %.3f %.3f", c.R, c.G, c.B, c.A)
    if tok.color ~= sig then
        tok.text:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 })
        tok.color = sig
    end
    local framed = role == "current"
    if tok.framed ~= framed then
        tok.frame:SetVisibility(framed and SHOWN or COLLAPSED)
        tok.framed = framed
    end
end

-- model: view.tape(...) or view.lines(...) for the configured layout; model.counter_always shows the counter
-- whatever the setting (the autosolver's text). now_ms starts the animations.
function M.show(model, now_ms)
    if not ensure() then return end
    if model.kind ~= opts.layout then return end -- the settings changed after the model was made
    set_text("counter", ui.counter, model.counter)
    ui.counter:SetVisibility((opts.counter or model.counter_always) and SHOWN or COLLAPSED)
    ui.message:SetVisibility(COLLAPSED)
    ui.body:SetVisibility(SHOWN)
    if model.kind == "tape" then
        for i, tok in ipairs(ui.cells) do
            local c = model.cells[i]
            if c then set_token(tok, c.text, c.role, c.alpha) else set_token(tok, "", "empty", 0) end
        end
    else
        for r, row in ipairs(ui.rows) do
            local line = model.lines[r]
            row.box:SetVisibility(line and SHOWN or COLLAPSED)
            for c, tok in ipairs(row.tokens) do
                local token = line and line[c]
                if token then set_token(tok, token.text, token.role, 1) else set_token(tok, "", "empty", 0) end
            end
        end
    end
    if model.pressed > anim.pressed and model.kind == "tape" and opts.slide then anim.slide = now_ms end
    if model.misses > anim.misses and opts.shake then anim.shake = now_ms end
    anim.pressed, anim.misses = model.pressed, model.misses
    ui.widget:SetVisibility(SHOWN)
end

function M.message(text)
    if not ensure() then return end
    set_text("message", ui.message, text)
    ui.message:SetVisibility(SHOWN)
    ui.counter:SetVisibility(COLLAPSED)
    ui.body:SetVisibility(COLLAPSED)
    ui.widget:SetVisibility(SHOWN)
end

function M.hide()
    if ui and ui.widget:IsValid() then ui.widget:SetVisibility(COLLAPSED) end
end

local function ease_out(t)
    return 1 - (1 - t) * (1 - t)
end

-- Every frame: the tape slides back into place after a press; the plate shakes after a miss.
function M.animate(now_ms)
    if not ui then return end
    if anim.slide then
        local t = (now_ms - anim.slide) / cfg.slide_ms
        if t >= 1 then
            anim.slide = nil
            ui.body:SetRenderTranslation({ X = 0, Y = 0 })
        else
            ui.body:SetRenderTranslation({ X = ui.step_px * (1 - ease_out(math.max(0, t))), Y = 0 })
        end
    end
    if anim.shake then
        local t = (now_ms - anim.shake) / cfg.shake_ms
        if t >= 1 then
            anim.shake = nil
            ui.plate:SetRenderTranslation({ X = 0, Y = 0 })
        else
            local amplitude = cfg.shake_px * opts.size / cfg.base_font_size
            ui.plate:SetRenderTranslation({ X = amplitude * math.sin(t * 6 * math.pi) * (1 - t), Y = 0 })
        end
    end
end

return M
