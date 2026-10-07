-- G1LockPickHelper languages: which one to use and its texts (lang/<id>.lua). Pure Lua 5.4, no UE4SS API.
-- The game's culture is read by main.lua (KismetInternationalizationLibrary.GetCurrentCulture).
local M = {}

M.LANGS = { "en", "ru" } -- en first: it fills whatever another language lacks

-- setting: [general] language ("auto" | "en" | "ru"); culture: the game's culture ("ru", "en-US", ...) or nil.
function M.resolve(setting, culture)
    if setting == "en" or setting == "ru" then return setting end
    if setting == "auto" and type(culture) == "string" then
        local c = culture:lower()
        if c == "ru" or c:match("^ru[-_]") then return "ru" end
    end
    return "en"
end

-- base with over's values where over has them; a list (like the settings.ini header) is taken whole.
local function merge(base, over)
    local out = {}
    for k, v in pairs(base) do
        local o = over and over[k]
        if type(v) == "table" and v[1] == nil then
            out[k] = merge(v, type(o) == "table" and o or nil)
        elseif o ~= nil and type(o) == type(v) then
            out[k] = o
        else
            out[k] = v
        end
    end
    return out
end

-- The texts of `lang` ({ text, ini }), with anything it lacks taken from English; an unknown or broken language
-- is English. require_fn is for tests.
function M.load(lang, require_fn)
    require_fn = require_fn or require
    local en = require_fn("lang.en")
    if lang == "en" then return en end
    local ok, other = pcall(require_fn, "lang." .. tostring(lang))
    if not ok or type(other) ~= "table" then return en end
    return merge(en, other)
end

return M
