// Texts.as, Values.as, Settings.as: the choice of the language, the texts and the labels of both languages (every string
// is checked letter by letter against lang/en.lua and lang/ru.lua of 1.2.0, with %s and %d turned into {0}), the
// settings struct with its defaults and limits, and the reading of the rows. The rows themselves (DefaultValue, the
// limits, the labels) cannot be read back by a script, so what ends up in the game's menu is checked by eye (Task 12).
// The tests do not depend on what the player has set in the options: a test-made settings object starts as a copy of the
// class default object (the player's values), so every case writes the values it needs first. The two checks that do read
// the player's state (the rows' declared defaults against FLPH_Values) run only with `-LPHTests=defaults`, on a clean profile.

void LPHTests_TextsLang(ULPH_TestRun T, int Setting, FName Display, ELPH_Lang Expected, FString What)
{
	T.EqualInt(int(LPH::LangFor(Setting, Display)), int(Expected), What);
}

void LPHTests_TextsLangFor(ULPH_TestRun T)
{
	T.Begin("Texts: LangFor");
	LPHTests_TextsLang(T, 0, n"Russian", ELPH_Lang::Ru, "auto, the game in Russian");
	LPHTests_TextsLang(T, 0, n"English", ELPH_Lang::En, "auto, the game in English");
	LPHTests_TextsLang(T, 0, n"German", ELPH_Lang::En, "auto, the game in German (no Russian texts for it)");
	LPHTests_TextsLang(T, 1, n"Russian", ELPH_Lang::En, "English chosen, the game in Russian");
	LPHTests_TextsLang(T, 2, n"English", ELPH_Lang::Ru, "Russian chosen, the game in English");
	LPHTests_TextsLang(T, 2, n"German", ELPH_Lang::Ru, "Russian chosen, the game in German");
	LPHTests_TextsLang(T, 1, n"English", ELPH_Lang::En, "English chosen, the game in English");
	LPHTests_TextsLang(T, 0, NAME_None, ELPH_Lang::En, "auto, no game settings");
	LPHTests_TextsLang(T, 2, NAME_None, ELPH_Lang::Ru, "Russian chosen, no game settings");
	LPHTests_TextsLang(T, 0, n"russian", ELPH_Lang::Ru, "names do not depend on the case");
	LPHTests_TextsLang(T, 7, n"Russian", ELPH_Lang::Ru, "a setting out of range counts as auto (Russian game)");
	LPHTests_TextsLang(T, -3, n"English", ELPH_Lang::En, "a setting out of range counts as auto (English game)");
}

void LPHTests_TextsFill(ULPH_TestRun T)
{
	T.Begin("Texts: Fill");
	T.EqualStr(LPH::Fill(LPH::Texts(ELPH_Lang::Ru).SolvingTime, "12"), "Автовзлом… 12 с", "ru solving time");
	T.EqualStr(LPH::Fill(LPH::Texts(ELPH_Lang::En).NotInDb, "X"), "Lock not in the database: X", "en lock not in the database");
	T.EqualStr(LPH::Fill(LPH::Texts(ELPH_Lang::En).HintOn, "F4"), "Hint shown (F4)", "en hint on");
	T.EqualStr(LPH::Fill(LPH::Texts(ELPH_Lang::Ru).HintOff, "F4"), "Подсказка скрыта (F4)", "ru hint off");
	T.EqualStr(LPH::Fill(LPH::Texts(ELPH_Lang::En).SolveOn, LPH::Texts(ELPH_Lang::En).DoubleReset), "Auto-pick on (double reset)", "en auto-pick on by the double reset");
	T.EqualStr(LPH::Fill(LPH::Texts(ELPH_Lang::Ru).SolveOff, LPH::Texts(ELPH_Lang::Ru).DoubleReset), "Автовзлом выключен (двойной сброс)", "ru auto-pick off by the double reset");
	T.EqualStr(LPH::Fill("no placeholder", "X"), "no placeholder", "a template without {0} stays as it is");
	T.EqualStr(LPH::Fill("a {0} b", ""), "a  b", "an empty value");
}

TArray<FString> LPHTests_TextsFields(FLPH_Texts X)
{
	TArray<FString> F;
	F.Add(X.NotInDb);
	F.Add(X.NoSafePath);
	F.Add(X.BadState);
	F.Add(X.HintOn);
	F.Add(X.HintOff);
	F.Add(X.Solving);
	F.Add(X.SolvingTime);
	F.Add(X.SolveArmed);
	F.Add(X.SolveStopped);
	F.Add(X.SolveUnavailable);
	F.Add(X.SolveOn);
	F.Add(X.SolveOff);
	F.Add(X.DoubleReset);
	F.Add(X.Thinking);
	return F;
}

TArray<FString> LPHTests_TextsFieldNames()
{
	TArray<FString> N;
	N.Add("NotInDb");
	N.Add("NoSafePath");
	N.Add("BadState");
	N.Add("HintOn");
	N.Add("HintOff");
	N.Add("Solving");
	N.Add("SolvingTime");
	N.Add("SolveArmed");
	N.Add("SolveStopped");
	N.Add("SolveUnavailable");
	N.Add("SolveOn");
	N.Add("SolveOff");
	N.Add("DoubleReset");
	N.Add("Thinking");
	return N;
}

void LPHTests_TextsStrings(ULPH_TestRun T)
{
	T.Begin("Texts: every string of en");
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);
	T.EqualStr(En.NotInDb, "Lock not in the database: {0}", "NotInDb");
	T.EqualStr(En.NoSafePath, "Can't open without risking the pick", "NoSafePath");
	T.EqualStr(En.BadState, "Can't read the lock", "BadState");
	T.EqualStr(En.HintOn, "Hint shown ({0})", "HintOn");
	T.EqualStr(En.HintOff, "Hint hidden ({0})", "HintOff");
	T.EqualStr(En.Solving, "Auto-picking…", "Solving");
	T.EqualStr(En.SolvingTime, "Auto-picking… {0} s", "SolvingTime");
	T.EqualStr(En.SolveArmed, "Auto-pick: waiting for the lock", "SolveArmed");
	T.EqualStr(En.SolveStopped, "Auto-pick stopped", "SolveStopped");
	T.EqualStr(En.SolveUnavailable, "Auto-pick unavailable", "SolveUnavailable");
	T.EqualStr(En.SolveOn, "Auto-pick on ({0})", "SolveOn");
	T.EqualStr(En.SolveOff, "Auto-pick off ({0})", "SolveOff");
	T.EqualStr(En.DoubleReset, "double reset", "DoubleReset");
	T.EqualStr(En.Thinking, "Thinking…", "Thinking");

	T.Begin("Texts: every string of ru");
	FLPH_Texts Ru = LPH::Texts(ELPH_Lang::Ru);
	T.EqualStr(Ru.NotInDb, "Замка нет в базе: {0}", "NotInDb");
	T.EqualStr(Ru.NoSafePath, "Без риска для отмычки не открыть", "NoSafePath");
	T.EqualStr(Ru.BadState, "Не удалось прочитать замок", "BadState");
	T.EqualStr(Ru.HintOn, "Подсказка видна ({0})", "HintOn");
	T.EqualStr(Ru.HintOff, "Подсказка скрыта ({0})", "HintOff");
	T.EqualStr(Ru.Solving, "Автовзлом…", "Solving");
	T.EqualStr(Ru.SolvingTime, "Автовзлом… {0} с", "SolvingTime");
	T.EqualStr(Ru.SolveArmed, "Автовзлом ждёт замок", "SolveArmed");
	T.EqualStr(Ru.SolveStopped, "Автовзлом остановлен", "SolveStopped");
	T.EqualStr(Ru.SolveUnavailable, "Автовзлом недоступен", "SolveUnavailable");
	T.EqualStr(Ru.SolveOn, "Автовзлом включён ({0})", "SolveOn");
	T.EqualStr(Ru.SolveOff, "Автовзлом выключен ({0})", "SolveOff");
	T.EqualStr(Ru.DoubleReset, "двойной сброс", "DoubleReset");
	T.EqualStr(Ru.Thinking, "Считаю…", "Thinking");

	// The rules that hold for any language: nothing empty, no leftover printf specifiers, {0} in the same strings.
	T.Begin("Texts: no empty strings, same placeholders");
	TArray<FString> Names = LPHTests_TextsFieldNames();
	TArray<FString> InEn = LPHTests_TextsFields(En);
	TArray<FString> InRu = LPHTests_TextsFields(Ru);
	T.EqualInt(InEn.Num(), Names.Num(), "en fields listed");
	T.EqualInt(InRu.Num(), Names.Num(), "ru fields listed");
	for (int i = 0; i < Names.Num() && i < InEn.Num() && i < InRu.Num(); i++)
	{
		T.True(!InEn[i].IsEmpty(), "en " + Names[i] + " is not empty");
		T.True(!InRu[i].IsEmpty(), "ru " + Names[i] + " is not empty");
		T.True(!InEn[i].Contains("%") && !InRu[i].Contains("%"), Names[i] + " has no %s or %d left");
		T.True(InEn[i].Contains("{0}") == InRu[i].Contains("{0}"), Names[i] + " has {0} in both languages or in neither");
	}
}

void LPHTests_TextsLabels(ULPH_TestRun T)
{
	T.Begin("Labels: every row of en");
	FLPH_Labels En = LPH::Labels(ELPH_Lang::En);
	T.EqualStr(En.Language, "Language (0 as in the game, 1 English, 2 Русский)", "Language");
	T.EqualStr(En.Tape, "Tape layout", "Tape");
	T.EqualStr(En.Gothic, "Gothic style", "Gothic");
	T.EqualStr(En.Icons, "Icons (0 auto, 1 letters, 2 icons)", "Icons");
	T.EqualStr(En.Gamepad, "Icon set (0 game, 1 PS, 2 Xbox, 3 Switch)", "Gamepad");
	T.EqualStr(En.Scale, "Size, %", "Scale");
	T.EqualStr(En.OffsetX, "Position X", "OffsetX");
	T.EqualStr(En.OffsetY, "Position Y", "OffsetY");
	T.EqualStr(En.Counter, "Counter", "Counter");
	T.EqualStr(En.Shake, "Shake on a miss", "Shake");
	T.EqualStr(En.TapeNext, "Upcoming keys", "TapeNext");
	T.EqualStr(En.TapeDone, "Pressed keys", "TapeDone");
	T.EqualStr(En.Slide, "Smooth scroll", "Slide");
	T.EqualStr(En.Plate, "Dark background", "Plate");
	T.EqualStr(En.PerLine, "Keys per line", "PerLine");
	T.EqualStr(En.MaxLines, "Lines on screen", "MaxLines");
	T.EqualStr(En.CollapseMin, "Fold repeats from", "CollapseMin");
	T.EqualStr(En.AutoPick, "Always auto-pick", "AutoPick");
	T.EqualStr(En.DoubleReset, "Double reset", "DoubleReset");
	T.EqualStr(En.Timer, "Countdown", "Timer");

	T.Begin("Labels: every row of ru");
	FLPH_Labels Ru = LPH::Labels(ELPH_Lang::Ru);
	T.EqualStr(Ru.Language, "Язык (0 авто, 1 English, 2 Русский)", "Language");
	T.EqualStr(Ru.Tape, "Лента вместо строк", "Tape");
	T.EqualStr(Ru.Gothic, "Готический стиль", "Gothic");
	T.EqualStr(Ru.Icons, "Значки (0 авто, 1 буквы, 2 значки)", "Icons");
	T.EqualStr(Ru.Gamepad, "Набор (0 игра, 1 PS, 2 Xbox, 3 Switch)", "Gamepad");
	T.EqualStr(Ru.Scale, "Размер, %", "Scale");
	T.EqualStr(Ru.OffsetX, "Положение по X", "OffsetX");
	T.EqualStr(Ru.OffsetY, "Положение по Y", "OffsetY");
	T.EqualStr(Ru.Counter, "Счётчик", "Counter");
	T.EqualStr(Ru.Shake, "Тряска при промахе", "Shake");
	T.EqualStr(Ru.TapeNext, "Следующих клавиш", "TapeNext");
	T.EqualStr(Ru.TapeDone, "Нажатых клавиш", "TapeDone");
	T.EqualStr(Ru.Slide, "Плавная прокрутка", "Slide");
	T.EqualStr(Ru.Plate, "Тёмный фон", "Plate");
	T.EqualStr(Ru.PerLine, "Клавиш в строке", "PerLine");
	T.EqualStr(Ru.MaxLines, "Строк на экране", "MaxLines");
	T.EqualStr(Ru.CollapseMin, "Сжимать повторы от", "CollapseMin");
	T.EqualStr(Ru.AutoPick, "Автовзлом всегда", "AutoPick");
	T.EqualStr(Ru.DoubleReset, "Двойной сброс", "DoubleReset");
	T.EqualStr(Ru.Timer, "Таймер", "Timer");
}

// The names of the fields in which two value structs differ, e.g. " Scale bTape"; empty when they are the same.
FString LPHTests_ValuesDiff(FLPH_Values A, FLPH_Values B)
{
	FString D = "";
	if (A.Language != B.Language) D += " Language";
	if (A.bTape != B.bTape) D += " bTape";
	if (A.bGothic != B.bGothic) D += " bGothic";
	if (A.Icons != B.Icons) D += " Icons";
	if (A.Gamepad != B.Gamepad) D += " Gamepad";
	if (A.Scale != B.Scale) D += " Scale";
	if (A.OffsetX != B.OffsetX) D += " OffsetX";
	if (A.OffsetY != B.OffsetY) D += " OffsetY";
	if (A.bCounter != B.bCounter) D += " bCounter";
	if (A.bShake != B.bShake) D += " bShake";
	if (A.TapeNext != B.TapeNext) D += " TapeNext";
	if (A.TapeDone != B.TapeDone) D += " TapeDone";
	if (A.bSlide != B.bSlide) D += " bSlide";
	if (A.bPlate != B.bPlate) D += " bPlate";
	if (A.PerLine != B.PerLine) D += " PerLine";
	if (A.MaxLines != B.MaxLines) D += " MaxLines";
	if (A.CollapseMin != B.CollapseMin) D += " CollapseMin";
	if (A.bAutoPick != B.bAutoPick) D += " bAutoPick";
	if (A.bDoubleReset != B.bDoubleReset) D += " bDoubleReset";
	if (A.bTimer != B.bTimer) D += " bTimer";
	if (A.bDebug != B.bDebug) D += " bDebug";
	return D;
}

// The defaults of settings.lua of 1.2.0, each one written out here.
FLPH_Values LPHTests_ValuesBrief()
{
	FLPH_Values V;
	V.Language = 0;
	V.bTape = true;
	V.bGothic = false;
	V.Icons = 0;
	V.Gamepad = 0;
	V.Scale = 100;
	V.OffsetX = -760;
	V.OffsetY = 0;
	V.bCounter = true;
	V.bShake = true;
	V.TapeNext = 5;
	V.TapeDone = 3;
	V.bSlide = true;
	V.bPlate = false;
	V.PerLine = 16;
	V.MaxLines = 6;
	V.CollapseMin = 3;
	V.bAutoPick = false;
	V.bDoubleReset = true;
	V.bTimer = true;
	V.bDebug = false;
	return V;
}

// Flips the Index-th switch, on the settings object and in the expected values alike (Index 0 to 9).
void LPHTests_ValuesFlip(ULPH_Settings S, FLPH_Values& V, int Index)
{
	if (Index == 0) { S.Tape.bValue = !S.Tape.bValue; V.bTape = !V.bTape; }
	else if (Index == 1) { S.Gothic.bValue = !S.Gothic.bValue; V.bGothic = !V.bGothic; }
	else if (Index == 2) { S.Counter.bValue = !S.Counter.bValue; V.bCounter = !V.bCounter; }
	else if (Index == 3) { S.Shake.bValue = !S.Shake.bValue; V.bShake = !V.bShake; }
	else if (Index == 4) { S.Slide.bValue = !S.Slide.bValue; V.bSlide = !V.bSlide; }
	else if (Index == 5) { S.Plate.bValue = !S.Plate.bValue; V.bPlate = !V.bPlate; }
	else if (Index == 6) { S.AutoPick.bValue = !S.AutoPick.bValue; V.bAutoPick = !V.bAutoPick; }
	else if (Index == 7) { S.DoubleReset.bValue = !S.DoubleReset.bValue; V.bDoubleReset = !V.bDoubleReset; }
	else if (Index == 8) { S.Timer.bValue = !S.Timer.bValue; V.bTimer = !V.bTimer; }
	else if (Index == 9) { S.Debug = !S.Debug; V.bDebug = !V.bDebug; }
}

// Writes all 21 fields of V into the rows of a settings object (and Debug). A test-made object starts as a copy of the class
// default object, i.e. of what the player has set (see the checks on the clean profile), so every case that needs known values
// writes them first and does not rely on the object's own.
void LPHTests_ValuesApply(ULPH_Settings S, FLPH_Values V)
{
	S.Language.Value = V.Language;
	S.Tape.bValue = V.bTape;
	S.Gothic.bValue = V.bGothic;
	S.Icons.Value = V.Icons;
	S.Gamepad.Value = V.Gamepad;
	S.Scale.Value = V.Scale;
	S.OffsetX.Value = V.OffsetX;
	S.OffsetY.Value = V.OffsetY;
	S.Counter.bValue = V.bCounter;
	S.Shake.bValue = V.bShake;
	S.TapeNext.Value = V.TapeNext;
	S.TapeDone.Value = V.TapeDone;
	S.Slide.bValue = V.bSlide;
	S.Plate.bValue = V.bPlate;
	S.PerLine.Value = V.PerLine;
	S.MaxLines.Value = V.MaxLines;
	S.CollapseMin.Value = V.CollapseMin;
	S.AutoPick.bValue = V.bAutoPick;
	S.DoubleReset.bValue = V.bDoubleReset;
	S.Timer.bValue = V.bTimer;
	S.Debug = V.bDebug;
}

// Bit Pass of Code as a bool: with Code 0 to 9 and Pass 0 to 3 every Code has its own four bits, so in one of the four
// passes any two switches differ and a swap of them shows.
bool LPHTests_Bit(int Code, int Pass)
{
	return ((Code >> Pass) & 1) == 1;
}

// In-range values, the numbers all different from each other and from their defaults, the ten switches set by their codes
// (Tape 0, Gothic 1, Counter 2, Shake 3, Slide 4, Plate 5, AutoPick 6, DoubleReset 7, Timer 8, Debug 9). Pass 0 chooses
// Russian for the labels, the other passes English.
FLPH_Values LPHTests_ValuesDistinct(int Pass)
{
	FLPH_Values V = LPHTests_ValuesBrief();
	V.Language = Pass == 0 ? 2 : 1;
	V.Icons = Pass == 0 ? 1 : 2;
	V.Gamepad = 3;
	V.TapeDone = 4;
	V.CollapseMin = 5;
	V.TapeNext = 7;
	V.MaxLines = 9;
	V.PerLine = 21;
	V.Scale = 150;
	V.OffsetX = -123;
	V.OffsetY = 456;
	V.bTape = LPHTests_Bit(0, Pass);
	V.bGothic = LPHTests_Bit(1, Pass);
	V.bCounter = LPHTests_Bit(2, Pass);
	V.bShake = LPHTests_Bit(3, Pass);
	V.bSlide = LPHTests_Bit(4, Pass);
	V.bPlate = LPHTests_Bit(5, Pass);
	V.bAutoPick = LPHTests_Bit(6, Pass);
	V.bDoubleReset = LPHTests_Bit(7, Pass);
	V.bTimer = LPHTests_Bit(8, Pass);
	V.bDebug = LPHTests_Bit(9, Pass);
	return V;
}

// The defaults with field Field (0..20, in the order of FLPH_Values) changed; any other Field: the defaults.
FLPH_Values LPHTests_ValuesOneOff(int Field)
{
	FLPH_Values V;
	if (Field == 0) V.Language = 2;
	if (Field == 1) V.bTape = !V.bTape;
	if (Field == 2) V.bGothic = !V.bGothic;
	if (Field == 3) V.Icons = 2;
	if (Field == 4) V.Gamepad = 3;
	if (Field == 5) V.Scale = 150;
	if (Field == 6) V.OffsetX = -123;
	if (Field == 7) V.OffsetY = 456;
	if (Field == 8) V.bCounter = !V.bCounter;
	if (Field == 9) V.bShake = !V.bShake;
	if (Field == 10) V.TapeNext = 7;
	if (Field == 11) V.TapeDone = 4;
	if (Field == 12) V.bSlide = !V.bSlide;
	if (Field == 13) V.bPlate = !V.bPlate;
	if (Field == 14) V.PerLine = 21;
	if (Field == 15) V.MaxLines = 9;
	if (Field == 16) V.CollapseMin = 5;
	if (Field == 17) V.bAutoPick = !V.bAutoPick;
	if (Field == 18) V.bDoubleReset = !V.bDoubleReset;
	if (Field == 19) V.bTimer = !V.bTimer;
	if (Field == 20) V.bDebug = !V.bDebug;
	return V;
}

void LPHTests_ValuesSame(ULPH_TestRun T)
{
	T.Begin("Values: SameValues sees every field");
	FLPH_Values Defaults;
	T.True(LPH::SameValues(Defaults, FLPH_Values()), "the defaults twice");
	T.True(LPH::SameValues(LPHTests_ValuesDistinct(1), LPHTests_ValuesDistinct(1)), "other values twice");
	int Fields = 0;
	for (int Field = 0; Field < 40; Field++)
	{
		FLPH_Values V = LPHTests_ValuesOneOff(Field);
		FString What = LPHTests_ValuesDiff(Defaults, V);
		if (What.IsEmpty())
			continue;
		Fields++;
		T.True(!LPH::SameValues(Defaults, V), "another" + What);
		T.True(!LPH::SameValues(V, Defaults), "another" + What + " (the other way round)");
	}
	T.EqualInt(Fields, 21, "(every field of LPHTests_ValuesDiff changed once)");
}

void LPHTests_ValuesDefaults(ULPH_TestRun T)
{
	T.Begin("Values: the defaults");
	FLPH_Values Brief = LPHTests_ValuesBrief();
	T.EqualStr(LPHTests_ValuesDiff(FLPH_Values(), Brief), "", "FLPH_Values() against settings.lua of 1.2.0");

	// The only link between the literals in the row declarations (Settings.as) and FLPH_Values is the rows' own state, and
	// that state is what the player has set in the options (a test-made object copies it). So these two checks mean something
	// only on a clean profile: GameUserSettings.ini without a [/Script/Angelscript.LPH_Settings] section.
	if (!FCommandLine::Get().Contains("-LPHTests=defaults"))
	{
		if (T.Output != nullptr)
			T.Output.Line("defaults check skipped (needs -LPHTests=defaults on a clean profile)");
		return;
	}
	T.EqualStr(LPHTests_ValuesDiff(LPH::ReadValues(), Brief), "", "ReadValues() on a clean profile");
	ULPH_Settings Fresh = Cast<ULPH_Settings>(NewObject(T, ULPH_Settings::StaticClass()));
	if (Fresh == nullptr)
	{
		T.True(false, "a ULPH_Settings object can be created");
		return;
	}
	T.EqualStr(LPHTests_ValuesDiff(LPH::ValuesOf(Fresh), Brief), "", "a fresh settings object on a clean profile");
}

void LPHTests_ValuesMapping(ULPH_TestRun T)
{
	T.Begin("Values: every row goes to its own field");
	// Settings objects of the test's own, each given the defaults table before the case (not the player's values).
	ULPH_Settings S = Cast<ULPH_Settings>(NewObject(T, ULPH_Settings::StaticClass()));
	if (S == nullptr)
	{
		T.True(false, "a ULPH_Settings object can be created");
		return;
	}
	LPHTests_ValuesApply(S, LPHTests_ValuesBrief());
	T.EqualStr(LPHTests_ValuesDiff(LPH::ValuesOf(S), LPHTests_ValuesBrief()), "", "the defaults table written into an object reads back");

	// Every switch on its own: only its field changes.
	for (int i = 0; i < 10; i++)
	{
		ULPH_Settings One = Cast<ULPH_Settings>(NewObject(T, ULPH_Settings::StaticClass()));
		FLPH_Values Expected = LPHTests_ValuesBrief();
		LPHTests_ValuesApply(One, Expected);
		LPHTests_ValuesFlip(One, Expected, i);
		T.EqualStr(LPHTests_ValuesDiff(LPH::ValuesOf(One), Expected), "", f"switch {i} flipped alone");
	}

	// All the numbers at once, every one different from the others and from its default.
	FLPH_Values V = LPHTests_ValuesBrief();
	S.Language.Value = 1;
	V.Language = 1;
	S.Icons.Value = 2;
	V.Icons = 2;
	S.Gamepad.Value = 3;
	V.Gamepad = 3;
	S.TapeDone.Value = 4;
	V.TapeDone = 4;
	S.CollapseMin.Value = 5;
	V.CollapseMin = 5;
	S.TapeNext.Value = 7;
	V.TapeNext = 7;
	S.MaxLines.Value = 9;
	V.MaxLines = 9;
	S.PerLine.Value = 21;
	V.PerLine = 21;
	S.Scale.Value = 150;
	V.Scale = 150;
	S.OffsetX.Value = -123;
	V.OffsetX = -123;
	S.OffsetY.Value = 456;
	V.OffsetY = 456;
	T.EqualStr(LPHTests_ValuesDiff(LPH::ValuesOf(S), V), "", "all the numbers at once");
}

void LPHTests_ValuesClamp(ULPH_TestRun T)
{
	T.Begin("Values: Clamped");
	// Below the limits.
	FLPH_Values Low;
	Low.Language = -5;
	Low.Icons = -1;
	Low.Gamepad = -1;
	Low.Scale = -1;
	Low.OffsetX = -99999;
	Low.OffsetY = -99999;
	Low.TapeNext = -3;
	Low.TapeDone = -1;
	Low.PerLine = 0;
	Low.MaxLines = 0;
	Low.CollapseMin = -2;
	FLPH_Values LowWant;
	LowWant.Language = 0;
	LowWant.Icons = 0;
	LowWant.Gamepad = 0;
	LowWant.Scale = 50;
	LowWant.OffsetX = -3000;
	LowWant.OffsetY = -2000;
	LowWant.TapeNext = 1;
	LowWant.TapeDone = 0;
	LowWant.PerLine = 4;
	LowWant.MaxLines = 1;
	LowWant.CollapseMin = 0;
	T.EqualStr(LPHTests_ValuesDiff(LPH::Clamped(Low), LowWant), "", "below the limits");
	// The limits themselves stay.
	T.EqualStr(LPHTests_ValuesDiff(LPH::Clamped(LowWant), LowWant), "", "the lower limits stay");

	// Above the limits.
	FLPH_Values High;
	High.Language = 99;
	High.Icons = 99;
	High.Gamepad = 99;
	High.Scale = 9999;
	High.OffsetX = 99999;
	High.OffsetY = 99999;
	High.TapeNext = 99;
	High.TapeDone = 99;
	High.PerLine = 999;
	High.MaxLines = 99;
	High.CollapseMin = 99;
	FLPH_Values HighWant;
	HighWant.Language = 2;
	HighWant.Icons = 2;
	HighWant.Gamepad = 3;
	HighWant.Scale = 200;
	HighWant.OffsetX = 3000;
	HighWant.OffsetY = 2000;
	HighWant.TapeNext = 10;
	HighWant.TapeDone = 6;
	HighWant.PerLine = 40;
	HighWant.MaxLines = 12;
	HighWant.CollapseMin = 20;
	T.EqualStr(LPHTests_ValuesDiff(LPH::Clamped(High), HighWant), "", "above the limits");
	T.EqualStr(LPHTests_ValuesDiff(LPH::Clamped(HighWant), HighWant), "", "the upper limits stay");

	// The switches are not touched, and values inside the limits stay as they are.
	FLPH_Values Mixed = LPHTests_ValuesBrief();
	Mixed.bTape = false;
	Mixed.bGothic = true;
	Mixed.bAutoPick = true;
	Mixed.bDebug = true;
	Mixed.Scale = 75;
	Mixed.OffsetX = -1500;
	T.EqualStr(LPHTests_ValuesDiff(LPH::Clamped(Mixed), Mixed), "", "switches and values inside the limits stay");
}

// Initialize relabels every row by assigning it a new struct: it must give each row back its own value. A slip in one of
// the twenty hand-written blocks (a row that reads another row's value) would swap the player's settings every time the
// menu is built. Four objects, each with the switches set by LPHTests_Bit, so that any swap of two switches shows in one
// of them; the labels of both languages are built (pass 0 asks for Russian).
void LPHTests_SettingsInitialize(ULPH_TestRun T)
{
	T.Begin("Settings: Initialize keeps the values of the rows");
	for (int Pass = 0; Pass < 4; Pass++)
	{
		ULPH_Settings S = Cast<ULPH_Settings>(NewObject(T, ULPH_Settings::StaticClass()));
		if (S == nullptr)
		{
			T.True(false, "a ULPH_Settings object can be created");
			return;
		}
		FLPH_Values V = LPHTests_ValuesDistinct(Pass);
		LPHTests_ValuesApply(S, V);
		T.EqualStr(LPHTests_ValuesDiff(LPH::ValuesOf(S), V), "", f"pass {Pass}: the values are in the rows before Initialize");
		S.Initialize();
		T.EqualStr(LPHTests_ValuesDiff(LPH::ValuesOf(S), V), "", f"pass {Pass}: after Initialize");
		S.Initialize();
		T.EqualStr(LPHTests_ValuesDiff(LPH::ValuesOf(S), V), "", f"pass {Pass}: after a second Initialize");
	}
}

void LPHTests_Texts(ULPH_TestRun T)
{
	LPHTests_TextsLangFor(T);
	LPHTests_TextsFill(T);
	LPHTests_TextsStrings(T);
	LPHTests_TextsLabels(T);
	LPHTests_ValuesDefaults(T);
	LPHTests_ValuesMapping(T);
	LPHTests_ValuesClamp(T);
	LPHTests_ValuesSame(T);
	LPHTests_SettingsInitialize(T);
}
