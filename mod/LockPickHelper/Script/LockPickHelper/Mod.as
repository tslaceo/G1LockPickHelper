// The mod for the whole run of the game: a game instance subsystem, made once when the game starts and kept across loads.
// It owns what must outlive a world - the log (LockPickHelper.log, a new file on every start), the lock database, the
// controller (the session, F4, the notes and F3's wait for the next minigame live there) - and nothing of a world (no
// widget, actor or component: those belong to the minigame window's extension and the world subsystems in Hotkeys.as,
// which die with their world). Everyone else reaches it with LPH::Mod().
//
// The settings reach the controller here (Configure): at the start, at every minigame start and right before every F3
// and F4 (Ruling R12). The icon set is decided here too (FollowIcons) and given to the controller when it changes.

// The last F3/F4 that counted (LPH::TakeHotkey).
struct FLPH_HotkeyGate
{
	bool bAny = false;
	bool bSolve = false; // F3 (or F4)
	FString Via; // the way it came: "key binding" or "key catcher"
	int64 AtMs = 0;
}

namespace LPH
{
	// The mod's game instance subsystem (null when there is none, e.g. no game instance yet).
	ULPH_Mod Mod()
	{
		return Cast<ULPH_Mod>(Subsystem::GetGameInstanceSubsystem(ULPH_Mod::StaticClass()));
	}

	// Whether this F3 (bSolve) or F4, which came by Via at Now, is a press of its own. F3/F4 come by the key binding outside
	// the minigame and by the key catcher in it; should one press ever come by both, the second one (the same key by the
	// other way within HotkeyTwiceMs) is not counted. The gate remembers the last press that counted.
	bool TakeHotkey(FLPH_HotkeyGate& Gate, bool bSolve, FString Via, int64 Now)
	{
		if (Gate.bAny && Gate.bSolve == bSolve && Gate.Via != Via && Now - Gate.AtMs < HotkeyTwiceMs)
			return false;
		Gate.bAny = true;
		Gate.bSolve = bSolve;
		Gate.Via = Via;
		Gate.AtMs = Now;
		return true;
	}

	FString IconSetText(ELPH_IconSet Set)
	{
		if (Set == ELPH_IconSet::PlayStation)
			return "PlayStation";
		if (Set == ELPH_IconSet::Xbox)
			return "Xbox";
		if (Set == ELPH_IconSet::Switch)
			return "Switch";
		return "letters";
	}

	FString LangText(ELPH_Lang Lang)
	{
		if (Lang == ELPH_Lang::Ru)
			return "ru";
		return "en";
	}

	// The settings in one line of the log.
	FString ValuesText(const FLPH_Values& V)
	{
		FString Text = f"language {V.Language}, tape {V.bTape}, gothic {V.bGothic}, icons {V.Icons}, gamepad {V.Gamepad}";
		Text += f", size {V.Scale}, position {V.OffsetX} {V.OffsetY}, counter {V.bCounter}, shake {V.bShake}";
		Text += f", tape next {V.TapeNext} done {V.TapeDone}, slide {V.bSlide}, plate {V.bPlate}";
		Text += f", lines {V.PerLine}x{V.MaxLines}, fold from {V.CollapseMin}, auto-pick always {V.bAutoPick}";
		Text += f", double reset {V.bDoubleReset}, timer {V.bTimer}, debug {V.bDebug}";
		return Text;
	}
}

class ULPH_Mod : UScriptGameInstanceSubsystem
{
	UPROPERTY()
	ULPH_Log ModLog;

	UPROPERTY()
	ULPH_LockDb Db;

	UPROPERTY()
	ULPH_Controller Controller;

	// The settings of the last Configure (bDebug on when the debug lines are forced: LPH::DebugAlways or -LPHDebug), and
	// the language of the texts.
	FLPH_Values Values;
	ELPH_Lang Lang = ELPH_Lang::En;

	// The minigame's window is open (its extension says so): the notes are drawn there, not on the viewport layer.
	bool bMinigameOpen = false;

	private bool bConfigured = false;
	private FString DebugWhy; // why the debug lines are on whatever the setting ("" when they follow it)
	private FName GameLanguage;

	// The icon set (FollowIcons) and what it was decided from.
	private bool bIconsKnown = false;
	private ELPH_IconSet Icons = ELPH_IconSet::Letters;
	private int InputType = -1;
	private int ButtonGraphics = -1;
	private FName GamepadName;
	private int64 IconsReadMs = LPH::NeverMs;

	private FLPH_HotkeyGate Gate;

	UFUNCTION(BlueprintOverride)
	void Initialize()
	{
		ModLog = Cast<ULPH_Log>(NewObject(this, ULPH_Log::StaticClass()));
		ModLog.Open("LockPickHelper.log");
		Db = Cast<ULPH_LockDb>(NewObject(this, ULPH_LockDb::StaticClass()));
		LPH_RegisterLockGraphs(Db);
		Controller = Cast<ULPH_Controller>(NewObject(this, ULPH_Controller::StaticClass()));
		Controller.Init(Db, ModLog);
		if (FCommandLine::Get().Contains("-LPHDebug"))
			DebugWhy = "-LPHDebug";
		else if (LPH::DebugAlways)
			DebugWhy = "always for the in-game checks";
		Configure();
		LogStart();
		ModLog.Flush();
	}

	UFUNCTION(BlueprintOverride)
	void Deinitialize()
	{
		if (ModLog != nullptr)
		{
			ModLog.Line("game instance ends");
			ModLog.Flush();
		}
	}

	// The settings and the language now, to the controller (also returned, for the hint widget). The game's input is read
	// again at the next FollowIcons. A change is logged.
	FLPH_Values Configure()
	{
		FLPH_Values V = LPH::ReadValues();
		if (!DebugWhy.IsEmpty())
			V.bDebug = true;
		FName Game = LPHGame::DisplayLanguage();
		ELPH_Lang NewLang = LPH::LangFor(V.Language, Game);
		bool bChanged = !bConfigured || !LPH::SameValues(V, Values);
		bool bLangChanged = bConfigured && (NewLang != Lang || Game != GameLanguage);
		Values = V;
		Lang = NewLang;
		GameLanguage = Game;
		TArray<FString> Letters; // no labels: the hint writes W, S, A, D (the game has no keys of its own for the minigame)
		Controller.Configure(V, NewLang, Letters);
		IconsReadMs = LPH::NeverMs;
		if (bConfigured && bChanged)
			ModLog.Line("settings: " + LPH::ValuesText(V));
		if (bLangChanged)
			ModLog.Line(f"language {LPH::LangText(NewLang)} (setting {V.Language}, game {Game})");
		bConfigured = true;
		return V;
	}

	// The icon set the hint draws now: by the settings, the device of the last input (read every call - cheap), the game's
	// button icons option and the gamepad's name (read every LPH::IconReadMs and after Configure). A new set goes to the
	// controller (it draws the hint again) and to the log. Needs a world (call it from the minigame's window).
	ELPH_IconSet FollowIcons(int64 Now)
	{
		if (Now - IconsReadMs >= LPH::IconReadMs)
		{
			IconsReadMs = Now;
			ButtonGraphics = LPHGame::ButtonGraphics();
			GamepadName = LPHGame::GamepadName();
		}
		int Input = LPHGame::InputType();
		ELPH_IconSet Set = LPH::IconSet(Values.Icons, Values.Gamepad, Input, ButtonGraphics, GamepadName);
		if (!bIconsKnown || Set != Icons || Input != InputType)
		{
			if (!bIconsKnown || Set != Icons)
			{
				FString SetText = LPH::IconSetText(Set);
				ModLog.Line(f"icons: {SetText} (input {Input}, button icons {ButtonGraphics}, gamepad {GamepadName}, settings {Values.Icons}/{Values.Gamepad})");
			}
			else
			{
				ModLog.Debug(f"input {Input}");
			}
			bIconsKnown = true;
			Icons = Set;
			InputType = Input;
			Controller.SetIcons(int(Set));
		}
		return Set;
	}

	// F3 (bSolve) or F4, by the key binding (outside the minigame) or the key catcher (in it): the settings first (R12), then
	// the controller. A press that came by both ways counts once.
	void Hotkey(bool bSolve, FString Via)
	{
		int64 Now = LPH::NowMs();
		FString KeyName = LPH::HintKeyName;
		if (bSolve)
			KeyName = LPH::SolveKeyName;
		if (!LPH::TakeHotkey(Gate, bSolve, Via, Now))
		{
			ModLog.Debug(f"{KeyName} by the {Via} too: the same press");
			return;
		}
		FString Where = bMinigameOpen ? "in the minigame" : "outside the minigame";
		ModLog.Debug(f"{KeyName} by the {Via}, {Where}");
		Configure();
		if (bSolve)
			Controller.Solve(Now);
		else
			Controller.ToggleHint(Now);
	}

	// The minigame's window opened / closed (its extension).
	void MinigameOpened()
	{
		bMinigameOpen = true;
	}

	void MinigameClosed()
	{
		bMinigameOpen = false;
		ModLog.Flush();
	}

	// A world is ready for play (Hotkeys.as). A minigame that was open in the world before (its window gave no Destruct)
	// ends here, with no call into anything of that world.
	void WorldReady(FString WorldName)
	{
		ModLog.Line(f"world ready: {WorldName}");
		if (bMinigameOpen)
		{
			ModLog.Line("a minigame was still open: closed");
			bMinigameOpen = false;
			Controller.Closed(LPH::NowMs());
		}
		ModLog.Flush();
	}

	// How many plates the lock has in the database (0: not there).
	int PlatesOf(FName Lock) const
	{
		FLPH_LockGraph Graph;
		int Dropped = 0;
		if (!Db.Find(Lock, 0, Graph, Dropped))
			return 0;
		return Graph.Plates;
	}

	// The start line (the first questions of a bug report), a warning when the database is for another game build, and the
	// settings.
	private void LogStart()
	{
		FString Build = LPHGame::GameBuild();
		FString BuildText = Build;
		if (Build.IsEmpty())
			BuildText = "unknown";
		FString LangName = LPH::LangText(Lang);
		FString DebugText = "off";
		if (Values.bDebug && DebugWhy.IsEmpty())
			DebugText = "on";
		else if (Values.bDebug)
			DebugText = "on (" + DebugWhy + ")";
		int Graphics = LPHGame::ButtonGraphics();
		int Locks = Db.Num();
		FString Head = f"LockPick Helper {LPH::ModVersion}: game {BuildText}, lock database {LPH::LocksBuild} ({LPH::LocksSource}, {Locks} locks)";
		Head += f", language {LangName} (setting {Values.Language}, game {GameLanguage}), icons {Values.Icons}/{Values.Gamepad} (button icons {Graphics})";
		Head += f", F3/F4 by key binding and key catcher, debug {DebugText}";
		ModLog.Line(Head);
		if (Build.IsEmpty())
			ModLog.Line(f"cannot read the game build; the lock database is for {LPH::LocksBuild}");
		else if (Build != LPH::LocksBuild)
			ModLog.Line(f"WARNING: the lock database is for {LPH::LocksBuild}, the game is {Build}: locks may have changed");
		ModLog.Line("settings: " + LPH::ValuesText(Values));
	}
}
