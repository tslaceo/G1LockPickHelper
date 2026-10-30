import contextlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import gen_lockgraphs as gen  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")
SAMPLE = os.path.join(FIXTURES, "modkit_locks_sample.as")
GROUNDTRUTH = os.path.join(FIXTURES, "groundtruth.json")
REPO = os.path.join(os.path.dirname(__file__), "..")
MODKIT = os.environ.get("G1R_MODKIT_DIR")
LUA = shutil.which("lua") or shutil.which("lua54")
LUA_1X = shutil.which("git") and subprocess.run(
    ["git", "-C", REPO, "cat-file", "-e", "v1.2.0:mod/G1LockPickHelper/Scripts/lockgraphs.lua"], capture_output=True
).returncode == 0


def sample_locks():
    with open(SAMPLE, encoding="utf-8") as f:
        return {lock.name: lock for lock in gen.parse_locks(f.read())}


def links_of(edges):
    """{src: sorted [(dst, dir), ...]} of 1-based (src, dst, dir) edges."""
    links = {}
    for src, dst, direction in edges:
        links.setdefault(src, []).append((dst, direction))
    return {src: sorted(v) for src, v in links.items()}


def one_based(lock):
    return [(src + 1, dst + 1, d) for src, dst, d in lock.edges]


def lock_text(*lines):
    """A lock class (header on line 1, `{` on line 2, the given lines from line 3)."""
    return "class UX_Lock: UGothicLockConfig\n{\n" + "".join(f" {line}\n" for line in lines) + "}\n"


class ParseTest(unittest.TestCase):
    def test_names_from_m_unique_name_or_the_class_name_without_u(self):
        locks = sample_locks()
        self.assertEqual(
            sorted(locks),
            [
                "AM_Chest_04_Lock", "Fixture_Plain_Lock", "Fixture_Unnamed_Lock", "OC_Chest_Digger526_Lock",
                "OC_Chest_Mud_Lock", "Test_Lock_85_07",
            ],
        )
        self.assertEqual(locks["Fixture_Unnamed_Lock"].class_name, "UFixture_Unnamed_Lock")
        self.assertEqual(locks["Fixture_Plain_Lock"].class_name, "Fixture_Plain_Lock")

    def test_the_last_m_unique_name_wins(self):
        # The `default` lines run in order: the game registers UOC_Mages_Room_01_Lock as Test_Lock_85_07 (1.x read it so).
        locks = sample_locks()
        self.assertNotIn("OC_Mages_Room_01_Lock", locks)
        self.assertEqual((locks["Test_Lock_85_07"].plates, len(locks["Test_Lock_85_07"].edges)), (6, 10))
        self.assertEqual(locks["Test_Lock_85_07"].class_name, "UOC_Mages_Room_01_Lock")
        self.assertEqual(locks["Test_Lock_85_07"].start, [7, 4, 4, 5, 1, 7])

    def test_other_classes_and_commented_classes_are_not_locks(self):
        self.assertNotIn("Not_A_Lock", sample_locks())
        self.assertNotIn("OC_Chest_Mud_Chest", sample_locks())

    def test_plates_edges_in_authored_order_and_start(self):
        locks = sample_locks()
        mud = locks["OC_Chest_Mud_Lock"]
        self.assertEqual(mud.plates, 5)
        self.assertEqual(mud.edges, [(4, 3, -1), (0, 4, -1), (0, 2, -1), (0, 1, 1), (4, 2, 1), (1, 3, -1)])
        self.assertEqual(mud.start, [7, 5, 7, 7, 5])  # 4 - rotation of AddPiece(id, rotation)
        digger = locks["OC_Chest_Digger526_Lock"]
        self.assertEqual(digger.plates, 5)
        self.assertEqual(digger.edges, [(4, 1, -1), (2, 4, -1), (0, 4, -1), (3, 1, 1), (2, 1, 1)])
        self.assertEqual(digger.start, [7, 7, 6, 4, 7])

    def test_commented_connections_are_skipped_and_pieces_are_placed_by_id(self):
        lock = sample_locks()["AM_Chest_04_Lock"]
        self.assertEqual(lock.plates, 6)
        self.assertEqual(lock.edges, [(2, 1, -1), (4, 0, -1), (0, 2, -1), (4, 1, -1), (3, 5, 1)])
        self.assertEqual(lock.start, [3, 4, 1, 5, 3, 3])  # the pieces come in the order 5 2 0 4 1 3 in the file

    def test_lock_without_connections(self):
        lock = sample_locks()["Fixture_Plain_Lock"]
        self.assertEqual((lock.plates, lock.edges, lock.start), (1, [], [4]))
        unnamed = sample_locks()["Fixture_Unnamed_Lock"]
        self.assertEqual((unnamed.plates, unnamed.edges, unnamed.start), (2, [(1, 0, 1)], [2, 6]))

    def test_the_extreme_holes_are_accepted(self):
        lock = gen.parse_locks(lock_text("default AddPiece(0, 3);", "default AddPiece(1, -3);"))[0]
        self.assertEqual(lock.start, [1, 7])

    def test_a_commented_out_line_that_would_be_an_error_is_not_one(self):
        text = lock_text("default AddPiece(0, 0);", "// default AddPiece(1, ROT);", "/* default AddConnection(0, 9, 0) */")
        self.assertEqual(gen.parse_locks(text)[0].plates, 1)

    def test_a_comment_marker_inside_a_string_is_not_a_comment(self):
        text = (
            'class UX_Lock: UGothicLockConfig\n{\n default m_UniqueName = n"A//B";\n default AddPiece(0, 0);\n'
            " default AddConnection(0, 0, 1);\n}\n"
        )
        lock = gen.parse_locks(text)[0]
        self.assertEqual((lock.name, lock.plates, lock.edges), ("A//B", 1, [(0, 0, 1)]))

    def test_plates_must_be_numbered_from_zero(self):
        text = "class UX_Lock: UGothicLockConfig\n{\n default AddPiece(0, 0);\n default AddPiece(2, 0);\n}\n"
        with self.assertRaises(ValueError):
            gen.parse_locks(text)

    def test_two_locks_that_differ_only_in_case_are_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "Script"))
            with open(os.path.join(tmp, "Script", "a.as"), "w", encoding="utf-8") as f:
                f.write(
                    'class UA_Lock: UGothicLockConfig\n{\n default m_UniqueName = n"X_Lock";\n default AddPiece(0, 0);\n}\n'
                    'class UB_Lock: UGothicLockConfig\n{\n default m_UniqueName = n"x_LOCK";\n default AddPiece(0, 0);\n}\n'
                )
            with self.assertRaises(ValueError):
                gen.load_locks(tmp)


class RejectionTest(unittest.TestCase):
    """What the generator does not understand or what cannot be a lock is an error that names the class and the line, never
    a lock written wrong (a regeneration from a newer Modkit must not go through silently)."""

    PIECE = "default AddPiece(0, 0);"

    def assertRejected(self, lines, *expected):
        with self.assertRaises(ValueError) as caught:
            gen.parse_locks(lock_text(*lines))
        message = str(caught.exception)
        self.assertIn("class UX_Lock", message)
        for part in expected:
            self.assertIn(part, message)

    def test_a_piece_that_is_not_numbers(self):
        self.assertRejected([self.PIECE, "default AddPiece(1, ROT);"], "line 4", "AddPiece(1, ROT)")

    def test_a_piece_without_a_semicolon(self):
        self.assertRejected([self.PIECE, "default AddPiece(1, 0)"], "line 4")

    def test_a_connection_without_a_semicolon(self):
        self.assertRejected([self.PIECE, "default AddPiece(1, 0);", "default AddConnection(0, 1, 1)"], "line 5", "AddConnection(0, 1, 1)")

    def test_a_connection_that_is_not_numbers(self):
        self.assertRejected([self.PIECE, "default AddConnection(0, N, 1);"], "line 4")

    def test_a_connection_written_without_default(self):
        self.assertRejected([self.PIECE, "AddConnection(0, 0, 1);"], "line 4")

    def test_a_name_with_an_escaped_quote(self):
        # (It used to fall back to the class name without a word.)
        self.assertRejected([r'default m_UniqueName = n"A\"B";', self.PIECE], "line 3", "m_UniqueName")

    def test_a_name_without_a_semicolon(self):
        self.assertRejected(['default m_UniqueName = n"A"', self.PIECE], "line 3")

    def test_a_name_written_without_default(self):
        self.assertRejected(['m_UniqueName = n"A";', self.PIECE], "line 3")

    def test_a_hole_outside_the_plate(self):
        self.assertRejected(["default AddPiece(0, 9);"], "plate 0", "hole -5")
        self.assertRejected(["default AddPiece(0, 0);", "default AddPiece(1, -4);"], "plate 1", "hole 8")
        self.assertRejected(["default AddPiece(0, 4);"], "hole 0")

    def test_a_direction_that_is_not_plus_or_minus_one(self):
        self.assertRejected([self.PIECE, "default AddConnection(0, 0, 0);"], "(0, 0, 0)", "direction")
        self.assertRejected([self.PIECE, "default AddConnection(0, 0, 2);"], "direction")

    def test_a_connection_to_a_plate_that_is_not_there(self):
        self.assertRejected([self.PIECE, "default AddConnection(3, 4, -1);"], "(3, 4, -1)", "not in 0..0")
        self.assertRejected([self.PIECE, "default AddConnection(0, 1, 1);"], "(0, 1, 1)")
        self.assertRejected([self.PIECE, "default AddConnection(-1, 0, 1);"], "(-1, 0, 1)")

    def test_a_class_without_pieces(self):
        self.assertRejected([], "no AddPiece")
        self.assertRejected(['default m_UniqueName = n"A";', "default AddConnection(0, 0, 1);"], "no AddPiece")

    def test_plates_that_are_not_from_zero_or_repeat(self):
        self.assertRejected([self.PIECE, "default AddPiece(2, 0);"], "not 0..1")
        self.assertRejected([self.PIECE, self.PIECE], "added twice")

    def test_the_message_of_a_source_file_names_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "Script", "Items"))
            with open(os.path.join(tmp, "Script", "Items", "Bad.as"), "w", encoding="utf-8") as f:
                f.write(lock_text(self.PIECE, "default AddPiece(1, ROT);"))
            with self.assertRaises(ValueError) as caught:
                gen.load_locks(tmp)
            self.assertIn("Bad.as", str(caught.exception))
            self.assertIn("line 4", str(caught.exception))

    def test_main_stops_and_writes_nothing_for_a_source_it_cannot_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "Script"))
            with open(os.path.join(tmp, "Script", "Bad.as"), "w", encoding="utf-8") as f:
                f.write(lock_text(self.PIECE, "default AddPiece(1, ROT);"))
            out_as, out_lua = os.path.join(tmp, "a.as"), os.path.join(tmp, "b.lua")
            with contextlib.redirect_stderr(io.StringIO()) as stderr:
                code = gen.main(["--modkit", tmp, "--out-as", out_as, "--out-lua", out_lua])
            self.assertEqual(code, 1)
            self.assertIn("Bad.as", stderr.getvalue())
            self.assertFalse(os.path.exists(out_as) or os.path.exists(out_lua))


class GroundTruthTest(unittest.TestCase):
    def test_digger526_equals_the_graph_read_in_the_game_by_1x(self):
        with open(GROUNDTRUTH, encoding="utf-8") as f:
            truth = json.load(f)["OC_Chest_Digger526_Lock"]
        lock = sample_locks()["OC_Chest_Digger526_Lock"]
        wanted = {int(src): sorted(tuple(link) for link in links) for src, links in truth["links"].items()}
        self.assertEqual(lock.plates, truth["plates"])
        self.assertEqual(links_of(one_based(lock)), wanted)


class OutputTest(unittest.TestCase):
    def setUp(self):
        self.locks = sample_locks()
        self.text_as = gen.to_angelscript(self.locks, "G1R-Modkit abc1234", "Build1_CL2")
        self.text_lua = gen.to_lua(self.locks, "G1R-Modkit abc1234", "Build1_CL2")

    def test_angelscript_registers_every_lock_with_its_edges_in_order(self):
        lines = self.text_as.splitlines()
        at = lines.index('\tDb.AddLock(n"OC_Chest_Mud_Lock", 5);')
        self.assertEqual(
            lines[at + 1:at + 7],
            [
                "\tDb.AddEdge(4, 3, -1);",
                "\tDb.AddEdge(0, 4, -1);",
                "\tDb.AddEdge(0, 2, -1);",
                "\tDb.AddEdge(0, 1, 1);",
                "\tDb.AddEdge(4, 2, 1);",
                "\tDb.AddEdge(1, 3, -1);",
            ],
        )
        self.assertEqual(self.text_as.count("Db.AddLock("), 6)
        self.assertIn("void LPH_RegisterLockGraphs(ULPH_LockDb Db)", self.text_as)

    def test_angelscript_constants_and_sorted_names(self):
        self.assertIn('const FString LocksSource = "G1R-Modkit abc1234";', self.text_as)
        self.assertIn('const FString LocksBuild = "Build1_CL2";', self.text_as)
        names = re.findall(r'Db\.AddLock\(n"([^"]+)"', self.text_as)
        self.assertEqual(names, sorted(names, key=str.lower))

    def test_lua_is_one_based_with_start(self):
        self.assertIn(
            '    ["OC_Chest_Mud_Lock"] = { plates = 5, edges = { {5, 4, -1}, {1, 5, -1}, {1, 3, -1}, {1, 2, 1}, {5, 3, 1}, '
            "{2, 4, -1} }, start = { 7, 5, 7, 7, 5 } },",
            self.text_lua,
        )
        self.assertIn('build = "Build1_CL2"', self.text_lua)
        self.assertIn('["Fixture_Plain_Lock"] = { plates = 1, edges = {}, start = { 4 } },', self.text_lua)

    @unittest.skipIf(LUA is None, "lua interpreter not installed")
    def test_lua_loads_the_generated_table(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "locks_data.lua").replace("\\", "/")
            with open(path, "w", encoding="utf-8") as f:
                f.write(self.text_lua)
            script = (
                f"local t = dofile('{path}') local l = t.locks.OC_Chest_Mud_Lock "
                "print(t.build, l.plates, #l.edges, l.edges[1][1], l.edges[1][2], l.edges[1][3], #l.start, l.start[2], "
                "#t.locks.Fixture_Plain_Lock.edges)"
            )
            out = subprocess.run([LUA, "-e", script], capture_output=True, text=True, check=True).stdout.split()
        self.assertEqual(out, ["Build1_CL2", "5", "6", "5", "4", "-1", "5", "5", "0"])


class MainTest(unittest.TestCase):
    def test_main_writes_both_files_from_a_modkit_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "modkit", "Script", "Items"))
            shutil.copy(SAMPLE, os.path.join(tmp, "modkit", "Script", "Items", "Locks.as"))
            out_as = os.path.join(tmp, "out", "LockGraphs.as")
            out_lua = os.path.join(tmp, "out", "locks_data.lua")
            with contextlib.redirect_stdout(io.StringIO()):
                code = gen.main(
                    ["--modkit", os.path.join(tmp, "modkit"), "--commit", "abc1234", "--build", "Build1_CL2",
                     "--out-as", out_as, "--out-lua", out_lua]
                )
            self.assertEqual(code, 0)
            with open(out_as, encoding="utf-8") as f:
                self.assertIn('Db.AddLock(n"OC_Chest_Mud_Lock", 5);', f.read())
            with open(out_lua, encoding="utf-8") as f:
                self.assertIn('build = "Build1_CL2"', f.read())

    def test_main_without_a_modkit_stops(self):
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch("sys.stderr"):
            with self.assertRaises(SystemExit):
                gen.main([])

    def test_main_with_a_folder_that_is_not_the_modkit_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            with contextlib.redirect_stderr(io.StringIO()):
                code = gen.main(["--modkit", tmp, "--out-as", os.path.join(tmp, "a"), "--out-lua", os.path.join(tmp, "b")])
            self.assertEqual(code, 1)


def parse_1x_database(text):
    """{name: (plates, [(src, dst, dir), ...])} of lockgraphs.lua of 1.x (plates 1-based)."""
    line_re = re.compile(r'^\s*\["([^"]+)"\]\s*=\s*\{\s*plates\s*=\s*(\d+),\s*edges\s*=(.*)$')
    edge_re = re.compile(r"\{\s*(-?\d+),\s*(-?\d+),\s*(-?\d+)\s*\}")
    db = {}
    for line in text.splitlines():
        match = line_re.match(line)
        if match:
            db[match.group(1)] = (int(match.group(2)), [tuple(int(x) for x in e) for e in edge_re.findall(match.group(3))])
    return db


@unittest.skipUnless(MODKIT, "set G1R_MODKIT_DIR to the G1R-Modkit repository")
class ModkitSourcesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.locks = gen.load_locks(MODKIT)

    def test_all_416_locks_are_found(self):
        # 346 in LockPickGeneric.as and 70 in TestLockDifficulty.as (most of those have a comment after the class header).
        self.assertEqual(len(self.locks), 416)
        self.assertEqual(len({name.lower() for name in self.locks}), 416)

    def test_digger526_equals_the_game_graph_read_by_1x(self):
        with open(GROUNDTRUTH, encoding="utf-8") as f:
            truth = json.load(f)["OC_Chest_Digger526_Lock"]
        lock = self.locks["OC_Chest_Digger526_Lock"]
        wanted = {int(src): sorted(tuple(link) for link in links) for src, links in truth["links"].items()}
        self.assertEqual(lock.plates, truth["plates"])
        self.assertEqual(links_of(one_based(lock)), wanted)

    def test_mud_start_equals_the_holes_read_in_the_game(self):
        # Read in game by the Modkit probe (run 1): the sign of "4 - rotation" is confirmed by it.
        self.assertEqual(self.locks["OC_Chest_Mud_Lock"].start, [7, 5, 7, 7, 5])

    def test_start_holes_are_inside_the_lock(self):
        for lock in self.locks.values():
            self.assertEqual(len(lock.start), lock.plates, lock.name)
            for hole in lock.start:
                self.assertTrue(1 <= hole <= 7, f"{lock.name}: hole {hole}")

    def test_output_has_every_lock(self):
        text = gen.to_angelscript(self.locks, "G1R-Modkit test", "Build1_CL2")
        self.assertIn('Db.AddLock(n"OC_Chest_Mud_Lock", 5);', text)
        self.assertEqual(text.count("Db.AddLock("), 416)

    @unittest.skipUnless(LUA_1X, "tag v1.2.0 is not in this repository")
    def test_locks_equal_the_1x_database_where_both_have_them(self):
        raw = subprocess.run(
            ["git", "-C", REPO, "show", "v1.2.0:mod/G1LockPickHelper/Scripts/lockgraphs.lua"],
            capture_output=True, check=True,
        ).stdout.decode("utf-8")
        old = parse_1x_database(raw)
        self.assertEqual(len(old), 416)
        old_by_key = {name.lower(): (name, data) for name, data in old.items()}
        new_by_key = {name.lower(): lock for name, lock in self.locks.items()}
        common = sorted(set(old_by_key) & set(new_by_key))
        for key in common:
            plates, edges = old_by_key[key][1]
            lock = self.locks[new_by_key[key].name]
            self.assertEqual((lock.plates, one_based(lock)), (plates, edges), lock.name)  # same graph, same order
        # Nothing differs between the Build83 cache of 1.x and the Modkit sources of Build102 (the name
        # OC_Chest_CUTTER_Lock is OC_Chest_Cutter_Lock in the cache: the game does not tell them apart).
        self.assertEqual(sorted(new_by_key.keys() ^ old_by_key.keys()), [])
        self.assertEqual(len(common), 416)

    def test_connections_join_plates_of_the_lock(self):
        for lock in self.locks.values():
            for src, dst, direction in lock.edges:
                self.assertTrue(0 <= src < lock.plates and 0 <= dst < lock.plates, f"{lock.name}: {src}->{dst}")
                self.assertIn(direction, (-1, 1), lock.name)

    @unittest.skipUnless(os.path.exists(gen.DEFAULT_AS), "LockGraphs.as is not generated yet")
    def test_committed_files_are_what_the_generator_writes(self):
        with open(gen.DEFAULT_AS, encoding="utf-8") as f:
            committed_as = f.read()
        source = re.search(r'LocksSource = "([^"]+)"', committed_as).group(1)
        build = re.search(r'LocksBuild = "([^"]+)"', committed_as).group(1)
        self.assertEqual(committed_as, gen.to_angelscript(self.locks, source, build))
        with open(gen.DEFAULT_LUA, encoding="utf-8") as f:
            self.assertEqual(f.read(), gen.to_lua(self.locks, source, build))


if __name__ == "__main__":
    unittest.main()
