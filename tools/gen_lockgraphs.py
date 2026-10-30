"""Generates the mod's lock database from the lock classes (UGothicLockConfig) of the G1R-Modkit sources.

    python tools/gen_lockgraphs.py --modkit <G1R-Modkit repo> [--commit <sha>] [--build <Build...>]
                                   [--out-as <LockGraphs.as>] [--out-lua <locks_data.lua>]

Writes two files:
  mod/LockPickHelper/Script/LockPickHelper/LockGraphs.as - what the game mod compiles (plates 0-based, as in the sources);
  tools/oracle/locks_data.lua - the same data for the Lua reference of the solver (plates 1-based) plus the plates'
                                starting holes.
"""
import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_AS = os.path.join(ROOT, "mod", "LockPickHelper", "Script", "LockPickHelper", "LockGraphs.as")
DEFAULT_LUA = os.path.join(ROOT, "tools", "oracle", "locks_data.lua")
MODKIT_ENV = "G1R_MODKIT_DIR"

# A plate rests in hole 4 when it is open; AddPiece(id, rotation) starts it `rotation` steps away from there:
# hole = 4 - rotation (checked in game for OC_Chest_Mud_Lock: holes 7 5 7 7 5).
GOAL_HOLE = 4
MIN_HOLE, MAX_HOLE = 1, 7

CLASS_RE = re.compile(r"\bclass\s+(\w+)\s*:\s*UGothicLockConfig\s*\{")
# The three kinds of line the generator understands. Group 1 of each is the keyword: every keyword in a lock class must be
# the start of one of these (see check_recognised), or the line is something new and the generator stops.
NAME_RE = re.compile(r'\bdefault\s+(m_UniqueName)\s*=\s*n"([^"]+)"\s*;')
PIECE_RE = re.compile(r"\bdefault\s+(AddPiece)\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)\s*;")
CONNECTION_RE = re.compile(r"\bdefault\s+(AddConnection)\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)\s*;")
KEYWORDS = (("m_UniqueName", NAME_RE), ("AddPiece", PIECE_RE), ("AddConnection", CONNECTION_RE))
# A string, a block comment, a line comment (the strings are skipped over, so a `//` inside one stays).
TOKEN_RE = re.compile(r'"(?:\\.|[^"\\\n])*"|/\*.*?\*/|//[^\n]*', re.S)
BRACE_RE = re.compile(r'"(?:\\.|[^"\\\n])*"|[{}]')


@dataclass
class Lock:
    name: str  # m_UniqueName, or the class name without the U prefix
    class_name: str
    plates: int  # the number of AddPiece
    edges: list = field(default_factory=list)  # (src, dst, dir), plates 0-based, in the authored order
    start: list = field(default_factory=list)  # the hole of every plate (1..7) at the start, front to back


def strip_comments(text):
    """The text without comments; line breaks stay (a block comment becomes the same number of line breaks)."""

    def blank(match):
        token = match.group(0)
        if token[0] == '"':
            return token
        return "\n" * token.count("\n") if token.startswith("/*") else ""

    return TOKEN_RE.sub(blank, text)


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def class_bodies(text):
    """(class name, offset of the header, offset of the body, body) of every `class X : UGothicLockConfig { ... }` in
    the text without comments."""
    for match in CLASS_RE.finditer(text):
        depth = 1
        end = None
        for brace in BRACE_RE.finditer(text, match.end()):
            if brace.group(0) == "{":
                depth += 1
            elif brace.group(0) == "}":
                depth -= 1
                if depth == 0:
                    end = brace.start()
                    break
        if end is None:
            raise ValueError(f"class {match.group(1)}: no closing brace")
        yield match.group(1), match.start(), match.end(), text[match.end():end]


def check_recognised(text, class_name, body_start, body):
    """Stops at a keyword of a lock class (m_UniqueName, AddPiece, AddConnection) that the strict patterns above did not
    take: a number that is not a number, a missing `;`, an escaped quote in a name, a call written another way. Such a
    line would be dropped silently and the lock written wrong."""
    for keyword, strict in KEYWORDS:
        recognised = {match.start(1) for match in strict.finditer(body)}
        for raw in re.finditer(rf"\b{keyword}\b", body):
            if raw.start() not in recognised:
                at = body_start + raw.start()
                line = text.split("\n")[line_of(text, at) - 1].strip()
                raise ValueError(f"class {class_name}, line {line_of(text, at)}: cannot read `{line}`")


def parse_locks(text):
    """The locks of one source file, in the order of the file. A lock class the generator cannot read in full, or one that
    cannot be a lock (no plates, a hole outside 1..7, a direction other than +-1, a connection to a plate that is not
    there), is a ValueError that names the class and the line."""
    text = strip_comments(text)
    locks = []
    for class_name, header_at, body_start, body in class_bodies(text):
        where = f"class {class_name}, line {line_of(text, header_at)}"
        check_recognised(text, class_name, body_start, body)
        # `default` lines run in order, so with two m_UniqueName lines (UOC_Mages_Room_01_Lock has) the last one wins.
        names = [match.group(2) for match in NAME_RE.finditer(body)]
        name = names[-1] if names else (class_name[1:] if class_name.startswith("U") else class_name)
        pieces = {}
        for match in PIECE_RE.finditer(body):
            plate, rotation = int(match.group(2)), int(match.group(3))
            if plate in pieces:
                raise ValueError(f"{where}: plate {plate} is added twice")
            pieces[plate] = rotation
        if not pieces:
            raise ValueError(f"{where}: no AddPiece, so no plates")
        if sorted(pieces) != list(range(len(pieces))):
            raise ValueError(f"{where}: the plates are not 0..{len(pieces) - 1}: {sorted(pieces)}")
        start = [GOAL_HOLE - pieces[plate] for plate in range(len(pieces))]
        for plate, hole in enumerate(start):
            if not MIN_HOLE <= hole <= MAX_HOLE:
                raise ValueError(f"{where}: plate {plate} starts in hole {hole}, not in {MIN_HOLE}..{MAX_HOLE}")
        edges = [(int(m.group(2)), int(m.group(3)), int(m.group(4))) for m in CONNECTION_RE.finditer(body)]
        for src, dst, direction in edges:
            if direction not in (-1, 1):
                raise ValueError(f"{where}: connection ({src}, {dst}, {direction}) has a direction other than -1 or 1")
            if not (0 <= src < len(pieces) and 0 <= dst < len(pieces)):
                raise ValueError(
                    f"{where}: connection ({src}, {dst}, {direction}) joins a plate that is not in 0..{len(pieces) - 1}"
                )
        locks.append(Lock(name, class_name, len(pieces), edges, start))
    return locks


def source_files(modkit_dir):
    """Every .as file under <modkit>/Script, sorted."""
    script_dir = os.path.join(modkit_dir, "Script")
    if not os.path.isdir(script_dir):
        raise ValueError(f"no Script folder in {modkit_dir}: is it the G1R-Modkit repository?")
    found = []
    for root, _, files in os.walk(script_dir):
        found += [os.path.join(root, name) for name in files if name.endswith(".as")]
    return sorted(found)


def load_locks(modkit_dir):
    """{name: Lock} of all the lock classes in the Modkit sources. The game compares names without case, so two
    locks whose names differ only in case would be one: that is an error here."""
    locks = {}
    seen = {}
    for path in source_files(modkit_dir):
        with open(path, encoding="utf-8", errors="replace") as source:
            text = source.read()
        if "UGothicLockConfig" not in text:
            continue
        try:
            found = parse_locks(text)
        except ValueError as error:
            raise ValueError(f"{os.path.relpath(path, modkit_dir)}: {error}") from None
        for lock in found:
            key = lock.name.lower()
            if key in seen:
                raise ValueError(f"the lock {lock.name} is defined twice (also as {seen[key]})")
            seen[key] = lock.name
            locks[lock.name] = lock
    return locks


def sorted_locks(locks):
    return [locks[name] for name in sorted(locks, key=lambda n: (n.lower(), n))]


def as_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def to_angelscript(locks, source, build):
    lines = [
        f"// Generated by tools/gen_lockgraphs.py from {source} ({build}). Do not edit by hand.",
        "// Plates are 0..Plates-1, front to back, as in the sources. AddEdge(Src, Dst, Dir) follows its AddLock, in the",
        "// authored order of AddConnection; the game drops the first round(LockpickPrecision) of them.",
        "",
        "namespace LPH",
        "{",
        f"\tconst FString LocksSource = {as_string(source)};",
        f"\tconst FString LocksBuild = {as_string(build)};",
        "}",
        "",
        "void LPH_RegisterLockGraphs(ULPH_LockDb Db)",
        "{",
    ]
    for lock in sorted_locks(locks):
        lines.append(f"\tDb.AddLock(n{as_string(lock.name)}, {lock.plates});")
        for src, dst, direction in lock.edges:
            lines.append(f"\tDb.AddEdge({src}, {dst}, {direction});")
    lines += ["}", ""]
    return "\n".join(lines)


def to_lua(locks, source, build):
    """The same locks for the Lua reference; plates are 1-based here."""
    lines = [
        f"-- Generated by tools/gen_lockgraphs.py from {source}. Do not edit by hand.",
        "-- plates, edges { src, dst, dir } (plates 1..plates front to back, authored order) and start: the hole of",
        "-- every plate at the start (4 - rotation of AddPiece), before the game drops any connection.",
        "return {",
        f"  build = {as_string(build)},",
        "  locks = {",
    ]
    for lock in sorted_locks(locks):
        edges = ", ".join(f"{{{src + 1}, {dst + 1}, {d}}}" for src, dst, d in lock.edges)
        edges = f"{{ {edges} }}" if edges else "{}"
        start = ", ".join(str(hole) for hole in lock.start)
        lines.append(f"    [{as_string(lock.name)}] = {{ plates = {lock.plates}, edges = {edges}, start = {{ {start} }} }},")
    lines += ["  },", "}", ""]
    return "\n".join(lines)


def git_commit(modkit_dir):
    try:
        out = subprocess.run(
            ["git", "-C", modkit_dir, "rev-parse", "--short", "HEAD"], capture_output=True, text=True, check=True
        )
        return out.stdout.strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def write_text(path, text):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generates LockGraphs.as and locks_data.lua from the G1R-Modkit sources")
    parser.add_argument("--modkit", default=os.environ.get(MODKIT_ENV), help=f"the G1R-Modkit repository (or set {MODKIT_ENV})")
    parser.add_argument("--commit", help="the Modkit commit the sources are from (default: git rev-parse of --modkit)")
    parser.add_argument("--build", default="unknown", help="the game build the Modkit matches, e.g. Build102_CL175960")
    parser.add_argument("--out-as", default=DEFAULT_AS)
    parser.add_argument("--out-lua", default=DEFAULT_LUA)
    args = parser.parse_args(argv)
    if not args.modkit:
        parser.error(f"give --modkit <G1R-Modkit repository> or set {MODKIT_ENV}")
    try:
        locks = load_locks(args.modkit)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    commit = args.commit or git_commit(args.modkit) or "unknown"
    source = f"G1R-Modkit {commit}"
    write_text(args.out_as, to_angelscript(locks, source, args.build))
    write_text(args.out_lua, to_lua(locks, source, args.build))
    edges = sum(len(lock.edges) for lock in locks.values())
    print(f"{len(locks)} locks, {edges} connections ({source}, {args.build}) -> {args.out_as}, {args.out_lua}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
