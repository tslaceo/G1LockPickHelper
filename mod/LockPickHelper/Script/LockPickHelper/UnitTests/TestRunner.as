// Runs the tests inside the game: the release game does not run Hazelight's Test_* functions, so the mod has its own
// runner. Start the game with `-LPHTests` (`-LPHTests=golden` adds the full reference runs; `-LPHTests=defaults` adds
// the two checks of the rows' defaults, which are right only on a clean profile, without the mod's section in
// GameUserSettings.ini): the tests run once, in the main menu world, and write Saved/LockPickHelper-tests.log; its last
// line is `tests done: <N> passed, <M> failed`.
// If the run stops without that line, a script error or a crash hit the case named in the last `case` line.
// The folder is UnitTests, not Tests: the game does not compile script folders named Test, Tests or Dev (silently: no
// error window, the files just are not there).

class ULPH_TestWorld : UScriptWorldSubsystem
{
	UPROPERTY()
	ULPH_Log TestLog;

	UPROPERTY()
	ULPH_TestRun Run;

	UFUNCTION(BlueprintOverride)
	void OnWorldBeginPlay()
	{
		FString Command = FCommandLine::Get();
		if (!Command.Contains("-LPHTests") || World.Name != n"MenuMap")
			return;
		bool bGolden = Command.Contains("-LPHTests=golden");

		TestLog = Cast<ULPH_Log>(NewObject(this, ULPH_Log::StaticClass()));
		TestLog.Open("LockPickHelper-tests.log");
		TestLog.Line(f"tests start, golden {bGolden}");
		Run = Cast<ULPH_TestRun>(NewObject(this, ULPH_TestRun::StaticClass()));
		Run.Output = TestLog;

		RunAll(Run, bGolden);

		TestLog.Line(f"tests done: {Run.Passed} passed, {Run.Failed} failed");
		TestLog.Flush();
	}

	// Each task adds the line of its own module here.
	void RunAll(ULPH_TestRun T, bool bGolden)
	{
		LPHTests_Keys(T);
		LPHTests_LockDb(T);
		LPHTests_Solver(T);
		LPHTests_SolverGolden(T);
		LPHTests_Tracker(T);
		LPHTests_AutoSolve(T);
		LPHTests_View(T);
		LPHTests_Texts(T);
		LPHTests_Controller(T);
		LPHTests_Icons(T);
		LPHTests_Plates(T);
		LPHTests_Game(T);
		LPHTests_HintWidget(T);

		if (bGolden)
		{
			// The full reference runs (the solver against the 1.2.0 sequences).
			LPHTests_SolverGoldenFull(T);
		}
	}
}
