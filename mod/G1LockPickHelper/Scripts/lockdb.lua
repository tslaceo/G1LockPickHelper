-- G1LockPickHelper lock database: case-insensitive lookup over lockgraphs.lua. Pure Lua 5.4.
local M = {}

-- The solver's graph { plates, links = { [src] = { {dst, dir}, ... } } } from a lock's authored connections
-- { {src, dst, dir}, ... } without the first `skip` of them.
function M.graph(plates, edges, skip)
    local links = {}
    for i = skip + 1, #edges do
        local e = edges[i]
        local list = links[e[1]] or {}
        list[#list + 1] = { e[2], e[3] }
        links[e[1]] = list
    end
    return { plates = plates, links = links }
end

-- data: the table returned by lockgraphs.lua. Returns { build = string, find = function(name, k) }, where
-- find(name, k) -> graph, name as stored in the database, connections removed | nil. The game removes the
-- first round(LockpickPrecision) connections of a lock at minigame setup ("Lockpicking skill" in
-- docs/TECHNICAL.md): k is that number (nil: 0), clamped to 0..#edges. FNames ignore case, the cache keeps it.
function M.new(data)
    local index = {}
    for name, lock in pairs(data.locks) do
        index[name:lower()] = { name = name, lock = lock }
    end
    return {
        build = data.build,
        find = function(name, k)
            local entry = index[name:lower()]
            if not entry then return nil end
            local edges = entry.lock.edges
            k = math.max(0, math.min(#edges, k or 0))
            return M.graph(entry.lock.plates, edges, k), entry.name, k
        end,
    }
end

-- raw: bytes of G1R\Version\version.txt (UTF-16 LE). Returns "Build<N>_CL<N>" or nil.
function M.parse_build(raw)
    return (raw:gsub("%z", "")):match("Build%d+_CL%d+")
end

return M
