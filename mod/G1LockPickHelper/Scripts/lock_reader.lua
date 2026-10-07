-- G1LockPickHelper lock reader: the only module that touches game objects (paths: "The minigame" in docs/TECHNICAL.md).
-- Every UE4SS call happens inside functions, so the pure helpers load in standalone Lua for tests.
local M = {}

-- Settled plate offsets (plate X - bar X) for holes 1..7, measured in game; D moves toward hole 7.
local HOLE_DX = { -18.50, -12.20, -6.10, 0.00, 6.30, 12.50, 18.70 }
local TOLERANCE = 0.1

-- dxs: offsets of the visible plates, front to back. Returns holes 1..7 (integers), or nil while any
-- plate is between holes (the game animates every move for about 0.6-1 s).
function M.to_positions(dxs)
    local out = {}
    for i, dx in ipairs(dxs) do
        for hole, ref in ipairs(HOLE_DX) do
            if math.abs(dx - ref) <= TOLERANCE then
                out[i] = hole
                break
            end
        end
        if not out[i] then return nil end
    end
    return out
end

local function valid(obj)
    return obj ~= nil and obj:IsValid()
end

-- task: the AbilityTask_LockPick from NotifyOnNewObject. True while that minigame is open.
function M.active(task)
    return valid(task) and valid(task.Ability)
end

-- Returns the lock's m_UniqueName or nil, err (the ability may not be set right after the task appears).
function M.lock_name(task)
    if not M.active(task) then return nil, "no ability" end
    local ok, name = pcall(function() return task.Ability.m_Lock:ToString() end)
    if not ok then return nil, "cannot read lock name: " .. tostring(name) end
    if name == "" or name == "None" then return nil, "no lock name" end
    return name
end

local scene_cache

local function scene()
    if valid(scene_cache) then return scene_cache end
    scene_cache = nil
    local sub = FindFirstOf("LockPickSubsystem")
    if not valid(sub) then return nil end
    local actor = sub.m_LockSceneActor
    if valid(actor) then scene_cache = actor end
    return scene_cache
end

-- Forgets the cached lock scene; call when a minigame opens so a stale actor is never read.
function M.reset()
    scene_cache = nil
end

-- Returns the plate offsets of the visible plates, front to back, or nil, err.
function M.plate_offsets()
    local actor = scene()
    if not actor then return nil, "no lock scene" end
    local ok, dxs, err = pcall(function()
        local out, problem = {}, nil
        actor.m_LockPieceData:ForEach(function(_, elem)
            if problem then return end
            local piece = elem:get()
            local plate, bar = piece.m_Plate, piece.m_Bar
            if not (valid(plate) and valid(bar)) then
                problem = "invalid lock piece"
                return
            end
            if plate.bHidden then return end
            local plate_root, bar_root = plate.m_RuntimeRootComponent, bar.m_RuntimeRootComponent
            if not (valid(plate_root) and valid(bar_root)) then
                problem = "lock piece without root component"
                return
            end
            out[#out + 1] = plate_root.RelativeLocation.X - bar_root.RelativeLocation.X
        end)
        return out, problem
    end)
    if not ok then return nil, "cannot read plates: " .. tostring(dxs) end
    if err then return nil, err end
    return dxs
end

-- Returns holes of the visible plates (integers, front to back), nil while they move, or nil, err.
function M.positions()
    local dxs, err = M.plate_offsets()
    if not dxs then return nil, err end
    return M.to_positions(dxs)
end

-- The player's lockpick skill: LockpickPrecision.CurrentValue of the game's only AttributeSet_Lockpicking (the
-- player's; "Lockpicking skill" in docs/TECHNICAL.md), or nil, err. One FindFirstOf: call it once per minigame.
function M.precision()
    local ok, value = pcall(function()
        local set = FindFirstOf("AttributeSet_Lockpicking")
        if not valid(set) then return nil end
        return set.LockpickPrecision.CurrentValue
    end)
    if not ok then return nil, "cannot read the lockpick skill: " .. tostring(value) end
    if type(value) ~= "number" then return nil, "no lockpick skill" end
    return value
end

-- Connections the game removes at a skill value: round(precision); 0 when the skill is unknown.
function M.connections_removed(precision)
    if type(precision) ~= "number" or precision ~= precision then return 0 end
    return math.floor(math.max(precision, 0) + 0.5)
end

return M
