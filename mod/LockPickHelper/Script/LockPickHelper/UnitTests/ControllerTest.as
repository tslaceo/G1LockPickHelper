// Controller.as: the hint and auto-pick scenarios of tests/main_test.lua of 1.2.0 (the minigame as the controller sees it:
// it opens, the lock is found, the plates are read every PollMs, the player presses keys, F3, F4, the autosolver's keys go
// out and come back, it closes), played against a fake minigame and the test's own clock with small locks of a database
// made here; then what 2.0 added: Thinking while a 7-plate lock of the real database prepares, the solver cache, the
// display's signature. No game objects.

// A fake minigame. Like the game it applies presses (W/S stop at the end plates, a strained A/D changes nothing, R takes the
// plates back to the start and the pick to plate 0), animates an A/D or R for AnimMs (no settled reading meanwhile) and
// ignores the presses of its first ReadyMs.
class ULPH_CtlGame : UObject
{
	UPROPERTY()
	ULPH_Solver Rules; // what a press does (nullptr: presses change nothing)

	TArray<int> Holes;
	TArray<int> StartHoles; // where R takes the plates
	int Cursor = 0;
	int Visible = 0; // the plates on screen (the holes' count unless a test says otherwise)
	bool bHighlight = true; // false: the reading has no selected plate (-1), as in 1.x
	bool bFreeze = false; // an A/D starts an animation that never ends (no settled reading any more)
	int64 OpenedMs = 0;
	int64 MovingUntilMs = -1; // no settled reading before this time
	int ReadyMs = 2000; // presses before this (since it opened) are ignored
	int AnimMs = 300;
	int Strains = 0;
	int Swallowed = 0;

	void Begin(ULPH_Solver InRules, const TArray<int>& From, int64 Now)
	{
		Rules = InRules;
		Holes = From;
		StartHoles = From;
		Cursor = 0;
		Visible = From.Num();
		bHighlight = true;
		bFreeze = false;
		OpenedMs = Now;
		MovingUntilMs = -1;
		Strains = 0;
		Swallowed = 0;
	}

	void Press(ELPH_Key Key, int64 Now)
	{
		if (Now - OpenedMs < ReadyMs || Rules == nullptr)
		{
			Swallowed++;
			return;
		}
		if (Key == ELPH_Key::R)
		{
			Holes = StartHoles;
			Cursor = 0;
			MovingUntilMs = Now + AnimMs;
			return;
		}
		TArray<int> After;
		int NewCursor = Cursor;
		if (!Rules.Apply(Holes, Cursor, Key, After, NewCursor))
		{
			Strains++;
			return;
		}
		Holes = After;
		Cursor = NewCursor;
		if (LPH::IsMove(Key))
		{
			MovingUntilMs = Now + AnimMs;
			if (bFreeze)
				MovingUntilMs = Now + 1000000000;
		}
	}

	// Every hole at 4.
	bool IsOpen() const
	{
		if (Holes.Num() == 0)
			return false;
		for (int Hole : Holes)
		{
			if (Hole != LPH::HoleGoal)
				return false;
		}
		return true;
	}

	FLPH_Reading Read(int64 Now) const
	{
		FLPH_Reading Reading;
		Reading.Visible = Visible;
		if (Now < MovingUntilMs)
			return Reading;
		Reading.bSettled = true;
		Reading.Holes = Holes;
		if (bHighlight)
			Reading.Cursor = Cursor;
		return Reading;
	}
}

// The glue as the controller sees it: a frame moves the clock, reads the plates when the controller wants them, ticks the
// controller, sends the autosolver's key (TakeKey, then the Broadcast: the game takes it and the handler reports it with
// OwnKey) and takes its display (Shown). Redraws counts the changes of the display's Sig (what the glue would redraw).
class ULPH_CtlRig : UObject
{
	UPROPERTY()
	ULPH_Controller Ctl;

	UPROPERTY()
	ULPH_CtlGame Game;

	UPROPERTY()
	ULPH_Log Log; // the controller's log: it keeps nothing until Listen opens it

	int64 Now = 0;
	int FrameMs = 10;
	int Reads = 0; // readings handed to the controller
	int SettledReads = 0;
	int64 LastSettledMs = -1; // when the last settled reading was handed over
	FLPH_Display Shown;
	int Redraws = 0;
	int64 FirstShownMs = -1; // the first frame since Open that showed anything (-1: none yet)
	FLPH_Display FirstShown; // and what it showed
	TArray<FString> Messages; // the message of every redraw that showed one
	TArray<FString> Counters; // the auto-pick counter (bCounterAlways), each time it changed
	int SigMismatches = 0; // frames where DisplaySig was not Display().Sig

	// The autosolver's keys.
	bool bOwnLost = false; // its Broadcast does not reach the handler: the glue calls OwnKeyMissed instead of OwnKey
	TArray<ELPH_Key> OwnKeys; // every key it sent, in order
	int64 LastOwnMs = -1;
	ELPH_Key LastOwnKey = ELPH_Key::R;
	int64 FirstOwnMoveMs = -1; // its first A/D
	int WsGaps = 0; // its keys that came after its W/S
	int MinWsGapMs = 1000000; // and the shortest such gap
	int MoveGaps = 0; // its keys that came after its A/D
	int MovesUnseen = 0; // of them, those sent before a settled reading after the A/D's animation

	void Frame()
	{
		Now += FrameMs;
		bool bRead = Ctl.WantsReading(Now);
		FLPH_Reading Reading;
		if (bRead)
		{
			Reading = Game.Read(Now);
			Reads++;
			if (Reading.bSettled)
			{
				SettledReads++;
				LastSettledMs = Now;
			}
		}
		Ctl.Tick(Now, bRead, Reading);
		ELPH_Key Key = ELPH_Key::R;
		if (Ctl.TakeKey(Now, Key))
			Own(Key);
		FString Before = Shown.Sig;
		FString Sig = Ctl.DisplaySig(Now);
		Shown = Ctl.Display(Now);
		if (Sig != Shown.Sig)
			SigMismatches++;
		if (Shown.Sig != Before)
		{
			Redraws++;
			if (Shown.Kind == ELPH_DisplayKind::Message)
				Messages.Add(Shown.Message);
		}
		if (Shown.Kind == ELPH_DisplayKind::Hint && Shown.Hint.bCounterAlways)
		{
			if (Counters.Num() == 0 || Counters[Counters.Num() - 1] != Shown.Hint.Counter)
				Counters.Add(Shown.Hint.Counter);
		}
		if (FirstShownMs < 0 && Shown.Kind != ELPH_DisplayKind::Hidden)
		{
			FirstShownMs = Now;
			FirstShown = Shown;
		}
	}

	// The glue's Broadcast of the autosolver's key: the game takes it; the handler reports it back (or does not).
	void Own(ELPH_Key Key)
	{
		if (LastOwnMs >= 0)
		{
			if (LPH::IsMove(LastOwnKey))
			{
				MoveGaps++;
				if (LastSettledMs < LastOwnMs + Game.AnimMs)
					MovesUnseen++;
			}
			else
			{
				WsGaps++;
				MinWsGapMs = Math::Min(MinWsGapMs, int(Now - LastOwnMs));
			}
		}
		LastOwnMs = Now;
		LastOwnKey = Key;
		if (FirstOwnMoveMs < 0 && LPH::IsMove(Key))
			FirstOwnMoveMs = Now;
		OwnKeys.Add(Key);
		Game.Press(Key, Now);
		if (bOwnLost)
			Ctl.OwnKeyMissed(Now);
		else
			Ctl.OwnKey(Key, Now);
	}

	void Run(int Ms)
	{
		int64 Stop = Now + Ms;
		while (Now < Stop)
			Frame();
	}

	// Frames until the game's lock is open (at most Ms), then until its last move has settled and been read.
	void RunUntilOpen(int Ms)
	{
		int64 Stop = Now + Ms;
		while (Now < Stop && !Game.IsOpen())
			Frame();
		Run(Game.AnimMs + 300);
	}

	// F3.
	void Solve()
	{
		Ctl.Solve(Now);
	}

	// Whether a redraw showed this message.
	bool Saw(FString Text) const
	{
		for (FString Each : Messages)
		{
			if (Each == Text)
				return true;
		}
		return false;
	}

	// The controller's log from now on is kept (and written to Saved/LockPickHelper-tests-controller.log).
	void Listen()
	{
		Log.Open("LockPickHelper-tests-controller.log");
	}

	bool Logged(FString Text) const
	{
		return Log.Buffer.Contains(Text);
	}

	// Frames until the controller has had Count more settled readings (at most 1000 frames).
	void RunSettled(int Count)
	{
		int Want = SettledReads + Count;
		for (int Guard = 0; Guard < 1000 && SettledReads < Want; Guard++)
			Frame();
	}

	// The minigame opens; its lock is not known yet.
	void OpenBare()
	{
		TArray<int> None;
		Game.Begin(nullptr, None, Now);
		Ctl.Opened(Now);
		FirstShownMs = -1;
	}

	// The minigame opens on this lock (found at once) with these holes; Rules plays the presses.
	void Open(FName Lock, float Precision, ULPH_Solver Rules, const TArray<int>& From)
	{
		Game.Begin(Rules, From, Now);
		Ctl.Opened(Now);
		Ctl.LockFound(Lock, Precision, Now);
		FirstShownMs = -1;
	}

	void Press(ELPH_Key Key)
	{
		Game.Press(Key, Now);
		Ctl.PlayerKey(Key, Now);
	}

	void Close()
	{
		Ctl.Closed(Now);
		Frame();
	}
}

// Lines that hold the whole plan, one token per key (LINES_INI of main_test.lua).
FLPH_Values LPHTests_CtlLines()
{
	FLPH_Values Values;
	Values.bTape = false;
	Values.PerLine = 40;
	Values.MaxLines = 12;
	Values.CollapseMin = 0;
	return Values;
}

// The same with auto-pick always on.
FLPH_Values LPHTests_CtlAlways()
{
	FLPH_Values Values = LPHTests_CtlLines();
	Values.bAutoPick = true;
	return Values;
}

ULPH_CtlRig LPHTests_CtlRig(UObject Outer, ULPH_LockDb Db, FLPH_Values Values)
{
	ULPH_CtlRig Rig = Cast<ULPH_CtlRig>(NewObject(Outer, ULPH_CtlRig::StaticClass()));
	Rig.Ctl = Cast<ULPH_Controller>(NewObject(Rig, ULPH_Controller::StaticClass()));
	Rig.Log = Cast<ULPH_Log>(NewObject(Rig, ULPH_Log::StaticClass())); // not opened: keeps nothing
	Rig.Ctl.Init(Db, Rig.Log);
	TArray<FString> Letters;
	Rig.Ctl.Configure(Values, ELPH_Lang::En, Letters);
	Rig.Game = Cast<ULPH_CtlGame>(NewObject(Rig, ULPH_CtlGame::StaticClass()));
	return Rig;
}

// The small locks of these tests.
ULPH_LockDb LPHTests_CtlDb(UObject Outer)
{
	ULPH_LockDb Db = LPHTests_MakeLockDb(Outer);
	// Three plates: plate 0 pushes plate 1 with it, plate 1 pushes plate 2 against it (the first connection goes at
	// lockpicking skill 1). The same plates again under two more names (the cache tests).
	Db.AddLock(n"LPHTest_Three", 3);
	Db.AddEdge(0, 1, 1);
	Db.AddEdge(1, 2, -1);
	Db.AddLock(n"LPHTest_Second", 3);
	Db.AddEdge(0, 1, 1);
	Db.AddEdge(1, 2, -1);
	Db.AddLock(n"LPHTest_Third", 3);
	Db.AddEdge(0, 1, 1);
	Db.AddEdge(1, 2, -1);
	// Two plates that push each other four holes: every move from the open lock strains, so no other state has a safe path.
	Db.AddLock(n"LPHTest_Stuck", 2);
	for (int i = 0; i < 4; i++)
	{
		Db.AddEdge(0, 1, 1);
		Db.AddEdge(1, 0, 1);
	}
	// Two plates without connections (a plan of three keys for the auto-pick timer).
	Db.AddLock(n"LPHTest_Two", 2);
	return Db;
}

// The seconds the auto-pick counter shows for the keys Plan[From..] (eta_seconds of main_test.lua 1.2.0): an A/D counts
// SolveEtaAdMs, a W/S SolveEtaWsMs, rounded up to a second, at least 1.
int LPHTests_EtaSeconds(FString Plan, int From)
{
	int Ms = 0;
	for (int i = From; i < Plan.Len(); i++)
	{
		FString Letter = Plan.Mid(i, 1);
		if (Letter == "A" || Letter == "D")
			Ms += LPH::SolveEtaAdMs;
		else
			Ms += LPH::SolveEtaWsMs;
	}
	return Math::Max(Math::IntegerDivisionTrunc(Ms + 999, 1000), 1);
}

// The seconds of an auto-pick counter text with the timer (-1: not such a text).
int LPHTests_SolvingSeconds(FString Text, const FLPH_Texts& X)
{
	for (int Seconds = 1; Seconds < 100; Seconds++)
	{
		if (Text == LPH::Fill(X.SolvingTime, f"{Seconds}"))
			return Seconds;
	}
	return -1;
}

// The autosolver's state: "off", "armed" or "running".
FString LPHTests_CtlAuto(ULPH_CtlRig Rig)
{
	return LPHTests_StateName(Rig.Ctl.Auto.GetState());
}

// A ready solver of the lock as the game plays it (the first Removed connections dropped).
ULPH_Solver LPHTests_CtlRules(UObject Outer, ULPH_LockDb Db, FName Lock, int Removed)
{
	FLPH_LockGraph Graph;
	int Dropped = 0;
	Db.Find(Lock, Removed, Graph, Dropped);
	return LPHTests_ReadySolver(Outer, Graph);
}

TArray<int> LPHTests_Holes7(int A, int B, int C, int D, int E, int F, int G)
{
	TArray<int> Holes;
	Holes.Add(A);
	Holes.Add(B);
	Holes.Add(C);
	Holes.Add(D);
	Holes.Add(E);
	Holes.Add(F);
	Holes.Add(G);
	return Holes;
}

// What is shown, as text: "hidden", "hint" or "message: <its text>".
FString LPHTests_CtlKind(const FLPH_Display& D)
{
	if (D.Kind == ELPH_DisplayKind::Hint)
		return "hint";
	if (D.Kind == ELPH_DisplayKind::Message)
		return "message: " + D.Message;
	return "hidden";
}

// The plan the hint shows from the current key on (the lines' tokens, or the tape's current and next cells), as letters.
FString LPHTests_CtlPlan(const FLPH_Display& D)
{
	FString Text;
	bool bOn = false;
	for (int Row = 0; Row < D.Hint.Lines.Num(); Row++)
	{
		for (int At = 0; At < D.Hint.Lines[Row].Tokens.Num(); At++)
		{
			if (D.Hint.Lines[Row].Tokens[At].Role == ELPH_Role::Current)
				bOn = true;
			if (bOn)
				Text += D.Hint.Lines[Row].Tokens[At].Text;
		}
	}
	for (int At = 0; At < D.Hint.Cells.Num(); At++)
	{
		if (D.Hint.Cells[At].Role == ELPH_Role::Current || D.Hint.Cells[At].Role == ELPH_Role::Next)
			Text += D.Hint.Cells[At].Text;
	}
	return Text;
}

// The key the hint shows now. False when it shows none (no hint, or the keys are used up).
bool LPHTests_CtlCurrent(const FLPH_Display& D, ELPH_Key& OutKey)
{
	if (D.Kind != ELPH_DisplayKind::Hint)
		return false;
	for (int Row = 0; Row < D.Hint.Lines.Num(); Row++)
	{
		for (int At = 0; At < D.Hint.Lines[Row].Tokens.Num(); At++)
		{
			if (D.Hint.Lines[Row].Tokens[At].Role == ELPH_Role::Current)
			{
				OutKey = D.Hint.Lines[Row].Tokens[At].Key;
				return true;
			}
		}
	}
	for (int At = 0; At < D.Hint.Cells.Num(); At++)
	{
		if (D.Hint.Cells[At].Role == ELPH_Role::Current && D.Hint.Cells[At].bHasKey)
		{
			OutKey = D.Hint.Cells[At].Key;
			return true;
		}
	}
	return false;
}

// Opens the lock, waits for the hint, keeps the session's solver, closes the minigame. Returns that solver.
ULPH_Solver LPHTests_CtlVisit(ULPH_TestRun T, ULPH_CtlRig Rig, FName Lock, float Precision, ULPH_Solver Rules, const TArray<int>& From)
{
	Rig.Open(Lock, Precision, Rules, From);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint of " + Lock.ToString());
	ULPH_Solver Used = Rig.Ctl.Solver;
	Rig.Close();
	return Used;
}

void LPHTests_Controller(ULPH_TestRun T)
{
	ULPH_LockDb Db = LPHTests_CtlDb(T);
	ULPH_Solver Three = LPHTests_CtlRules(T, Db, n"LPHTest_Three", 0);
	TArray<int> Start = LPHTests_Holes3(3, 5, 4);
	T.Begin("Controller fixtures");
	T.True(Three.IsReady(), "the three-plate rules are ready");
	T.True(LPHTests_Plan(Three, Start, 0) != "nil", "the three-plate lock has a safe path from the start");

	LPHTests_ControllerReady(T, Db, Three, Start);
	LPHTests_ControllerPresses(T, Db, Three, Start);
	LPHTests_ControllerNoHint(T, Db, Three, Start);
	LPHTests_ControllerToggle(T, Db, Three, Start);
	LPHTests_ControllerSig(T, Db, Three, Start);
	LPHTests_ControllerCache(T, Db, Three, Start);
	LPHTests_ControllerSeven(T);
	LPHTests_ControllerSolve(T, Db, Three, Start);
	LPHTests_ControllerEarly(T, Db, Three, Start);
	LPHTests_ControllerStops(T, Db, Three, Start);
	LPHTests_ControllerDoubleReset(T, Db, Three, Start);
	LPHTests_ControllerCountdown(T, Db, Three, Start);
	LPHTests_ControllerNoAuto(T, Db, Three, Start);
	LPHTests_ControllerDisplaySig(T, Db, Three, Start);
}

// 1.x: "hint appears after the ready delay", "the hint waits for ready_frames frames even when the clock jumps", and the
// two equal settled readings of tick().
void LPHTests_ControllerReady(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FString Plan = LPHTests_Plan(Three, Start, 0);
	int Total = Plan.Len();

	T.Begin("Controller 01 the hint shows after the ready delay, from the solver's plan");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs - 10);
	T.True(Rig.FirstShownMs < 0, "nothing shown before the ready delay");
	Rig.Run(100);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint after the ready delay");
	T.True(Rig.FirstShownMs >= LPH::ReadyDelayMs, "the hint not before the ready delay");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Plan, "the keys are the solver's plan from plate 0");
	T.EqualStr(Rig.Shown.Hint.Counter, f"0/{Total}", "counter");
	T.True(Rig.Shown.Hint.bLines, "lines, as configured");

	T.Begin("Controller 02 the hint waits for ReadyFrames frames when the clock jumps (a loading freeze)");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.FrameMs = 1000;
	for (int i = 0; i < 10; i++)
		Rig.Frame();
	T.True(Rig.FirstShownMs < 0, "nothing after 10 long frames");
	T.True(Rig.SettledReads >= 2, "(the plates were read and settled meanwhile)");
	Rig.FrameMs = 10;
	for (int i = 0; i < 25; i++)
		Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint once enough frames passed");

	T.Begin("Controller 03 the hint waits for two equal settled readings in a row");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Game.MovingUntilMs = LPH::ReadyDelayMs + 400; // the plates still move
	Rig.Run(LPH::ReadyDelayMs + 390);
	T.True(Rig.FirstShownMs < 0, "nothing while the plates move");
	T.EqualInt(Rig.SettledReads, 0, "(no settled reading yet)");
	Rig.RunSettled(1);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "one settled reading is not enough");
	TArray<int> Other = LPHTests_Holes3(3, 5, 5);
	Rig.Game.Holes = Other; // a move ends between two readings
	Rig.RunSettled(1);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "two settled readings that differ are not enough");
	Rig.RunSettled(1);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "two equal settled readings in a row");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), LPHTests_Plan(Three, Other, 0), "the plan from the holes read");

	T.Begin("Controller 04 the plates are read once per PollMs, and only once the lock is prepared");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.OpenBare();
	Rig.Run(300);
	T.EqualInt(Rig.Reads, 0, "no reading before the lock is known");
	Rig.Game.Begin(Three, Start, Rig.Now);
	Rig.Ctl.LockFound(n"LPHTest_Three", 0.0, Rig.Now);
	T.True(!Rig.Ctl.WantsReading(Rig.Now), "no reading while the solver prepares");
	Rig.Run(LPH::ReadyDelayMs);
	int Before = Rig.Reads;
	Rig.Run(500);
	int Reads = Rig.Reads - Before;
	T.True(Reads >= 9 && Reads <= 11, f"plates read {Reads} times in 500 ms of 10 ms frames");
}

// 1.x: "hint appears ... and opens the lock", "a press is shown in the next frame", "a wrong key is a miss", "W pressed
// before the hint parks the cursor", "a partial plate reading never counts as solved".
void LPHTests_ControllerPresses(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FString Plan = LPHTests_Plan(Three, Start, 0);
	int Total = Plan.Len();

	T.Begin("Controller 05 a press shows in the next frame; following the hint opens the lock");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	ELPH_Key Key = ELPH_Key::R;
	T.True(LPHTests_CtlCurrent(Rig.Shown, Key), "a current key");
	Rig.Press(Key);
	Rig.Frame();
	T.EqualStr(Rig.Shown.Hint.Counter, f"1/{Total}", "counter after one frame");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Plan.Mid(1, Total - 1), "the rest of the plan");
	int Presses = 1;
	for (int Guard = 0; Guard < 200 && Rig.Shown.Kind == ELPH_DisplayKind::Hint; Guard++)
	{
		if (LPHTests_CtlCurrent(Rig.Shown, Key))
		{
			Rig.Press(Key);
			Presses++;
		}
		Rig.Run(400);
	}
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "hidden once the lock is open");
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "the game's plates");
	T.EqualInt(Rig.Game.Strains, 0, "strains");
	T.EqualInt(Presses, Total, "every key of the plan pressed once");

	T.Begin("Controller 06 a wrong key is a miss and the hint is worked out again");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.True(LPHTests_CtlCurrent(Rig.Shown, Key), "a current key");
	ELPH_Key Wrong = ELPH_Key::W;
	if (Key == ELPH_Key::W)
		Wrong = ELPH_Key::S;
	Rig.Press(Wrong);
	Rig.Frame();
	T.EqualInt(Rig.Shown.Hint.Misses, 1, "misses");
	FString Again = LPHTests_Plan(Three, Rig.Game.Holes, Rig.Game.Cursor);
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Again, "the plan from where the wrong key left the pick");
	T.EqualStr(Rig.Shown.Hint.Counter, f"0/{Again.Len()}", "counter of the new plan");

	T.Begin("Controller 07 W before the hint: parked first without a highlight, from the highlight with one");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Game.bHighlight = false;
	Rig.Run(1000);
	Rig.Press(ELPH_Key::W); // the game is not ready yet and ignores it
	T.EqualInt(Rig.Game.Swallowed, 1, "(the game ignored the W)");
	Rig.Run(LPH::ReadyDelayMs);
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), "SS" + Plan, "parked: the cursor is not known");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(1000);
	Rig.Press(ELPH_Key::W);
	Rig.Run(LPH::ReadyDelayMs);
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Plan, "the highlighted plate is the cursor: no parking");
	T.EqualStr(Rig.Shown.Hint.Counter, f"0/{Total}", "counter");
	T.EqualStr(LPHTests_CtlPlan(Rig.FirstShown), Plan, "no parking in the first frame of the hint either");

	T.Begin("Controller 08 a partial reading while tracking never counts as solved");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	Rig.Game.Holes = LPHTests_Holes2(4, 4); // one plate missing from the reading
	Rig.Game.Visible = 2;
	Rig.Run(300);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "still the hint");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Plan, "the same plan");
}

// 1.x: "unknown lock shows a message", "plate count different from the database shows a message", "with [solve] auto an
// unlocked chest or door ... shows no note", the tracker's NoSafePath, "closing the minigame hides the hint".
void LPHTests_ControllerNoHint(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);
	FLPH_Texts Ru = LPH::Texts(ELPH_Lang::Ru);
	TArray<FString> Letters;

	T.Begin("Controller 09 a lock that is not in the database: a message with its name");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"Nope_Lock", 0.0, nullptr, Start);
	Rig.Run(100);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.NotInDb, "Nope_Lock"), "the message");
	T.True(!Rig.Ctl.WantsReading(Rig.Now), "no readings for it");
	Rig.Press(ELPH_Key::W);
	Rig.Run(LPH::ReadyDelayMs + 500);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.NotInDb, "Nope_Lock"), "the message stays");
	T.EqualInt(Rig.Reads, 0, "no plates read");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Ctl.Configure(LPHTests_CtlLines(), ELPH_Lang::Ru, Letters);
	Rig.Open(n"Nope_Lock", 0.0, nullptr, Start);
	Rig.Run(100);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(Ru.NotInDb, "Nope_Lock"), "in Russian");

	T.Begin("Controller 10 no lock (an unlocked chest or door): nothing at all, not even an armed auto-pick");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlAlways());
	Rig.OpenBare();
	T.EqualStr(LPHTests_CtlAuto(Rig), "armed", "(auto-pick always arms it)");
	Rig.Run(500);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "nothing while the lock is not known");
	Rig.Ctl.NoLock(Rig.Now);
	Rig.Run(LPH::ReadyDelayMs + 2000);
	T.True(Rig.FirstShownMs < 0, "nothing shown at all");
	T.True(Rig.Ctl.Auto.GetState() == ELPH_AutoState::Off, "the armed autosolver is dropped");
	T.EqualInt(Rig.Reads, 0, "no plates read");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlAlways());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(100);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveArmed, "(an armed autosolver on a known lock says it waits)");

	T.Begin("Controller 11 visible plates other than the database's: a message, no tracking");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, LPHTests_Holes2(3, 5));
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.BadState, "two plates of three");
	T.True(!Rig.Ctl.WantsReading(Rig.Now), "no more readings");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Game.Visible = 4;
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.BadState, "four plates of three");

	T.Begin("Controller 12 no safe path from the start: the tracker's message");
	ULPH_Solver Stuck = LPHTests_CtlRules(T, Db, n"LPHTest_Stuck", 0);
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Stuck", 0.0, Stuck, LPHTests_Holes2(3, 4));
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.NoSafePath, "the message");

	T.Begin("Controller 13 closing the minigame hides the hint and ends the session");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	Rig.Close();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "hidden after Closed");
	T.True(!Rig.Ctl.WantsReading(Rig.Now), "no readings");
	int Redraws = Rig.Redraws;
	Rig.Ctl.PlayerKey(ELPH_Key::D, Rig.Now);
	Rig.Run(500);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "still hidden");
	T.EqualInt(Rig.Redraws, Redraws, "nothing to redraw after the session ended");
	T.True(Rig.Ctl.Auto.GetState() == ELPH_AutoState::Off, "the autosolver is off");
}

// 1.x: "toggle key hides and shows the hint", "a toggle outside a minigame shows the note and then hides it".
void LPHTests_ControllerToggle(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);

	T.Begin("Controller 14 F4 hides and shows the hint, with a note for ToggleNoteMs");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(50);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.HintOff, "F4"), "the note after the first toggle");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "hidden after the note");
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(50);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.HintOn, "F4"), "the note after the second toggle");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint is back after the note");

	T.Begin("Controller 15 F4 outside a minigame: the note, then nothing");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Run(100);
	T.True(Rig.FirstShownMs < 0, "nothing shown");
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(50);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.HintOff, "F4"), "off note");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "hidden after the note");
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(50);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.HintOn, "F4"), "on note");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "hidden again");
}

// The display's signature (render's of 1.x) and the hint's layout from Configure.
void LPHTests_ControllerSig(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FString Plan = LPHTests_Plan(Three, Start, 0);
	TArray<FString> Letters;

	T.Begin("Controller 16 the Sig stays without changes and changes with a press, Configure and the icons");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	FString Sig = Rig.Shown.Sig;
	int Builds = Rig.Ctl.ModelBuilds;
	int Redraws = Rig.Redraws;
	Rig.Run(500);
	T.EqualStr(Rig.Shown.Sig, Sig, "the same Sig without changes");
	T.EqualInt(Rig.Ctl.ModelBuilds, Builds, "the model is not built again without changes");
	T.EqualInt(Rig.Redraws, Redraws, "nothing to redraw");
	ELPH_Key Key = ELPH_Key::R;
	LPHTests_CtlCurrent(Rig.Shown, Key);
	Rig.Press(Key);
	Rig.Frame();
	T.True(Rig.Shown.Sig != Sig, "a press changes the Sig");
	T.EqualInt(Rig.Ctl.ModelBuilds, Builds + 1, "and builds the model once");
	Sig = Rig.Shown.Sig;
	Rig.Run(800);
	T.EqualStr(Rig.Shown.Sig, Sig, "the plates confirming the press change nothing");
	TArray<FString> Same;
	Rig.Ctl.Configure(LPHTests_CtlLines(), ELPH_Lang::En, Same);
	Rig.Frame();
	T.True(Rig.Shown.Sig != Sig, "Configure changes the Sig (the settings may be new)");
	Sig = Rig.Shown.Sig;
	Rig.Ctl.SetIcons(1);
	Rig.Frame();
	T.True(Rig.Shown.Sig != Sig, "another icon set changes the Sig");
	Sig = Rig.Shown.Sig;
	Rig.Ctl.SetIcons(1);
	Rig.Frame();
	T.EqualStr(Rig.Shown.Sig, Sig, "the same icon set does not");
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Frame();
	Sig = Rig.Shown.Sig;
	Rig.Run(500);
	T.EqualStr(Rig.Shown.Sig, Sig, "a message keeps its Sig");
	Rig.Close();
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(Rig.Shown.Sig, "hidden", "the Sig of nothing shown");

	T.Begin("Controller 17 tape or lines, their sizes and the labels come from Configure");
	FLPH_Values Tape; // the defaults: tape, 5 next, 3 done
	Rig = LPHTests_CtlRig(T, Db, Tape);
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	T.True(!Rig.Shown.Hint.bLines, "a tape");
	T.EqualInt(Rig.Shown.Hint.Cells.Num(), Tape.TapeDone + 1 + Tape.TapeNext, "its cells");
	bool bCurrentAfterDone = Rig.Shown.Hint.Cells.Num() > Tape.TapeDone
		&& Rig.Shown.Hint.Cells[Tape.TapeDone].Role == ELPH_Role::Current;
	T.True(bCurrentAfterDone, "the current key after the done cells");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Plan.Mid(0, Tape.TapeNext + 1), "the current key and the next ones");
	Rig.Ctl.Configure(LPHTests_CtlLines(), ELPH_Lang::En, Letters);
	Rig.Frame();
	T.True(Rig.Shown.Hint.bLines, "lines after Configure");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Plan, "the whole plan");
	FLPH_Values Short;
	Short.TapeNext = 2;
	Short.TapeDone = 1;
	TArray<FString> Words;
	Words.Add("Up");
	Words.Add("Down");
	Words.Add("Left");
	Words.Add("Right");
	Rig.Ctl.Configure(Short, ELPH_Lang::En, Words);
	Rig.Frame();
	T.EqualInt(Rig.Shown.Hint.Cells.Num(), 4, "a shorter tape");
	ELPH_Key Key2 = ELPH_Key::R;
	T.True(LPHTests_CtlCurrent(Rig.Shown, Key2), "a current key");
	FString Label = "";
	if (Rig.Shown.Hint.Cells.Num() > 1)
		Label = Rig.Shown.Hint.Cells[1].Text;
	T.EqualStr(Label, LPH::KeyLabel(Key2, Words), "the current key's label");
	T.True(Label.Len() > 1, "(a label, not a letter)");
}

// 1.x: "solver cache keeps the two most recently used locks", "the solver cache keys on the lock and the skill".
void LPHTests_ControllerCache(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	T.Begin("Controller 18 the cache keeps the solvers of the two most recently used locks");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	ULPH_Solver A1 = LPHTests_CtlVisit(T, Rig, n"LPHTest_Three", 0.0, Three, Start);
	ULPH_Solver B1 = LPHTests_CtlVisit(T, Rig, n"LPHTest_Second", 0.0, Three, Start);
	ULPH_Solver A2 = LPHTests_CtlVisit(T, Rig, n"LPHTest_Three", 0.0, Three, Start);
	ULPH_Solver C1 = LPHTests_CtlVisit(T, Rig, n"LPHTest_Third", 0.0, Three, Start);
	ULPH_Solver A3 = LPHTests_CtlVisit(T, Rig, n"LPHTest_Three", 0.0, Three, Start);
	ULPH_Solver B2 = LPHTests_CtlVisit(T, Rig, n"LPHTest_Second", 0.0, Three, Start);
	T.True(A1 != nullptr && B1 != nullptr && C1 != nullptr, "(each session had a solver)");
	T.True(A1 != B1 && A1 != C1 && B1 != C1, "one solver per lock");
	T.True(A2 == A1, "the first lock again: its solver from the cache");
	T.True(A3 == A1, "still cached after a third lock (it was used after the second)");
	T.True(B2 != B1, "the second lock was the least recently used: prepared again");

	T.Begin("Controller 19 the cache keys on the lock and the connections the skill removes");
	ULPH_Solver Pruned = LPHTests_CtlRules(T, Db, n"LPHTest_Three", 1);
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	ULPH_Solver Skill0 = LPHTests_CtlVisit(T, Rig, n"LPHTest_Three", 0.0, Three, Start);
	Rig.Open(n"LPHTest_Three", 1.0, Pruned, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), LPHTests_Plan(Pruned, Start, 0), "skill 1: the plan without the first connection");
	T.True(LPHTests_Plan(Pruned, Start, 0) != LPHTests_Plan(Three, Start, 0), "(the two plans differ)");
	ULPH_Solver Skill1 = Rig.Ctl.Solver;
	Rig.Close();
	ULPH_Solver Skill0Again = LPHTests_CtlVisit(T, Rig, n"LPHTest_Three", 0.4, Three, Start);
	T.True(Skill1 != Skill0, "another skill, another solver");
	T.True(Skill0Again == Skill0, "skill 0 again (0.4 rounds to 0): from the cache");
}

// 2.0: Thinking while a 7-plate lock of the real database prepares, and the same lock again from the cache.
void LPHTests_ControllerSeven(ULPH_TestRun T)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);
	ULPH_LockDb Real = LPHTests_MakeLockDb(T);
	LPH_RegisterLockGraphs(Real);
	// OC_Chest_Kirgo_Lock, skill 0, cursor 0: the reference keys of the 1.2.0 solver (GoldenSolver.as).
	TArray<int> Start = LPHTests_Holes7(5, 5, 4, 6, 5, 1, 7);
	FString Golden = "AAAAWAAWDDWAAAAAWAAAAWDDDWAAASSSSD";

	T.Begin("Controller 20 a 7-plate lock at 1 ms a frame: Thinking after the ready delay, then the hint");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Real, LPHTests_CtlLines());
	Rig.Ctl.BudgetMs = 1;
	Rig.FrameMs = 50;
	Rig.Open(n"OC_Chest_Kirgo_Lock", 0.0, nullptr, Start);
	bool bEarly = false;
	int64 ThinkingFrom = -1;
	for (int Guard = 0; Guard < 5000 && Rig.Shown.Kind != ELPH_DisplayKind::Hint; Guard++)
	{
		Rig.Frame();
		if (Rig.Now < LPH::ReadyDelayMs && Rig.Shown.Kind != ELPH_DisplayKind::Hidden)
			bEarly = true;
		if (ThinkingFrom < 0 && LPHTests_CtlKind(Rig.Shown) == "message: " + En.Thinking)
			ThinkingFrom = Rig.Now;
	}
	T.True(!bEarly, "nothing before the ready delay");
	T.True(ThinkingFrom >= LPH::ReadyDelayMs, f"Thinking from the ready delay on (from {ThinkingFrom} ms)");
	T.True(ThinkingFrom < LPH::ReadyDelayMs + 100, "Thinking at once after the ready delay");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "then the hint");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Golden, "the keys of 1.2.0");
	T.True(Rig.Ctl.PrepareTicks > 1, f"prepared over several frames ({Rig.Ctl.PrepareTicks})");
	ULPH_Solver First = Rig.Ctl.Solver;

	T.Begin("Controller 21 the same lock again: the solver from the cache, ready at once");
	Rig.Close();
	int64 OpenedAt = Rig.Now;
	Rig.Open(n"OC_Chest_Kirgo_Lock", 0.0, nullptr, Start);
	T.True(Rig.Ctl.Solver == First, "the same solver");
	T.True(Rig.Ctl.Solver != nullptr && Rig.Ctl.Solver.IsReady(), "ready");
	bool bMessage = false;
	for (int Guard = 0; Guard < 5000 && Rig.Shown.Kind != ELPH_DisplayKind::Hint; Guard++)
	{
		Rig.Frame();
		if (Rig.Shown.Kind == ELPH_DisplayKind::Message)
			bMessage = true;
	}
	T.True(!bMessage, "no Thinking (no message at all)");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	int64 After = Rig.FirstShownMs - OpenedAt;
	T.True(After >= LPH::ReadyDelayMs && After <= LPH::ReadyDelayMs + 150, f"the hint right after the ready delay ({After} ms)");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Golden, "the keys of 1.2.0");
}

// 1.x: "F3 opens the lock: the autosolver presses the hint without strain", "F3 again stops the autosolver; the hint
// stays", "F3 before the minigame is ready waits for the lock, then solves it", "with the hint hidden the autosolver solves
// with a short note only", "F3 again with the hint hidden notes the stop".
void LPHTests_ControllerSolve(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);
	FString Plan = LPHTests_Plan(Three, Start, 0);
	int Total = Plan.Len();

	T.Begin("Controller 22 F3 in a ready minigame: the autosolver presses the hint at its pace and opens the lock");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	T.True(!Rig.Shown.Hint.bCounterAlways, "the plain hint's counter follows the setting");
	Rig.Solve();
	Rig.Frame();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlAuto(Rig), "running", "running");
	T.EqualInt(Rig.OwnKeys.Num(), 1, "the first key at once");
	int Eta = LPHTests_EtaSeconds(Plan, 1);
	T.EqualStr(Rig.Shown.Hint.Counter, LPH::Fill(En.SolvingTime, f"{Eta}"), "the counter says how long it needs");
	T.True(Rig.Shown.Hint.bCounterAlways, "shown whatever the counter setting");
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "plates");
	T.EqualInt(Rig.Game.Strains, 0, "strains");
	T.EqualStr(LPH::KeysText(Rig.OwnKeys), Plan, "pressed exactly the hint");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "the hint is gone");
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "off once the lock is open");
	T.True(!Rig.Saw(En.SolveStopped), "no stop note");
	T.True(Rig.WsGaps > 0 && Rig.MoveGaps > 0, f"(keys after a W/S: {Rig.WsGaps}, after an A/D: {Rig.MoveGaps})");
	T.EqualInt(Rig.MinWsGapMs, LPH::SolveWsGapMs, "after a W/S the next key comes SolveWsGapMs later, not sooner");
	T.EqualInt(Rig.MovesUnseen, 0, "after an A/D the next key only once a reading has shown the move");
	int Sent = Rig.OwnKeys.Num();
	Rig.Run(1000);
	T.EqualInt(Rig.OwnKeys.Num(), Sent, "nothing more");

	T.Begin("Controller 23 F3 again stops the autosolver; the hint and its counter stay");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	Rig.Run(500);
	int Pressed = Rig.OwnKeys.Num();
	T.True(Pressed > 0 && Pressed < Total, f"(it pressed {Pressed} of {Total})");
	Rig.Solve();
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "off");
	Rig.Run(3000);
	T.EqualInt(Rig.OwnKeys.Num(), Pressed, "no keys after the second F3");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	T.EqualStr(Rig.Shown.Hint.Counter, f"{Pressed}/{Total}", "the counter is back");
	T.True(!Rig.Shown.Hint.bCounterAlways, "and follows the setting again");
	T.EqualInt(Rig.Messages.Num(), 0, "no note while the hint is shown");

	T.Begin("Controller 24 F3 before the minigame is ready arms the autosolver: it waits for the lock, then solves it");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	int64 OpenedAt = Rig.Now;
	Rig.OpenBare();
	Rig.Run(200);
	Rig.Solve();
	T.EqualStr(LPHTests_CtlAuto(Rig), "armed", "armed");
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "nothing while the lock is not known");
	Rig.Game.Begin(Three, Start, OpenedAt);
	Rig.Ctl.LockFound(n"LPHTest_Three", 0.0, Rig.Now);
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveArmed, "it waits once the lock is known");
	Rig.Run(LPH::ReadyDelayMs - 500);
	T.EqualInt(Rig.OwnKeys.Num(), 0, "nothing pressed before the minigame is ready");
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "plates");
	T.EqualInt(Rig.Game.Strains, 0, "strains");
	T.EqualInt(Rig.Game.Swallowed, 0, "no key the game ignored");
	T.EqualStr(LPH::KeysText(Rig.OwnKeys), Plan, "the hint's keys");

	T.Begin("Controller 25 with the hint hidden F3 shows only a note: on, then off");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(LPH::ToggleNoteMs + 50);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "hidden");
	int Redraws = Rig.Redraws;
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.SolveOn, "F3"), "the note");
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "plates");
	T.EqualInt(Rig.Redraws, Redraws + 2, "the note and its end only");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "hidden");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(LPH::ToggleNoteMs + 50);
	Rig.Solve();
	Rig.Run(1000);
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.SolveOff, "F3"), "the note of the stop");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "hidden again");
}

// 1.x: "F3 just before a minigame opens arms it: the lock is solved", "F3 outside a minigame waits solve_early_ms; F3 again
// cancels", "with [solve] auto every lock is solved as it opens", "with [solve] auto F3 outside a minigame skips the next
// one; F3 twice goes back to the setting", "F3 outside a minigame with the hint hidden notes the wait".
void LPHTests_ControllerEarly(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);

	T.Begin("Controller 26 F3 outside a minigame arms the one that opens within SolveEarlyMs");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveArmed, "it waits for the lock");
	Rig.Run(4000);
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.EqualStr(LPHTests_CtlAuto(Rig), "armed", "the minigame 4 s later is armed");
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveArmed, "and says so once its lock is known");
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "solved");
	T.EqualInt(Rig.Game.Strains, 0, "strains");
	Rig.Close();
	Rig.Solve();
	Rig.Run(LPH::SolveEarlyMs - 100);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveArmed, "(still waiting)");
	Rig.Run(1100);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "the wait is over");
	int Sent = Rig.OwnKeys.Num();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "the minigame 6 s later is not armed");
	Rig.Run(LPH::ReadyDelayMs + 1000);
	T.EqualInt(Rig.OwnKeys.Num(), Sent, "nothing pressed");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "just the hint");
	Rig.Close();
	Rig.Solve();
	Rig.Frame();
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "F3 twice: no wait shown");
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "and the next minigame is not armed");
	Rig.Close();

	T.Begin("Controller 27 auto-pick always: every minigame is armed; F3 outside skips the next one, F3 twice goes back");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlAlways());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.EqualStr(LPHTests_CtlAuto(Rig), "armed", "armed at the start");
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveArmed, "it says so once the lock is known");
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "solved");
	Rig.Close();
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.SolveOff, "F3"), "note: the next one is skipped");
	Rig.Run(1000);
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "the next minigame is not armed");
	Sent = Rig.OwnKeys.Num();
	Rig.Run(LPH::ReadyDelayMs + 1000);
	T.EqualInt(Rig.OwnKeys.Num(), Sent, "nothing pressed");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "just the hint");
	Rig.Close();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.EqualStr(LPHTests_CtlAuto(Rig), "armed", "the one after it is armed, as set");
	Rig.Close();
	Rig.Solve();
	Rig.Frame();
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.SolveOn, "F3"), "F3 twice: note: back to the setting");
	Rig.Run(1000);
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.EqualStr(LPHTests_CtlAuto(Rig), "armed", "armed, as set");
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "solved");

	T.Begin("Controller 28 F3 outside a minigame with the hint hidden: a note");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(LPH::ToggleNoteMs + 50);
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.SolveOn, "F3"), "the note");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "then nothing (the hint is hidden)");
}

// 1.x: "a player press stops the autosolver and the hint follows the player", "presses the game swallows stop the
// autosolver with a note", "a hook that does not fire for our own call stops the autosolver", "closing the minigame during
// an autosolve: no more calls into the task"; and the A/D timeout, a player's press while the solver prepares (Review
// Focus 5), the minigame closed in the middle of auto-pick (Review Focus 1).
void LPHTests_ControllerStops(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);
	FString Plan = LPHTests_Plan(Three, Start, 0);
	int Total = Plan.Len();

	T.Begin("Controller 29 a player press stops the autosolver; the hint follows the player");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	Rig.Run(500);
	int Pressed = Rig.OwnKeys.Num();
	T.True(Pressed > 0, "(it pressed)");
	ELPH_Key Key = ELPH_Key::R;
	T.True(LPHTests_CtlCurrent(Rig.Shown, Key), "a current key");
	Rig.Press(Key);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "stopped");
	FString Letter = LPH::KeyLetter(Key);
	T.True(Rig.Logged(f"autosolve: cancelled by a player press ({Letter})"), "logged");
	Rig.Run(3000);
	T.EqualInt(Rig.OwnKeys.Num(), Pressed, "only the player's press after it");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint stays");
	T.EqualStr(Rig.Shown.Hint.Counter, f"{Pressed + 1}/{Total}", "the player's press counted");
	T.EqualInt(Rig.Game.Strains, 0, "strains");
	T.True(!Rig.Saw(En.SolveStopped), "no stop note");

	T.Begin("Controller 30 a player press while the solver still prepares neither starts nor breaks auto-pick");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.True(Rig.Ctl.Solver != nullptr && !Rig.Ctl.Solver.IsReady(), "(the solver prepares)");
	Rig.Press(ELPH_Key::W);
	Rig.Press(ELPH_Key::R);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "the presses do not start it");
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Plan, "from the plate the game highlights");
	T.EqualInt(Rig.OwnKeys.Num(), 0, "nothing pressed by itself");
	Rig.Solve();
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "F3 then opens the lock");
	T.EqualInt(Rig.Game.Strains, 0, "strains");
	T.EqualStr(LPH::KeysText(Rig.OwnKeys), Plan, "with the hint's keys");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlAlways());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.True(Rig.Ctl.Solver != nullptr && !Rig.Ctl.Solver.IsReady(), "(armed, the solver prepares)");
	Rig.Press(ELPH_Key::W);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "a press stops an armed autosolver (any press of the player, as 1.x)");
	T.True(Rig.Logged("autosolve: cancelled by a player press (W)"), "logged");
	Rig.Run(LPH::ReadyDelayMs + 1000);
	T.EqualInt(Rig.OwnKeys.Num(), 0, "nothing pressed by itself");
	T.EqualStr(LPHTests_CtlPlan(Rig.Shown), Plan, "the hint from the plate the game highlights");
	Rig.Solve();
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "F3 opens the lock");
	T.EqualInt(Rig.Game.Strains, 0, "strains");

	T.Begin("Controller 31 an A/D the plates never show stops the autosolver after SolveTimeoutMs, with a note");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Game.bFreeze = true;
	Rig.Solve();
	for (int Guard = 0; Guard < 1000 && Rig.FirstOwnMoveMs < 0; Guard++)
		Rig.Frame();
	T.True(Rig.FirstOwnMoveMs >= 0, "(it pressed an A/D)");
	int Sent = Rig.OwnKeys.Num();
	int Left = int(Rig.FirstOwnMoveMs + LPH::SolveTimeoutMs - Rig.Now);
	Rig.Run(Left - 100);
	T.EqualStr(LPHTests_CtlAuto(Rig), "running", "still waiting just before the timeout");
	Rig.Run(200);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "stopped after it");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveStopped, "the note");
	T.True(Rig.Logged("autosolve stopped: timeout"), "logged");
	T.EqualInt(Rig.OwnKeys.Num(), Sent, "nothing pressed while it waited");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint after the note");

	T.Begin("Controller 32 keys the game swallows: the replans stop the autosolver with a note");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Game.ReadyMs = 1000000000;
	Rig.Solve();
	bool bNoted = false;
	for (int Guard = 0; Guard < 2000 && !bNoted; Guard++)
	{
		Rig.Frame();
		bNoted = LPHTests_CtlKind(Rig.Shown) == "message: " + En.SolveStopped;
	}
	T.True(bNoted, "the note");
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "stopped");
	T.True(Rig.Logged("autosolve stopped: replans"), "logged");
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "3 5 4", "nothing moved");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint after the note");

	T.Begin("Controller 33 its own key that does not reach the handler stops the autosolver with a note; the hint counts it");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.bOwnLost = true;
	Rig.Solve();
	Rig.Frame();
	Rig.Frame();
	T.EqualInt(Rig.OwnKeys.Num(), 1, "one key sent");
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "stopped");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveStopped, "the note");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "the hint after the note");
	T.EqualStr(Rig.Shown.Hint.Counter, f"1/{Total}", "the tracker still got that key");
	T.EqualInt(Rig.Game.Strains, 0, "strains");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	Rig.Frame();
	T.EqualInt(Rig.OwnKeys.Num(), 1, "(one key sent and reported back)");
	Rig.Ctl.OwnKeyMissed(Rig.Now);
	T.EqualStr(LPHTests_CtlAuto(Rig), "running", "OwnKeyMissed with no key in flight changes nothing");
	Rig.Run(200);
	T.True(!Rig.Saw(En.SolveStopped), "no note");

	T.Begin("Controller 34 the minigame closed during auto-pick: TakeKey gives nothing more, no stop note");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	Rig.Run(500);
	int Before = Rig.OwnKeys.Num();
	for (int Guard = 0; Guard < 100 && Rig.OwnKeys.Num() == Before; Guard++)
		Rig.Frame(); // closed right after a key went out: the next one is due soon
	Rig.Ctl.Closed(Rig.Now);
	Sent = Rig.OwnKeys.Num();
	bool bAny = false;
	ELPH_Key Late = ELPH_Key::R;
	for (int i = 0; i < 100; i++)
	{
		Rig.Now += 10;
		if (Rig.Ctl.TakeKey(Rig.Now, Late))
			bAny = true;
	}
	T.True(!bAny, "TakeKey gives nothing");
	Rig.Run(500);
	T.EqualInt(Rig.OwnKeys.Num(), Sent, "no key after the close");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hidden", "the hint is gone");
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "off");
	T.True(!Rig.Saw(En.SolveStopped), "no stop note");
	T.True(!Rig.Logged("autosolve stopped"), "closing is not a stop of its own");
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 1000);
	T.EqualInt(Rig.OwnKeys.Num(), Sent, "the next minigame is not picked by itself");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "just the hint");
}

// 1.x: "two resets within double_reset_ms start the autosolver; it opens the lock", "resets further apart do not start
// the autosolver", "[solve] double_reset = false turns the double reset off", "a reset that stops the autosolver starts no
// pair", "a double reset with the hint hidden notes it".
void LPHTests_ControllerDoubleReset(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);

	T.Begin("Controller 35 two resets within DoubleResetMs start the autosolver; it opens the lock");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Press(ELPH_Key::R);
	Rig.Run(LPH::DoubleResetMs);
	Rig.Press(ELPH_Key::R);
	T.EqualStr(LPHTests_CtlAuto(Rig), "running", "running after the second reset, DoubleResetMs after the first");
	T.True(Rig.Logged("autosolve: double reset"), "logged");
	Rig.Frame();
	Rig.Frame();
	T.True(Rig.Shown.Hint.bCounterAlways, "the auto-pick counter");
	T.EqualInt(Rig.Messages.Num(), 0, "no note while the hint is shown");
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "plates");
	T.EqualInt(Rig.Game.Strains, 0, "strains");

	T.Begin("Controller 36 resets further apart, or with the double reset off, start nothing");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Press(ELPH_Key::R);
	Rig.Run(LPH::DoubleResetMs + 100);
	Rig.Press(ELPH_Key::R);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "DoubleResetMs + 100 apart: off");
	Rig.Run(2000);
	T.EqualInt(Rig.OwnKeys.Num(), 0, "nothing pressed");
	FLPH_Values NoDouble = LPHTests_CtlLines();
	NoDouble.bDoubleReset = false;
	Rig = LPHTests_CtlRig(T, Db, NoDouble);
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Press(ELPH_Key::R);
	Rig.Run(100);
	Rig.Press(ELPH_Key::R);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "the double reset turned off: off");
	Rig.Run(2000);
	T.EqualInt(Rig.OwnKeys.Num(), 0, "nothing pressed");

	T.Begin("Controller 37 a reset during auto-pick only stops it; the next reset starts no pair");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	Rig.Run(500);
	int Pressed = Rig.OwnKeys.Num();
	Rig.Press(ELPH_Key::R);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "the first reset stopped it");
	T.True(Rig.Logged("autosolve: cancelled by a player press (R)"), "logged");
	Rig.Run(100);
	Rig.Press(ELPH_Key::R);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "the second did not start it");
	T.True(!Rig.Logged("autosolve: double reset"), "no double reset");
	Rig.Run(2000);
	T.EqualInt(Rig.OwnKeys.Num(), Pressed, "nothing pressed");

	T.Begin("Controller 38 a double reset with the hint hidden shows a note");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(LPH::ToggleNoteMs + 50);
	Rig.Press(ELPH_Key::R);
	Rig.Run(100);
	Rig.Press(ELPH_Key::R);
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + LPH::Fill(En.SolveOn, En.DoubleReset), "the note");
}

// 1.x: "the auto-pick time counts down to 1 s as the keys go", "with [solve] timer = false auto-pick shows no seconds",
// "the autosolver's text shows even with the counter off".
void LPHTests_ControllerCountdown(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);
	FLPH_Texts Ru = LPH::Texts(ELPH_Lang::Ru);
	FString Plan = LPHTests_Plan(Three, Start, 0);
	TArray<FString> Letters;

	T.Begin("Controller 39 the auto-pick counter: the seconds of the keys left, rounded up, down to 1 s");
	ULPH_Solver Two = LPHTests_CtlRules(T, Db, n"LPHTest_Two", 0);
	TArray<int> TwoStart = LPHTests_Holes2(5, 3);
	T.EqualStr(LPHTests_Plan(Two, TwoStart, 0), "AWD", "(the two-plate plan)");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Two", 0.0, Two, TwoStart);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(Rig.Shown.Hint.Counter, LPH::Fill(En.SolvingTime, "1"), "A W D: 1 s");
	Rig.Ctl.Configure(LPHTests_CtlLines(), ELPH_Lang::Ru, Letters);
	Rig.Frame();
	T.EqualStr(Rig.Shown.Hint.Counter, LPH::Fill(Ru.SolvingTime, "1"), "in Russian");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	int Checked = 0;
	int Wrong = 0;
	for (int Guard = 0; Guard < 3000 && !Rig.Game.IsOpen(); Guard++)
	{
		Rig.Frame();
		if (Rig.Shown.Kind != ELPH_DisplayKind::Hint || !Rig.Shown.Hint.bCounterAlways)
			continue;
		Checked++;
		int Want = LPHTests_EtaSeconds(Plan, Rig.Shown.Hint.Pressed);
		if (Rig.Shown.Hint.Counter != LPH::Fill(En.SolvingTime, f"{Want}"))
			Wrong++;
	}
	T.True(Checked > 50, f"(checked {Checked} frames)");
	T.EqualInt(Wrong, 0, "every frame: A/D SolveEtaAdMs and W/S SolveEtaWsMs for the keys left, rounded up");
	Rig.Run(Rig.Game.AnimMs + 300);
	T.True(Rig.Counters.Num() >= 2, f"(the counter changed: {Rig.Counters.Num()} texts)");
	bool bUp = false;
	bool bSeconds = true;
	int Last = 1000;
	for (FString Each : Rig.Counters)
	{
		int Seconds = LPHTests_SolvingSeconds(Each, En);
		if (Seconds < 0)
			bSeconds = false;
		if (Seconds > Last)
			bUp = true;
		Last = Seconds;
	}
	T.True(bSeconds, "always seconds");
	T.True(!bUp, "never up");
	T.EqualInt(Last, 1, "down to 1 s");

	T.Begin("Controller 40 without the timer the counter says auto-pick runs, without seconds");
	FLPH_Values NoTimer = LPHTests_CtlLines();
	NoTimer.bTimer = false;
	Rig = LPHTests_CtlRig(T, Db, NoTimer);
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(Rig.Shown.Hint.Counter, En.Solving, "the text");
	T.True(Rig.Shown.Hint.bCounterAlways, "shown whatever the counter setting");
}

// 1.x: "F3 on a lock without a hint: autosolve unavailable, then the message again", "F3 on an opened lock: autosolve
// unavailable, nothing pressed", "an armed autosolver on a lock not in the database logs its stop", "an armed autosolver on
// a lock with another plate count logs its stop"; the review of 2.0: no line for a lock-less minigame, the armed
// autosolver's message before Thinking.
void LPHTests_ControllerNoAuto(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);
	FString NotInDb = "message: " + LPH::Fill(En.NotInDb, "Nope_Lock");

	T.Begin("Controller 41 F3 with no hint or on the open lock: auto-pick unavailable");
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Listen();
	Rig.Open(n"Nope_Lock", 0.0, nullptr, Start);
	Rig.Run(100);
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveUnavailable, "not in the database: the note");
	T.True(Rig.Logged("autosolve unavailable: no hint for this lock"), "logged");
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "off");
	Rig.Run(LPH::ToggleNoteMs);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), NotInDb, "the message is back");
	ULPH_Solver Stuck = LPHTests_CtlRules(T, Db, n"LPHTest_Stuck", 0);
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Stuck", 0.0, Stuck, LPHTests_Holes2(3, 4));
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.NoSafePath, "(no safe path)");
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveUnavailable, "no safe path: the note");
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "off");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	Rig.Solve();
	Rig.RunUntilOpen(20000);
	T.EqualStr(LPHTests_AutoHolesText(Rig.Game.Holes), "4 4 4", "(open)");
	int Sent = Rig.OwnKeys.Num();
	Rig.Solve();
	Rig.Frame();
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.SolveUnavailable, "the open lock: the note");
	T.True(Rig.Logged("autosolve unavailable: the lock is already open"), "logged");
	Rig.Run(1000);
	T.EqualInt(Rig.OwnKeys.Num(), Sent, "nothing pressed");

	T.Begin("Controller 42 auto-pick always on a lock with no hint: the autosolver goes off without a note");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlAlways());
	Rig.Listen();
	Rig.Open(n"Nope_Lock", 0.0, nullptr, Start);
	Rig.Run(100);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "not in the database: off");
	T.True(Rig.Logged("autosolve stopped: not in the database"), "logged");
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), NotInDb, "the message");
	T.True(!Rig.Saw(En.SolveStopped), "no stop note");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlAlways());
	Rig.Listen();
	Rig.Open(n"LPHTest_Three", 0.0, Three, LPHTests_Holes2(3, 5));
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "message: " + En.BadState, "two plates of three: the message");
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "off");
	T.True(Rig.Logged("autosolve stopped: the visible plates do not fit the lock"), "logged");
	T.True(!Rig.Saw(En.SolveStopped), "no stop note");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlAlways());
	Rig.Listen();
	Rig.OpenBare();
	Rig.Run(500);
	Rig.Ctl.NoLock(Rig.Now);
	Rig.Run(500);
	T.EqualStr(LPHTests_CtlAuto(Rig), "off", "no lock: off");
	T.True(!Rig.Logged("autosolve stopped"), "no lock: no line in the log (1.x was silent for unlocked chests)");
	FLPH_Values Debug = LPHTests_CtlAlways();
	Debug.bDebug = true;
	Rig = LPHTests_CtlRig(T, Db, Debug);
	Rig.Listen();
	Rig.OpenBare();
	Rig.Ctl.NoLock(Rig.Now);
	T.True(Rig.Logged("autosolve stopped: no lock"), "only in the debug log");

	T.Begin("Controller 43 an armed autosolver while the solver prepares after the ready delay: its message, not Thinking");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlLines());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	T.True(Rig.Ctl.Solver != nullptr && !Rig.Ctl.Solver.IsReady(), "(the solver prepares)");
	Rig.Now += LPH::ReadyDelayMs + 100;
	T.EqualStr(LPHTests_CtlKind(Rig.Ctl.Display(Rig.Now)), "message: " + En.Thinking, "not armed: Thinking");
	Rig = LPHTests_CtlRig(T, Db, LPHTests_CtlAlways());
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Now += LPH::ReadyDelayMs + 100;
	T.EqualStr(LPHTests_CtlKind(Rig.Ctl.Display(Rig.Now)), "message: " + En.SolveArmed, "armed: its message");
}

// DisplaySig (what the glue compares every frame) against Display().Sig.
void LPHTests_ControllerDisplaySig(ULPH_TestRun T, ULPH_LockDb Db, ULPH_Solver Three, const TArray<int>& Start)
{
	FLPH_Texts En = LPH::Texts(ELPH_Lang::En);

	T.Begin("Controller 44 DisplaySig is the Sig of Display (hint, notes, auto-pick, the wait, hidden) and builds no model");
	FLPH_Values Tape; // the defaults: tape, timer
	ULPH_CtlRig Rig = LPHTests_CtlRig(T, Db, Tape);
	Rig.Open(n"LPHTest_Three", 0.0, Three, Start);
	Rig.Run(LPH::ReadyDelayMs + 200);
	T.EqualStr(LPHTests_CtlKind(Rig.Shown), "hint", "(the hint)");
	ELPH_Key Key = ELPH_Key::R;
	LPHTests_CtlCurrent(Rig.Shown, Key);
	Rig.Press(Key);
	int Builds = Rig.Ctl.ModelBuilds;
	FString Sig = Rig.Ctl.DisplaySig(Rig.Now);
	T.True(Sig != Rig.Shown.Sig, "(the press changed the Sig)");
	T.EqualInt(Rig.Ctl.ModelBuilds, Builds, "DisplaySig builds no model");
	FLPH_Display Shown = Rig.Ctl.Display(Rig.Now);
	T.EqualStr(Shown.Sig, Sig, "Display returns that Sig");
	T.EqualInt(Rig.Ctl.ModelBuilds, Builds + 1, "and builds the model");
	Rig.Run(500);
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(200);
	Rig.Ctl.ToggleHint(Rig.Now);
	Rig.Run(LPH::ToggleNoteMs + 50);
	Rig.Solve();
	Rig.RunUntilOpen(20000);
	Rig.Close();
	Rig.Solve();
	Rig.Run(LPH::SolveEarlyMs + 100);
	T.EqualInt(Rig.SigMismatches, 0, "DisplaySig was Display().Sig in every frame");
	T.True(Rig.Counters.Num() >= 2, "(the countdown was shown)");
	T.True(Rig.Saw(LPH::Fill(En.HintOff, "F4")), "(a note was shown)");
	T.True(Rig.Saw(En.SolveArmed), "(the wait for the next minigame was shown)");
	T.True(Rig.Redraws >= 8, f"(the display changed {Rig.Redraws} times)");
	T.EqualStr(Rig.Shown.Sig, LPH::HiddenSig, "(hidden at the end)");
}
