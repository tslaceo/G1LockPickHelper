-- G1LockPickHelper menu: the settings in Shared Mod Menu (F2), when that mod is installed. Its bridge
-- (modmenu.lua) is loaded from Shared Mod Menu's own folder; we do not ship it.
-- The bridge calls get/set from its own game-thread loop in this mod's Lua state; set only reports the
-- change through opts.on_change, which must touch Lua tables only (no UE calls).
-- The keys tab is read-only: its actions do nothing (the bridge has no text items), the keys change in
-- settings.ini and take effect after a game restart.
-- Texts come from opts.text (lang/<id>.lua, text.menu); after a language change main.lua calls update().
local M = {}

-- Menu layout: `section`/`key` name a setting (settings.lua); `on`/`off` map a switch to a two-value
-- setting; `choices` map a slider 0..n-1 to a choice setting; names and hints come from opts.text by `id`.
M.SECTIONS = {
    { id = "general", items = {
        { id = "language", section = "general", key = "language", kind = "num", choices = { "auto", "en", "ru" } },
        { id = "smm_fix", section = "general", key = "smm_fix", kind = "bool" },
    } },
    { id = "view", items = {
        { id = "tape", section = "hint", key = "layout", kind = "bool", on = "tape", off = "lines" },
        { id = "gothic", section = "hint", key = "style", kind = "bool", on = "gothic", off = "simple" },
        { id = "icons", section = "hint", key = "icons", kind = "num", choices = { "auto", "keys", "gamepad" } },
        { id = "gamepad", section = "hint", key = "gamepad", kind = "num",
            choices = { "auto", "playstation", "xbox", "switch" } },
        { id = "scale", section = "hint", key = "scale", kind = "num", step = 10 },
        { id = "offset_x", section = "hint", key = "offset_x", kind = "num", step = 20 },
        { id = "offset_y", section = "hint", key = "offset_y", kind = "num", step = 20 },
        { id = "counter", section = "hint", key = "counter", kind = "bool" },
        { id = "shake", section = "hint", key = "shake", kind = "bool" },
        { id = "preview", kind = "action" },
        { id = "reset_position", kind = "action" },
    } },
    { id = "tape", items = {
        { id = "next", section = "tape", key = "next", kind = "num", step = 1 },
        { id = "done", section = "tape", key = "done", kind = "num", step = 1 },
        { id = "slide", section = "tape", key = "slide", kind = "bool" },
        { id = "plate", section = "tape", key = "plate", kind = "bool" },
    } },
    { id = "lines", items = {
        { id = "per_line", section = "lines", key = "per_line", kind = "num", step = 1 },
        { id = "max_lines", section = "lines", key = "max_lines", kind = "num", step = 1 },
        { id = "collapse_min", section = "lines", key = "collapse_min", kind = "num", step = 1 },
    } },
    { id = "solve", items = {
        { id = "solve_auto", section = "solve", key = "auto", kind = "bool" },
        { id = "double_reset", section = "solve", key = "double_reset", kind = "bool" },
    } },
}

local function menu_item(it, opts)
    local item = { name = opts.text.items[it.id] or it.id, kind = it.kind, desc = opts.text.desc[it.id] }
    if it.kind == "action" then
        item.set = function() opts.actions[it.id]() end
    elseif it.choices then
        local n = #it.choices
        item.min, item.max, item.step = 0, n - 1, 1
        item.get = function()
            local v = opts.values[it.section][it.key]
            for i, c in ipairs(it.choices) do
                if c == v then return i - 1 end
            end
            return 0
        end
        item.set = function(v)
            local i = math.floor((tonumber(v) or 0) + 0.5) + 1
            opts.on_change(it.section, it.key, it.choices[math.max(1, math.min(n, i))])
        end
    elseif it.on then
        item.get = function() return opts.values[it.section][it.key] == it.on end
        item.set = function(v) opts.on_change(it.section, it.key, v and it.on or it.off) end
    elseif it.kind == "bool" then
        item.get = function() return opts.values[it.section][it.key] end
        item.set = function(v) opts.on_change(it.section, it.key, v and true or false) end
    else
        local e = opts.schema(it.section, it.key)
        item.min, item.max, item.step = e.min, e.max, it.step
        item.get = function() return opts.values[it.section][it.key] end
        item.set = function(v) opts.on_change(it.section, it.key, v) end
    end
    return item
end

-- The keys tab: the binds as action items (the bridge has switches, numbers and actions only) whose set
-- does nothing. opts.keys holds the configured names, opts.missing_keys marks the ones UE4SS did not know. The last
-- item tells about the double reset (two resets in a row start the autosolver; the gamepad's way).
local function keys_section(opts)
    local function K(id)
        local name = opts.keys[id]
        if opts.missing_keys and opts.missing_keys[id] then return string.format(opts.text.key_missing, name) end
        return name
    end
    local function key_item(name, desc)
        return { name = name, kind = "action", desc = desc or opts.text.desc.keys, set = function() end }
    end
    return { title = opts.text.sections.keys, items = {
        key_item(string.format(opts.text.items.key_toggle, K("toggle"))),
        key_item(string.format(opts.text.items.key_solve, K("solve"))),
        key_item(string.format(opts.text.items.key_select, K("W"), K("S"))),
        key_item(string.format(opts.text.items.key_shift, K("A"), K("D"))),
        key_item(opts.text.items.key_double_reset, opts.text.desc.key_double_reset),
    } }
end

-- The bridge's spec: { { title, items = { { name, kind, desc, get, set, min, max, step }, ... } }, ... }.
function M.spec(opts)
    local out = {}
    for _, section in ipairs(M.SECTIONS) do
        local items = {}
        for _, it in ipairs(section.items) do items[#items + 1] = menu_item(it, opts) end
        out[#out + 1] = { title = opts.text.sections[section.id] or section.id, items = items }
    end
    if opts.keys then out[#out + 1] = keys_section(opts) end
    return out
end

local function register(bridge, opts)
    local ok, err = pcall(bridge.register, opts.text.name, M.spec(opts))
    if not ok then return false, err end
    return true
end

-- Loads <mods_dir>/SharedModMenu/Scripts/modmenu.lua and registers the settings. Returns the bridge when
-- registered; otherwise false after one log line, and the mod keeps working on settings.ini alone.
function M.attach(opts)
    local path = opts.mods_dir .. "/SharedModMenu/Scripts/modmenu.lua"
    local chunk, err = (opts.loadfile or loadfile)(path)
    if not chunk then
        opts.log("Shared Mod Menu not found (settings.ini only): %s", tostring(err))
        return false
    end
    local ok, bridge = pcall(chunk)
    if not (ok and type(bridge) == "table" and type(bridge.register) == "function") then
        opts.log("Shared Mod Menu bridge did not load: %s", tostring(bridge))
        return false
    end
    local registered, rerr = register(bridge, opts)
    if not registered then
        opts.log("Shared Mod Menu registration failed: %s", tostring(rerr))
        return false
    end
    opts.log("settings menu registered in Shared Mod Menu (bridge API %s)", tostring(bridge.VERSION))
    return bridge
end

-- Registers the settings again (new texts after a language change) and asks an open menu to re-read them
-- (checked with bridge API 3 only: an open menu re-reads at once, a closed one on its next open; older bridges
-- are untested). True when registered.
function M.update(bridge, opts)
    local ok, err = register(bridge, opts)
    if not ok then
        opts.log("Shared Mod Menu update failed: %s", tostring(err))
        return false
    end
    if type(bridge.requestRefresh) == "function" then pcall(bridge.requestRefresh) end
    return true
end

return M
