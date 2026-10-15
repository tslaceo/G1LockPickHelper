-- G1LockPickHelper settings: the player's settings.ini - schema, parsing, checking, writing. Pure Lua 5.4
-- (io is passed in for tests). Values are nested: values.hint.layout, values.tape.next, values.keys.W.
-- The file's header and comments are in the player's language: the `ini` table of lang/<id>.lua.
local M = {}

-- Order here is the order in the file.
M.SCHEMA = {
    { section = "general", key = "language", kind = "choice", default = "auto", choices = { "auto", "en", "ru" } },
    { section = "general", key = "debug", kind = "bool", default = false },
    { section = "general", key = "smm_fix", kind = "bool", default = true },
    { section = "hint", key = "layout", kind = "choice", default = "tape", choices = { "tape", "lines" } },
    { section = "hint", key = "style", kind = "choice", default = "simple", choices = { "simple", "gothic" } },
    { section = "hint", key = "icons", kind = "choice", default = "auto", choices = { "auto", "keys", "gamepad" } },
    { section = "hint", key = "gamepad", kind = "choice", default = "auto",
        choices = { "auto", "playstation", "xbox", "switch" } },
    { section = "hint", key = "scale", kind = "int", default = 100, min = 50, max = 200 },
    { section = "hint", key = "offset_x", kind = "int", default = -760, min = -3000, max = 3000 },
    { section = "hint", key = "offset_y", kind = "int", default = 0, min = -2000, max = 2000 },
    { section = "hint", key = "counter", kind = "bool", default = true },
    { section = "hint", key = "shake", kind = "bool", default = true },
    { section = "tape", key = "next", kind = "int", default = 5, min = 1, max = 10 },
    { section = "tape", key = "done", kind = "int", default = 3, min = 0, max = 6 },
    { section = "tape", key = "slide", kind = "bool", default = true },
    { section = "tape", key = "plate", kind = "bool", default = false },
    { section = "lines", key = "per_line", kind = "int", default = 16, min = 4, max = 40 },
    { section = "lines", key = "max_lines", kind = "int", default = 6, min = 1, max = 12 },
    { section = "lines", key = "collapse_min", kind = "int", default = 3, min = 0, max = 20 },
    { section = "lines", key = "plate", kind = "bool", default = false },
    { section = "solve", key = "auto", kind = "bool", default = false },
    { section = "solve", key = "double_reset", kind = "bool", default = true },
    { section = "solve", key = "timer", kind = "bool", default = true },
    { section = "keys", key = "toggle", kind = "key", default = "F4" },
    { section = "keys", key = "solve", kind = "key", default = "F3" },
    { section = "keys", key = "W", kind = "key", default = "W" },
    { section = "keys", key = "S", kind = "key", default = "S" },
    { section = "keys", key = "A", kind = "key", default = "A" },
    { section = "keys", key = "D", kind = "key", default = "D" },
}

local index = {} -- "section.key" in lower case -> schema entry
for _, e in ipairs(M.SCHEMA) do
    index[e.section .. "." .. e.key:lower()] = e
end

function M.entry(section, key)
    return index[tostring(section):lower() .. "." .. tostring(key):lower()]
end

function M.defaults()
    local values = {}
    for _, e in ipairs(M.SCHEMA) do
        values[e.section] = values[e.section] or {}
        values[e.section][e.key] = e.default
    end
    return values
end

local BOOLS = {
    ["true"] = true, ["1"] = true, yes = true, on = true,
    ["false"] = false, ["0"] = false, no = false, off = false,
}

-- Checks one value (a string from the file or a Lua value from the menu) against its schema entry.
-- Returns the value to store and, when it differs from what was given, a description of the problem.
local function coerce(e, raw)
    local given = string.format("[%s] %s = %s", e.section, e.key, tostring(raw))
    if e.kind == "int" then
        local n = tonumber(raw)
        if not n or n ~= n or n == math.huge or n == -math.huge then
            return e.default, string.format("%s is not a number, using %d", given, e.default)
        end
        n = math.floor(n + 0.5)
        if n < e.min or n > e.max then
            local clamped = math.max(e.min, math.min(e.max, n))
            return clamped, string.format("%s is out of range %d..%d, using %d", given, e.min, e.max, clamped)
        end
        return n
    elseif e.kind == "bool" then
        if type(raw) == "boolean" then return raw end
        local b = BOOLS[tostring(raw):lower()]
        if b == nil then return e.default, string.format("%s is not true/false, using %s", given, tostring(e.default)) end
        return b
    elseif e.kind == "choice" then
        local s = tostring(raw):lower()
        for _, c in ipairs(e.choices) do
            if c == s then return c end
        end
        return e.default, string.format("%s is not one of %s, using %s", given, table.concat(e.choices, "|"), e.default)
    end
    -- key: a UE4SS key name; whether such a key exists is checked where the keys are bound
    local s = tostring(raw)
    if s:match("^[%w_]+$") then return s:upper() end
    return e.default, string.format("%s is not a key name, using %s", given, e.default)
end

-- Sets one value. Returns false for an unknown setting; true plus a problem when the value was adjusted.
function M.set(values, section, key, raw)
    local e = M.entry(section, key)
    if not e then return false, string.format("unknown setting [%s] %s", tostring(section), tostring(key)) end
    local value, problem = coerce(e, raw)
    values[e.section][e.key] = value
    return true, problem
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Parses settings.ini text. Returns values (defaults for anything missing or wrong) and a list of problems.
function M.parse(text)
    local values, problems = M.defaults(), {}
    local section
    local n = 0
    text = text:gsub("^\239\187\191", "") -- UTF-8 BOM
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        line = trim((line:gsub("\r$", "")))
        line = line:gsub("%s*[;#].*$", "") -- strip trailing comment from whole line
        line = trim(line) -- trim again after comment removal
        if line ~= "" then
            local name = line:match("^%[%s*([%w_]+)%s*%]$")
            if name then
                section = name:lower()
            else
                local key, value = line:match("^([%w_]+)%s*=%s*(.-)$")
                if not key then
                    problems[#problems + 1] = string.format("line %d: cannot read %q", n, line)
                elseif not section or not M.entry(section, key) then
                    problems[#problems + 1] = string.format("line %d: unknown setting [%s] %s", n, tostring(section), key)
                else
                    value = trim(value)
                    local _, problem = M.set(values, section, key, value)
                    if problem then problems[#problems + 1] = string.format("line %d: %s", n, problem) end
                end
            end
        end
    end
    return values, problems
end

local function format_value(e, v)
    if e.kind == "bool" then return v and "true" or "false" end
    if e.kind == "int" then return string.format("%d", v) end
    return tostring(v)
end

-- The whole file: the header, sections in schema order, one line per setting with its comment.
-- ini: { header = { lines }, comments = { ["section.key"] = text } } of the language (lang/<id>.lua).
function M.serialize(values, ini)
    ini = ini or { header = {}, comments = {} }
    local out = {}
    for _, line in ipairs(ini.header) do out[#out + 1] = line end
    local section
    for _, e in ipairs(M.SCHEMA) do
        if e.section ~= section then
            section = e.section
            out[#out + 1] = ""
            out[#out + 1] = "[" .. section .. "]"
        end
        local v = values[e.section] and values[e.section][e.key]
        if v == nil then v = e.default end
        local line = e.key .. " = " .. format_value(e, v)
        local comment = ini.comments[e.section .. "." .. e.key]
        if comment then line = line .. "  ; " .. comment end
        out[#out + 1] = line
    end
    return table.concat(out, "\n") .. "\n"
end

-- Reads settings.ini. Returns values (defaults for anything missing or wrong), problems, and true when the file
-- could not be opened (missing): the caller writes it once it knows the player's language.
function M.load(path, io_lib)
    io_lib = io_lib or io
    local f = io_lib.open(path, "rb")
    if not f then return M.defaults(), {}, true end
    local text = f:read("a") or ""
    f:close()
    local values, problems = M.parse(text)
    return values, problems, false
end

-- Writes settings.ini with the header and comments of `ini` (the language). Returns true, or false and the error.
function M.save(path, values, ini, io_lib)
    io_lib = io_lib or io
    local f, err = io_lib.open(path, "wb")
    if not f then return false, err end
    local ok, werr = f:write(M.serialize(values, ini))
    local closed, cerr = f:close()
    if not ok then return false, werr end
    if not closed then return false, cerr end
    return true
end

return M
