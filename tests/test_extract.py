import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from extract_lockgraphs import GAME_DIR_ENV, cache_path, game_dir, main, parse_locks  # noqa: E402

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "groundtruth.json")
GAME_DIR = game_dir()
CACHE = cache_path(GAME_DIR) if GAME_DIR else ""


def links_of(lock):
    """{src: sorted [(dst, dir), ...]} of an extracted lock (edges) or of the ground-truth fixture (links)."""
    links = {}
    if "edges" in lock:
        for src, dst, d in lock["edges"]:
            links.setdefault(src, []).append((dst, d))
    else:
        for src, dsts in lock["links"].items():
            for dst, d in dsts:
                links.setdefault(int(src), []).append((dst, d))
    return {src: sorted(v) for src, v in links.items()}


def normalize(lock):
    return {"plates": lock["plates"], "links": links_of(lock)}


class GameDirTest(unittest.TestCase):
    def test_argument_wins(self):
        self.assertEqual(game_dir("A", {GAME_DIR_ENV: "B"}), "A")

    def test_environment(self):
        self.assertEqual(game_dir(None, {GAME_DIR_ENV: "B"}), "B")

    def test_neither(self):
        self.assertIsNone(game_dir(None, {}))
        self.assertIsNone(game_dir("", {GAME_DIR_ENV: ""}))

    def test_paths_inside_the_game_folder(self):
        self.assertEqual(cache_path("G"), os.path.join("G", "G1R", "Script", "PrecompiledScript_Shipping.Cache"))

    def test_main_without_a_game_dir_stops(self):
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch("sys.stderr"):
            with self.assertRaises(SystemExit):
                main([])

    def test_main_failure_keeps_the_existing_output(self):
        # A game folder with the cache but without version.txt: main must fail before it touches --out.
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.dirname(cache_path(tmp)))
            with open(cache_path(tmp), "wb") as f:
                f.write(b"cache")
            out = os.path.join(tmp, "lockgraphs.lua")
            with open(out, "w", encoding="utf-8") as f:
                f.write("old text")
            with mock.patch("extract_lockgraphs.parse_locks", return_value={}):
                with self.assertRaises(FileNotFoundError):
                    main(["--game-dir", tmp, "--out", out])
            with open(out, encoding="utf-8") as f:
                self.assertEqual(f.read(), "old text")


@unittest.skipUnless(os.path.exists(CACHE), f"game cache not found (set {GAME_DIR_ENV} to the game folder)")
class ExtractGroundTruthTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(CACHE, "rb") as f:
            cls.locks = parse_locks(f.read())
        with open(FIXTURE, encoding="utf-8") as f:
            cls.expected = json.load(f)

    def test_finds_many_locks(self):
        self.assertGreater(len(self.locks), 10)

    def test_matches_ground_truth(self):
        for name, lock in self.expected.items():
            with self.subTest(lock=name):
                self.assertIn(name, self.locks)
                self.assertEqual(normalize(self.locks[name]), normalize(lock))

    def test_edges_keep_authored_order(self):
        # The game drops the first round(LockpickPrecision) connections; in game Shadow316 lost 1->4 at skill 1.
        self.assertEqual(
            self.locks["OC_Chest_Shadow316_Lock"]["edges"],
            [(1, 4, -1), (1, 3, -1), (5, 1, -1), (3, 2, 1), (4, 3, -1), (3, 1, -1), (2, 1, -1)],
        )


if __name__ == "__main__":
    unittest.main()
