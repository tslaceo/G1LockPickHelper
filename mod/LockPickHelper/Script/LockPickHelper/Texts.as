// The words the mod shows: the notes of the hint and the labels of the rows in the game's options. They live in the
// game's text database (Story/Conversation/text/LockPickHelper.<language>.textdb.yaml, mounted by Config/Game.ini), one
// Text-ID per string: "LPH_<field of FLPH_Texts>" for the notes, "LPH_Row_<field of FLPH_Labels>" for the labels. The game
// picks the language its own interface is in, and another mod can add a language to these IDs with a YAML of its own.
// The English below is the fallback for an ID the database does not answer (it gives an empty string then), and the
// English YAML must say the same (tests/test_texts.py). {0} is filled by the mod (LPH::Fill). The player-facing name of
// the autosolver is "auto-pick" / "автовзлом" / "Auto-Knacken" / "autootwieranie".

struct FLPH_Texts
{
	FString NotInDb; // {0}: the lock's name
	FString NoSafePath;
	FString BadState;
	FString HintOn; // {0}: the key's name
	FString HintOff; // {0}: the key's name
	FString Solving; // instead of the counter while the autosolver presses
	FString SolvingTime; // the same with the timer; {0}: about the seconds left
	FString SolveArmed; // F3 or auto-pick before the minigame is ready
	FString SolveStopped; // the autosolver stopped by itself
	FString SolveUnavailable;
	FString SolveOn; // {0}: the key's name, or DoubleReset
	FString SolveOff; // {0}: the key's name
	FString DoubleReset;
	FString Thinking; // new in 2.0: the solver is still preparing the lock
}

// The labels of the rows of ULPH_Settings, one field per row, named like the row.
struct FLPH_Labels
{
	FString Tape;
	FString Gothic;
	FString Icons;
	FString Gamepad;
	FString Scale;
	FString OffsetX;
	FString OffsetY;
	FString Counter;
	FString Shake;
	FString TapeNext;
	FString TapeDone;
	FString Slide;
	FString Plate;
	FString PerLine;
	FString MaxLines;
	FString CollapseMin;
	FString AutoPick;
	FString DoubleReset;
	FString Timer;
}

namespace LPH
{
	// The template with its {0} replaced by Value.
	FString Fill(FString Template, FString Value)
	{
		return Template.Replace("{0}", Value);
	}

	// The string of Id in the game's language; Fallback when the text database has nothing for it.
	FString Loc(FString Id, FString Fallback)
	{
		FString Text = LocText(Id).ToString();
		if (Text.IsEmpty())
			return Fallback;
		return Text;
	}

	// A row's label: the text of Id, which follows the game's language in the open menu, or Fallback when the text
	// database has nothing for it.
	FText RowText(FString Id, FString Fallback)
	{
		FText Text = LocText(Id);
		if (Text.ToString().IsEmpty())
			return FText::FromString(Fallback);
		return Text;
	}

	FLPH_Texts TextsEn()
	{
		FLPH_Texts X;
		X.NotInDb = "Lock not in the database: {0}";
		X.NoSafePath = "Can't open without risking the pick";
		X.BadState = "Can't read the lock";
		X.HintOn = "Hint shown ({0})";
		X.HintOff = "Hint hidden ({0})";
		X.Solving = "Auto-picking…";
		X.SolvingTime = "Auto-picking… {0} s";
		X.SolveArmed = "Auto-pick: waiting for the lock";
		X.SolveStopped = "Auto-pick stopped";
		X.SolveUnavailable = "Auto-pick unavailable";
		X.SolveOn = "Auto-pick on ({0})";
		X.SolveOff = "Auto-pick off ({0})";
		X.DoubleReset = "double reset";
		X.Thinking = "Thinking…";
		return X;
	}

	// The notes in the language the game's interface is in now.
	FLPH_Texts GameTexts()
	{
		FLPH_Texts En = TextsEn();
		FLPH_Texts X;
		X.NotInDb = Loc("LPH_NotInDb", En.NotInDb);
		X.NoSafePath = Loc("LPH_NoSafePath", En.NoSafePath);
		X.BadState = Loc("LPH_BadState", En.BadState);
		X.HintOn = Loc("LPH_HintOn", En.HintOn);
		X.HintOff = Loc("LPH_HintOff", En.HintOff);
		X.Solving = Loc("LPH_Solving", En.Solving);
		X.SolvingTime = Loc("LPH_SolvingTime", En.SolvingTime);
		X.SolveArmed = Loc("LPH_SolveArmed", En.SolveArmed);
		X.SolveStopped = Loc("LPH_SolveStopped", En.SolveStopped);
		X.SolveUnavailable = Loc("LPH_SolveUnavailable", En.SolveUnavailable);
		X.SolveOn = Loc("LPH_SolveOn", En.SolveOn);
		X.SolveOff = Loc("LPH_SolveOff", En.SolveOff);
		X.DoubleReset = Loc("LPH_DoubleReset", En.DoubleReset);
		X.Thinking = Loc("LPH_Thinking", En.Thinking);
		return X;
	}

	// Whether two sets of notes are the same, field by field (the controller redraws only for new ones).
	bool SameTexts(const FLPH_Texts& A, const FLPH_Texts& B)
	{
		return A.NotInDb == B.NotInDb && A.NoSafePath == B.NoSafePath && A.BadState == B.BadState && A.HintOn == B.HintOn
			&& A.HintOff == B.HintOff && A.Solving == B.Solving && A.SolvingTime == B.SolvingTime
			&& A.SolveArmed == B.SolveArmed && A.SolveStopped == B.SolveStopped && A.SolveUnavailable == B.SolveUnavailable
			&& A.SolveOn == B.SolveOn && A.SolveOff == B.SolveOff && A.DoubleReset == B.DoubleReset
			&& A.Thinking == B.Thinking;
	}

	FLPH_Labels LabelsEn()
	{
		FLPH_Labels L;
		L.Tape = "Tape layout";
		L.Gothic = "Gold letters";
		L.Icons = "Icons (0 auto, 1 letters, 2 icons)";
		L.Gamepad = "Icon set (0 game, 1 PS, 2 Xbox, 3 Switch)";
		L.Scale = "Size, %";
		L.OffsetX = "Position X";
		L.OffsetY = "Position Y";
		L.Counter = "Counter";
		L.Shake = "Shake on a miss";
		L.TapeNext = "Upcoming keys";
		L.TapeDone = "Pressed keys";
		L.Slide = "Smooth scroll";
		L.Plate = "Dark background";
		L.PerLine = "Keys per line";
		L.MaxLines = "Lines on screen";
		L.CollapseMin = "Fold repeats from";
		L.AutoPick = "Always auto-pick";
		L.DoubleReset = "Double reset";
		L.Timer = "Countdown";
		return L;
	}

	// The labels in the language the game's interface is in now (for the log and the tests; the menu holds the texts
	// themselves, see RowText).
	FLPH_Labels GameLabels()
	{
		FLPH_Labels En = LabelsEn();
		FLPH_Labels L;
		L.Tape = Loc("LPH_Row_Tape", En.Tape);
		L.Gothic = Loc("LPH_Row_Gothic", En.Gothic);
		L.Icons = Loc("LPH_Row_Icons", En.Icons);
		L.Gamepad = Loc("LPH_Row_Gamepad", En.Gamepad);
		L.Scale = Loc("LPH_Row_Scale", En.Scale);
		L.OffsetX = Loc("LPH_Row_OffsetX", En.OffsetX);
		L.OffsetY = Loc("LPH_Row_OffsetY", En.OffsetY);
		L.Counter = Loc("LPH_Row_Counter", En.Counter);
		L.Shake = Loc("LPH_Row_Shake", En.Shake);
		L.TapeNext = Loc("LPH_Row_TapeNext", En.TapeNext);
		L.TapeDone = Loc("LPH_Row_TapeDone", En.TapeDone);
		L.Slide = Loc("LPH_Row_Slide", En.Slide);
		L.Plate = Loc("LPH_Row_Plate", En.Plate);
		L.PerLine = Loc("LPH_Row_PerLine", En.PerLine);
		L.MaxLines = Loc("LPH_Row_MaxLines", En.MaxLines);
		L.CollapseMin = Loc("LPH_Row_CollapseMin", En.CollapseMin);
		L.AutoPick = Loc("LPH_Row_AutoPick", En.AutoPick);
		L.DoubleReset = Loc("LPH_Row_DoubleReset", En.DoubleReset);
		L.Timer = Loc("LPH_Row_Timer", En.Timer);
		return L;
	}

	// Whether the text database answers the mod's IDs at all (a mount that went wrong gives every ID an empty string).
	bool TextsInDatabase()
	{
		return !LocText("LPH_Thinking").ToString().IsEmpty();
	}
}
