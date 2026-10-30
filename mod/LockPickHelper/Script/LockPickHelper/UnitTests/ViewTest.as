// View.as: the 14 cases of tests/view_test.lua of 1.2.0 (cases 01 to 14, in the order of that file; the tracker's Index is
// 0-based here, so a Lua index of 3 is Index 2 and the counter is Min(Index, total)), then the edge cases 2.0 adds
// (15 and on): the extreme tape and line settings of Review Focus 4, a view without a plan, labels that are missing.
// Case 12 of the Lua file renders M.SAMPLE of view.lua; 2.0 has no sample in View.as (the settings preview builds its
// own), so the same view is built by hand here.

// "D+ A- W+" -> the history { D ok, A miss, W ok }
bool LPHTests_ViewKeyOf(FString Letter, ELPH_Key& Key)
{
	if (Letter == "W")
		Key = ELPH_Key::W;
	else if (Letter == "S")
		Key = ELPH_Key::S;
	else if (Letter == "A")
		Key = ELPH_Key::A;
	else if (Letter == "D")
		Key = ELPH_Key::D;
	else
		return false;
	return true;
}

TArray<FLPH_Press> LPHTests_ViewHistory(FString Spec)
{
	TArray<FLPH_Press> History;
	for (int i = 0; i < Spec.Len(); i++)
	{
		ELPH_Key Key = ELPH_Key::W;
		if (!LPHTests_ViewKeyOf(Spec.Mid(i, 1), Key))
			continue;
		FLPH_Press Press;
		Press.Key = Key;
		Press.bOk = Spec.Mid(i + 1, 1) == "+";
		History.Add(Press);
	}
	return History;
}

TArray<ELPH_Key> LPHTests_ViewKeys(FString Letters)
{
	TArray<ELPH_Key> Keys;
	for (int i = 0; i < Letters.Len(); i++)
	{
		ELPH_Key Key = ELPH_Key::W;
		if (LPHTests_ViewKeyOf(Letters.Mid(i, 1), Key))
			Keys.Add(Key);
	}
	return Keys;
}

// A tracker view made by hand: the keys as letters, the current Index (0-based), the history spec.
FLPH_TrackerView LPHTests_ViewOf(FString Keys, int Index, FString History)
{
	FLPH_TrackerView View;
	View.Status = ELPH_Status::Ok;
	View.Keys = LPHTests_ViewKeys(Keys);
	View.Index = Index;
	View.History = LPHTests_ViewHistory(History);
	return View;
}

// Alternating A and D (no key ever repeats, so nothing folds): Count letters.
FString LPHTests_ViewAlt(int Count)
{
	FString Letters;
	for (int i = 0; i < Count; i++)
	{
		if (i % 2 == 0)
			Letters += "A";
		else
			Letters += "D";
	}
	return Letters;
}

// A long view: HistoryCount pressed (all ok) alternating keys, then a plan of PlanCount alternating keys from Index.
FLPH_TrackerView LPHTests_ViewLong(int HistoryCount, int PlanCount, int Index)
{
	FLPH_TrackerView View;
	View.Status = ELPH_Status::Ok;
	View.Keys = LPHTests_ViewKeys(LPHTests_ViewAlt(PlanCount));
	View.Index = Index;
	FString Letters = LPHTests_ViewAlt(HistoryCount);
	for (int i = 0; i < HistoryCount; i++)
	{
		ELPH_Key Key = ELPH_Key::A;
		LPHTests_ViewKeyOf(Letters.Mid(i, 1), Key);
		FLPH_Press Press;
		Press.Key = Key;
		Press.bOk = true;
		View.History.Add(Press);
	}
	return View;
}

FString LPHTests_ViewRole(ELPH_Role Role)
{
	if (Role == ELPH_Role::Done)
		return "done";
	if (Role == ELPH_Role::Miss)
		return "miss";
	if (Role == ELPH_Role::Current)
		return "current";
	if (Role == ELPH_Role::Next)
		return "next";
	if (Role == ELPH_Role::Todo)
		return "todo";
	if (Role == ELPH_Role::Empty)
		return "empty";
	return "?";
}

// "A:miss W:done _:empty": the text ("_" when empty) and role of every cell.
FString LPHTests_ViewCells(const FLPH_HintModel& M)
{
	FString Out;
	for (int i = 0; i < M.Cells.Num(); i++)
	{
		if (i > 0)
			Out += " ";
		FString Text = M.Cells[i].Text;
		if (Text.Len() == 0)
			Text = "_";
		Out += Text + ":" + LPHTests_ViewRole(M.Cells[i].Role);
	}
	return Out;
}

// "D+ A- W+ S+ A* D D / ...": a + after a pressed key, - after a miss, * after the current one; lines divided by " / ".
FString LPHTests_ViewMark(ELPH_Role Role)
{
	if (Role == ELPH_Role::Done)
		return "+";
	if (Role == ELPH_Role::Miss)
		return "-";
	if (Role == ELPH_Role::Current)
		return "*";
	if (Role == ELPH_Role::Todo)
		return "";
	return "?";
}

FString LPHTests_ViewLines(const FLPH_HintModel& M)
{
	FString Out;
	for (int Row = 0; Row < M.Lines.Num(); Row++)
	{
		if (Row > 0)
			Out += " / ";
		for (int At = 0; At < M.Lines[Row].Tokens.Num(); At++)
		{
			if (At > 0)
				Out += " ";
			Out += M.Lines[Row].Tokens[At].Text + LPHTests_ViewMark(M.Lines[Row].Tokens[At].Role);
		}
	}
	return Out;
}

// A cell's alpha in thousandths (rounded), -1 when there is no such cell.
int LPHTests_ViewAlpha(const FLPH_HintModel& M, int Cell)
{
	if (Cell < 0 || Cell >= M.Cells.Num())
		return -1;
	return Math::FloorToInt(M.Cells[Cell].Alpha * 1000.0 + 0.5);
}

// Safe readers (a model with fewer cells or tokens than expected must fail the check, not stop the run).
FString LPHTests_ViewCellText(const FLPH_HintModel& M, int Cell)
{
	if (Cell < 0 || Cell >= M.Cells.Num())
		return "<no cell>";
	return M.Cells[Cell].Text;
}

FString LPHTests_ViewCellRole(const FLPH_HintModel& M, int Cell)
{
	if (Cell < 0 || Cell >= M.Cells.Num())
		return "<no cell>";
	return LPHTests_ViewRole(M.Cells[Cell].Role);
}

bool LPHTests_ViewCellHasKey(const FLPH_HintModel& M, int Cell)
{
	if (Cell < 0 || Cell >= M.Cells.Num())
		return true; // (a missing cell is not an empty one: the check that wants "no key" must fail)
	return M.Cells[Cell].bHasKey;
}

FString LPHTests_ViewTokenText(const FLPH_HintModel& M, int Row, int At)
{
	if (Row < 0 || Row >= M.Lines.Num() || At < 0 || At >= M.Lines[Row].Tokens.Num())
		return "<no token>";
	return M.Lines[Row].Tokens[At].Text;
}

// The row of the window the current token is in (-1: none), and how many tokens the model has in all and in the longest row.
int LPHTests_ViewCurrentRow(const FLPH_HintModel& M)
{
	int Found = -1;
	for (int Row = 0; Row < M.Lines.Num(); Row++)
	{
		for (int At = 0; At < M.Lines[Row].Tokens.Num(); At++)
		{
			if (M.Lines[Row].Tokens[At].Role == ELPH_Role::Current)
			{
				if (Found >= 0)
					return -2; // two current tokens
				Found = Row;
			}
		}
	}
	return Found;
}

int LPHTests_ViewTokenCount(const FLPH_HintModel& M)
{
	int Total = 0;
	for (int Row = 0; Row < M.Lines.Num(); Row++)
		Total += M.Lines[Row].Tokens.Num();
	return Total;
}

int LPHTests_ViewLongestRow(const FLPH_HintModel& M)
{
	int Longest = 0;
	for (int Row = 0; Row < M.Lines.Num(); Row++)
		Longest = Math::Max(Longest, M.Lines[Row].Tokens.Num());
	return Longest;
}

// The model of a hand-made view with the settings of the Lua file (TAPE: 5 next, 3 done; RUNS: 16 x 6, fold from 3;
// FLAT: 16 x 6, no folding) and no labels.
FLPH_HintModel LPHTests_ViewTape(const FLPH_TrackerView& V, int Next, int Done)
{
	TArray<FString> NoLabels;
	return LPH::Tape(V, Next, Done, NoLabels);
}

FLPH_HintModel LPHTests_ViewLinesOf(const FLPH_TrackerView& V, int PerLine, int MaxLines, int CollapseMin)
{
	TArray<FString> NoLabels;
	return LPH::Lines(V, PerLine, MaxLines, CollapseMin, NoLabels);
}

FLPH_HintModel LPHTests_ViewRuns(const FLPH_TrackerView& V)
{
	return LPHTests_ViewLinesOf(V, 16, 6, 3);
}

FLPH_HintModel LPHTests_ViewFlat(const FLPH_TrackerView& V)
{
	return LPHTests_ViewLinesOf(V, 16, 6, 0);
}

FString LPHTests_ViewRunsText(FString Keys, int Index, FString History)
{
	return LPHTests_ViewLines(LPHTests_ViewRuns(LPHTests_ViewOf(Keys, Index, History)));
}

void LPHTests_View(ULPH_TestRun T)
{
	LPHTests_ViewCases01(T);
	LPHTests_ViewCases07(T);
	LPHTests_ViewCases12(T);
	LPHTests_ViewTapeEdges(T);
	LPHTests_ViewLineEdges(T);
	LPHTests_ViewOddInput(T);
}

void LPHTests_ViewCases01(ULPH_TestRun T)
{
	// 01
	T.Begin("View 01 tape: last presses, the current key, the next keys");
	FLPH_HintModel M = LPHTests_ViewTape(LPHTests_ViewOf("WSADDAWSA", 2, "D+ A- W+ S+"), 5, 3);
	T.True(!M.bLines, "the tape is not the lines");
	T.EqualStr(LPHTests_ViewCells(M), "A:miss W:done S:done A:current D:next D:next A:next W:next S:next", "cells");
	T.EqualInt(LPHTests_ViewAlpha(M, 0), 280, "furthest done");
	T.EqualInt(LPHTests_ViewAlpha(M, 2), 750, "nearest done");
	T.EqualInt(LPHTests_ViewAlpha(M, 3), 1000, "current");
	T.EqualInt(LPHTests_ViewAlpha(M, 4), 850, "first next");
	T.EqualInt(LPHTests_ViewAlpha(M, 6), 500, "middle next");
	T.EqualInt(LPHTests_ViewAlpha(M, 8), 150, "last next");
	T.EqualStr(M.Counter, "2/9", "counter");
	T.True(!M.bCounterAlways, "the counter is not forced");

	// 02
	T.Begin("View 02 tape: missing history and plan leave empty cells; the current key keeps its place");
	M = LPHTests_ViewTape(LPHTests_ViewOf("WS", 0, ""), 5, 3);
	T.EqualStr(LPHTests_ViewCells(M), "_:empty _:empty _:empty W:current S:next _:empty _:empty _:empty _:empty", "cells");

	// 03
	T.Begin("View 03 tape: one next and one done key use the first alphas; done = 0 starts at the current key");
	M = LPHTests_ViewTape(LPHTests_ViewOf("WSA", 1, "W+"), 1, 1);
	T.EqualStr(LPHTests_ViewCells(M), "W:done S:current A:next", "cells");
	T.EqualInt(LPHTests_ViewAlpha(M, 0), 750, "done alpha");
	T.EqualInt(LPHTests_ViewAlpha(M, 2), 850, "next alpha");
	M = LPHTests_ViewTape(LPHTests_ViewOf("WSA", 0, ""), 2, 0);
	T.EqualStr(LPHTests_ViewCells(M), "W:current S:next A:next", "no done cells");

	// 04
	T.Begin("View 04 tape: after the last key the current cell is empty");
	M = LPHTests_ViewTape(LPHTests_ViewOf("WS", 2, "W+ S+"), 2, 2);
	T.EqualStr(LPHTests_ViewCells(M), "W:done S:done _:empty _:empty _:empty", "cells");
	T.EqualStr(M.Counter, "2/2", "counter");

	// 05
	T.Begin("View 05 labels replace key names");
	TArray<FString> Labels;
	Labels.Add("UP");
	Labels.Add("DOWN");
	M = LPH::Tape(LPHTests_ViewOf("WS", 0, ""), 1, 0, Labels);
	T.EqualStr(LPHTests_ViewCells(M), "UP:current DOWN:next", "cells");
	M = LPH::Lines(LPHTests_ViewOf("WS", 0, ""), 4, 1, 0, Labels);
	T.EqualStr(LPHTests_ViewLines(M), "UP* DOWN", "lines");

	// 06
	T.Begin("View 06 press and miss counts pass through");
	FLPH_TrackerView V = LPHTests_ViewOf("W", 0, "");
	V.Pressed = 7;
	V.Misses = 2;
	M = LPHTests_ViewTape(V, 5, 3);
	T.EqualInt(M.Pressed, 7, "tape pressed");
	T.EqualInt(M.Misses, 2, "tape misses");
	M = LPHTests_ViewFlat(V);
	T.EqualInt(M.Pressed, 7, "lines pressed");
	T.EqualInt(M.Misses, 2, "lines misses");
}

void LPHTests_ViewCases07(ULPH_TestRun T)
{
	// 07
	T.Begin("View 07 lines: history then the rest of the plan");
	FLPH_HintModel M = LPHTests_ViewFlat(LPHTests_ViewOf("WSADD", 2, "D+ A- W+ S+"));
	T.True(M.bLines, "the lines are the lines");
	T.EqualStr(LPHTests_ViewLines(M), "D+ A- W+ S+ A* D D", "tokens");
	T.EqualStr(M.Counter, "2/5", "counter");

	// 08
	T.Begin("View 08 lines: the window follows the current line");
	FString Twenty = "WWWWWWWWWWWWWWWWWWWW";
	M = LPHTests_ViewLinesOf(LPHTests_ViewOf(Twenty, 13, "W+ W+ W+ W+ W+ W+ W+ W+ W+ W+ W+ W+ W+"), 4, 2, 0);
	T.EqualStr(LPHTests_ViewLines(M), "W+ W+ W+ W+ / W+ W* W W", "lines 3 and 4 of 5");
	M = LPHTests_ViewLinesOf(LPHTests_ViewOf(Twenty, 1, "W+"), 4, 2, 0);
	T.EqualStr(LPHTests_ViewLines(M), "W+ W* W W / W W W W", "lines 1 and 2");

	// 09
	T.Begin("View 09 lines: a run counts down while it is pressed");
	T.EqualStr(LPHTests_ViewRunsText("DAAAAAW", 0, ""), "D* A×5 W", "start");
	T.EqualStr(LPHTests_ViewRunsText("DAAAAAW", 1, "D+"), "D+ A×5* W", "after D");
	T.EqualStr(LPHTests_ViewRunsText("DAAAAAW", 2, "D+ A+"), "D+ A×4* W", "after one A");
	T.EqualStr(LPHTests_ViewRunsText("DAAAAAW", 5, "D+ A+ A+ A+ A+"), "D+ A×1* W", "one left");
	T.EqualStr(LPHTests_ViewRunsText("DAAAAAW", 6, "D+ A+ A+ A+ A+ A+"), "D+ A×5+ W*", "run done");

	// 10
	T.Begin("View 10 lines: runs shorter than CollapseMin stay single keys; 0 and 1 turn runs off");
	T.EqualStr(LPHTests_ViewRunsText("DAAW", 0, ""), "D* A A W", "two A");
	M = LPHTests_ViewLinesOf(LPHTests_ViewOf("DAAAW", 0, ""), 16, 6, 1);
	T.EqualStr(LPHTests_ViewLines(M), "D* A A A W", "CollapseMin 1");
	M = LPHTests_ViewFlat(LPHTests_ViewOf("DAAAW", 0, ""));
	T.EqualStr(LPHTests_ViewLines(M), "D* A A A W", "CollapseMin 0");

	// 11
	T.Begin("View 11 lines: a miss splits a run");
	T.EqualStr(LPHTests_ViewRunsText("AAAW", 0, "A+ A+ D-"), "A+ A+ D- A×3* W", "short pressed part");
	T.EqualStr(LPHTests_ViewRunsText("AAW", 0, "A+ A+ A+ D-"), "A×3+ D- A* A W", "long pressed part");
}

void LPHTests_ViewCases12(ULPH_TestRun T)
{
	// 12 (view.lua's M.SAMPLE: a miss, a run in progress, a long plan)
	T.Begin("View 12 the example renders in both layouts");
	FLPH_TrackerView Sample = LPHTests_ViewOf("DAAAAWDDSADDDWASDAAW", 2, "S+ W- D+ A+");
	Sample.Pressed = 4;
	Sample.Misses = 1;
	FLPH_HintModel M = LPHTests_ViewTape(Sample, 5, 3);
	T.EqualStr(LPHTests_ViewCellText(M, 3), "A", "current");
	T.EqualInt(M.Misses, 1, "misses");
	FLPH_HintModel L = LPHTests_ViewRuns(Sample);
	T.True(LPHTests_ViewLines(L).Contains("A×3*"), "run in progress");
	T.EqualStr(L.Counter, "2/20", "counter");

	// 13
	T.Begin("View 13 tape cells carry the model key; empty cells have none");
	TArray<FString> Labels;
	Labels.Add("UP");
	Labels.Add("DN");
	Labels.Add("LT");
	Labels.Add("RT");
	M = LPH::Tape(LPHTests_ViewOf("WSADDAWSA", 2, "D+ A- W+ S+"), 5, 3, Labels);
	FString Letters;
	for (int i = 0; i < M.Cells.Num(); i++)
	{
		if (i > 0)
			Letters += " ";
		if (M.Cells[i].bHasKey)
			Letters += LPH::KeyLetter(M.Cells[i].Key);
		else
			Letters += "_";
	}
	T.EqualStr(Letters, "A W S A D D A W S", "keys");
	T.EqualStr(LPHTests_ViewCellText(M, 3), "LT", "the text is still the label");
	FLPH_HintModel E = LPHTests_ViewTape(LPHTests_ViewOf("WS", 0, ""), 5, 3);
	T.True(!LPHTests_ViewCellHasKey(E, 0), "empty done cell");
	T.True(!LPHTests_ViewCellHasKey(E, 5), "empty next cell");

	// 14
	T.Begin("View 14 lines tokens carry the key and, for a run, its count");
	T.EqualStr(LPHTests_ViewTokenCounts(LPHTests_ViewRuns(LPHTests_ViewOf("DAAAAAW", 1, "D+"))), "D:0 A:5 W:0", "a run in the plan");
	T.EqualStr(LPHTests_ViewTokenCounts(LPHTests_ViewRuns(LPHTests_ViewOf("DAAAAAW", 3, "D+ A+ A+"))), "D:0 A:3 W:0", "the current run counts down");
	T.EqualStr(LPHTests_ViewTokenCounts(LPHTests_ViewFlat(LPHTests_ViewOf("DAAAAAW", 1, "D+"))), "D:0 A:0 A:0 A:0 A:0 A:0 W:0", "no folding");
	T.EqualStr(LPHTests_ViewTokenCounts(LPHTests_ViewRuns(LPHTests_ViewOf("WWWWD", 4, "W+ W+ W+ W+"))), "W:4 D:0", "a pressed run");
}

// "D:0 A:5 W:0": the key and Count of every token of the first line (Count 0: a single key).
FString LPHTests_ViewTokenCounts(const FLPH_HintModel& M)
{
	FString Out;
	if (M.Lines.Num() == 0)
		return Out;
	for (int At = 0; At < M.Lines[0].Tokens.Num(); At++)
	{
		if (At > 0)
			Out += " ";
		FString Letter = LPH::KeyLetter(M.Lines[0].Tokens[At].Key);
		int Count = M.Lines[0].Tokens[At].Count;
		Out += f"{Letter}:{Count}";
	}
	return Out;
}

void LPHTests_ViewTapeEdges(ULPH_TestRun T)
{
	// 15
	T.Begin("View 15 tape: ten next keys and six done keys (the settings' extremes)");
	FLPH_HintModel M = LPHTests_ViewTape(LPHTests_ViewOf(LPHTests_ViewAlt(20), 8, "A+ D+ A+ D+ A+ D+ A+ D+"), 10, 6);
	T.EqualInt(M.Cells.Num(), 17, "6 + 1 + 10 cells");
	T.EqualStr(LPHTests_ViewCellRole(M, 6), "current", "the current key is the 7th cell");
	T.EqualStr(LPHTests_ViewCellText(M, 6), "A", "current key");
	bool bDone = true;
	for (int i = 0; i < 6; i++)
		bDone = bDone && LPHTests_ViewCellRole(M, i) == "done";
	T.True(bDone, "six done cells");
	bool bNext = true;
	for (int i = 7; i < 17; i++)
		bNext = bNext && LPHTests_ViewCellRole(M, i) == "next";
	T.True(bNext, "ten next cells");
	T.EqualInt(LPHTests_ViewAlpha(M, 0), 280, "furthest done");
	T.EqualInt(LPHTests_ViewAlpha(M, 5), 750, "nearest done");
	T.EqualInt(LPHTests_ViewAlpha(M, 7), 850, "first next");
	T.EqualInt(LPHTests_ViewAlpha(M, 16), 150, "last next");
	bool bFalling = true;
	for (int i = 8; i < 17; i++)
		bFalling = bFalling && LPHTests_ViewAlpha(M, i) < LPHTests_ViewAlpha(M, i - 1);
	T.True(bFalling, "the next alphas fall");
	bool bRising = true;
	for (int i = 1; i < 6; i++)
		bRising = bRising && LPHTests_ViewAlpha(M, i) > LPHTests_ViewAlpha(M, i - 1);
	T.True(bRising, "the done alphas rise toward the current key");
	T.EqualStr(M.Counter, "8/20", "counter");

	// 16
	T.Begin("View 16 tape: ten next and six done keys with little history and plan: no extra cells");
	M = LPHTests_ViewTape(LPHTests_ViewOf("AD", 0, ""), 10, 6);
	T.EqualInt(M.Cells.Num(), 17, "still 17 cells");
	T.EqualStr(LPHTests_ViewCells(M), "_:empty _:empty _:empty _:empty _:empty _:empty A:current D:next _:empty _:empty _:empty _:empty _:empty _:empty _:empty _:empty _:empty", "cells");
	M = LPHTests_ViewTape(LPHTests_ViewOf("AD", 2, "A+ D+"), 10, 6);
	T.EqualInt(M.Cells.Num(), 17, "17 cells after the last key");
	T.EqualStr(LPHTests_ViewCells(M), "_:empty _:empty _:empty _:empty A:done D:done _:empty _:empty _:empty _:empty _:empty _:empty _:empty _:empty _:empty _:empty _:empty", "cells after the last key");
	T.EqualStr(M.Counter, "2/2", "counter after the last key");
}

void LPHTests_ViewLineEdges(ULPH_TestRun T)
{
	// 17
	T.Begin("View 17 lines 40 x 12: a plan of 300 keys fits (8 lines) and the current key is the first token");
	FLPH_HintModel M = LPHTests_ViewLinesOf(LPHTests_ViewLong(0, 300, 0), 40, 12, 3);
	T.EqualInt(M.Lines.Num(), 8, "lines");
	T.EqualInt(LPHTests_ViewTokenCount(M), 300, "tokens");
	T.EqualInt(LPHTests_ViewLongestRow(M), 40, "longest row");
	T.EqualInt(LPHTests_ViewCurrentRow(M), 0, "the current token's row");
	T.EqualStr(M.Counter, "0/300", "counter");

	// 18
	T.Begin("View 18 lines 40 x 12: a long history and a 300-key plan are windowed to 12 lines with the current key in view");
	M = LPHTests_ViewLinesOf(LPHTests_ViewLong(200, 300, 0), 40, 12, 3);
	T.EqualInt(M.Lines.Num(), 12, "200 + 300: lines (13 in all)");
	T.EqualInt(LPHTests_ViewCurrentRow(M), 4, "200 + 300: the current token's row (line 6 of 13, the window is lines 2 to 13)");
	T.EqualInt(LPHTests_ViewTokenCount(M), 460, "200 + 300: tokens (11 full lines and the short last one)");
	M = LPHTests_ViewLinesOf(LPHTests_ViewLong(300, 300, 0), 40, 12, 3);
	T.EqualInt(M.Lines.Num(), 12, "300 + 300: lines (15 in all)");
	T.EqualInt(LPHTests_ViewCurrentRow(M), 4, "300 + 300: the current token's row");
	M = LPHTests_ViewLinesOf(LPHTests_ViewLong(500, 300, 0), 40, 12, 3);
	T.EqualInt(M.Lines.Num(), 12, "500 + 300: lines (20 in all)");
	T.EqualInt(LPHTests_ViewCurrentRow(M), 4, "500 + 300: the current token's row");
	// (The three above are pinned to the end of the lines; with a longer plan the window starts one line above the current one.)
	M = LPHTests_ViewLinesOf(LPHTests_ViewLong(100, 600, 0), 40, 12, 3);
	T.EqualInt(M.Lines.Num(), 12, "100 + 600: lines (18 in all)");
	T.EqualInt(LPHTests_ViewCurrentRow(M), 1, "100 + 600: the window starts one line above the current one");
	M = LPHTests_ViewLinesOf(LPHTests_ViewLong(300, 600, 0), 40, 12, 3);
	T.EqualInt(M.Lines.Num(), 12, "300 + 600: lines (23 in all)");
	T.EqualInt(LPHTests_ViewCurrentRow(M), 1, "300 + 600: the window starts one line above the current one");
	M = LPHTests_ViewLinesOf(LPHTests_ViewLong(100, 300, 299), 40, 12, 3);
	T.EqualInt(M.Lines.Num(), 3, "100 + the last key: lines");
	T.EqualInt(LPHTests_ViewCurrentRow(M), 2, "100 + the last key: the current key is in the last line");
	M = LPHTests_ViewLinesOf(LPHTests_ViewLong(0, 300, 150), 40, 12, 3);
	T.EqualInt(M.Lines.Num(), 4, "from the middle: lines");
	T.EqualInt(LPHTests_ViewTokenCount(M), 150, "from the middle: tokens");
	T.EqualInt(LPHTests_ViewCurrentRow(M), 0, "from the middle: the current token's row");
	T.EqualStr(M.Counter, "150/300", "from the middle: counter");

	// 19
	T.Begin("View 19 lines: whatever the position, at most 12 lines and one current token in them");
	bool bOk = true;
	int Checked = 0;
	for (int History = 0; History <= 500; History += 37)
	{
		for (int Index = 0; Index < 300; Index += 41)
		{
			M = LPHTests_ViewLinesOf(LPHTests_ViewLong(History, 300, Index), 40, 12, 3);
			Checked++;
			if (M.Lines.Num() > 12 || LPHTests_ViewCurrentRow(M) < 0 || LPHTests_ViewLongestRow(M) > 40)
			{
				bOk = false;
				T.Output.Line(f"view 19: history {History}, index {Index}: {M.Lines.Num()} lines, current row {LPHTests_ViewCurrentRow(M)}");
			}
		}
	}
	T.True(bOk, "every position fits the window");
	T.True(Checked > 50, "the positions were visited");

	// 20
	T.Begin("View 20 lines: CollapseMin 0 and 1 never fold, 2 and up fold from that length");
	FString Ws;
	for (int i = 0; i < 300; i++)
		Ws += "W";
	FLPH_TrackerView Run = LPHTests_ViewOf(Ws, 0, "");
	M = LPHTests_ViewLinesOf(Run, 40, 12, 0);
	T.EqualInt(LPHTests_ViewTokenCount(M), 300, "CollapseMin 0: 300 tokens");
	T.EqualInt(M.Lines.Num(), 8, "CollapseMin 0: lines");
	M = LPHTests_ViewLinesOf(Run, 40, 12, 1);
	T.EqualInt(LPHTests_ViewTokenCount(M), 300, "CollapseMin 1: 300 tokens");
	bool bSingles = true;
	for (int Row = 0; Row < M.Lines.Num(); Row++)
	{
		for (int At = 0; At < M.Lines[Row].Tokens.Num(); At++)
			bSingles = bSingles && M.Lines[Row].Tokens[At].Count == 0;
	}
	T.True(bSingles, "CollapseMin 1: every token is a single key");
	M = LPHTests_ViewLinesOf(Run, 40, 12, 2);
	T.EqualStr(LPHTests_ViewLines(M), "W×300*", "CollapseMin 2: the whole run");
	M = LPHTests_ViewLinesOf(Run, 40, 12, 300);
	T.EqualStr(LPHTests_ViewLines(M), "W×300*", "CollapseMin 300: a run of exactly 300");
	M = LPHTests_ViewLinesOf(Run, 40, 12, 301);
	T.EqualInt(LPHTests_ViewTokenCount(M), 300, "CollapseMin 301: a run of 300 stays single keys");
	M = LPHTests_ViewLinesOf(LPHTests_ViewOf("DAAW", 0, ""), 16, 6, 2);
	T.EqualStr(LPHTests_ViewLines(M), "D* A×2 W", "CollapseMin 2 folds a pair");
	M = LPHTests_ViewLinesOf(LPHTests_ViewOf(Ws, 150, "W+ W+ W+ W+ W+ W+ W+ W+ W+ W+"), 40, 12, 3);
	T.EqualStr(LPHTests_ViewLines(M), "W×150*", "ten pressed W and 150 more W: one current run of what is left");
}

void LPHTests_ViewOddInput(ULPH_TestRun T)
{
	// 21
	T.Begin("View 21 the multiplication sign is one character");
	FLPH_HintModel M = LPHTests_ViewRuns(LPHTests_ViewOf("DAAAAAW", 1, "D+"));
	FString Text = LPHTests_ViewTokenText(M, 0, 1);
	T.EqualStr(Text, "A×5", "the run text");
	T.EqualInt(Text.Len(), 3, "the run text A, the sign and 5 is 3 characters");

	// 22
	T.Begin("View 22 a view without a plan");
	FLPH_TrackerView NoPlan;
	M = LPHTests_ViewTape(NoPlan, 2, 1);
	T.EqualStr(LPHTests_ViewCells(M), "_:empty _:empty _:empty _:empty", "tape: all cells empty");
	T.EqualStr(M.Counter, "0/0", "tape counter");
	M = LPHTests_ViewRuns(NoPlan);
	T.EqualInt(M.Lines.Num(), 0, "lines: none");
	T.EqualStr(M.Counter, "0/0", "lines counter");
	M = LPHTests_ViewRuns(LPHTests_ViewOf("WS", 2, "W+ S+"));
	T.EqualStr(LPHTests_ViewLines(M), "W+ S+", "the keys are used up: the history stays");
	T.EqualStr(M.Counter, "2/2", "counter when used up");

	// 23
	T.Begin("View 23 lines: a PerLine or MaxLines below 1 acts as 1");
	M = LPHTests_ViewLinesOf(LPHTests_ViewOf("WSA", 1, "W+"), 0, 0, 0);
	T.EqualStr(LPHTests_ViewLines(M), "S*", "one token in one line");

	// 24
	T.Begin("View 24 labels: a missing or empty label shows the letter");
	TArray<FString> Labels;
	Labels.Add("UP");
	Labels.Add("");
	M = LPH::Tape(LPHTests_ViewOf("WSAD", 0, ""), 3, 0, Labels);
	T.EqualStr(LPHTests_ViewCells(M), "UP:current S:next A:next D:next", "tape");
	M = LPH::Lines(LPHTests_ViewOf("WSAD", 0, ""), 16, 6, 0, Labels);
	T.EqualStr(LPHTests_ViewLines(M), "UP* S A D", "lines");
}
