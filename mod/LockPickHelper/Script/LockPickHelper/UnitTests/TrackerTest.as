// Tracker.as: the 30 cases of tests/tracker_test.lua of 1.2.0 (cases 01 to 30, in the order of that file, with the cursor
// 0-based and Observe given -1 as the highlight, as 1.x had no highlight), then the cases of the highlight that 2.0 added
// (31 and on).

// The fake minigame: applies presses the way the game does (W/S clamp, a strained move changes nothing).
class ULPH_FakeGame : UObject
{
	UPROPERTY()
	ULPH_Solver Solver;

	TArray<int> Holes;
	int Cursor = 0;
	int Strains = 0;

	void Start(ULPH_Solver Prepared, const TArray<int>& StartHoles, int StartCursor)
	{
		Solver = Prepared;
		Holes = StartHoles;
		Cursor = StartCursor;
		Strains = 0;
	}

	// False when the move strained (the game keeps everything as it was and counts the strain).
	bool Press(ELPH_Key Key)
	{
		TArray<int> After;
		int NewCursor = Cursor;
		bool bMoved = Solver.Apply(Holes, Cursor, Key, After, NewCursor);
		if (bMoved)
		{
			Holes = After;
			Cursor = NewCursor;
		}
		else
		{
			Strains++;
		}
		return bMoved;
	}
}

TArray<int> LPHTests_Holes3(int A, int B, int C)
{
	TArray<int> Holes;
	Holes.Add(A);
	Holes.Add(B);
	Holes.Add(C);
	return Holes;
}

TArray<int> LPHTests_Holes5(int A, int B, int C, int D, int E)
{
	TArray<int> Holes;
	Holes.Add(A);
	Holes.Add(B);
	Holes.Add(C);
	Holes.Add(D);
	Holes.Add(E);
	return Holes;
}

ULPH_Tracker LPHTests_NewTracker(UObject Outer, ULPH_Solver Solver, const TArray<int>& Holes, bool bCursorKnown)
{
	ULPH_Tracker Tracker = Cast<ULPH_Tracker>(NewObject(Outer, ULPH_Tracker::StaticClass()));
	Tracker.Init(Solver, Holes, bCursorKnown, LPH::GraceMs);
	return Tracker;
}

ULPH_FakeGame LPHTests_NewGame(UObject Outer, ULPH_Solver Solver, const TArray<int>& Holes, int Cursor)
{
	ULPH_FakeGame Game = Cast<ULPH_FakeGame>(NewObject(Outer, ULPH_FakeGame::StaticClass()));
	Game.Start(Solver, Holes, Cursor);
	return Game;
}

// The solver's keys for a state as text ("nil" when it has none, as the Lua tests' str(nil)).
FString LPHTests_Plan(ULPH_Solver Solver, const TArray<int>& Holes, int Cursor)
{
	TArray<ELPH_Key> Keys;
	if (Solver.Solve(Holes, Cursor, Keys) != ELPH_SolveStatus::Ok)
		return "nil";
	return LPH::KeysText(Keys);
}

FString LPHTests_Hint(ULPH_Tracker Tracker)
{
	FLPH_TrackerView View = Tracker.View();
	return LPH::KeysText(View.Keys);
}

// A key the hint does not show right now (W/S never strain a lock).
ELPH_Key LPHTests_WrongKey(ULPH_Tracker Tracker)
{
	FLPH_TrackerView View = Tracker.View();
	if (View.Index < View.Keys.Num() && View.Keys[View.Index] == ELPH_Key::W)
		return ELPH_Key::S;
	return ELPH_Key::W;
}

// Presses the hinted keys until the hint is exhausted; the game reports settled plates after every A/D. Returns the time.
int64 LPHTests_Follow(ULPH_TestRun T, ULPH_Tracker Tracker, ULPH_FakeGame Game, int64 StartMs)
{
	int64 Now = StartMs;
	for (int Guard = 0; Guard < 500; Guard++)
	{
		FLPH_TrackerView View = Tracker.View();
		if (View.Status != ELPH_Status::Ok || View.Index >= View.Keys.Num())
			return Now;
		ELPH_Key Key = View.Keys[View.Index];
		Game.Press(Key);
		Tracker.Key(Key, Now);
		Now += 300;
		if (LPH::IsMove(Key))
		{
			Tracker.Observe(Game.Holes, -1, Now);
			Now += 300;
		}
	}
	T.True(false, "the hint never ends");
	return Now;
}

ULPH_Solver LPHTests_DiggerSolver(UObject Outer)
{
	ULPH_LockDb Db = LPHTests_MakeLockDb(Outer);
	LPH_RegisterLockGraphs(Db);
	FLPH_LockGraph Graph;
	int Removed = 0;
	Db.Find(n"OC_Chest_Digger526_Lock", 0, Graph, Removed);
	return LPHTests_ReadySolver(Outer, Graph);
}

// The same series as SolverTest.as uses (a full-period generator mod 65537).
int LPHTests_Next(int Seed)
{
	return ((Seed * 75) + 74) % 65537;
}

void LPHTests_Tracker(ULPH_TestRun T)
{
	ULPH_Solver Digger = LPHTests_DiggerSolver(T);
	ULPH_Solver Free3 = LPHTests_ReadySolver(T, LPHTests_FreePlates(3));
	T.Begin("Tracker fixtures");
	T.True(Digger.IsReady(), "the Digger526 solver is ready");
	T.EqualInt(Digger.Plates(), 5, "OC_Chest_Digger526_Lock has 5 plates");
	T.True(Free3.IsReady(), "the free 3-plate solver is ready");

	LPHTests_TrackerCases01(T, Digger, Free3);
	LPHTests_TrackerCases08(T, Digger, Free3);
	LPHTests_TrackerCases15(T, Digger, Free3);
	LPHTests_TrackerCases19(T, Free3);
	LPHTests_TrackerCases25(T, Free3);
	LPHTests_TrackerHighlight(T, Free3);
}

void LPHTests_TrackerCases01(ULPH_TestRun T, ULPH_Solver Digger, ULPH_Solver Free3)
{
	TArray<int> DiggerStart = LPHTests_Holes5(7, 7, 6, 4, 7);
	TArray<int> Start = LPHTests_Holes3(3, 5, 4);

	// 01
	T.Begin("Tracker 01 first hint is the solver's answer from plate 0");
	ULPH_Tracker Tr = LPHTests_NewTracker(T, Digger, DiggerStart, true);
	FLPH_TrackerView V = Tr.View();
	T.True(V.Status == ELPH_Status::Ok, "status is Ok");
	T.EqualInt(V.Index, 0, "index");
	T.EqualStr(LPH::KeysText(V.Keys), LPHTests_Plan(Digger, DiggerStart, 0), "keys");
	T.EqualInt(V.Plan, 1, "the first plan is plan 1");

	// 02
	T.Begin("Tracker 02 following the hint opens the lock without strain");
	ULPH_FakeGame Game = LPHTests_NewGame(T, Digger, DiggerStart, 0);
	Tr = LPHTests_NewTracker(T, Digger, DiggerStart, true);
	LPHTests_Follow(T, Tr, Game, 0);
	T.EqualInt(Game.Strains, 0, "strains");
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "status is Solved");

	// 03
	T.Begin("Tracker 03 solved only once the game shows every plate at 4");
	Game = LPHTests_NewGame(T, Free3, Start, 0);
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	V = Tr.View();
	TArray<ELPH_Key> Keys = V.Keys;
	for (ELPH_Key Key : Keys)
	{
		Game.Press(Key);
		Tr.Key(Key, 0);
	}
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Ok, "status before the game confirms");
	T.EqualInt(V.Index, Keys.Num(), "index (past the last key)");
	Tr.Observe(Game.Holes, -1, 100);
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "status after");

	// 04
	T.Begin("Tracker 04 wrong W replans from the next plate");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	T.EqualStr(LPHTests_Hint(Tr), "DWA", "first hint");
	int PlanBefore = Tr.View().Plan;
	Tr.Key(ELPH_Key::W, 0);
	V = Tr.View();
	T.EqualInt(V.Index, 0, "index");
	T.EqualStr(LPH::KeysText(V.Keys), LPHTests_Plan(Free3, Start, 1), "keys");
	T.EqualInt(V.Plan, PlanBefore + 1, "a wrong press is one replan");

	// 05
	T.Begin("Tracker 05 wrong A/D replans from the moved plates");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::A, 0);
	TArray<int> Moved = LPHTests_Holes3(2, 5, 4);
	T.EqualStr(LPHTests_Hint(Tr), LPHTests_Plan(Free3, Moved, 0), "keys");
	Tr.Observe(Moved, -1, 400);
	T.EqualStr(LPHTests_Hint(Tr), LPHTests_Plan(Free3, Moved, 0), "keys after the game confirms");

	// 06
	T.Begin("Tracker 06 old positions within the grace period are not a mismatch");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::D, 1000);
	Tr.Observe(Start, -1, 1100);
	V = Tr.View();
	T.EqualStr(LPH::KeysText(V.Keys), "DWA", "keys");
	T.EqualInt(V.Index, 1, "index");

	// 07
	T.Begin("Tracker 07 a press the game swallowed is taken back after the grace period");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::D, 1000);
	Tr.Observe(Start, -1, 2300);
	V = Tr.View();
	T.EqualStr(LPH::KeysText(V.Keys), "SSDWA", "keys (the cursor is forgotten: parked first)");
	T.EqualInt(V.Index, 0, "index");
}

void LPHTests_TrackerCases08(ULPH_TestRun T, ULPH_Solver Digger, ULPH_Solver Free3)
{
	TArray<int> DiggerStart = LPHTests_Holes5(7, 7, 6, 4, 7);
	TArray<int> Start = LPHTests_Holes3(3, 5, 4);

	// 08
	T.Begin("Tracker 08 cursor desync is resolved from the plate that moved");
	ULPH_FakeGame Game = LPHTests_NewGame(T, Free3, Start, 0);
	ULPH_Tracker Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::W, 0); // the game swallowed this W: it still has the cursor on plate 0
	T.EqualStr(LPHTests_Hint(Tr), "ASD", "hint for the wrong cursor");
	Game.Press(ELPH_Key::A);
	Tr.Key(ELPH_Key::A, 300);
	Tr.Observe(Game.Holes, -1, 600);
	T.EqualStr(LPHTests_Hint(Tr), LPHTests_Plan(Free3, LPHTests_Holes3(2, 5, 4), 0), "keys from the real cursor");
	LPHTests_Follow(T, Tr, Game, 900);
	FLPH_TrackerView V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "status");

	// 09
	T.Begin("Tracker 09 W/S pressed after the mismatched move are replayed onto the found cursor");
	Game = LPHTests_NewGame(T, Free3, Start, 0);
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::W, 0); // swallowed
	Game.Press(ELPH_Key::A);
	Tr.Key(ELPH_Key::A, 300);
	Game.Press(ELPH_Key::W);
	Tr.Key(ELPH_Key::W, 500);
	Tr.Observe(Game.Holes, -1, 900);
	T.EqualStr(LPHTests_Hint(Tr), LPHTests_Plan(Free3, LPHTests_Holes3(2, 5, 4), 1), "keys from plate 1");
	LPHTests_Follow(T, Tr, Game, 1200);
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "status");

	// 10
	T.Begin("Tracker 10 a change no single move explains parks the cursor");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::D, 0);
	TArray<int> Odd = LPHTests_Holes3(3, 4, 5);
	Tr.Observe(Odd, -1, 400);
	T.EqualStr(LPHTests_Hint(Tr), "SS" + LPHTests_Plan(Free3, Odd, 0), "keys");

	// 11
	T.Begin("Tracker 11 back at the start positions parks the cursor (pick broke or R)");
	Game = LPHTests_NewGame(T, Digger, DiggerStart, 0);
	Tr = LPHTests_NewTracker(T, Digger, DiggerStart, true);
	V = Tr.View();
	TArray<ELPH_Key> Keys = V.Keys;
	int i = 0;
	int64 Now = 0;
	do // follow the hint through its first move and let the game confirm it
	{
		Game.Press(Keys[i]);
		Tr.Key(Keys[i], Now);
		Now += 300;
		i++;
	}
	while (i < Keys.Num() && !LPH::IsMove(Keys[i - 1]));
	Tr.Observe(Game.Holes, -1, Now);
	while (i < Keys.Num() && !LPH::IsMove(Keys[i]))
	{
		Tr.Key(Keys[i], Now);
		i++;
	}
	T.True(i < Keys.Num(), "the hint has a second move");
	Tr.Key(Keys[i], Now); // say the pick broke on this move:
	Tr.Observe(DiggerStart, -1, Now + 1500); // the lock is back at the start, cursor on plate 0
	T.EqualStr(LPHTests_Hint(Tr), "SSSS" + LPHTests_Plan(Digger, DiggerStart, 0), "keys");

	// 12
	T.Begin("Tracker 12 a strained move parks the cursor");
	TArray<int> Edge = LPHTests_Holes3(1, 5, 4);
	Tr = LPHTests_NewTracker(T, Free3, Edge, true);
	Tr.Key(ELPH_Key::A, 0);
	T.EqualStr(LPHTests_Hint(Tr), "SS" + LPHTests_Plan(Free3, Edge, 0), "keys");

	// 13
	T.Begin("Tracker 13 unknown cursor at the start parks it first");
	Tr = LPHTests_NewTracker(T, Digger, DiggerStart, false);
	T.EqualStr(LPHTests_Hint(Tr), "SSSS" + LPHTests_Plan(Digger, DiggerStart, 0), "keys");
	Game = LPHTests_NewGame(T, Digger, DiggerStart, 2);
	LPHTests_Follow(T, Tr, Game, 0);
	T.EqualInt(Game.Strains, 0, "strains");
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "status");

	// 14
	T.Begin("Tracker 14 R parks the cursor");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::R, 0);
	T.EqualStr(LPHTests_Hint(Tr), "SS" + LPHTests_Plan(Free3, Start, 0), "keys");
}

void LPHTests_TrackerCases15(ULPH_TestRun T, ULPH_Solver Digger, ULPH_Solver Free3)
{
	TArray<int> Start = LPHTests_Holes3(3, 5, 4);

	// 15
	T.Begin("Tracker 15 fast presses: an intermediate reading keeps the hint");
	ULPH_Tracker Tr = LPHTests_NewTracker(T, Free3, Start, true);
	int PlanBefore = Tr.View().Plan;
	Tr.Key(ELPH_Key::D, 0);
	Tr.Key(ELPH_Key::W, 100);
	Tr.Key(ELPH_Key::A, 200);
	Tr.Observe(LPHTests_Holes3(4, 5, 4), -1, 700); // the game finished D, A still animating
	FLPH_TrackerView V = Tr.View();
	T.EqualInt(V.Plan, PlanBefore, "same hint (no replan)");
	T.EqualStr(LPH::KeysText(V.Keys), "DWA", "keys");
	T.EqualInt(V.Index, 3, "index");
	Tr.Observe(LPHTests_Holes3(4, 4, 4), -1, 1200);
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "status");

	// 16
	T.Begin("Tracker 16 random detours: hinted presses never strain");
	int Seed = 7;
	ULPH_Tracker Walker = Cast<ULPH_Tracker>(NewObject(T, ULPH_Tracker::StaticClass()));
	ULPH_FakeGame Game = Cast<ULPH_FakeGame>(NewObject(T, ULPH_FakeGame::StaticClass()));
	int Runs = 0;
	int Solved = 0;
	int Detours = 0;
	for (int Run = 0; Run < 200; Run++)
	{
		TArray<int> RunStart;
		TArray<ELPH_Key> Probe;
		do
		{
			RunStart.Reset();
			for (int Plate = 0; Plate < 5; Plate++)
			{
				Seed = LPHTests_Next(Seed);
				RunStart.Add(1 + (Seed % 7));
			}
		}
		while (Digger.Solve(RunStart, 0, Probe) != ELPH_SolveStatus::Ok);

		Walker.Init(Digger, RunStart, true, LPH::GraceMs);
		Game.Start(Digger, RunStart, 0);
		int64 Now = 0;
		int Presses = 0;
		bool bFailed = false;
		while (!bFailed && Walker.View().Status == ELPH_Status::Ok)
		{
			FLPH_TrackerView RunView = Walker.View();
			ELPH_Key Key = ELPH_Key::W;
			bool bHinted = RunView.Index < RunView.Keys.Num();
			Seed = LPHTests_Next(Seed);
			if (bHinted && (Seed % 10) >= 2)
			{
				Key = RunView.Keys[RunView.Index];
			}
			else
			{
				bHinted = false;
				Detours++;
				Seed = LPHTests_Next(Seed);
				int Pick = Seed % 4;
				if (Pick == 1)
					Key = ELPH_Key::S;
				else if (Pick == 2)
					Key = ELPH_Key::A;
				else if (Pick == 3)
					Key = ELPH_Key::D;
			}
			bool bMoved = Game.Press(Key);
			if (bHinted && LPH::IsMove(Key) && !bMoved)
			{
				T.True(false, f"run {Run}: hinted {LPH::KeyLetter(Key)} strained from {LPH::KeysText(RunView.Keys)}");
				bFailed = true;
			}
			Walker.Key(Key, Now);
			Now += 300;
			Walker.Observe(Game.Holes, -1, Now);
			Now += 300;
			Presses++;
			if (Presses > 2000)
			{
				T.True(false, f"run {Run}: not solved after 2000 presses");
				bFailed = true;
			}
		}
		FLPH_TrackerView End = Walker.View();
		if (!bFailed)
			T.True(End.Status == ELPH_Status::Solved, f"run {Run}: status is Solved");
		if (End.Status == ELPH_Status::Solved)
			Solved++;
		Runs++;
	}
	T.EqualInt(Runs, 200, "200 random runs");
	T.EqualInt(Solved, 200, "all 200 runs end Solved");
	T.True(Detours > 100, f"the runs took detours ({Detours})");

	// 17
	T.Begin("Tracker 17 an all-4 reading is solved even off the expected path");
	Tr = LPHTests_NewTracker(T, Free3, LPHTests_Holes3(4, 5, 4), false);
	Tr.Key(ELPH_Key::A, 0);
	Tr.Observe(LPHTests_Holes3(4, 4, 4), -1, 400);
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "status");

	// 18
	T.Begin("Tracker 18 R after progress plans from the start positions");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::D, 0);
	Tr.Observe(LPHTests_Holes3(4, 5, 4), -1, 400);
	Tr.Key(ELPH_Key::R, 500);
	T.EqualStr(LPHTests_Hint(Tr), "SS" + LPHTests_Plan(Free3, Start, 0), "keys");
}

void LPHTests_TrackerCases19(ULPH_TestRun T, ULPH_Solver Free3)
{
	TArray<int> Start = LPHTests_Holes3(3, 5, 4);

	// 19
	T.Begin("Tracker 19 history keeps hinted presses: ok, misses and the press count");
	ULPH_Tracker Tr = LPHTests_NewTracker(T, Free3, Start, true);
	FLPH_TrackerView V = Tr.View();
	ELPH_Key First = V.Keys[0];
	Tr.Key(First, 0);
	Tr.Key(LPHTests_WrongKey(Tr), 100);
	V = Tr.View();
	T.EqualInt(V.History.Num(), 2, "history");
	T.True(V.History[0].Key == First, "first key");
	T.True(V.History[0].bOk, "first ok");
	T.True(!V.History[1].bOk, "second is a miss");
	T.EqualInt(V.Misses, 1, "misses");
	T.EqualInt(V.Pressed, 2, "pressed");

	// 20
	T.Begin("Tracker 20 R clears the history; misses and presses stay counted");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(LPHTests_WrongKey(Tr), 0);
	Tr.Key(ELPH_Key::R, 100);
	V = Tr.View();
	T.EqualInt(V.History.Num(), 0, "history cleared");
	T.EqualInt(V.Misses, 1, "misses kept");
	T.EqualInt(V.Pressed, 1, "presses kept");

	// 21
	T.Begin("Tracker 21 a resync from the game's readings is not a miss");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	V = Tr.View();
	T.True(V.Keys[0] == ELPH_Key::D, "hint starts with D on plate 0");
	Tr.Key(ELPH_Key::D, 0);
	Tr.Observe(LPHTests_Holes3(3, 6, 4), -1, 400); // the game moved plate 1: the cursor was elsewhere
	V = Tr.View();
	T.EqualInt(V.Misses, 0, "misses");
	T.EqualInt(V.History.Num(), 1, "history unchanged");

	// 22
	T.Begin("Tracker 22 a press the game swallowed is not a miss");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	V = Tr.View();
	Tr.Key(V.Keys[0], 0);
	Tr.Observe(Start, -1, 2000); // grace passed, the plates never moved
	V = Tr.View();
	T.EqualInt(V.Misses, 0, "misses");

	// 23
	T.Begin("Tracker 23 no history while there is no hint");
	Tr = LPHTests_NewTracker(T, Free3, LPHTests_Holes3(9, 4, 4), true);
	V = Tr.View();
	T.True(V.Status == ELPH_Status::BadState, "status");
	Tr.Key(ELPH_Key::W, 0);
	V = Tr.View();
	T.EqualInt(V.History.Num(), 0, "history");
	T.EqualInt(V.Misses, 0, "misses");

	// 24
	T.Begin("Tracker 24 history keeps the last 512 presses");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	for (int i = 1; i <= 600; i++)
		Tr.Key(LPHTests_WrongKey(Tr), i);
	V = Tr.View();
	T.EqualInt(V.History.Num(), 512, "history");
	T.EqualInt(V.Pressed, 600, "pressed");
}

void LPHTests_TrackerCases25(ULPH_TestRun T, ULPH_Solver Free3)
{
	TArray<int> Start = LPHTests_Holes3(3, 5, 4);

	// 25
	T.Begin("Tracker 25 pending counts the A/D the game has not shown yet");
	ULPH_Tracker Tr = LPHTests_NewTracker(T, Free3, Start, true);
	T.EqualInt(Tr.Pending(), 0, "at the start");
	Tr.Key(ELPH_Key::W, 0);
	T.EqualInt(Tr.Pending(), 0, "W/S do not wait for the plates");
	Tr.Key(ELPH_Key::D, 100);
	T.EqualInt(Tr.Pending(), 1, "after D");
	Tr.Observe(Start, -1, 200);
	T.EqualInt(Tr.Pending(), 1, "old positions within the grace period");
	Tr.Observe(LPHTests_Holes3(3, 6, 4), -1, 500);
	T.EqualInt(Tr.Pending(), 0, "confirmed");

	// 26
	T.Begin("Tracker 26 pending: the game confirms the first of two moves");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::D, 0);
	Tr.Key(ELPH_Key::D, 100);
	T.EqualInt(Tr.Pending(), 2, "two moves");
	Tr.Observe(LPHTests_Holes3(4, 5, 4), -1, 400);
	T.EqualInt(Tr.Pending(), 1, "one left");
	Tr.Observe(LPHTests_Holes3(5, 5, 4), -1, 700);
	T.EqualInt(Tr.Pending(), 0, "both shown");

	// 27
	T.Begin("Tracker 27 pending: a move the game swallowed is dropped after the grace period");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::D, 1000);
	Tr.Observe(Start, -1, 2300);
	T.EqualInt(Tr.Pending(), 0, "taken back");

	// 28
	T.Begin("Tracker 28 pending: a mismatched move is dropped by the resync");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::D, 0);
	Tr.Observe(LPHTests_Holes3(3, 6, 4), -1, 400); // the game moved plate 1: the cursor was not on plate 0
	T.EqualInt(Tr.Pending(), 0, "resynced");

	// 29
	T.Begin("Tracker 29 pending is 0 once the lock is solved");
	Tr = LPHTests_NewTracker(T, Free3, LPHTests_Holes3(3, 4, 4), true);
	Tr.Key(ELPH_Key::D, 0);
	T.EqualInt(Tr.Pending(), 1, "before the plates show it");
	Tr.Observe(LPHTests_Holes3(4, 4, 4), -1, 300);
	FLPH_TrackerView V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "solved");
	T.EqualInt(Tr.Pending(), 0, "nothing left to wait for");

	// 30
	T.Begin("Tracker 30 pending counts an R until the plates show the start again");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(ELPH_Key::D, 0);
	Tr.Observe(LPHTests_Holes3(4, 5, 4), -1, 400);
	Tr.Key(ELPH_Key::R, 500);
	T.EqualInt(Tr.Pending(), 1, "R in flight");
	Tr.Observe(Start, -1, 900);
	T.EqualInt(Tr.Pending(), 0, "back at the start");
}

// New in 2.0: Observe is given the plate the game highlights.
void LPHTests_TrackerHighlight(ULPH_TestRun T, ULPH_Solver Free3)
{
	TArray<int> Start = LPHTests_Holes3(3, 5, 4);

	// 31
	T.Begin("Tracker 31 unknown cursor, highlight 2: a plan without parking, Plan grows");
	ULPH_Tracker Tr = LPHTests_NewTracker(T, Free3, Start, false);
	FLPH_TrackerView V = Tr.View();
	T.EqualStr(LPH::KeysText(V.Keys), "SSDWA", "parked before the highlight");
	int PlanBefore = V.Plan;
	Tr.Observe(Start, 2, 100);
	V = Tr.View();
	T.EqualStr(LPH::KeysText(V.Keys), LPHTests_Plan(Free3, Start, 2), "the plan from plate 2");
	T.True(LPH::KeysText(V.Keys) != "SSDWA", "no parking");
	T.EqualInt(V.Plan, PlanBefore + 1, "Plan grew by one");
	T.EqualInt(V.Index, 0, "index");
	T.True(V.Status == ELPH_Status::Ok, "status");
	// The cursor is known now: another reading with a highlight changes nothing.
	Tr.Observe(Start, 0, 150);
	V = Tr.View();
	T.EqualInt(V.Plan, PlanBefore + 1, "a known cursor ignores the highlight");
	// And the hint is right for a pick that really is on plate 2.
	ULPH_FakeGame Game = LPHTests_NewGame(T, Free3, Start, 2);
	LPHTests_Follow(T, Tr, Game, 200);
	T.EqualInt(Game.Strains, 0, "strains");
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "following the hint from the highlighted cursor opens the lock");

	// 32
	T.Begin("Tracker 32 unknown cursor, highlight -1: parking as in 1.x");
	Tr = LPHTests_NewTracker(T, Free3, Start, false);
	PlanBefore = Tr.View().Plan;
	Tr.Observe(Start, -1, 100);
	V = Tr.View();
	T.EqualStr(LPH::KeysText(V.Keys), "SSDWA", "still parked");
	T.EqualInt(V.Plan, PlanBefore, "no replan");

	// 33
	T.Begin("Tracker 33 the highlight does not touch the interval while an A/D waits for the plates");
	TArray<int> Six = LPHTests_Holes3(6, 5, 4);
	Tr = LPHTests_NewTracker(T, Free3, Six, true);
	Tr.Key(ELPH_Key::D, 1000); // 6 -> 7: expected
	Tr.Key(ELPH_Key::D, 1050); // a strain: the cursor is forgotten, both presses wait for the plates
	V = Tr.View();
	T.EqualStr(LPH::KeysText(V.Keys), "SS" + LPHTests_Plan(Free3, LPHTests_Holes3(7, 5, 4), 0), "parked after the strain");
	PlanBefore = V.Plan;
	T.EqualInt(Tr.Pending(), 2, "two moves wait");
	Tr.Observe(Six, 2, 1100); // the old holes within the grace period
	V = Tr.View();
	T.EqualInt(V.Plan, PlanBefore, "no replan from the highlight");
	T.EqualStr(LPH::KeysText(V.Keys), "SS" + LPHTests_Plan(Free3, LPHTests_Holes3(7, 5, 4), 0), "still parked");
	T.EqualInt(Tr.Pending(), 2, "the moves still wait");
	// The grace period is over and the plates never moved: the presses were swallowed. The holes are the game's, the
	// cursor stays unknown for this reading (a press was waiting when it came) ...
	Tr.Observe(Six, 2, 2500);
	V = Tr.View();
	T.EqualInt(V.Plan, PlanBefore + 1, "one replan for the swallowed presses");
	T.EqualStr(LPH::KeysText(V.Keys), "SS" + LPHTests_Plan(Free3, Six, 0), "parked from the game's holes");
	T.EqualInt(Tr.Pending(), 0, "taken back");
	// ... and the next reading, with nothing waiting, takes the highlight.
	Tr.Observe(Six, 2, 2550);
	V = Tr.View();
	T.EqualInt(V.Plan, PlanBefore + 2, "one more replan for the highlight");
	T.EqualStr(LPH::KeysText(V.Keys), LPHTests_Plan(Free3, Six, 2), "the plan from the highlighted plate");

	// 34
	T.Begin("Tracker 34 a W the highlight may not show yet is not answered in the reading that clears it");
	Tr = LPHTests_NewTracker(T, Free3, Start, false);
	Tr.Key(ELPH_Key::W, 0);
	PlanBefore = Tr.View().Plan;
	Tr.Observe(Start, 0, 50); // confirms the holes; the highlight may be one frame behind the W
	V = Tr.View();
	T.EqualInt(V.Plan, PlanBefore, "no replan from the highlight in that reading");
	T.EqualInt(Tr.Pending(), 0, "the reading cleared the press");
	Tr.Observe(Start, 1, 100);
	V = Tr.View();
	T.EqualInt(V.Plan, PlanBefore + 1, "the next reading takes the highlight");
	T.EqualStr(LPH::KeysText(V.Keys), LPHTests_Plan(Free3, Start, 1), "the plan from the highlighted plate");

	// 35
	T.Begin("Tracker 35 a highlight outside the plates is no cursor");
	Tr = LPHTests_NewTracker(T, Free3, Start, false);
	PlanBefore = Tr.View().Plan;
	Tr.Observe(Start, 3, 100);
	Tr.Observe(Start, 7, 150);
	V = Tr.View();
	T.EqualInt(V.Plan, PlanBefore, "no replan");
	T.EqualStr(LPH::KeysText(V.Keys), "SSDWA", "still parked");

	// 36
	T.Begin("Tracker 36 a lock that is open takes no highlight");
	Tr = LPHTests_NewTracker(T, Free3, Start, false);
	Tr.Observe(LPHTests_Holes3(4, 4, 4), 1, 100);
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "solved");
	T.EqualInt(V.Keys.Num(), 0, "no keys");

	// 37
	T.Begin("Tracker 37 Init starts afresh and Plan keeps growing");
	Tr = LPHTests_NewTracker(T, Free3, Start, true);
	Tr.Key(LPHTests_WrongKey(Tr), 0);
	Tr.Key(ELPH_Key::D, 10);
	Tr.Observe(LPHTests_Holes3(4, 4, 4), -1, 100);
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Solved, "solved before the second Init");
	PlanBefore = V.Plan;
	Tr.Init(Free3, Start, true, LPH::GraceMs);
	V = Tr.View();
	T.True(V.Status == ELPH_Status::Ok, "status after Init");
	T.EqualStr(LPH::KeysText(V.Keys), "DWA", "keys after Init");
	T.EqualInt(V.History.Num(), 0, "history after Init");
	T.EqualInt(V.Misses, 0, "misses after Init");
	T.EqualInt(V.Pressed, 0, "pressed after Init");
	T.EqualInt(Tr.Pending(), 0, "pending after Init");
	T.True(V.Plan > PlanBefore, "Plan does not go back across Init");

	// 38
	T.Begin("Tracker 38 a tracker without a solver says BadState");
	ULPH_Tracker Bare = Cast<ULPH_Tracker>(NewObject(T, ULPH_Tracker::StaticClass()));
	Bare.Init(nullptr, Start, true, LPH::GraceMs);
	V = Bare.View();
	T.True(V.Status == ELPH_Status::BadState, "status");
	Bare.Key(ELPH_Key::D, 0);
	Bare.Observe(Start, 1, 100);
	V = Bare.View();
	T.True(V.Status == ELPH_Status::BadState, "status after presses and a reading");
}
