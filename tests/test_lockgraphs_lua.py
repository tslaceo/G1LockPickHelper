import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from lockgraphs_lua import to_lua  # noqa: E402

LUA = shutil.which("lua") or shutil.which("lua54")

LOCKS = {
    "CHEST_B": {"plates": 2, "edges": []},
    'CHEST_"A"': {"plates": 3, "edges": [(2, 1, -1), (1, 3, 1), (2, 3, 1)]},
}


class ToLuaTest(unittest.TestCase):
    def test_header_and_sorted_names(self):
        text = to_lua(LOCKS, "Build83_CL174209", "abc123")
        self.assertIn('build = "Build83_CL174209"', text)
        self.assertIn('cache_sha1 = "abc123"', text)
        self.assertLess(text.index('CHEST_\\"A\\"'), text.index("CHEST_B"))

    @unittest.skipIf(LUA is None, "lua interpreter not installed")
    def test_lua_loads_generated_table(self):
        text = to_lua(LOCKS, "Build83_CL174209", "abc123")
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "lockgraphs.lua").replace("\\", "/")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            script = (
                f"local t = dofile('{path}') "
                "local l = t.locks['CHEST_\"A\"'] "
                "print(t.build, l.plates, #l.edges, l.edges[1][1], l.edges[1][2], l.edges[1][3], #t.locks.CHEST_B.edges)"
            )
            out = subprocess.run([LUA, "-e", script], capture_output=True, text=True, check=True).stdout.split()
        self.assertEqual(out, ["Build83_CL174209", "3", "3", "2", "1", "-1", "0"])


if __name__ == "__main__":
    unittest.main()
