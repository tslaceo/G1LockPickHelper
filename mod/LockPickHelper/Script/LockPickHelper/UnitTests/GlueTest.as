// The glue's own decisions that need no game object: what the key catcher does with a key (KeyCatcher.as), when one press
// of F3/F4 came by both ways (Mod.as), when the minigame's lock is searched for and given up (LockPickExtension.as), the
// reading in the log; and that the mod's game instance subsystem is there in the main menu with its database. The rest of
// the glue (the minigame's window, Broadcast, focus, the viewport layer) is checked in the game.

void LPHTests_Glue(ULPH_TestRun T)
{
	LPHTests_GlueCatch(T);
	LPHTests_GlueHotkeys(T);
	LPHTests_GlueLockWait(T);
	LPHTests_GlueReadingText(T);
	LPHTests_GlueMod(T);
	LPHTests_GlueLogText(T);
}

// The log is written as UTF-8 without a byte order mark (Notepad and the runner read it; the default wrote UTF-16 once a
// line had Cyrillic). Saved/LockPickHelper-tests-utf8.log keeps the line, to look at its bytes.
void LPHTests_GlueLogText(ULPH_TestRun T)
{
	T.Begin("Glue: the log keeps Cyrillic");
	ULPH_Log Probe = Cast<ULPH_Log>(NewObject(T, ULPH_Log::StaticClass()));
	Probe.Open("LockPickHelper-tests-utf8.log");
	FString Text = LPH::Fill(LPH::Texts(ELPH_Lang::Ru).SolvingTime, "12");
	Probe.Line(Text);
	Probe.Flush();
	FString Back;
	T.True(FFileHelper::LoadFileToString(Back, Probe.Path), "the file reads back");
	T.True(Back.Contains(Text), "the Russian line reads back as written");
	T.True(!Probe.bWaiting, "nothing waits after Flush");

	T.Begin("Glue: FlushIfDue");
	Probe.Line("one more");
	T.True(Probe.bWaiting, "a line right after a write waits in memory");
	Probe.FlushIfDue();
	T.True(Probe.bWaiting, "FlushIfDue does not write before LogFlushMs");
	int64 Until = LPH::NowMs() + LPH::LogFlushMs + 10;
	int Spins = 0;
	while (LPH::NowMs() < Until)
		Spins++;
	Probe.FlushIfDue();
	T.True(!Probe.bWaiting, "FlushIfDue writes once LogFlushMs has passed");
	FString Later;
	FFileHelper::LoadFileToString(Later, Probe.Path);
	T.True(Later.Contains("one more") && Later.Contains(Text), "the file has both lines");
}

FString LPHTests_CatchText(ELPH_CatchAction Action)
{
	if (Action == ELPH_CatchAction::Pass)
		return "pass";
	if (Action == ELPH_CatchAction::Solve)
		return "solve";
	if (Action == ELPH_CatchAction::Hint)
		return "hint";
	if (Action == ELPH_CatchAction::Relay)
		return "relay";
	if (Action == ELPH_CatchAction::Swallow)
		return "swallow";
	return "?";
}

// The action for a key, and for a relayed one its letter after a colon ("relay:W").
FString LPHTests_Catch(FKey Key, bool bRepeat)
{
	ELPH_Key Pad = ELPH_Key::R;
	ELPH_CatchAction Action = LPH::CatchAction(Key, bRepeat, Pad);
	FString Text = LPHTests_CatchText(Action);
	if (Action == ELPH_CatchAction::Relay)
		Text += ":" + LPH::KeyLetter(Pad);
	return Text;
}

void LPHTests_GlueCatch(ULPH_TestRun T)
{
	T.Begin("Glue: the key catcher");
	T.EqualStr(LPHTests_Catch(EKeys::F3, false), "solve", "F3 is auto-pick");
	T.EqualStr(LPHTests_Catch(EKeys::F4, false), "hint", "F4 is the hint");
	T.EqualStr(LPHTests_Catch(EKeys::F3, true), "swallow", "a held F3 does not toggle again");
	T.EqualStr(LPHTests_Catch(EKeys::F4, true), "swallow", "a held F4 does not toggle again");

	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_DPad_Up, false), "relay:W", "D-pad up is W");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_DPad_Down, false), "relay:S", "D-pad down is S");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_DPad_Left, false), "relay:A", "D-pad left is A");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_DPad_Right, false), "relay:D", "D-pad right is D");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_DPad_Up, true), "relay:W", "a held D-pad up repeats");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_DPad_Right, true), "relay:D", "a held D-pad right repeats");

	// Everything else reaches the minigame as without the mod.
	T.EqualStr(LPHTests_Catch(EKeys::W, false), "pass", "W passes");
	T.EqualStr(LPHTests_Catch(EKeys::S, false), "pass", "S passes");
	T.EqualStr(LPHTests_Catch(EKeys::A, false), "pass", "A passes");
	T.EqualStr(LPHTests_Catch(EKeys::D, false), "pass", "D passes");
	T.EqualStr(LPHTests_Catch(EKeys::R, false), "pass", "R passes");
	T.EqualStr(LPHTests_Catch(EKeys::Escape, false), "pass", "Esc passes");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_FaceButton_Top, false), "pass", "the top face button (reset) passes");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_FaceButton_Right, false), "pass", "the right face button (exit) passes");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_FaceButton_Bottom, false), "pass", "the bottom face button passes");
	T.EqualStr(LPHTests_Catch(EKeys::Gamepad_LeftStick_Up, false), "pass", "the left stick passes");
	T.EqualStr(LPHTests_Catch(EKeys::Up, false), "pass", "the arrow up passes");
	T.EqualStr(LPHTests_Catch(EKeys::F5, false), "pass", "F5 passes");
	T.EqualStr(LPHTests_Catch(EKeys::W, true), "pass", "a held W passes");

	T.Begin("Glue: held keys");
	FLPH_HeldKeys Held;
	T.True(!LPH::KeyDown(Held, EKeys::F3), "F3 down is a press");
	T.True(LPH::KeyDown(Held, EKeys::F3), "F3 down again before it went up is a repeat");
	T.True(LPH::KeyDown(Held, EKeys::F3), "and again");
	T.True(!LPH::KeyDown(Held, EKeys::F4), "F4 while F3 is held is a press");
	LPH::KeyUp(Held, EKeys::F3);
	T.True(!LPH::KeyDown(Held, EKeys::F3), "F3 after it went up is a press");
	T.True(LPH::KeyDown(Held, EKeys::F4), "F4 is still held");
	LPH::KeyUp(Held, EKeys::Gamepad_DPad_Up);
	T.EqualInt(Held.Keys.Num(), 2, "the up of a key that was not down changes nothing");
	LPH::KeyUp(Held, EKeys::F3);
	LPH::KeyUp(Held, EKeys::F4);
	T.EqualInt(Held.Keys.Num(), 0, "nothing held after both went up");
	LPH::KeyDown(Held, EKeys::F3);
	Held.Keys.Reset(); // the catcher's ForgetHeld
	T.True(!LPH::KeyDown(Held, EKeys::F3), "after forgetting, F3 is a press");
}

void LPHTests_GlueHotkeys(ULPH_TestRun T)
{
	T.Begin("Glue: one press of F3/F4 by two ways");
	FLPH_HotkeyGate Gate;
	T.True(LPH::TakeHotkey(Gate, true, "key binding", 1000), "the first F3 counts");
	T.True(!LPH::TakeHotkey(Gate, true, "key catcher", 1000 + LPH::HotkeyTwiceMs - 1), "the same F3 by the other way does not");
	T.True(LPH::TakeHotkey(Gate, true, "key catcher", 1000 + LPH::HotkeyTwiceMs + 200), "a later F3 by that way counts");

	FLPH_HotkeyGate Same;
	T.True(LPH::TakeHotkey(Same, true, "key catcher", 5000), "F3 by the catcher");
	T.True(LPH::TakeHotkey(Same, true, "key catcher", 5010), "another F3 by the same way counts (a second press)");

	FLPH_HotkeyGate Other;
	T.True(LPH::TakeHotkey(Other, true, "key binding", 7000), "F3");
	T.True(LPH::TakeHotkey(Other, false, "key catcher", 7001), "F4 right after F3 by the other way counts");
	T.True(!LPH::TakeHotkey(Other, false, "key binding", 7002), "the same F4 by the binding does not");

	FLPH_HotkeyGate Edge;
	T.True(LPH::TakeHotkey(Edge, false, "key binding", 9000), "F4");
	T.True(LPH::TakeHotkey(Edge, false, "key catcher", 9000 + LPH::HotkeyTwiceMs), "HotkeyTwiceMs later it is a new press");
}

FString LPHTests_LockStepText(ELPH_LockStep Step)
{
	if (Step == ELPH_LockStep::Try)
		return "try";
	if (Step == ELPH_LockStep::GiveUp)
		return "give up";
	return "none";
}

void LPHTests_GlueLockWait(ULPH_TestRun T)
{
	T.Begin("Glue: the search for the lock");
	FLPH_LockWait Idle;
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Idle, 100)), "none", "nothing before the minigame opens");

	int64 Open = 50000;
	FLPH_LockWait Wait;
	LPH::LockWaitStart(Wait, Open);
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Wait, Open)), "try", "at once when the window opens");
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Wait, Open)), "none", "not again in the same frame");
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Wait, Open + LPH::LockRetryMs - 1)), "none", "not before LockRetryMs");
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Wait, Open + LPH::LockRetryMs)), "try", "again after LockRetryMs");
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Wait, Open + LPH::LockRetryMs + 16)), "none", "the next frame waits");

	// Every frame (16 ms) until LockWaitMs: the tries are LockRetryMs apart, then it gives up once.
	int Tries = 2;
	int GiveUps = 0;
	int64 GaveUpAt = -1;
	for (int64 Now = Open + LPH::LockRetryMs + 32; Now <= Open + LPH::LockWaitMs + 500; Now += 16)
	{
		ELPH_LockStep Step = LPH::LockStep(Wait, Now);
		if (Step == ELPH_LockStep::Try)
			Tries++;
		if (Step == ELPH_LockStep::GiveUp)
		{
			GiveUps++;
			GaveUpAt = Now;
		}
	}
	T.True(Tries >= 18 && Tries <= 20, f"about LockWaitMs / LockRetryMs tries (got {Tries})");
	T.EqualInt(GiveUps, 1, "it gives up once");
	T.True(GaveUpAt >= Open + LPH::LockWaitMs && GaveUpAt < Open + LPH::LockWaitMs + LPH::LockRetryMs,
		"it gives up at LockWaitMs");
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Wait, Open + 9000)), "none", "nothing after giving up");

	FLPH_LockWait Found;
	LPH::LockWaitStart(Found, Open);
	LPH::LockStep(Found, Open);
	LPH::LockWaitStop(Found);
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Found, Open + 500)), "none", "nothing once the lock is found");
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Found, Open + LPH::LockWaitMs + 100)), "none", "and no give-up");

	// A new minigame starts the search anew.
	LPH::LockWaitStart(Found, Open + 60000);
	T.EqualStr(LPHTests_LockStepText(LPH::LockStep(Found, Open + 60000)), "try", "the next minigame searches again");
}

void LPHTests_GlueReadingText(ULPH_TestRun T)
{
	T.Begin("Glue: a reading in the log");
	FLPH_Reading Reading;
	Reading.bSettled = true;
	Reading.Visible = 5;
	Reading.Holes.Add(7);
	Reading.Holes.Add(5);
	Reading.Holes.Add(7);
	Reading.Holes.Add(7);
	Reading.Holes.Add(5);
	Reading.Cursor = 1;
	T.EqualStr(LPH::ReadingText(Reading), "visible 5, holes 7 5 7 7 5, cursor 1", "a settled reading");
	FLPH_Reading Moving;
	Moving.Visible = 7;
	T.EqualStr(LPH::ReadingText(Moving), "visible 7, not settled", "a plate on its way");
	FLPH_Reading Nothing;
	T.EqualStr(LPH::ReadingText(Nothing), "visible 0, not settled", "nothing read");
}

void LPHTests_GlueMod(ULPH_TestRun T)
{
	T.Begin("Glue: the mod in the main menu");
	ULPH_Mod M = LPH::Mod();
	T.True(M != nullptr, "the game instance subsystem is there");
	if (M == nullptr)
		return;
	T.True(M.Db != nullptr && M.Db.Num() == 416, "it holds the lock database (416 locks)");
	T.True(M.Controller != nullptr, "it holds the controller");
	T.True(M.ModLog != nullptr && M.ModLog.Path.Contains("LockPickHelper.log"), "it writes LockPickHelper.log");
	T.True(!M.bMinigameOpen, "no minigame is open");
	T.EqualInt(M.PlatesOf(n"OC_Chest_Mud_Lock"), 5, "PlatesOf a lock of the database");
	T.EqualInt(M.PlatesOf(n"oc_chest_mud_lock"), 5, "PlatesOf ignores case");
	T.EqualInt(M.PlatesOf(n"No_Such_Lock"), 0, "PlatesOf a lock that is not there");
}
