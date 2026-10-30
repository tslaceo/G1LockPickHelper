// The lockpicking minigame's window (W_LockPickUI) as the mod sees it: an extension of the window, made once per world
// with the window (which lives the whole world and is shown again for every minigame: Construct when a minigame opens,
// Tick every frame while it is open, Destruct when it closes or the world goes). It ties the game to the controller
// (Controller.as), which knows nothing of the game:
// - Construct: the settings (Configure, then Opened - the auto-pick setting arms the session there), the window's key
//   events heard (once per window), the hint attached to the window's canvas, the key catcher (KeyCatcher.as) in the
//   canvas with the focus, the search for the lock started.
// - Tick, in this order: the lock (looked for at once and every LockRetryMs until found; NoLock after LockWaitMs), the
//   icons, the catcher's focus (taken back every FocusRetryMs when lost), the plates (read when the controller wants a
//   reading), the controller's Tick, the auto-pick's key (TakeKey, sent with Broadcast; the handler sees it inside that
//   call as our own - Ruling R2), the drawing (DisplaySig every frame, Display only when it changed - Ruling R10), the
//   hint's animation.
// - The window's key events (m_OnUp/Down/Left/RightPressed, m_OnResetPressed; never m_OnBackPressed, which closes the
//   minigame): our own key during our Broadcast goes to OwnKey, every other press (the keyboard, the gamepad, the D-pad the
//   catcher passes on) to PlayerKey.
// - Destruct: the session ends (Closed) and the hint forgets the window's widgets without a call into them (Ruling R14);
//   the next Construct of the same window takes the old plate out of the canvas first.

// The search for the minigame's lock (LPH::LockStep).
struct FLPH_LockWait
{
	bool bWaiting = false;
	int64 OpenedMs = 0;
	int64 LastTryMs = 0;
	int Tries = 0;
}

enum ELPH_LockStep
{
	None, // nothing this frame
	Try, // look for the lock now
	GiveUp // LockWaitMs passed without a lock: the minigame has none
}

namespace LPH
{
	// A minigame opened at Now: the search starts (its first try is due at once).
	void LockWaitStart(FLPH_LockWait& Wait, int64 Now)
	{
		Wait.bWaiting = true;
		Wait.OpenedMs = Now;
		Wait.LastTryMs = Now;
		Wait.Tries = 0;
	}

	// The lock was found (or the minigame closed): no more tries.
	void LockWaitStop(FLPH_LockWait& Wait)
	{
		Wait.bWaiting = false;
	}

	// What to do in this frame: try at once, then every LockRetryMs (the search walks the hero's abilities and may walk the
	// objects around him: not every frame), give up once LockWaitMs has passed since the opening.
	ELPH_LockStep LockStep(FLPH_LockWait& Wait, int64 Now)
	{
		if (!Wait.bWaiting)
			return ELPH_LockStep::None;
		if (Now - Wait.OpenedMs >= LockWaitMs)
		{
			Wait.bWaiting = false;
			return ELPH_LockStep::GiveUp;
		}
		if (Wait.Tries > 0 && Now - Wait.LastTryMs < LockRetryMs)
			return ELPH_LockStep::None;
		Wait.Tries++;
		Wait.LastTryMs = Now;
		return ELPH_LockStep::Try;
	}

	// A reading for the log: "visible 5, holes 7 5 7 7 5, cursor 1".
	FString ReadingText(const FLPH_Reading& Reading)
	{
		FString Text = f"visible {Reading.Visible}";
		if (!Reading.bSettled)
			return Text + ", not settled";
		Text += ", holes " + HolesText(Reading.Holes);
		if (Reading.Cursor >= 0)
			Text += f", cursor {Reading.Cursor}";
		else
			Text += ", no cursor";
		return Text;
	}
}

class ULPH_LockPickExtension : UGothicModExt_WidgetExtension
{
	default AddToWidgetOfClass = n"/Game/UI/LockPick/W_LockPickUI.W_LockPickUI_C";

	// The mod (a game instance subsystem: it outlives this window).
	UPROPERTY()
	private ULPH_Mod Main;

	// The hint in the window's canvas.
	UPROPERTY()
	private ULPH_HintWidget Hint;

	// The plate of the hint of the last minigame: Destruct forgets it without a call (the world may be going), the next
	// Construct of this window takes it out of the canvas.
	UPROPERTY()
	private UBorder StalePlate;

	// The key catcher in the window's canvas (made once; it stays there between the minigames, like the window).
	UPROPERTY()
	private ULPH_KeyCatcher Catcher;

	private bool bOpen = false; // between Construct and Destruct
	private bool bListening = false; // the window's key events are heard (once per window)
	private int64 OpenedMs = 0;
	private FLPH_LockWait LockWait;
	private int Plates = 0; // the lock's plates in the database (0: not known, or not there)
	private FString LastSig; // what is drawn (the Sig of the controller's Display)

	// Our own Broadcast: bOwnCall while it runs, bOwnSeen once the handler saw the key; bRelaying while the catcher's
	// D-pad press is passed on.
	private bool bOwnCall = false;
	private bool bOwnSeen = false;
	private bool bRelaying = false;

	// The catcher's focus.
	private int64 FocusCheckMs = 0;
	private bool bFocusLost = false;
	private int FocusTries = 0;

	// The readings in the log (debug).
	private bool bFirstReading = false;
	private FString LastReadingText;

	UFUNCTION(BlueprintOverride)
	bool RequiresTick() const
	{
		return true;
	}

	UFUNCTION(BlueprintOverride)
	void Construct()
	{
		Main = LPH::Mod();
		ULockPickUIWidget Window = Cast<ULockPickUIWidget>(GetWidget());
		if (Main == nullptr || Window == nullptr)
			return;
		int64 Now = LPH::NowMs();
		if (bOpen)
			Main.ModLog.Line("minigame window shown again without closing");
		bOpen = true;
		OpenedMs = Now;
		Main.MinigameOpened();

		// The settings before Opened: the auto-pick setting arms the session there (R12).
		FLPH_Values Values = Main.Configure();
		ELPH_IconSet Icons = Main.FollowIcons(Now);
		Main.Controller.Opened(Now);
		Main.ModLog.Debug(f"minigame opened: difficulty {Window.m_LockDifficulty}, the game hears its keys already {Window.m_OnUpPressed.IsBound()}");
		Listen(Window);

		UCanvasPanel Canvas = Cast<UCanvasPanel>(Window.GetRootWidget());
		if (Canvas == nullptr)
			Main.ModLog.Line("the minigame window's root is not a canvas: no hint, no key catcher");

		// The hint (Ruling R14: the plate of the last minigame leaves the canvas now, when this window is alive).
		if (Hint == nullptr)
		{
			Hint = Cast<ULPH_HintWidget>(NewObject(this, ULPH_HintWidget::StaticClass()));
			Hint.UseLog(Main.ModLog);
		}
		if (IsValid(StalePlate))
			StalePlate.RemoveFromParent();
		StalePlate = nullptr;
		if (Canvas != nullptr)
			Hint.Attach(Window, Canvas);
		Hint.Configure(Values);
		Hint.SetIcons(Icons);
		LastSig = "";

		// The key catcher and its focus.
		AddCatcher(Window, Canvas);
		bFocusLost = false;
		FocusTries = 0;
		FocusCheckMs = Now;
		if (Catcher != nullptr)
		{
			bool bKeyboard = TakeFocus();
			Main.ModLog.Debug(f"key catcher: keyboard focus {bKeyboard}, user focus {UserFocus()}");
		}

		// The lock.
		Plates = 0;
		bFirstReading = false;
		LastReadingText = "";
		if (Main.ModLog.bDebug)
			Main.ModLog.Debug("lock search: " + LPHGame::DescribeLockSearch());
		LPH::LockWaitStart(LockWait, Now);
		FollowLock(Now);
	}

	UFUNCTION(BlueprintOverride)
	void Tick(FGeometry MyGeometry, float InDeltaTime)
	{
		if (!bOpen || Main == nullptr)
			return;
		ULPH_Controller Ctl = Main.Controller;
		int64 Now = LPH::NowMs();
		FollowLock(Now);
		Hint.SetIcons(Main.FollowIcons(Now));
		FollowFocus(Now);

		bool bRead = Ctl.WantsReading(Now);
		FLPH_Reading Reading;
		if (bRead)
		{
			Reading = LPHGame::ReadPlates(Plates);
			LogReading(Reading);
		}
		Ctl.Tick(Now, bRead, Reading);

		PressOwnKey(Now);
		if (!bOpen)
			return; // the minigame closed inside our Broadcast (the lock opened)

		Draw(Now);
		Hint.Animate(Now);
		Main.ModLog.FlushIfDue();
	}

	UFUNCTION(BlueprintOverride)
	void Destruct()
	{
		if (!bOpen)
			return;
		bOpen = false;
		LPH::LockWaitStop(LockWait);
		if (Main != nullptr)
		{
			int64 Now = LPH::NowMs();
			Main.ModLog.Debug(f"minigame window closed after {Now - OpenedMs} ms");
			Main.Controller.Closed(Now);
			Main.MinigameClosed();
		}
		if (Hint != nullptr)
		{
			StalePlate = Hint.PlateBorder();
			Hint.Detach();
		}
	}

	// A key the catcher got and what it decided (KeyCatcher.as).
	void Caught(FKey Key, bool bRepeat, ELPH_CatchAction Action, ELPH_Key Pad)
	{
		if (Main == nullptr)
			return;
		if (Action == ELPH_CatchAction::Solve)
		{
			Main.Hotkey(true, "key catcher");
		}
		else if (Action == ELPH_CatchAction::Hint)
		{
			Main.Hotkey(false, "key catcher");
		}
		else if (Action == ELPH_CatchAction::Relay)
		{
			FString Letter = LPH::KeyLetter(Pad);
			if (bRepeat)
				Main.ModLog.Debug(f"key catcher: {Key.KeyName} held, passed on as {Letter}");
			else
				Main.ModLog.Debug(f"key catcher: {Key.KeyName}, passed on as {Letter}");
			Relay(Pad);
		}
		else if (!bRepeat)
		{
			Main.ModLog.Debug(f"key catcher: {Key.KeyName} goes to the minigame");
		}
	}

	// A D-pad press of the player into the minigame, through its event (the handler takes it as the player's).
	void Relay(ELPH_Key Key)
	{
		ULockPickUIWidget Window = Cast<ULockPickUIWidget>(GetWidget());
		if (!bOpen || Window == nullptr)
			return;
		bRelaying = true;
		Press(Window, Key);
		bRelaying = false;
	}

	// The lock: found -> LockFound (with the skill), given up -> NoLock.
	private void FollowLock(int64 Now)
	{
		ELPH_LockStep Step = LPH::LockStep(LockWait, Now);
		if (Step == ELPH_LockStep::Try)
		{
			FName Lock;
			if (!LPHGame::FindLock(Lock))
				return;
			LPH::LockWaitStop(LockWait);
			Plates = Main.PlatesOf(Lock);
			Main.ModLog.Debug(f"lock {Lock} found after {LockWait.Tries} tries, {Now - OpenedMs} ms");
			Main.Controller.LockFound(Lock, LPHGame::Precision(), Now);
		}
		else if (Step == ELPH_LockStep::GiveUp)
		{
			if (Main.ModLog.bDebug)
			{
				FString Search = LPHGame::DescribeLockSearch();
				Main.ModLog.Debug(f"no lock after {Now - OpenedMs} ms, {LockWait.Tries} tries; " + Search);
			}
			Main.Controller.NoLock(Now);
		}
	}

	// The key the autosolver wants pressed, sent with the window's event; the handler sees it inside that call.
	private void PressOwnKey(int64 Now)
	{
		ELPH_Key Key = ELPH_Key::W;
		if (!Main.Controller.TakeKey(Now, Key))
			return;
		ULockPickUIWidget Window = Cast<ULockPickUIWidget>(GetWidget());
		if (Window == nullptr)
		{
			Main.Controller.OwnKeyMissed(Now);
			return;
		}
		bOwnCall = true;
		bOwnSeen = false;
		Press(Window, Key);
		bOwnCall = false;
		if (!bOwnSeen)
			Main.Controller.OwnKeyMissed(Now);
	}

	// W up, S down, A left, D right, R reset (the autosolver never sends R; m_OnBackPressed is never touched).
	private void Press(ULockPickUIWidget Window, ELPH_Key Key)
	{
		if (Key == ELPH_Key::W)
			Window.m_OnUpPressed.Broadcast();
		else if (Key == ELPH_Key::S)
			Window.m_OnDownPressed.Broadcast();
		else if (Key == ELPH_Key::A)
			Window.m_OnLeftPressed.Broadcast();
		else if (Key == ELPH_Key::D)
			Window.m_OnRightPressed.Broadcast();
		else if (Key == ELPH_Key::R)
			Window.m_OnResetPressed.Broadcast();
	}

	// What the controller shows, drawn only when it changed.
	private void Draw(int64 Now)
	{
		ULPH_Controller Ctl = Main.Controller;
		FString Sig = Ctl.DisplaySig(Now);
		if (Sig == LastSig)
			return;
		FLPH_Display Shown = Ctl.Display(Now);
		LastSig = Shown.Sig;
		if (Shown.Kind == ELPH_DisplayKind::Hint)
			Hint.ShowHint(Shown.Hint, Now);
		else if (Shown.Kind == ELPH_DisplayKind::Message)
			Hint.ShowMessage(Shown.Message);
		else
			Hint.Hide();
		Main.ModLog.Debug("draw " + Shown.Sig);
	}

	// The window's key events, heard once per window (it lives the whole world).
	private void Listen(ULockPickUIWidget Window)
	{
		if (bListening)
			return;
		bListening = true;
		Window.m_OnUpPressed.AddUFunction(this, n"OnUp");
		Window.m_OnDownPressed.AddUFunction(this, n"OnDown");
		Window.m_OnLeftPressed.AddUFunction(this, n"OnLeft");
		Window.m_OnRightPressed.AddUFunction(this, n"OnRight");
		Window.m_OnResetPressed.AddUFunction(this, n"OnReset");
	}

	UFUNCTION()
	private void OnUp()
	{
		Heard(ELPH_Key::W);
	}

	UFUNCTION()
	private void OnDown()
	{
		Heard(ELPH_Key::S);
	}

	UFUNCTION()
	private void OnLeft()
	{
		Heard(ELPH_Key::A);
	}

	UFUNCTION()
	private void OnRight()
	{
		Heard(ELPH_Key::D);
	}

	UFUNCTION()
	private void OnReset()
	{
		Heard(ELPH_Key::R);
	}

	// A press the window's event carried: ours inside our Broadcast, the player's otherwise.
	private void Heard(ELPH_Key Key)
	{
		if (!bOpen || Main == nullptr)
			return;
		int64 Now = LPH::NowMs();
		FString Letter = LPH::KeyLetter(Key);
		if (bOwnCall)
		{
			bOwnSeen = true;
			Main.ModLog.Debug(f"press {Letter}: auto-pick");
			Main.Controller.OwnKey(Key, Now);
			return;
		}
		if (bRelaying)
			Main.ModLog.Debug(f"press {Letter}: player, D-pad");
		else
			Main.ModLog.Debug(f"press {Letter}: player");
		Main.Controller.PlayerKey(Key, Now);
	}

	// The catcher in the canvas: an invisible focusable 1x1 widget (made once; put back if it left the canvas).
	private void AddCatcher(ULockPickUIWidget Window, UCanvasPanel Canvas)
	{
		if (Canvas == nullptr)
			return;
		if (Catcher == nullptr)
		{
			Catcher = Cast<ULPH_KeyCatcher>(Window.ConstructWidget(ULPH_KeyCatcher, n"LPH_KeyCatcher"));
			if (Catcher == nullptr)
			{
				Main.ModLog.Line("the key catcher was not made: F3/F4 and the D-pad do not work in the minigame");
				return;
			}
			Catcher.Owner = this;
			Catcher.SetbIsFocusable(true);
			Catcher.SetVisibility(ESlateVisibility::Visible);
		}
		if (Catcher.GetParent() == nullptr)
		{
			UCanvasPanelSlot Slot = Canvas.AddChildToCanvas(Catcher);
			if (Slot != nullptr)
				Slot.SetSize(FVector2D(1.0, 1.0));
		}
	}

	// The keyboard's and the player's focus to the catcher (the keys held before went up elsewhere).
	private bool TakeFocus()
	{
		Catcher.ForgetHeld();
		APlayerController Player = Gameplay::GetPlayerController(0);
		if (Player != nullptr)
			Catcher.SetUserFocus(Player);
		Catcher.SetKeyboardFocus();
		return Catcher.HasKeyboardFocus();
	}

	private bool UserFocus()
	{
		APlayerController Player = Gameplay::GetPlayerController(0);
		return Player != nullptr && Catcher.HasUserFocus(Player);
	}

	// The catcher's focus goes away with Alt+Tab (and the game may take it): taken back every FocusRetryMs.
	private void FollowFocus(int64 Now)
	{
		if (Catcher == nullptr || Now - FocusCheckMs < LPH::FocusRetryMs)
			return;
		FocusCheckMs = Now;
		if (Catcher.HasKeyboardFocus())
		{
			if (bFocusLost)
				Main.ModLog.Debug(f"key catcher: the focus is back ({FocusTries} tries)");
			bFocusLost = false;
			return;
		}
		if (!bFocusLost)
		{
			bFocusLost = true;
			FocusTries = 0;
			Main.ModLog.Debug(f"key catcher: the focus is lost (user focus {UserFocus()}); taking it back");
		}
		FocusTries++;
		if (TakeFocus())
		{
			Main.ModLog.Debug(f"key catcher: the focus is back ({FocusTries} tries)");
			bFocusLost = false;
		}
	}

	// A settled reading that differs from the last one, in the debug log; the first of the minigame with the plates the
	// database has (are the unused plates counted? Ruling R13).
	private void LogReading(const FLPH_Reading& Reading)
	{
		if (!Main.ModLog.bDebug || !Reading.bSettled)
			return;
		FString Text = LPH::ReadingText(Reading);
		if (Text == LastReadingText)
			return;
		LastReadingText = Text;
		if (!bFirstReading)
		{
			bFirstReading = true;
			Main.ModLog.Debug(f"first reading: {Text} (the database has {Plates} plates)");
			return;
		}
		Main.ModLog.Debug("reading: " + Text);
	}
}
