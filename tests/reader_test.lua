-- Unit tests for the pure parts of lock_reader.lua and lockdb.lua. Run from repo root: lua tests/reader_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local reader = require("lock_reader")
local lockdb = require("lockdb")
local t = require("testlib")
local test, eq, str = t.test, t.eq, t.str

test("settled offsets map to holes", function()
    local p = reader.to_positions({ 18.70, 12.50, 6.30, 0.00, -6.10, -12.20, -18.50 })
    eq(str(p), "7 6 5 4 3 2 1", "holes")
    for i = 1, #p do eq(math.type(p[i]), "integer", "type of hole " .. i) end
end)

test("small noise is tolerated", function()
    eq(str(reader.to_positions({ 18.65, -6.04, 0.03 })), "7 3 4", "holes")
end)

test("a plate between holes means not settled", function()
    eq(reader.to_positions({ 18.70, 14.00, 0.00 }), nil, "result")
end)

test("no plates gives an empty list", function()
    eq(#reader.to_positions({}), 0, "length")
end)

local DATA = {
    build = "Build83_CL174209",
    locks = { ["OC_Chest_Cutter_lock"] = { plates = 4, edges = { { 1, 2, -1 }, { 3, 1, 1 }, { 1, 4, 1 } } } },
}

-- Links of a graph as text: by source plate, in the order the graph keeps them.
local function links_str(graph)
    local out = {}
    for src = 1, graph.plates do
        for _, l in ipairs(graph.links[src] or {}) do out[#out + 1] = string.format("%d>%d:%d", src, l[1], l[2]) end
    end
    return table.concat(out, " ")
end

test("lookup ignores case and returns the stored name", function()
    local db = lockdb.new(DATA)
    local graph, name, removed = db.find("OC_CHEST_CUTTER_LOCK")
    eq(graph.plates, 4, "plates")
    eq(name, "OC_Chest_Cutter_lock", "name")
    eq(removed, 0, "nothing removed by default")
    eq(db.build, "Build83_CL174209", "build")
end)

test("unknown lock gives nil", function()
    eq(lockdb.new(DATA).find("Nope_Lock"), nil, "graph")
end)

test("the graph keeps every connection, grouped by the source plate in authored order", function()
    eq(links_str(lockdb.new(DATA).find("OC_Chest_Cutter_lock", 0)), "1>2:-1 1>4:1 3>1:1", "links")
end)

test("k removes the first k connections of the authored list", function()
    local db = lockdb.new(DATA)
    local graph, _, removed = db.find("OC_Chest_Cutter_lock", 1)
    eq(links_str(graph), "1>4:1 3>1:1", "without the first")
    eq(removed, 1, "removed")
    eq(links_str(db.find("OC_Chest_Cutter_lock", 2)), "1>4:1", "without the first two")
end)

test("k is clamped to the number of connections", function()
    local db = lockdb.new(DATA)
    local graph, _, removed = db.find("OC_Chest_Cutter_lock", 9)
    eq(links_str(graph), "", "no links")
    eq(removed, 3, "all removed")
    graph, _, removed = db.find("OC_Chest_Cutter_lock", -1)
    eq(links_str(graph), "1>2:-1 1>4:1 3>1:1", "nothing removed")
    eq(removed, 0, "clamped to 0")
end)

test("the real database: Shadow316 at skill 1 has no 1->4 connection", function()
    local db = lockdb.new(dofile("mod/G1LockPickHelper/Scripts/lockgraphs.lua"))
    eq(db.find("oc_chest_digger526_lock").plates, 5, "plates")
    eq(links_str(db.find("OC_Chest_Shadow316_Lock", 0)), "1>4:-1 1>3:-1 2>1:-1 3>2:1 3>1:-1 4>3:-1 5>1:-1", "full")
    eq(links_str(db.find("OC_Chest_Shadow316_Lock", 1)), "1>3:-1 2>1:-1 3>2:1 3>1:-1 4>3:-1 5>1:-1", "skill 1")
end)

test("build is read from UTF-16 version.txt", function()
    local raw = ("\255\254" .. ("Build83_CL174209\r\n"):gsub(".", "%0\0"))
    eq(lockdb.parse_build(raw), "Build83_CL174209", "build")
    eq(lockdb.parse_build("garbage"), nil, "no build")
end)

local function fake_obj(fields)
    fields.IsValid = function() return true end
    return fields
end

test("the lockpick skill is read from the player's attribute set", function()
    FindFirstOf = function(name)
        if name == "AttributeSet_Lockpicking" then
            return fake_obj({ LockpickPrecision = { BaseValue = 0.0, CurrentValue = 1.0 } })
        end
    end
    eq(reader.precision(), 1.0, "precision")
    FindFirstOf = function() return nil end
    local p, err = reader.precision()
    eq(p, nil, "no attribute set")
    eq(err, "no lockpick skill", "error")
    FindFirstOf = function() error("boom") end
    p, err = reader.precision()
    eq(p, nil, "failing read")
    eq(err:find("boom", 1, true) ~= nil, true, "error text")
end)

test("connections removed: round(skill), 0 when unknown", function()
    local cases = { { nil, 0 }, { 0, 0 }, { 0.4, 0 }, { 0.6, 1 }, { 1.0, 1 }, { 2, 2 }, { -1, 0 }, { 0 / 0, 0 } }
    for _, c in ipairs(cases) do
        local k = reader.connections_removed(c[1])
        eq(k, c[2], "skill " .. tostring(c[1]))
        eq(math.type(k), "integer", "integer for " .. tostring(c[1]))
    end
end)

local function with_scene(pieces, fn)
    FindFirstOf = function(name)
        if name ~= "LockPickSubsystem" then return nil end
        return fake_obj({ m_LockSceneActor = fake_obj({ m_LockPieceData = pieces }) })
    end
    reader.reset()
    local ok, err = pcall(fn)
    FindFirstOf = nil
    reader.reset()
    if not ok then error(err, 0) end
end

test("a plate without a root component is an error, not a throw", function()
    local bar = fake_obj({ m_RuntimeRootComponent = fake_obj({ RelativeLocation = { X = 0 } }) })
    local pieces = { ForEach = function(_, cb)
        cb(1, { get = function() return { m_Plate = fake_obj({ bHidden = false }), m_Bar = bar } end })
    end }
    with_scene(pieces, function()
        local dxs, err = reader.plate_offsets()
        eq(dxs, nil, "offsets")
        eq(err, "lock piece without root component", "error")
    end)
end)

test("a throwing lock scene is an error, not a throw", function()
    with_scene({ ForEach = function() error("boom") end }, function()
        local dxs, err = reader.plate_offsets()
        eq(dxs, nil, "offsets")
        if not tostring(err):find("^cannot read plates") then error("unexpected error: " .. tostring(err)) end
    end)
end)

test("an unreadable lock name is an error, not a throw", function()
    local task = fake_obj({ Ability = fake_obj({ m_Lock = { ToString = function() error("bad name") end } }) })
    local name, err = reader.lock_name(task)
    eq(name, nil, "name")
    if not tostring(err):find("^cannot read lock name") then error("unexpected error: " .. tostring(err)) end
end)

t.finish()
