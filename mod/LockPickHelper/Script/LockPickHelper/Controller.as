// The controller: one minigame session, from the window opening to its closing, the hint it shows and the auto-pick (the
// session part of main.lua of 1.2.0 - tick, render, model_of, step_prepare, drop_auto, on_key, player_key, double_reset,
// toggle_solve, toggle_early, step_auto, auto_stopped and the F3/F4 of drain_keys - ported by meaning). It touches no game
// object: the glue tells it what happens - the minigame opened, its lock, the plates it read, the player's presses, F3,
// F4, the minigame closed - sends the keys TakeKey hands out and draws what Display returns. Every time is the caller's
// LPH::NowMs() (the tests hand in their own clock); only the solver's budget per frame is real time.
//
// A session goes through phases: Lock (waiting for the lock's name) -> Prepare (the solver works BudgetMs a frame; a lock
// prepared before comes from the cache of the last LPH::ContextCache locks, ready at once) -> Ready (the minigame takes
// presses only after ReadyDelayMs since it opened and ReadyFrames frames, and the plates count only when two settled
// readings in a row agree) -> Track (the tracker follows the presses and the readings). Idle: no hint for this minigame -
// its lock is not in the database, the visible plates do not fit it, or it has no lock (a chest or door that is not
// locked); the session then shows its message, or nothing, until it closes.
//
// Auto-pick: the session's autosolver is armed at the start by the auto-pick setting or by F3 shortly before (and by F3
// or a double reset before the tracker exists); it runs once there is a tracker. Every frame TakeKey asks it for a key;
// the glue sends that key to the game with Broadcast, and its handler, which sees the press during that call, reports it
// with OwnKey (the tracker takes it; the autosolver goes on). Any press of the player (PlayerKey) stops it. It stops by
// itself when the lock is open, when there is no hint, when an A/D does not show in time, after too many replans, and when
// its own key did not reach the handler (OwnKeyMissed); all but the open lock show a note. The session's end stops it.
//
// Display shows, in this order: the note (F3, F4, auto-pick stopped or unavailable; shown with the hint off too and outside
// a minigame), the session's message, the hint (or the tracker's NoSafePath / BadState; nothing once the lock is open),
// "auto-pick waits for the lock" (only once the lock is known; outside a minigame while F3 arms the next one), Thinking
// (new in 2.0: the solver still prepares after ReadyDelayMs), nothing. F4 off hides all but the note. While the autosolver
// runs, the hint's counter says so ("Auto-picking... N s" with the timer), whatever the counter setting.
//
// The glue, every frame of an open minigame: Tick (with the plates read when WantsReading), then TakeKey (and its
// Broadcast), then DisplaySig - and Display only when that changed. Opened/LockFound/NoLock/Closed, Solve (F3), ToggleHint
// (F4) and PlayerKey come as they happen.

// One reading of the minigame's plates.
struct FLPH_Reading
{
	TArray<int> Holes; // the holes (1..7) of the settled plates 0..n-1, front to back
	int Cursor = -1; // the plate the game highlights (-1: none read)
	int Visible = 0; // how many plates the game shows
	bool bSettled = false; // false: a plate is moving, or the reading failed (Holes then mean nothing)
}

enum ELPH_DisplayKind
{
	Hidden,
	Hint,
	Message
}

// What to draw. Sig changes exactly when the drawing has to change (the signature of render in 1.x): the glue redraws only
// then. Every Sig but the hidden one carries the session's number and the settings' version, so a new session or new
// settings always draw afresh.
struct FLPH_Display
{
	ELPH_DisplayKind Kind = ELPH_DisplayKind::Hidden;
	FString Message; // Kind Message: the text
	FLPH_HintModel Hint; // Kind Hint: the model (LPH::Tape or LPH::Lines)
	FString Sig;
}

enum ELPH_Phase
{
	Off, // no minigame
	Lock, // the minigame is open, its lock is not known yet
	Prepare, // the solver prepares the lock
	Ready, // the solver is ready; waiting until the minigame takes presses
	Track, // the hint follows the player
	Idle // no hint for this minigame
}

namespace LPH
{
	const FString HintKeyName = "F4"; // the keys' names in their notes (F3 and F4 are fixed in 2.0)
	const FString SolveKeyName = "F3";
	const FString HiddenSig = "hidden"; // the Sig of nothing shown

	// "3 5 4": holes for the log.
	FString HolesText(const TArray<int>& Holes)
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
}

class ULPH_Controller : UObject
{
	// What the tests look at (the glue uses the methods only).

	// The session's autosolver.
	UPROPERTY()
	ULPH_AutoSolve Auto;

	// The session's solver (from LockFound on).
	UPROPERTY()
	ULPH_Solver Solver;

	int BudgetMs = LPH::PrepareBudgetMs; // the solver's work per frame (the tests lower it)
	int PrepareTicks = 0; // the Ticks the solver worked in this session
	int ModelBuilds = 0; // hint models built

	// The rest is the controller's own.

	UPROPERTY()
	private ULPH_LockDb Db;

	UPROPERTY()
	private ULPH_Log ModLog;

	// The session's tracker (from Track on).
	UPROPERTY()
	private ULPH_Tracker Tracker;

	// The prepared solvers of the last LPH::ContextCache locks, the most recently used last, by the lock and the
	// connections the skill removed (another skill is another graph). 1.x: contexts and context_order.
	UPROPERTY()
	private TArray<ULPH_Solver> CacheSolvers;
	private TArray<FName> CacheLocks;
	private TArray<int> CacheRemoved;

	// Configure.
	private FLPH_Values Values;
	private FLPH_Texts Texts;
	private TArray<FString> Labels; // what the hint writes for W, S, A, D (empty: the letters)
	private int Version = 0; // grows with every Configure
	private int Icons = 0; // the icon set the hint draws (SetIcons)

	// F4, the notes and F3 outside a minigame: they outlive the sessions.
	private bool bEnabled = true;
	private bool bNote = false;
	private FString Note;
	private int64 NoteUntilMs = 0;
	private bool bEarly = false; // F3 came outside a minigame (1.x early): the one opened before EarlyUntilMs
	private bool bEarlySolve = false; // is auto-picked (or, with auto-pick always, skipped)
	private int64 EarlyUntilMs = 0;

	// The session.
	private ELPH_Phase Phase = ELPH_Phase::Off;
	private int Session = 0; // grows with every Opened
	private int64 OpenedMs = 0;
	private int Frames = 0; // Ticks since Opened
	private FName LockName;
	private int Removed = 0; // the connections the skill removed
	private int Plates = 0; // the lock's plates in the database
	private FString SessionMessage; // shown until the session ends (empty: none)
	private bool bEarlyNav = false; // W/S came before the tracker: the cursor is not known (1.x early_nav)
	private bool bHasLast = false; // the previous reading was settled: LastHoles, LastVisible
	private TArray<int> LastHoles;
	private int LastVisible = 0;
	private TArray<int> LoggedHoles; // the holes last written to the debug log
	private int64 LastReadMs = LPH::NeverMs;
	private bool bOwnSent = false; // TakeKey handed out OwnSentKey and neither OwnKey nor OwnKeyMissed came yet
	private ELPH_Key OwnSentKey = ELPH_Key::W;
	private bool bResetHalf = false; // the player's last reset (at ResetAtMs) may start a double reset (1.x reset_at)
	private int64 ResetAtMs = 0;

	// Display: the hint's model and its Sig; the model is built again only when the Sig changes.
	private FString HintSig;
	private FLPH_HintModel HintModel;
	private int LoggedPlan = 0; // the tracker's Plan last written to the debug log

	// Db: the lock database; InLog: the mod's log (nullptr: none). The texts are English until Configure.
	void Init(ULPH_LockDb InDb, ULPH_Log InLog)
	{
		Db = InDb;
		ModLog = InLog;
		Texts = LPH::Texts(ELPH_Lang::En);
		Auto = Cast<ULPH_AutoSolve>(NewObject(this, ULPH_AutoSolve::StaticClass()));
		Auto.Init(LPH::SolveWsGapMs, LPH::SolveTimeoutMs, LPH::SolveMaxReplans);
	}

	// The player's settings, the language of the texts and the labels of W, S, A, D, at every minigame start, before
	// Opened (the auto-pick setting arms the session there). A hint shown is drawn again with them; a message already shown
	// keeps its words until it ends. The debug log follows bDebug.
	void Configure(FLPH_Values InValues, ELPH_Lang InLang, const TArray<FString>& InLabels)
	{
		Values = InValues;
		Texts = LPH::Texts(InLang);
		Labels = InLabels;
		Version++;
		if (ModLog != nullptr)
			ModLog.bDebug = InValues.bDebug;
	}

	// The icon set the hint draws (the glue's ELPH_IconSet as a number; 0: the letters). Another one draws the hint again.
	void SetIcons(int IconSet)
	{
		Icons = IconSet;
	}

	// A minigame opened: a new session that waits for its lock (a session the glue did not close ends here). Its
	// autosolver is armed by the auto-pick setting, or as F3 said shortly before (the hero sits down first).
	void Opened(int64 Now)
	{
		EndSession();
		Session++;
		Phase = ELPH_Phase::Lock;
		OpenedMs = Now;
		bool bSolve = Values.bAutoPick;
		if (bEarly && Now < EarlyUntilMs)
			bSolve = bEarlySolve;
		bEarly = false;
		if (bSolve)
		{
			Auto.Arm();
			LogDebug("minigame opened, autosolve armed");
		}
		else
		{
			LogDebug("minigame opened");
		}
	}

	// The minigame's lock and the player's lockpicking skill (LockpickPrecision: the game drops that many of the lock's
	// connections, rounded). Not in the database: its message, no hint. Otherwise the solver, from the cache or a new one
	// that Tick prepares. Only while the session waits for its lock.
	void LockFound(FName Lock, float Precision, int64 Now)
	{
		if (Phase != ELPH_Phase::Lock)
			return;
		FString LockText = Lock.ToString();
		FLPH_LockGraph Graph;
		int Dropped = 0;
		if (Db == nullptr || !Db.Find(Lock, LPH::ConnectionsRemoved(Precision), Graph, Dropped))
		{
			LogLine(f"lock not in database: {LockText}");
			SessionMessage = LPH::Fill(Texts.NotInDb, LockText);
			Phase = ELPH_Phase::Idle;
			DropAuto("not in the database", true);
			return;
		}
		LogLine(f"lock {LockText} ({Graph.Plates} plates, precision {Precision}, {Dropped} connections removed)");
		LockName = Lock;
		Removed = Dropped;
		Plates = Graph.Plates;
		int Hit = CacheFind(Lock, Dropped);
		if (Hit >= 0)
		{
			Solver = CacheSolvers[Hit];
			CacheUse(Hit);
			Phase = ELPH_Phase::Ready;
			LogDebug("solver from the cache");
			return;
		}
		Solver = Cast<ULPH_Solver>(NewObject(this, ULPH_Solver::StaticClass()));
		Solver.Begin(Graph);
		Phase = ELPH_Phase::Prepare;
	}

	// The minigame has no lock (a chest or door that is not locked): nothing to show until it closes. An armed autosolver
	// goes off with a debug line only (1.x never saw a lock-less minigame and said nothing).
	void NoLock(int64 Now)
	{
		if (Phase != ELPH_Phase::Lock)
			return;
		LogDebug("no lock: nothing to show");
		Phase = ELPH_Phase::Idle;
		DropAuto("no lock", false);
	}

	// The minigame closed (or its world went away): the session ends with its autosolver (no note: that is no stop of its
	// own); only a note can still show.
	void Closed(int64 Now)
	{
		if (Phase == ELPH_Phase::Off)
			return;
		LogDebug("minigame closed");
		EndSession();
		if (ModLog != nullptr)
			ModLog.Flush();
	}

	// Whether the glue should read the plates for this frame's Tick: once per PollMs, from the solver being ready until
	// the session has a hint or gives up (Ready and Track).
	bool WantsReading(int64 Now) const
	{
		if (Phase != ELPH_Phase::Ready && Phase != ELPH_Phase::Track)
			return false;
		return Now - LastReadMs >= LPH::PollMs;
	}

	// Every frame of an open minigame: counts the frame, lets the solver work while it prepares, and takes the reading of
	// the plates when there is one.
	void Tick(int64 Now, bool bHasReading, const FLPH_Reading& Reading)
	{
		if (Phase == ELPH_Phase::Off)
			return;
		Frames++;
		if (Phase == ELPH_Phase::Prepare)
		{
			PrepareTicks++;
			if (!Solver.Step(BudgetMs))
				return;
			CacheAdd(LockName, Removed, Solver);
			Phase = ELPH_Phase::Ready;
			LogDebug(f"solver ready after {Now - OpenedMs} ms, {PrepareTicks} frames");
		}
		if (bHasReading && (Phase == ELPH_Phase::Ready || Phase == ELPH_Phase::Track))
		{
			LastReadMs = Now;
			TakeReading(Reading, Now);
		}
	}

	// A press of the player (keyboard, gamepad, or the D-pad the glue passes on; never the autosolver's own key): it stops
	// the autosolver (armed or running), the tracker takes it, and a reset may be half of a double reset.
	void PlayerKey(ELPH_Key Key, int64 Now)
	{
		if (Phase == ELPH_Phase::Off)
			return;
		bool bWasOff = Auto.GetState() == ELPH_AutoState::Off;
		if (Auto.PlayerPressed())
		{
			FString Letter = LPH::KeyLetter(Key);
			LogLine(f"autosolve: cancelled by a player press ({Letter})");
		}
		OnKey(Key, Now);
		if (Key == ELPH_Key::R)
			DoubleReset(bWasOff, Now);
	}

	// F4, in a minigame or not: the hint on or off, and a note that says so for ToggleNoteMs.
	void ToggleHint(int64 Now)
	{
		bEnabled = !bEnabled;
		FString Template = Texts.HintOff;
		if (bEnabled)
		{
			Template = Texts.HintOn;
			LogLine("hint on");
		}
		else
		{
			LogLine("hint off");
		}
		ShowNote(LPH::Fill(Template, LPH::HintKeyName), Now);
	}

	// F3. In a minigame: starts the autosolver (arms it before the tracker exists) or stops it; with no hint for the lock,
	// or on the open lock, a note says it is unavailable. Outside a minigame: the one that opens within SolveEarlyMs is
	// auto-picked (with auto-pick always: skipped); F3 again within that time goes back to the setting. With the hint
	// hidden a note says what F3 did.
	void Solve(int64 Now)
	{
		ToggleSolve(LPH::SolveKeyName, Now);
	}

	// The key the autosolver wants pressed now (step_auto of 1.x), once per frame after Tick. True: the glue sends OutKey
	// at once with Broadcast, and the handler reports it during that call with OwnKey - or, if it did not come, the glue
	// calls OwnKeyMissed. The key counts as sent from here on. False: nothing to press now; never outside a minigame, so
	// a closed minigame gets no key. A stop of its own (the lock open, a timeout, ...) happens here.
	bool TakeKey(int64 Now, ELPH_Key& OutKey)
	{
		if (Phase == ELPH_Phase::Off || Auto.GetState() == ELPH_AutoState::Off)
			return false;
		bool bHasView = Tracker != nullptr;
		FLPH_TrackerView Seen;
		int Pending = 0;
		if (bHasView)
		{
			Seen = Tracker.View();
			Pending = Tracker.Pending();
		}
		ELPH_Key Key = ELPH_Key::W;
		ELPH_AutoStop Stop = ELPH_AutoStop::None;
		bool bPress = Auto.Step(Seen, bHasView, Pending, Now, Key, Stop);
		if (Stop != ELPH_AutoStop::None)
			AutoStopped(Stop, Now);
		if (!bPress)
			return false;
		bOwnSent = true;
		OwnSentKey = Key;
		if (Tracing())
		{
			FString Letter = LPH::KeyLetter(Key);
			LogDebug(f"autosolve: {Letter} at +{Now - OpenedMs} ms");
		}
		OutKey = Key;
		return true;
	}

	// The autosolver's key reached the handler during the glue's Broadcast: the tracker takes it like any press, and the
	// autosolver goes on.
	void OwnKey(ELPH_Key Key, int64 Now)
	{
		if (Phase == ELPH_Phase::Off)
			return;
		bOwnSent = false;
		OnKey(Key, Now);
	}

	// The key of the last TakeKey did not reach the handler during its Broadcast (1.x: "hook did not fire"). It went to the
	// game all the same, so the tracker takes it; but the autosolver could not tell its keys from the player's any more,
	// so it stops, with a note. Nothing happens when no key is out (OwnKey reported it, or none was taken).
	void OwnKeyMissed(int64 Now)
	{
		if (Phase == ELPH_Phase::Off || !bOwnSent)
			return;
		bOwnSent = false;
		OnKey(OwnSentKey, Now);
		Auto.Stop();
		FString Letter = LPH::KeyLetter(OwnSentKey);
		LogLine(f"autosolve stopped: {Letter} did not reach the handler");
		ShowNote(Texts.SolveStopped, Now);
	}

	// What to draw now (the order is in the comment at the top). The hint's model is built again only when its Sig
	// changes. The glue may call DisplaySig every frame and this only when that changed.
	FLPH_Display Display(int64 Now)
	{
		FString Text;
		FString Sig;
		ELPH_DisplayKind Kind = Decide(Now, Text, Sig);
		FLPH_Display Result;
		Result.Kind = Kind;
		Result.Sig = Sig;
		if (Kind == ELPH_DisplayKind::Message)
		{
			Result.Message = Text;
		}
		else if (Kind == ELPH_DisplayKind::Hint)
		{
			if (Tracker == nullptr) // (Decide shows a hint only with a tracker)
				return HiddenDisplay();
			if (Sig != HintSig)
				BuildHint(Sig);
			Result.Hint = HintModel;
		}
		return Result;
	}

	// The Sig Display would return now, decided the same way but without the hint's model (no copies of the tracker's
	// keys and history).
	FString DisplaySig(int64 Now)
	{
		FString Text;
		FString Sig;
		Decide(Now, Text, Sig);
		return Sig;
	}

	// Whether the hint is on (F4).
	bool IsEnabled() const
	{
		return bEnabled;
	}

	// on_key of 1.x: the tracker takes the press; before it exists only W/S matter - the cursor is then not known.
	private void OnKey(ELPH_Key Key, int64 Now)
	{
		FString Letter = LPH::KeyLetter(Key);
		if (Tracker != nullptr)
		{
			LogDebug(f"key {Letter}");
			Tracker.Key(Key, Now);
		}
		else if (Key == ELPH_Key::W || Key == ELPH_Key::S)
		{
			bEarlyNav = true;
			LogDebug(f"key {Letter} before tracking: the cursor is not known");
		}
	}

	// double_reset of 1.x: two resets of the player within DoubleResetMs work as F3 (the gamepad has no key of its own in
	// the minigame). A reset that stopped the autosolver starts no pair.
	private void DoubleReset(bool bWasOff, int64 Now)
	{
		if (!Values.bDoubleReset)
			return;
		if (bWasOff && bResetHalf && Now - ResetAtMs <= LPH::DoubleResetMs)
		{
			bResetHalf = false;
			LogLine("autosolve: double reset");
			ToggleSolve(Texts.DoubleReset, Now);
			return;
		}
		bResetHalf = bWasOff;
		ResetAtMs = Now;
	}

	// toggle_solve of 1.x (Solve has what it does). Source: the key's name in the notes (F3, or the double reset).
	private void ToggleSolve(FString Source, int64 Now)
	{
		if (Phase == ELPH_Phase::Off)
		{
			ToggleEarly(Now);
			return;
		}
		if (Auto.GetState() == ELPH_AutoState::Off)
		{
			if (Phase == ELPH_Phase::Idle)
			{
				Unavailable("no hint for this lock", Now);
				return;
			}
			if (Tracker != nullptr)
			{
				FLPH_TrackerSummary Mark = Tracker.Summary();
				if (Mark.Status == ELPH_Status::Solved)
				{
					Unavailable("the lock is already open", Now);
					return;
				}
				if (Mark.Status != ELPH_Status::Ok)
				{
					Unavailable("no hint for this lock", Now);
					return;
				}
			}
		}
		ELPH_AutoState State = Auto.Toggle(Tracker != nullptr);
		FString StateText = AutoStateText(State);
		LogLine("autosolve: " + StateText);
		SolveNote(State != ELPH_AutoState::Off, Source, Now);
	}

	// toggle_early of 1.x: F3 outside a minigame (right after using the chest, while the hero sits down).
	private void ToggleEarly(int64 Now)
	{
		if (bEarly && Now < EarlyUntilMs)
		{
			bEarly = false;
			if (Values.bAutoPick)
			{
				LogLine("autosolve: the next minigame as set (solve)");
				SolveNoteAlways(true, LPH::SolveKeyName, Now);
			}
			else
			{
				LogLine("autosolve: the next minigame as set (no autosolve)");
				SolveNote(false, LPH::SolveKeyName, Now);
			}
			return;
		}
		bEarly = true;
		EarlyUntilMs = Now + LPH::SolveEarlyMs;
		bEarlySolve = !Values.bAutoPick;
		if (bEarlySolve)
		{
			LogLine("autosolve: armed for the next minigame");
			SolveNote(true, LPH::SolveKeyName, Now);
		}
		else
		{
			LogLine("autosolve: the next minigame is skipped");
			SolveNoteAlways(false, LPH::SolveKeyName, Now);
		}
	}

	// solve_note of 1.x: with the hint hidden a note says what F3 did (a shown hint tells it by itself).
	private void SolveNote(bool bOn, FString Source, int64 Now)
	{
		if (!bEnabled)
			SolveNoteAlways(bOn, Source, Now);
	}

	// The note of F3 whatever the hint's state: "Auto-pick on (F3)" / "Auto-pick off (F3)".
	private void SolveNoteAlways(bool bOn, FString Source, int64 Now)
	{
		FString Template = Texts.SolveOff;
		if (bOn)
			Template = Texts.SolveOn;
		ShowNote(LPH::Fill(Template, Source), Now);
	}

	// F3 with nothing the autosolver could do: a note (shown with the hint hidden too), the reason in the log.
	private void Unavailable(FString Reason, int64 Now)
	{
		LogLine("autosolve unavailable: " + Reason);
		ShowNote(Texts.SolveUnavailable, Now);
	}

	// auto_stopped of 1.x: the autosolver stopped by itself. The open lock is what it was for; any other reason is logged
	// and noted.
	private void AutoStopped(ELPH_AutoStop Reason, int64 Now)
	{
		if (Reason == ELPH_AutoStop::Solved)
		{
			LogDebug("autosolve: lock opened");
			return;
		}
		FString ReasonText = AutoStopText(Reason);
		LogLine("autosolve stopped: " + ReasonText);
		ShowNote(Texts.SolveStopped, Now);
	}

	// drop_auto of 1.x: this minigame has no hint, so a waiting autosolver goes off (bAlways: logged like its other stops;
	// otherwise a debug line).
	private void DropAuto(FString Reason, bool bAlways)
	{
		if (Auto.GetState() != ELPH_AutoState::Off)
		{
			if (bAlways)
				LogLine("autosolve stopped: " + Reason);
			else
				LogDebug("autosolve stopped: " + Reason);
		}
		Auto.Stop();
	}

	// The state's name in the log, as 1.x wrote it.
	private FString AutoStateText(ELPH_AutoState State) const
	{
		if (State == ELPH_AutoState::Armed)
			return "armed";
		if (State == ELPH_AutoState::Running)
			return "running";
		return "off";
	}

	// The reason's name in the log, as 1.x wrote it.
	private FString AutoStopText(ELPH_AutoStop Reason) const
	{
		if (Reason == ELPH_AutoStop::Solved)
			return "solved";
		if (Reason == ELPH_AutoStop::NoSafePath)
			return "no_safe_path";
		if (Reason == ELPH_AutoStop::BadState)
			return "bad_state";
		if (Reason == ELPH_AutoStop::Timeout)
			return "timeout";
		if (Reason == ELPH_AutoStop::Replans)
			return "replans";
		return "none";
	}

	// A reading once the solver is ready (tick of 1.x): only two equal settled readings in a row count. In Ready such a
	// pair starts the tracker once the minigame takes presses (or ends the session's hint when the visible plates do not
	// fit the lock); in Track it goes to the tracker.
	private void TakeReading(const FLPH_Reading& Reading, int64 Now)
	{
		bool bAgain = Reading.bSettled && bHasLast && Reading.Visible == LastVisible
			&& LPH::SameHoles(Reading.Holes, LastHoles);
		bHasLast = Reading.bSettled;
		LastHoles = Reading.Holes;
		LastVisible = Reading.Visible;
		if (!bAgain)
			return;

		bool bFits = Reading.Visible == Plates && Reading.Holes.Num() == Plates;
		if (Phase == ELPH_Phase::Ready)
		{
			if (Now - OpenedMs < LPH::ReadyDelayMs || Frames < LPH::ReadyFrames)
				return;
			if (!bFits)
			{
				FString LockText = LockName.ToString();
				LogLine(f"lock {LockText}: {Reading.Visible} visible plates, database has {Plates}");
				SessionMessage = Texts.BadState;
				Phase = ELPH_Phase::Idle;
				DropAuto("the visible plates do not fit the lock", true);
				return;
			}
			StartTracking(Reading, Now);
			return;
		}
		if (!bFits)
			return; // a partial reading (the pieces being taken down): skipped
		if (!LPH::SameHoles(Reading.Holes, LoggedHoles))
		{
			LoggedHoles = Reading.Holes;
			if (Tracing())
			{
				FString HolesLine = LPH::HolesText(Reading.Holes);
				LogDebug(f"plates {HolesLine}");
			}
		}
		Tracker.Observe(Reading.Holes, Reading.Cursor, Now);
	}

	// Ready -> Track: the tracker starts from the settled holes, the cursor on plate 0 unless W/S came before. The same
	// reading is its first observation, so a highlighted plate is taken at once when the cursor is not known (no parking
	// hint for one poll).
	private void StartTracking(const FLPH_Reading& Reading, int64 Now)
	{
		// A tracker starts its Plan at 1. The autosolver runs only with a tracker and a session has one tracker, so here it
		// is off or armed, and an armed one has seen no Plan yet: the new tracker's Plan 1 is no replan for it. (A running
		// one would be from a tracker before: stopped.)
		if (Auto.GetState() == ELPH_AutoState::Running)
			Auto.Stop();
		Tracker = Cast<ULPH_Tracker>(NewObject(this, ULPH_Tracker::StaticClass()));
		Tracker.Init(Solver, Reading.Holes, !bEarlyNav, LPH::GraceMs);
		Tracker.Observe(Reading.Holes, Reading.Cursor, Now);
		Phase = ELPH_Phase::Track;
		LoggedHoles = Reading.Holes;
		if (Tracing())
		{
			FString HolesLine = LPH::HolesText(Reading.Holes);
			FString CursorText = "0";
			if (bEarlyNav)
				CursorText = "unknown";
			LogDebug(f"tracking from {HolesLine}, cursor {CursorText}, highlight {Reading.Cursor}");
		}
	}

	// render of 1.x without the drawing: what to show (the order is in the comment at the top), the message's text and
	// the Sig. Display and DisplaySig both decide here, so their Sigs cannot differ. A note that has run out ends here.
	private ELPH_DisplayKind Decide(int64 Now, FString& OutText, FString& OutSig)
	{
		if (bNote && Now >= NoteUntilMs)
			bNote = false;
		if (bNote)
			return Say(Note, OutText, OutSig);
		if (!bEnabled)
			return Hide(OutSig);
		if (Phase == ELPH_Phase::Off)
		{
			if (bEarly && bEarlySolve && Now < EarlyUntilMs)
				return Say(Texts.SolveArmed, OutText, OutSig); // F3 armed the next minigame
			return Hide(OutSig);
		}
		if (!SessionMessage.IsEmpty())
			return Say(SessionMessage, OutText, OutSig);
		if (Tracker != nullptr)
		{
			FLPH_TrackerSummary Mark = Tracker.Summary();
			if (Mark.Status == ELPH_Status::Ok)
			{
				OutSig = HintSigOf(Mark);
				return ELPH_DisplayKind::Hint;
			}
			if (Mark.Status == ELPH_Status::NoSafePath)
				return Say(Texts.NoSafePath, OutText, OutSig);
			if (Mark.Status == ELPH_Status::BadState)
				return Say(Texts.BadState, OutText, OutSig);
			return Hide(OutSig); // the lock is open
		}
		// Not before the lock is known: a chest or door that is not locked opens the minigame too. The armed autosolver's
		// message comes before Thinking: the player asked for it.
		if (Auto.GetState() == ELPH_AutoState::Armed && Phase != ELPH_Phase::Lock)
			return Say(Texts.SolveArmed, OutText, OutSig);
		if (Phase == ELPH_Phase::Prepare && Now - OpenedMs >= LPH::ReadyDelayMs)
			return Say(Texts.Thinking, OutText, OutSig);
		return Hide(OutSig);
	}

	private ELPH_DisplayKind Say(FString Text, FString& OutText, FString& OutSig) const
	{
		OutText = Text;
		OutSig = f"message|{Session}|{Version}|" + Text;
		return ELPH_DisplayKind::Message;
	}

	private ELPH_DisplayKind Hide(FString& OutSig) const
	{
		OutSig = LPH::HiddenSig;
		return ELPH_DisplayKind::Hidden;
	}

	// The hint's Sig: the session, the settings' version, the icon set, whether the autosolver runs and the tracker's
	// numbers. The auto-pick counter follows from these too: its text from the version, its seconds from the keys left
	// (the keys change only with Plan).
	private FString HintSigOf(const FLPH_TrackerSummary& Mark) const
	{
		int Running = 0;
		if (Auto.GetState() == ELPH_AutoState::Running)
			Running = 1;
		FString Sig = f"hint|{Session}|{Version}|{Icons}|{Running}|";
		Sig += f"{Mark.Plan}|{Mark.Index}|{Mark.HistoryNum}|{Mark.Pressed}|{Mark.Misses}";
		return Sig;
	}

	// The hint's model for this Sig, from the tracker's View. While the autosolver runs its text takes the counter's place
	// and shows whatever the counter setting (render of 1.x).
	private void BuildHint(FString Sig)
	{
		FLPH_TrackerView Seen = Tracker.View();
		HintModel = ModelOf(Seen);
		if (Auto.GetState() == ELPH_AutoState::Running)
		{
			HintModel.Counter = SolvingText(Seen);
			HintModel.bCounterAlways = true;
		}
		HintSig = Sig;
		ModelBuilds++;
		if (Seen.Plan != LoggedPlan)
		{
			LoggedPlan = Seen.Plan;
			if (Tracing())
			{
				FString KeysLine = LPH::KeysText(Seen.Keys);
				LogDebug(f"hint ({Seen.Keys.Num()} keys): {KeysLine}");
			}
		}
	}

	// "Auto-picking..." and, with the timer, about the seconds the keys left take: each A/D SolveEtaAdMs, each W/S
	// SolveEtaWsMs, rounded up, at least 1.
	private FString SolvingText(const FLPH_TrackerView& Seen) const
	{
		if (!Values.bTimer)
			return Texts.Solving;
		int Ms = LPH::EtaMs(Seen.Keys, Seen.Index, LPH::SolveEtaAdMs, LPH::SolveEtaWsMs);
		int Seconds = Math::Max(Math::IntegerDivisionTrunc(Ms + 999, 1000), 1);
		return LPH::Fill(Texts.SolvingTime, f"{Seconds}");
	}

	// model_of of 1.x: the tape or the lines of the settings.
	private FLPH_HintModel ModelOf(const FLPH_TrackerView& Seen) const
	{
		if (Values.bTape)
			return LPH::Tape(Seen, Values.TapeNext, Values.TapeDone, Labels);
		return LPH::Lines(Seen, Values.PerLine, Values.MaxLines, Values.CollapseMin, Labels);
	}

	private FLPH_Display HiddenDisplay() const
	{
		FLPH_Display Result;
		Result.Sig = LPH::HiddenSig;
		return Result;
	}

	// A short note over whatever is shown, for ToggleNoteMs.
	private void ShowNote(FString Text, int64 Now)
	{
		Note = Text;
		NoteUntilMs = Now + LPH::ToggleNoteMs;
		bNote = true;
	}

	// Forgets the session and stops its autosolver (the cache, F4, the notes and F3's wait stay).
	private void EndSession()
	{
		Phase = ELPH_Phase::Off;
		Auto.Stop();
		Solver = nullptr;
		Tracker = nullptr;
		Frames = 0;
		LockName = NAME_None;
		Removed = 0;
		Plates = 0;
		SessionMessage = "";
		bEarlyNav = false;
		bHasLast = false;
		LastHoles.Reset();
		LastVisible = 0;
		LoggedHoles.Reset();
		LastReadMs = LPH::NeverMs;
		PrepareTicks = 0;
		bOwnSent = false;
		bResetHalf = false;
		ResetAtMs = 0;
		HintSig = "";
		HintModel = FLPH_HintModel();
		LoggedPlan = 0;
	}

	// The cache entry of this lock and skill (-1: none).
	private int CacheFind(FName Lock, int Dropped) const
	{
		for (int i = 0; i < CacheLocks.Num(); i++)
		{
			if (CacheLocks[i] == Lock && CacheRemoved[i] == Dropped)
				return i;
		}
		return -1;
	}

	// The entry At becomes the most recently used.
	private void CacheUse(int At)
	{
		ULPH_Solver Kept = CacheSolvers[At];
		FName KeptLock = CacheLocks[At];
		int KeptRemoved = CacheRemoved[At];
		CacheSolvers.RemoveAt(At);
		CacheLocks.RemoveAt(At);
		CacheRemoved.RemoveAt(At);
		CacheAdd(KeptLock, KeptRemoved, Kept);
	}

	// A prepared solver goes in as the most recently used; the least recently used beyond LPH::ContextCache go out.
	private void CacheAdd(FName Lock, int Dropped, ULPH_Solver Prepared)
	{
		CacheSolvers.Add(Prepared);
		CacheLocks.Add(Lock);
		CacheRemoved.Add(Dropped);
		while (CacheSolvers.Num() > LPH::ContextCache)
		{
			CacheSolvers.RemoveAt(0);
			CacheLocks.RemoveAt(0);
			CacheRemoved.RemoveAt(0);
		}
	}

	private void LogLine(FString Text)
	{
		if (ModLog != nullptr)
			ModLog.Line(Text);
	}

	private void LogDebug(FString Text)
	{
		if (ModLog != nullptr)
			ModLog.Debug(Text);
	}

	// Whether debug lines go to the log (a line that takes work to build is built only then).
	private bool Tracing() const
	{
		return ModLog != nullptr && ModLog.bDebug;
	}
}
