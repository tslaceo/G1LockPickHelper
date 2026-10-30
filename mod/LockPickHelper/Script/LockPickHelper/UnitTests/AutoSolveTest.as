// AutoSolve.as: the 20 cases of tests/autosolve_test.lua of 1.2.0 (cases 01 to 20, in the order of that file). The keys and
// the tracker's Index are 0-based here, and "a new keys table" of 1.x is a new Plan number. Cases 01 to 16 hand the
// autosolver a tracker view made by hand; cases 17 to 20 drive it together with a real tracker against a fake minigame
// (ULPH_FakeGame and the Digger526 solver of TrackerTest.as).

enum ELPH_TestSwallow
{
	None, // the game takes every press
	FirstMove, // the game ignores the first A/D
	All // the game ignores every press
}

// What a drive of the autosolver ended with.
struct FLPH_AutoDriveResult
{
	ELPH_AutoStop Reason = ELPH_AutoStop::None; // None: it was still running when the time ran out
	TArray<int> Holes; // the game's holes at the end
	int Strains = 0;
	int Swallowed = 0; // presses the game ignored
	TArray<ELPH_Key> Presses; // every key the autosolver pressed, in order
}

FString LPHTests_StateName(ELPH_AutoState State)
{
	if (State == ELPH_AutoState::Off)
		return "off";
	if (State == ELPH_AutoState::Armed)
		return "armed";
	if (State == ELPH_AutoState::Running)
		return "running";
	return "?";
}

FString LPHTests_StopName(ELPH_AutoStop Stop)
{
	if (Stop == ELPH_AutoStop::None)
		return "none";
	if (Stop == ELPH_AutoStop::Solved)
		return "solved";
	if (Stop == ELPH_AutoStop::NoSafePath)
		return "nosafepath";
	if (Stop == ELPH_AutoStop::BadState)
		return "badstate";
	if (Stop == ELPH_AutoStop::Timeout)
		return "timeout";
	if (Stop == ELPH_AutoStop::Replans)
		return "replans";
	return "?";
}

// The autosolver as the Lua tests had it: 60 ms after a W/S, 2500 ms for an A/D, 3 replans in a row.
ULPH_AutoSolve LPHTests_NewAuto(UObject Outer)
{
	ULPH_AutoSolve Auto = Cast<ULPH_AutoSolve>(NewObject(Outer, ULPH_AutoSolve::StaticClass()));
	Auto.Init(60, 2500, 3);
	return Auto;
}

// The keys of a row of letters: "WAD".
TArray<ELPH_Key> LPHTests_KeyList(FString Letters)
{
	TArray<ELPH_Key> Keys;
	for (int i = 0; i < Letters.Len(); i++)
		Keys.Add(LPHTests_KeyOfLetter(Letters.Mid(i, 1)));
	return Keys;
}

// A tracker view with a hint (status Ok). A new Plan number is what a tracker replan makes (1.x: a new keys table).
FLPH_TrackerView LPHTests_AutoView(FString Letters, int Index, int Plan)
{
	FLPH_TrackerView View;
	View.Status = ELPH_Status::Ok;
	View.Keys = LPHTests_KeyList(Letters);
	View.Index = Index;
	View.Plan = Plan;
	return View;
}

// A tracker view without a hint: Solved, NoSafePath or BadState.
FLPH_TrackerView LPHTests_AutoViewNoHint(ELPH_Status Status, int Plan)
{
	FLPH_TrackerView View;
	View.Status = Status;
	View.Plan = Plan;
	return View;
}

// One Step call as text: the key's letter when it says to press it, "-" when it does not, and "/<reason>" added when it has
// just stopped itself ("-/timeout"). Key and Stop start as values Step must overwrite (R is never a hint's key; Stop
// Timeout would show), so a Step that leaves its results unset fails the check.
FString LPHTests_AutoStepWith(ULPH_AutoSolve Auto, const FLPH_TrackerView& View, bool bHasView, int Pending, int64 Now)
{
	ELPH_Key Key = ELPH_Key::R;
	ELPH_AutoStop Stop = ELPH_AutoStop::Timeout;
	bool bPress = Auto.Step(View, bHasView, Pending, Now, Key, Stop);
	FString Text = "-";
	if (bPress)
		Text = LPH::KeyLetter(Key);
	if (Stop != ELPH_AutoStop::None)
		Text += "/" + LPHTests_StopName(Stop);
	return Text;
}

FString LPHTests_AutoStep(ULPH_AutoSolve Auto, const FLPH_TrackerView& View, int Pending, int64 Now)
{
	return LPHTests_AutoStepWith(Auto, View, true, Pending, Now);
}

// The holes in a row: "4 4 4 4 4".
FString LPHTests_AutoHolesText(const TArray<int>& Holes)
{
	FString Text;
	for (int i = 0; i < Holes.Num(); i++)
	{
		if (i > 0)
			Text += " ";
		Text += f"{Holes[i]}";
	}
	return Text;
}

// The autosolver (toggled on, as F3 does while the tracker exists) with a real tracker against a fake minigame, every
// 10 ms: an A/D shows on the plates 300 ms after the press, the plates are read every 50 ms. Swallow says which presses
// the game ignores (the tracker still counts them); bBlind: the plates are never read. Runs until the autosolver stops
// itself, or 120 s.
FLPH_AutoDriveResult LPHTests_AutoDrive(UObject Outer, ULPH_Solver Solver, const TArray<int>& Start, ELPH_TestSwallow Swallow, bool bBlind)
{
	ULPH_Tracker Tracker = LPHTests_NewTracker(Outer, Solver, Start, true);
	ULPH_AutoSolve Auto = LPHTests_NewAuto(Outer);
	Auto.Toggle(true);
	ULPH_FakeGame Game = LPHTests_NewGame(Outer, Solver, Start, 0);
	TArray<int> Shown = Start;
	int ShownAt = 0;
	FLPH_AutoDriveResult Result;

	for (int Now = 0; Now <= 120000; Now += 10)
	{
		if (Now >= ShownAt)
			Shown = Game.Holes;
		if (Now % LPH::PollMs == 0 && !bBlind)
			Tracker.Observe(Shown, -1, Now);

		FLPH_TrackerView View = Tracker.View();
		ELPH_Key Key = ELPH_Key::R;
		ELPH_AutoStop Stop = ELPH_AutoStop::None;
		bool bPress = Auto.Step(View, true, Tracker.Pending(), Now, Key, Stop);
		if (Stop != ELPH_AutoStop::None)
		{
			Result.Reason = Stop;
			break;
		}
		if (!bPress)
			continue;

		Result.Presses.Add(Key);
		bool bIgnored = Swallow == ELPH_TestSwallow::All;
		if (Swallow == ELPH_TestSwallow::FirstMove && LPH::IsMove(Key) && Result.Swallowed == 0)
			bIgnored = true;
		if (bIgnored)
		{
			Result.Swallowed++;
		}
		else if (Game.Press(Key))
		{
			if (LPH::IsMove(Key))
				ShownAt = Now + 300;
		}
		Tracker.Key(Key, Now);
	}

	Result.Holes = Game.Holes;
	Result.Strains = Game.Strains;
	return Result;
}

void LPHTests_AutoSolve(ULPH_TestRun T)
{
	LPHTests_AutoCases01(T);
	LPHTests_AutoCases09(T);
	LPHTests_AutoCases14(T);
	LPHTests_AutoDriven(T);
}

void LPHTests_AutoCases01(ULPH_TestRun T)
{
	// 01
	T.Begin("AutoSolve 01 EtaMs counts the keys from From on, each A/D at the A/D time and each W/S at the W/S time");
	TArray<ELPH_Key> Plan = LPHTests_KeyList("WADS");
	T.EqualInt(LPH::EtaMs(Plan, 0, 400, 70), 940, "the whole plan");
	T.EqualInt(LPH::EtaMs(Plan, 2, 400, 70), 470, "from the third key");
	T.EqualInt(LPH::EtaMs(Plan, 4, 400, 70), 0, "nothing left");
	T.EqualInt(LPH::EtaMs(Plan, 9, 400, 70), 0, "From beyond the end");
	T.EqualInt(LPH::EtaMs(Plan, -1, 400, 70), 940, "From before the start counts from the start");

	// 02
	T.Begin("AutoSolve 02 off by default: no key");
	ULPH_AutoSolve Auto = LPHTests_NewAuto(T);
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "off", "state");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 0, 1), 0, 0), "-", "key");

	// 03
	T.Begin("AutoSolve 03 F3 while tracking runs and presses the hint's current key");
	Auto = LPHTests_NewAuto(T);
	T.EqualStr(LPHTests_StateName(Auto.Toggle(true)), "running", "state");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("WA", 1, 1), 0, 0), "A", "the current key");

	// 04
	T.Begin("AutoSolve 04 F3 before the minigame is ready arms; the tracker starts it");
	Auto = LPHTests_NewAuto(T);
	FLPH_TrackerView NoView;
	T.EqualStr(LPHTests_StateName(Auto.Toggle(false)), "armed", "state");
	T.EqualStr(LPHTests_AutoStepWith(Auto, NoView, false, 0, 0), "-", "no tracker: nothing");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "armed", "still armed");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("D", 0, 1), 0, 100), "D", "first key once the tracker exists");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "running", "running");

	// 05
	T.Begin("AutoSolve 05 F3 again stops it, armed or running");
	Auto = LPHTests_NewAuto(T);
	Auto.Toggle(false);
	T.EqualStr(LPHTests_StateName(Auto.Toggle(false)), "off", "armed -> off");
	Auto.Toggle(true);
	T.EqualStr(LPHTests_StateName(Auto.Toggle(true)), "off", "running -> off");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("D", 0, 1), 0, 0), "-", "no key when off");

	// 06
	T.Begin("AutoSolve 06 Arm starts from off only");
	Auto = LPHTests_NewAuto(T);
	Auto.Arm();
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "armed", "armed");
	Auto.Toggle(true); // armed -> off
	Auto.Toggle(true); // off -> running
	Auto.Arm();
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "running", "Arm does not demote a running autosolver");

	// 07
	T.Begin("AutoSolve 07 after a W/S it waits the W/S gap");
	Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	FLPH_TrackerView View = LPHTests_AutoView("WWA", 0, 1);
	T.EqualStr(LPHTests_AutoStep(Auto, View, 0, 1000), "W", "first");
	View.Index = 1;
	T.EqualStr(LPHTests_AutoStep(Auto, View, 0, 1030), "-", "within the pause");
	T.EqualStr(LPHTests_AutoStep(Auto, View, 0, 1060), "W", "after the pause");

	// 08
	T.Begin("AutoSolve 08 after an A/D it waits until the plates confirm it");
	Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	View = LPHTests_AutoView("AW", 0, 1);
	T.EqualStr(LPHTests_AutoStep(Auto, View, 0, 0), "A", "A");
	View.Index = 1;
	T.EqualStr(LPHTests_AutoStep(Auto, View, 1, 100), "-", "unconfirmed");
	T.EqualStr(LPHTests_AutoStep(Auto, View, 1, 2000), "-", "still unconfirmed, before the timeout");
	T.EqualStr(LPHTests_AutoStep(Auto, View, 0, 2050), "W", "confirmed: the next key at once");
}

void LPHTests_AutoCases09(ULPH_TestRun T)
{
	// 09
	T.Begin("AutoSolve 09 it never presses while a move is unconfirmed, even one it did not make");
	ULPH_AutoSolve Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	FLPH_TrackerView View = LPHTests_AutoView("A", 0, 1);
	T.EqualStr(LPHTests_AutoStep(Auto, View, 1, 0), "-", "the player's move is still animating");
	T.EqualStr(LPHTests_AutoStep(Auto, View, 0, 300), "A", "then the key");

	// 10
	T.Begin("AutoSolve 10 an A/D unconfirmed for the timeout stops it");
	Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	View = LPHTests_AutoView("AW", 0, 1);
	LPHTests_AutoStep(Auto, View, 0, 0); // presses the A
	View.Index = 1;
	T.EqualStr(LPHTests_AutoStep(Auto, View, 1, 2501), "-/timeout", "key and reason");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "off", "state");

	// 11
	T.Begin("AutoSolve 11 a move it did not make that never shows also stops it after the timeout");
	Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	View = LPHTests_AutoView("A", 0, 1);
	T.EqualStr(LPHTests_AutoStep(Auto, View, 1, 0), "-", "waits");
	T.EqualStr(LPHTests_AutoStep(Auto, View, 1, 2501), "-/timeout", "key and reason");

	// 12
	T.Begin("AutoSolve 12 max replans replans in a row stop it");
	Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 0, 1), 0, 0), "A", "first plan");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 0, 2), 0, 400), "A", "replan 1");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 0, 3), 0, 800), "A", "replan 2");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 0, 4), 0, 1200), "-/replans", "after replan 3");

	// 13
	T.Begin("AutoSolve 13 a move confirmed as planned resets the replan count");
	Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 0, 1), 0, 0); // presses the A of the first plan
	View = LPHTests_AutoView("AD", 0, 2);
	T.EqualStr(LPHTests_AutoStep(Auto, View, 0, 400), "A", "replan 1");
	View.Index = 1;
	T.EqualStr(LPHTests_AutoStep(Auto, View, 0, 800), "D", "the A was confirmed as planned");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 0, 3), 0, 1200), "A", "replan 1 again");
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 0, 4), 0, 1600), "A", "replan 2: still running");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "running", "state");
}

void LPHTests_AutoCases14(ULPH_TestRun T)
{
	// 14
	T.Begin("AutoSolve 14 a solved lock stops it; no hint stops it with the tracker's status");
	ULPH_AutoSolve Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoViewNoHint(ELPH_Status::Solved, 1), 0, 0), "-/solved", "solved");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "off", "state after solved");
	Auto.Toggle(true);
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoViewNoHint(ELPH_Status::NoSafePath, 1), 0, 0), "-/nosafepath", "no safe path");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "off", "state after no safe path");
	Auto.Toggle(true);
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoViewNoHint(ELPH_Status::BadState, 1), 0, 0), "-/badstate", "bad state");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "off", "state after bad state");

	// 15
	T.Begin("AutoSolve 15 a player press stops it");
	Auto = LPHTests_NewAuto(T);
	T.True(!Auto.PlayerPressed(), "off: nothing to stop");
	Auto.Toggle(true);
	T.True(Auto.PlayerPressed(), "running: stopped");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "off", "state");
	Auto.Arm();
	T.True(Auto.PlayerPressed(), "armed: stopped");

	// 16
	T.Begin("AutoSolve 16 nothing to press after the last key");
	Auto = LPHTests_NewAuto(T);
	Auto.Toggle(true);
	T.EqualStr(LPHTests_AutoStep(Auto, LPHTests_AutoView("A", 1, 1), 0, 0), "-", "key");
	T.EqualStr(LPHTests_StateName(Auto.GetState()), "running", "still running until the plates show the open lock");
}

void LPHTests_AutoDriven(ULPH_TestRun T)
{
	ULPH_Solver Digger = LPHTests_DiggerSolver(T);
	TArray<int> DiggerStart = LPHTests_Holes5(7, 7, 6, 4, 7);
	T.Begin("AutoSolve fixtures");
	T.True(Digger.IsReady(), "the Digger526 solver is ready");

	// 17
	T.Begin("AutoSolve 17 it opens a lock without strain, pressing exactly the hint");
	FLPH_AutoDriveResult Run = LPHTests_AutoDrive(T, Digger, DiggerStart, ELPH_TestSwallow::None, false);
	T.EqualStr(LPHTests_StopName(Run.Reason), "solved", "reason");
	T.EqualStr(LPHTests_AutoHolesText(Run.Holes), "4 4 4 4 4", "plates");
	T.EqualInt(Run.Strains, 0, "strains");
	T.EqualStr(LPH::KeysText(Run.Presses), LPHTests_Plan(Digger, DiggerStart, 0), "presses");

	// 18
	T.Begin("AutoSolve 18 a swallowed A/D is redone after the tracker gives up on it");
	Run = LPHTests_AutoDrive(T, Digger, DiggerStart, ELPH_TestSwallow::FirstMove, false);
	T.EqualInt(Run.Swallowed, 1, "one A/D swallowed");
	T.EqualStr(LPHTests_StopName(Run.Reason), "solved", "reason");
	T.EqualInt(Run.Strains, 0, "strains");

	// 19
	T.Begin("AutoSolve 19 A/D the game keeps swallowing stop it after max replans");
	Run = LPHTests_AutoDrive(T, Digger, DiggerStart, ELPH_TestSwallow::All, false);
	T.EqualStr(LPHTests_StopName(Run.Reason), "replans", "reason");
	T.EqualStr(LPHTests_AutoHolesText(Run.Holes), LPHTests_AutoHolesText(DiggerStart), "nothing moved");

	// 20
	T.Begin("AutoSolve 20 plates that are never read stop it after the timeout");
	Run = LPHTests_AutoDrive(T, Digger, DiggerStart, ELPH_TestSwallow::None, true);
	T.EqualStr(LPHTests_StopName(Run.Reason), "timeout", "reason");
	bool bLastIsMove = Run.Presses.Num() > 0 && LPH::IsMove(Run.Presses[Run.Presses.Num() - 1]);
	T.True(bLastIsMove, "the last press is the unconfirmed A/D");
}
