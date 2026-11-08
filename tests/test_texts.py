"""The mod's texts in the game's text database (mod/LockPickHelper/Story/Conversation/text/*.textdb.yaml) against each
other and against Texts.as: the same IDs everywhere, one language per file, nothing empty, {0} where English has it, and
the English YAML saying exactly what Texts.as falls back to. Stdlib only: the YAML here is the game's simple TextDB format
(an ID line, then `  <language>: "<text>"` lines), parsed by hand."""

import os
import re
import unittest

REPO = os.path.join(os.path.dirname(__file__), "..")
MOD = os.path.join(REPO, "mod", "LockPickHelper")
TEXT_DIR = os.path.join(MOD, "Story", "Conversation", "text")
SCRIPT_DIR = os.path.join(MOD, "Script", "LockPickHelper")
LANGUAGES = ("english", "russian", "german", "polish")
YAML_SUFFIX = ".textdb.yaml"

ID_LINE = re.compile(r"^([A-Za-z0-9_]+):\s*$")
TEXT_LINE = re.compile(r'^\s+([A-Za-z0-9_]+):\s*"((?:[^"\\]|\\.)*)"\s*$')
PRINTF = re.compile(r"%[A-Za-z]")


def unescape(text):
    return re.sub(r"\\(.)", r"\1", text)


def parse_textdb(raw):
    """{ID: {language: text}} of a TextDB YAML, the IDs in file order. Blank lines and # comments are skipped; any other
    line that is not an ID or a quoted text of the ID above it is an error."""
    entries = {}
    current = None
    for number, line in enumerate(raw.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = ID_LINE.match(line)
        if m:
            current = m.group(1)
            if current in entries:
                raise ValueError(f"line {number}: {current} twice")
            entries[current] = {}
            continue
        m = TEXT_LINE.match(line)
        if m and current is not None:
            language = m.group(1)
            if language in entries[current]:
                raise ValueError(f"line {number}: {current} has {language} twice")
            entries[current][language] = unescape(m.group(2))
            continue
        raise ValueError(f"line {number}: not an ID or a quoted text: {line!r}")
    return entries


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def yaml_path(language):
    return os.path.join(TEXT_DIR, f"LockPickHelper.{language}{YAML_SUFFIX}")


def load_yaml(language):
    return parse_textdb(read_bytes(yaml_path(language)).decode("utf-8"))


def texts_as():
    return read_bytes(os.path.join(SCRIPT_DIR, "Texts.as")).decode("utf-8")


def function_body(source, name):
    m = re.search(r"\b" + name + r"\(\)\s*\{(.*?)\n\t\}", source, re.S)
    if not m:
        raise AssertionError(f"Texts.as has no {name}()")
    return m.group(1)


def struct_fields(source, name):
    m = re.search(r"struct " + name + r"\s*\{(.*?)\n\}", source, re.S)
    if not m:
        raise AssertionError(f"Texts.as has no struct {name}")
    return re.findall(r"^\s*FString (\w+);", m.group(1), re.M)


def assigned_strings(source, function, var):
    """[(field, text)] of `<var>.<field> = "<text>";` in the function, in order."""
    return [(f, unescape(t)) for f, t in
            re.findall(r"\b" + var + r'\.(\w+) = "((?:[^"\\]|\\.)*)";', function_body(source, function))]


def loc_pairs(source, function, var):
    """[(field, id, fallback field)] of `<var>.<field> = Loc("<id>", En.<field>);` in the function, in order."""
    return re.findall(r"\b" + var + r'\.(\w+) = Loc\("(\w+)", En\.(\w+)\);', function_body(source, function))


class TextsAsTest(unittest.TestCase):
    """Texts.as itself: GameTexts / GameLabels ask the text database for every field, each by its own ID, with the
    field's own English as the fallback."""

    def check_game_function(self, struct, function, var, prefix):
        source = texts_as()
        fields = struct_fields(source, struct)
        pairs = loc_pairs(source, function, var)
        self.assertEqual([f for f, _, _ in pairs], fields, f"{function} sets every field of {struct}, in order")
        for field, text_id, fallback in pairs:
            self.assertEqual(text_id, prefix + field, f"{function}: the ID of {field}")
            self.assertEqual(fallback, field, f"{function}: the fallback of {field}")

    def test_game_texts(self):
        self.check_game_function("FLPH_Texts", "GameTexts", "X", "LPH_")

    def test_game_labels(self):
        self.check_game_function("FLPH_Labels", "GameLabels", "L", "LPH_Row_")

    def test_english_tables_fill_every_field(self):
        source = texts_as()
        self.assertEqual([f for f, _ in assigned_strings(source, "TextsEn", "X")], struct_fields(source, "FLPH_Texts"))
        self.assertEqual([f for f, _ in assigned_strings(source, "LabelsEn", "L")], struct_fields(source, "FLPH_Labels"))


def code_ids():
    """The IDs of Texts.as in the order of the structs: the notes, then the labels."""
    source = texts_as()
    return ([text_id for _, text_id, _ in loc_pairs(source, "GameTexts", "X")]
            + [text_id for _, text_id, _ in loc_pairs(source, "GameLabels", "L")])


def code_english():
    """{ID: the English fallback of Texts.as}."""
    source = texts_as()
    strings = {}
    for function, var, prefix in (("TextsEn", "X", "LPH_"), ("LabelsEn", "L", "LPH_Row_")):
        for field, text in assigned_strings(source, function, var):
            strings[prefix + field] = text
    return strings


class YamlTest(unittest.TestCase):
    def test_the_four_files_and_nothing_else(self):
        names = sorted(n for n in os.listdir(TEXT_DIR) if n.endswith(YAML_SUFFIX))
        self.assertEqual(names, sorted(os.path.basename(yaml_path(lang)) for lang in LANGUAGES))

    def test_utf8_without_bom(self):
        for language in LANGUAGES:
            raw = read_bytes(yaml_path(language))
            self.assertFalse(raw.startswith(b"\xef\xbb\xbf"), f"{language}: no byte order mark")
            raw.decode("utf-8")

    def test_same_ids_as_english_and_as_the_code(self):
        ids = code_ids()
        self.assertEqual(len(ids), len(set(ids)), "no ID twice in Texts.as")
        english = load_yaml("english")
        self.assertEqual(list(english), ids, "english: the IDs of Texts.as, in the order of the structs")
        for language in LANGUAGES:
            self.assertEqual(list(load_yaml(language)), list(english), f"{language}: the IDs of english, in its order")

    def test_each_file_only_its_own_language(self):
        for language in LANGUAGES:
            for text_id, texts in load_yaml(language).items():
                self.assertEqual(list(texts), [language], f"{language}: {text_id}")

    def test_no_empty_string(self):
        for language in LANGUAGES:
            for text_id, texts in load_yaml(language).items():
                self.assertTrue(texts[language].strip(), f"{language}: {text_id} is empty")

    def test_placeholders_as_in_english(self):
        english = load_yaml("english")
        for language in LANGUAGES:
            for text_id, texts in load_yaml(language).items():
                self.assertEqual("{0}" in texts[language], "{0}" in english[text_id]["english"],
                                 f"{language}: {text_id} has {{0}} where english has it")
                self.assertNotRegex(re.sub(r"\{0\}", "", texts[language]), r"[{}]", f"{language}: {text_id}")

    def test_no_printf_specifiers(self):
        # "Size, %" is a label of its own (a percent sign, not %d); the notes have no % at all.
        for language in LANGUAGES:
            for text_id, texts in load_yaml(language).items():
                text = texts[language]
                self.assertIsNone(PRINTF.search(text), f"{language}: {text_id} has a %s or %d")
                if not text_id.startswith("LPH_Row_"):
                    self.assertNotIn("%", text, f"{language}: {text_id}")

    def test_english_is_the_fallback_of_the_code(self):
        english = {text_id: texts["english"] for text_id, texts in load_yaml("english").items()}
        self.assertEqual(english, code_english())


class SettingsTest(unittest.TestCase):
    def test_rows_ask_for_their_own_ids(self):
        """Each row of Settings.as is declared with LocText("LPH_Row_<row>") and relabelled in Initialize with
        RowText("LPH_Row_<row>", L.<row>); the rows are the fields of FLPH_Labels."""
        source = read_bytes(os.path.join(SCRIPT_DIR, "Settings.as")).decode("utf-8")
        rows = struct_fields(texts_as(), "FLPH_Labels")
        declared = re.findall(r"FModUserSettings(?:Bool|Int) (\w+) = FModUserSettings(?:Bool|Int)\((.*?)\);", source, re.S)
        self.assertEqual([row for row, _ in declared], rows, "the rows, in the order of FLPH_Labels")
        for row, body in declared:
            self.assertIn(f'DisplayText = LocText("LPH_Row_{row}")', body, row)
        relabelled = re.findall(r'\n\t\t(\w+) = FModUserSettings(?:Bool|Int)\(.*?DisplayText = LPH::RowText\("(\w+)", L\.(\w+)\)',
                                source, re.S)
        self.assertEqual([(row, f"LPH_Row_{row}", row) for row in rows], relabelled, "Initialize")


class MountTest(unittest.TestCase):
    def test_game_ini_mounts_the_texts_under_the_mod_name(self):
        raw = read_bytes(os.path.join(MOD, "Config", "Game.ini")).decode("utf-8")
        self.assertEqual(
            [line for line in raw.splitlines() if line.strip()],
            [
                "[/Script/AlkimiaStoryFileImport.AlkimiaLocalizationSubsystem]",
                '+MountPoints=(MountPoint="/LockPickHelper", Module="LockPickHelper", MountPath="/Story/Conversation")',
            ],
        )


if __name__ == "__main__":
    unittest.main()
