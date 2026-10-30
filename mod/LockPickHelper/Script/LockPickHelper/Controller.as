// The controller: one minigame session, from the window opening to its closing, and the hint it shows (the session part of
// main.lua of 1.2.0 - tick, render, model_of, step_prepare, drop_auto, on_key and the F4 of drain_keys - ported by
// meaning). It touches no game object: the glue tells it what happens - the minigame opened, its lock, the plates it read,
// the player's presses, F4, the minigame closed - and draws what Display returns. Every time is the caller's LPH::NowMs()
// (the tests hand in their own clock); only the solver's budget per frame is real time.
//
// A session goes through phases: Lock (waiting for the lock's name) -> Prepare (the solver works BudgetMs a frame; a lock
// prepared before comes from the cache of the last LPH::ContextCache locks, ready at once) -> Ready (the minigame takes
// presses only after ReadyDelayMs since it opened and ReadyFrames frames, and the plates count only when two settled
// readings in a row agree) -> Track (the tracker follows the presses and the readings). Idle: no hint for this minigame -
// its lock is not in the database, the visible plates do not fit it, or it has no lock (a chest or door that is not
// locked); the session then shows its message, or nothing, until it closes.
//
// Display shows, in this order: the note of F4 (whatever else is on, F4 off too), the session's message, the hint (or the
// tracker's NoSafePath / BadState; nothing once the lock is open), "auto-pick waits for the lock" (only once the lock is
// known), Thinking (new in 2.0: the solver still prepares after ReadyDelayMs), nothing. F4 off hides all but the note.

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
	const FString HintKeyName = "F4"; // the toggle key's name in its notes (F3 and F4 are fixed in 2.0)
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
	UPROPERTY()
	ULPH_LockDb Db;

	UPROPERTY()
	ULPH_Log ModLog;

	// The autosolver. Task 9 drives it; here it only goes off when the session ends or can have no hint.
	UPROPERTY()
	ULPH_AutoSolve Auto;

	// The session's solver (from LockFound on) and tracker (from Track on).
	UPROPERTY()
	ULPH_Solver Solver;

	UPROPERTY()
	ULPH_Tracker Tracker;

	// The prepared solvers of the last LPH::ContextCache locks, the most recently used last, by the lock and the
	// connections the skill removed (another skill is another graph). 1.x: contexts and context_order.
	UPROPERTY()
	TArray<ULPH_Solver> CacheSolvers;
	TArray<FName> CacheLocks;
	TArray<int> CacheRemoved;

	// Configure.
	FLPH_Values Values;
	FLPH_Texts Texts;
	TArray<FString> Labels; // what the hint writes for W, S, A, D (empty: the letters)
	int Version = 0; // grows with every Configure
	int Icons = 0; // the icon set the hint draws (SetIcons)
	int BudgetMs = LPH::PrepareBudgetMs; // the solver's work per frame (the tests lower it)

	// F4 and its notes: they outlive the sessions.
	bool bEnabled = true;
	bool bNote = false;
	FString Note;
	int64 NoteUntilMs = 0;

	// The session.
	ELPH_Phase Phase = ELPH_Phase::Off;
	int Session = 0; // grows with every Opened
	int64 OpenedMs = 0;
	int Frames = 0; // Ticks since Opened
	FName LockName;
	int Removed = 0; // the connections the skill removed
	int Plates = 0; // the lock's plates in the database
	FString SessionMessage; // shown until the session ends (empty: none)
	bool bEarlyNav = false; // W/S came before the tracker: the cursor is not known (1.x early_nav)
	bool bHasLast = false; // the previous reading was settled: LastHoles, LastVisible
	TArray<int> LastHoles;
	int LastVisible = 0;
	TArray<int> LoggedHoles; // the holes last written to the debug log
	int64 LastReadMs = LPH::NeverMs;
	int PrepareTicks = 0; // the Ticks the solver worked in this session

	// Display: the hint's model and its Sig; the model is built again only when the Sig changes.
	FString HintSig;
	FLPH_HintModel HintModel;
	int LoggedPlan = 0; // the tracker's Plan last written to the debug log
	int ModelBuilds = 0; // models built (the tests count them)

	// Db: the lock database; InLog: the mod's log (nullptr: none). The texts are English until Configure.
	void Init(ULPH_LockDb InDb, ULPH_Log InLog)
	{
		Db = InDb;
		ModLog = InLog;
		Texts = LPH::Texts(ELPH_Lang::En);
		Auto = Cast<ULPH_AutoSolve>(NewObject(this, ULPH_AutoSolve::StaticClass()));
		Auto.Init(LPH::SolveWsGapMs, LPH::SolveTimeoutMs, LPH::SolveMaxReplans);
	}

	// The player's settings, the language of the texts and the labels of W, S, A, D, at every minigame start. A hint shown
	// is drawn again with them; a message already shown keeps its words until it ends. The debug log follows bDebug.
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

	// A minigame opened: a new session that waits for its lock (a session the glue did not close ends here).
	void Opened(int64 Now)
	{
		EndSession();
		Session++;
		Phase = ELPH_Phase::Lock;
		OpenedMs = Now;
		LogDebug("minigame opened");
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
			DropAuto("not in the database");
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

	// The minigame has no lock (a chest or door that is not locked): nothing to show until it closes.
	void NoLock(int64 Now)
	{
		if (Phase != ELPH_Phase::Lock)
			return;
		LogDebug("no lock: nothing to show");
		Phase = ELPH_Phase::Idle;
		DropAuto("no lock");
	}

	// The minigame closed (or its world went away): the session ends; only a note can still show.
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

	// A press of the player (keyboard, gamepad, or the D-pad the glue passes on).
	void PlayerKey(ELPH_Key Key, int64 Now)
	{
		if (Phase == ELPH_Phase::Off)
			return;
		OnKey(Key, Now);
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

	// What to draw now (every frame; the order is in the comment at the top). The hint's model is built again only when its
	// Sig changes.
	FLPH_Display Display(int64 Now)
	{
		if (bNote && Now >= NoteUntilMs)
			bNote = false;
		if (bNote)
			return MessageDisplay(Note);
		if (!bEnabled || Phase == ELPH_Phase::Off)
			return HiddenDisplay();
		if (!SessionMessage.IsEmpty())
			return MessageDisplay(SessionMessage);
		if (Tracker != nullptr)
		{
			FLPH_TrackerSummary Mark = Tracker.Summary();
			if (Mark.Status == ELPH_Status::Ok)
				return HintDisplay(Mark);
			if (Mark.Status == ELPH_Status::NoSafePath)
				return MessageDisplay(Texts.NoSafePath);
			if (Mark.Status == ELPH_Status::BadState)
				return MessageDisplay(Texts.BadState);
			return HiddenDisplay(); // the lock is open
		}
		// Not before the lock is known: a chest or door that is not locked opens the minigame too.
		if (Auto.GetState() == ELPH_AutoState::Armed && Phase != ELPH_Phase::Lock)
			return MessageDisplay(Texts.SolveArmed);
		if (Phase == ELPH_Phase::Prepare && Now - OpenedMs >= LPH::ReadyDelayMs)
			return MessageDisplay(Texts.Thinking);
		return HiddenDisplay();
	}

	// on_key of 1.x: the tracker takes the press; before it exists only W/S matter - the cursor is then not known.
	void OnKey(ELPH_Key Key, int64 Now)
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

	// A reading once the solver is ready (tick of 1.x): only two equal settled readings in a row count. In Ready such a
	// pair starts the tracker once the minigame takes presses (or ends the session's hint when the visible plates do not
	// fit the lock); in Track it goes to the tracker.
	void TakeReading(const FLPH_Reading& Reading, int64 Now)
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
				DropAuto("the visible plates do not fit the lock");
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
	void StartTracking(const FLPH_Reading& Reading, int64 Now)
	{
		// The autosolver runs only with a tracker and Opened/Closed stop it, so it is off or armed here, and an armed one has
		// seen no Plan yet: the new tracker's Plan 1 is no replan for it. (A running one would be from a tracker before.)
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

	// The hint's display: its Sig from the tracker's numbers, the session, the settings' version, the icon set and whether
	// the autosolver runs; the model (and the tracker's View with it) only when that Sig is new.
	FLPH_Display HintDisplay(const FLPH_TrackerSummary& Mark)
	{
		int Running = 0;
		if (Auto.GetState() == ELPH_AutoState::Running)
			Running = 1;
		FString Sig = f"hint|{Session}|{Version}|{Icons}|{Running}|";
		Sig += f"{Mark.Plan}|{Mark.Index}|{Mark.HistoryNum}|{Mark.Pressed}|{Mark.Misses}";
		if (Sig != HintSig)
		{
			FLPH_TrackerView Seen = Tracker.View();
			HintModel = ModelOf(Seen);
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
		FLPH_Display Result;
		Result.Kind = ELPH_DisplayKind::Hint;
		Result.Hint = HintModel;
		Result.Sig = Sig;
		return Result;
	}

	// model_of of 1.x: the tape or the lines of the settings.
	FLPH_HintModel ModelOf(const FLPH_TrackerView& Seen) const
	{
		if (Values.bTape)
			return LPH::Tape(Seen, Values.TapeNext, Values.TapeDone, Labels);
		return LPH::Lines(Seen, Values.PerLine, Values.MaxLines, Values.CollapseMin, Labels);
	}

	FLPH_Display MessageDisplay(FString Text) const
	{
		FLPH_Display Result;
		Result.Kind = ELPH_DisplayKind::Message;
		Result.Message = Text;
		Result.Sig = f"message|{Session}|{Version}|" + Text;
		return Result;
	}

	FLPH_Display HiddenDisplay() const
	{
		FLPH_Display Result;
		Result.Sig = LPH::HiddenSig;
		return Result;
	}

	// A short note over whatever is shown, for ToggleNoteMs.
	void ShowNote(FString Text, int64 Now)
	{
		Note = Text;
		NoteUntilMs = Now + LPH::ToggleNoteMs;
		bNote = true;
	}

	// drop_auto of 1.x: this minigame has no hint, so a waiting autosolver goes off (logged like its other stops).
	void DropAuto(FString Reason)
	{
		if (Auto.GetState() != ELPH_AutoState::Off)
			LogLine("autosolve stopped: " + Reason);
		Auto.Stop();
	}

	// Forgets the session (the cache, F4 and the note stay).
	void EndSession()
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
		HintSig = "";
		HintModel = FLPH_HintModel();
		LoggedPlan = 0;
	}

	// The cache entry of this lock and skill (-1: none).
	int CacheFind(FName Lock, int Dropped) const
	{
		for (int i = 0; i < CacheLocks.Num(); i++)
		{
			if (CacheLocks[i] == Lock && CacheRemoved[i] == Dropped)
				return i;
		}
		return -1;
	}

	// The entry At becomes the most recently used.
	void CacheUse(int At)
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
	void CacheAdd(FName Lock, int Dropped, ULPH_Solver Prepared)
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

	void LogLine(FString Text)
	{
		if (ModLog != nullptr)
			ModLog.Line(Text);
	}

	void LogDebug(FString Text)
	{
		if (ModLog != nullptr)
			ModLog.Debug(Text);
	}

	// Whether debug lines go to the log (a line that takes work to build is built only then).
	bool Tracing() const
	{
		return ModLog != nullptr && ModLog.bDebug;
	}
}
