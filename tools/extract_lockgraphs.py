"""Extracts lockpick plate graphs from G1R PrecompiledScript_Shipping.Cache.

Usage: python tools/extract_lockgraphs.py --game-dir "<Gothic 1 Remake folder>" [--out PATH]
       (or set the G1R_GAME_DIR environment variable instead of --game-dir)
Format notes: docs/TECHNICAL.md
"""
import argparse
import hashlib
import os
import re
import struct
import sys

from lockgraphs_lua import to_lua

GAME_DIR_ENV = "G1R_GAME_DIR"
DEFAULT_OUT = os.path.join(os.path.dirname(__file__), "..", "mod", "G1LockPickHelper", "Scripts", "lockgraphs.lua")

MAX_STR_LEN = 1024
MAX_PLATES = 7  # the lock scene has a pool of 7 plate actors ("The minigame" in docs/TECHNICAL.md)
CLASS_HEADER_TAIL = 12  # class header: STR name, STR namespace, 8 flag bytes, i32 method count
METHOD_META_SIZE = 56  # method record: STR name, STR namespace, 56 bytes, i32 n, n bytecode words
STATIC_TYPE_GAP = 32  # bytes between the superclass strings and "__StaticType_<class>"
STATIC_TYPE_PREFIX = "__StaticType_"

OP_PSHC4, OP_PSHVPTR, OP_PSHRPTR, OP_ADDSI, OP_CALLSYS, OP_RET = 0x02, 0x30, 0x3B, 0x4F, 0x3D, 0x0A
OP_WORDS = {OP_PSHC4: 2, OP_PSHVPTR: 1, OP_PSHRPTR: 1, OP_ADDSI: 2, OP_CALLSYS: 3, OP_RET: 1}
CALLSYS_WORD = bytes([OP_CALLSYS, 0, 0, 0])
THIS = ("this",)


class FormatError(Exception):
    pass


def skip(what, reason):
    print(f"skipped {what}: {reason}", file=sys.stderr)


def encode_str(s):
    raw = s.encode("ascii")
    return struct.pack("<i", len(raw)) + raw + b"\x00"


INIT_DEFAULTS = encode_str("__InitDefaults")
LOCK_SUPERCLASS = encode_str("UGothicLockConfig") + encode_str("/Script/G1R.GothicLockConfig")


def i32(data, pos):
    return struct.unpack_from("<i", data, pos)[0]


def u32(data, pos):
    return struct.unpack_from("<I", data, pos)[0]


def is_text(raw):
    return all(32 <= b < 127 for b in raw)


def read_str(data, pos):
    """Reads STR at pos: i32 len, len ASCII bytes, NUL (no NUL when empty). Returns (text, end)."""
    n = i32(data, pos)
    if n == 0:
        return "", pos + 4
    raw = data[pos + 4:pos + 4 + n]
    if not 0 < n <= MAX_STR_LEN or data[pos + 4 + n] != 0 or not is_text(raw):
        raise FormatError(f"no string at {pos:#x}")
    return raw.decode("ascii"), pos + 5 + n


def str_start_before(data, end):
    """Start offset of the STR that ends exactly at `end`."""
    if data[end - 1] == 0:
        first = end - 1  # first byte of the printable run before the NUL
        while end - 1 - first < MAX_STR_LEN and 32 <= data[first - 1] < 127:
            first -= 1
        for n in range(1, end - first):
            if i32(data, end - 5 - n) == n:
                return end - 5 - n
    if i32(data, end - 4) == 0:
        return end - 4
    raise FormatError(f"no string ends at {end:#x}")


def read_tail_tables(data):
    """Walks the two last sections backwards from EOF.

    Property record: u32 ?, u32 offset2 (= 2 * ADDSi operand), STR name, u32 owner typeId.
    Returns (names, props): FName literal strings by index, and {(typeId, offset2): property name}.
    """
    props, count = {}, 0
    end = len(data)
    while True:
        owner = u32(data, end - 4)
        start = str_start_before(data, end - 4)
        props[(owner, u32(data, start - 4))] = read_str(data, start)[0]
        end, count = start - 8, count + 1
        if i32(data, end - 4) == count:
            break
    names = []
    end -= 4
    while True:
        start = str_start_before(data, end)
        names.append(read_str(data, start)[0])
        end = start
        if i32(data, end - 4) == len(names):
            break
    names.reverse()
    return names, props


class FunctionNames:
    """Resolves CALLSYS pointers through the reference record: 8 pointer bytes followed by STR name.

    Occurrences that are CALLSYS operands (preceded by the opcode word) are bytecode, not the record.
    """

    def __init__(self, data):
        self.data = data
        self.cache = {}

    def __call__(self, ptr):
        if ptr not in self.cache:
            needle = struct.pack("<Q", ptr)
            found = set()
            pos = self.data.find(needle)
            while pos != -1:
                if self.data[pos - 4:pos] != CALLSYS_WORD:
                    try:
                        found.add(read_str(self.data, pos + 8)[0])
                    except FormatError:
                        pass
                pos = self.data.find(needle, pos + 1)
            self.cache[ptr] = found.pop() if len(found) == 1 else None
        if self.cache[ptr] is None:
            raise FormatError(f"cannot resolve function pointer {ptr:#x}")
        return self.cache[ptr]

    def pointer(self, name):
        return next((ptr for ptr, n in self.cache.items() if n == name), None)


def find_lock_classes(data):
    """{class name: superclass offset} for every class whose superclass is GothicLockConfig."""
    classes = {}
    for m in re.finditer(re.escape(LOCK_SUPERCLASS), data):
        try:
            name, _ = read_str(data, m.end() + STATIC_TYPE_GAP)
        except FormatError:
            name = ""
        if not name.startswith(STATIC_TYPE_PREFIX):
            skip(f"GothicLockConfig subclass at {m.start():#x}", f"no {STATIC_TYPE_PREFIX} name")
            continue
        classes[name[len(STATIC_TYPE_PREFIX):]] = m.start()
    return classes


def method_owner(data, method_pos):
    """Class name from the class header right before the first method record."""
    ns_start = str_start_before(data, method_pos - CLASS_HEADER_TAIL)
    owner_start = str_start_before(data, ns_start)
    return read_str(data, owner_start)[0]


def method_bytecode(data, method_pos):
    _, pos = read_str(data, method_pos)
    _, pos = read_str(data, pos)
    pos += METHOD_META_SIZE
    n = i32(data, pos)
    if not 0 < n <= (len(data) - pos - 4) // 4:
        raise FormatError(f"bad bytecode length {n} at {pos:#x}")
    return struct.unpack_from(f"<{n}I", data, pos + 4)


def run_init_defaults(words, function_name, property_name, names):
    """Executes the subset of AngelScript bytecode used by lock defaults.

    Returns (unique_names, pieces, links): m_UniqueName assignments in order, AddPiece (index, rotation)
    and AddConnection (src, dst, dir) arguments, all 0-based as in the cache.
    """
    stack, result = [], None
    unique_names, pieces, links = [], [], []

    def pop(count):
        if len(stack) < count:
            raise FormatError("stack underflow")
        return [stack.pop() for _ in range(count)]

    def ints(values):
        if not all(isinstance(v, int) for v in values):
            raise FormatError(f"expected int arguments, got {values}")
        return values

    i = 0
    while i < len(words):
        word = words[i]
        op, arg = word & 0xFF, word >> 16
        size = OP_WORDS.get(op)
        if size is None or i + size > len(words):
            raise FormatError(f"unexpected opcode {op:#x} at word {i}")
        if op == OP_PSHC4:
            stack.append(struct.unpack("<i", struct.pack("<I", words[i + 1]))[0])
        elif op == OP_PSHVPTR:
            if arg != 0:
                raise FormatError(f"PshVPtr of local variable {arg} at word {i}")
            stack.append(THIS)
        elif op == OP_PSHRPTR:
            stack.append(result)
        elif op == OP_ADDSI:
            if pop(1) != [THIS]:
                raise FormatError(f"ADDSi not on this at word {i}")
            prop = property_name.get((words[i + 1], 2 * arg))
            if prop is None:
                raise FormatError(f"unknown property offset {arg:#x} of type {words[i + 1]:#x}")
            stack.append(("prop", prop))
        elif op == OP_CALLSYS:
            fn = function_name(words[i + 1] | words[i + 2] << 32)
            if fn == "__STATIC_NAME":
                (index,) = ints(pop(1))
                if not 0 <= index < len(names):
                    raise FormatError(f"FName literal index {index} out of range")
                result = ("fname", names[index])
            elif fn == "opAssign":
                target, value = pop(2)
                if not (isinstance(target, tuple) and target[0] == "prop"
                        and isinstance(value, tuple) and value[0] == "fname"):
                    raise FormatError(f"unexpected assignment {target} = {value}")
                if target[1] == "m_UniqueName":
                    unique_names.append(value[1])
            elif fn in ("AddPiece", "AddConnection"):
                args = pop(3 if fn == "AddPiece" else 4)
                if args[0] != THIS:
                    raise FormatError(f"{fn} not called on this at word {i}")
                (pieces if fn == "AddPiece" else links).append(tuple(ints(args[1:])))
            else:
                raise FormatError(f"unexpected call {fn} at word {i}")
        elif op == OP_RET:
            if i + size != len(words) or stack:
                raise FormatError(f"RET at word {i} before the end or with a non-empty stack")
            return unique_names, pieces, links
        i += size
    raise FormatError("bytecode does not end with RET")


def to_lock_graph(pieces, links):
    """Cache numbering (0-based, front to back) -> project lock (1-based, front to back).

    Returns {"plates": n, "edges": [(src, dst, dir), ...]}: the AddConnection calls in authored order. The game
    removes the first round(LockpickPrecision) of them at minigame setup ("Lockpicking skill" in docs/TECHNICAL.md).
    """
    plates = len(pieces)
    indices = [index for index, _ in pieces]
    if indices != list(range(plates)) or not 1 <= plates <= MAX_PLATES:
        raise FormatError(f"unexpected AddPiece indices {indices} (expected 0..n-1, n <= {MAX_PLATES})")
    edges = []
    for src, dst, direction in links:
        if not (0 <= src < plates and 0 <= dst < plates and src != dst and direction in (1, -1)):
            raise FormatError(f"bad AddConnection({src}, {dst}, {direction})")
        edges.append((src + 1, dst + 1, direction))
    return {"plates": plates, "edges": edges}


def parse_locks(data):
    """Returns {unique_name: {"plates": int, "edges": [(src, dst, dir), ...]}}: plates 1-based front-to-back,
    edges in authored order."""
    names, property_name = read_tail_tables(data)
    function_name = FunctionNames(data)
    lock_classes = find_lock_classes(data)
    if not lock_classes:
        raise FormatError("no GothicLockConfig subclasses found")
    locks, owners, parsed = {}, {}, set()
    calls = {"AddPiece": 0, "AddConnection": 0}
    for m in re.finditer(re.escape(INIT_DEFAULTS), data):
        try:
            owner = method_owner(data, m.start())
        except FormatError:
            continue
        if owner not in lock_classes:
            continue
        parsed.add(owner)
        where = f"{owner} (__InitDefaults at {m.start():#x})"
        try:
            words = method_bytecode(data, m.start())
            unique_names, pieces, links = run_init_defaults(words, function_name, property_name, names)
            lock = to_lock_graph(pieces, links)
            if not unique_names:
                raise FormatError("no m_UniqueName assignment")
        except FormatError as e:
            skip(where, e)
            continue
        name = unique_names[-1]  # the bytecode runs top to bottom: the last assignment stays
        if name in locks:
            skip(where, f"m_UniqueName {name} already defined by {owners[name]}")
            continue
        locks[name], owners[name] = lock, owner
        calls["AddPiece"] += len(pieces)
        calls["AddConnection"] += len(links)
    for owner in sorted(set(lock_classes) - parsed):
        skip(f"{owner} (superclass at {lock_classes[owner]:#x})", "no __InitDefaults record found")
    for fn, count in calls.items():
        ptr = function_name.pointer(fn)
        sites = data.count(CALLSYS_WORD + struct.pack("<Q", ptr)) if ptr is not None else 0
        if sites != count:
            print(f"warning: {sites} {fn} call sites in the cache, {count} in extracted locks", file=sys.stderr)
    return locks


def game_dir(arg=None, environ=None):
    """The game folder: --game-dir, else the G1R_GAME_DIR environment variable; None when neither is set."""
    environ = os.environ if environ is None else environ
    return arg or environ.get(GAME_DIR_ENV) or None


def cache_path(gdir):
    return os.path.join(gdir, "G1R", "Script", "PrecompiledScript_Shipping.Cache")


def version_path(gdir):
    return os.path.join(gdir, "G1R", "Version", "version.txt")


def read_build(path):
    with open(path, encoding="utf-16") as f:
        return f.read().strip()


def main(argv=None):
    ap = argparse.ArgumentParser(description="Extract lockpick plate graphs from Gothic 1 Remake.")
    ap.add_argument("--game-dir", help=f"the game folder (default: the {GAME_DIR_ENV} environment variable)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args(argv)
    gdir = game_dir(args.game_dir)
    if not gdir:
        ap.error(f"set --game-dir or the {GAME_DIR_ENV} environment variable to the game folder")
    with open(cache_path(gdir), "rb") as f:
        data = f.read()
    locks = parse_locks(data)
    sha1 = hashlib.sha1(data).hexdigest()
    text = to_lua(locks, read_build(version_path(gdir)), sha1)  # everything that can fail runs before --out is opened
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    sizes = {}
    for lock in locks.values():
        sizes[lock["plates"]] = sizes.get(lock["plates"], 0) + 1
    print(f"locks: {len(locks)}; by plate count: {dict(sorted(sizes.items()))}; out: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
