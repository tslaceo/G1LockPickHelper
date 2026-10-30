// The key catcher: inside the lockpicking minigame no key reaches the player's input (no key binding, no polling), so
// the mod puts an invisible focusable widget of 1x1 into the minigame's canvas and gives it the keyboard and the
// player's focus (probe runs 7-8). A key goes to it first:
// - F3 and F4 it handles itself (auto-pick, the hint; a held key does not toggle again);
// - the D-pad it passes on as the player's W/S/A/D (for the minigame the D-pad moves its own focus, which is on the catcher
//   now; the mod sends the press through the minigame's event instead), held ones too;
// - everything else (W/S/A/D, R, Esc, the face buttons) it leaves alone: the key bubbles up to the minigame's window, which
//   works as without the mod.
// The window's extension (LockPickExtension.as) makes it, keeps its focus and does what it decides.

enum ELPH_CatchAction
{
	Pass, // not ours: the minigame gets it
	Solve, // F3
	Hint, // F4
	Relay, // the D-pad: the player's W/S/A/D through the minigame's event
	Swallow // a held F3/F4: nothing
}

// The keys held down on the catcher. Slate marks the repeats of a held key, but a script cannot read that mark here
// (Input::InputEvent_IsRepeat takes an FInputEvent, and an FKeyEvent does not convert to one in this build), so the
// catcher keeps them itself: down -> held, up -> not held; it forgets them all when it gets the focus anew (an up may have
// gone elsewhere).
struct FLPH_HeldKeys
{
	TArray<FKey> Keys;
}

namespace LPH
{
	// A key went down: true when it was held already (a repeat).
	bool KeyDown(FLPH_HeldKeys& Held, FKey Key)
	{
		for (int i = 0; i < Held.Keys.Num(); i++)
		{
			if (Held.Keys[i] == Key)
				return true;
		}
		Held.Keys.Add(Key);
		return false;
	}

	// A key went up.
	void KeyUp(FLPH_HeldKeys& Held, FKey Key)
	{
		for (int i = Held.Keys.Num() - 1; i >= 0; i--)
		{
			if (Held.Keys[i] == Key)
				Held.Keys.RemoveAt(i);
		}
	}

	// What the catcher does with a key (bRepeat: the key is held and this is a repeat). OutKey: the letter of a relayed
	// D-pad press (up W, down S, left A, right D); left alone otherwise.
	ELPH_CatchAction CatchAction(FKey Key, bool bRepeat, ELPH_Key& OutKey)
	{
		if (Key == EKeys::F3)
		{
			if (bRepeat)
				return ELPH_CatchAction::Swallow;
			return ELPH_CatchAction::Solve;
		}
		if (Key == EKeys::F4)
		{
			if (bRepeat)
				return ELPH_CatchAction::Swallow;
			return ELPH_CatchAction::Hint;
		}
		if (Key == EKeys::Gamepad_DPad_Up)
		{
			OutKey = ELPH_Key::W;
			return ELPH_CatchAction::Relay;
		}
		if (Key == EKeys::Gamepad_DPad_Down)
		{
			OutKey = ELPH_Key::S;
			return ELPH_CatchAction::Relay;
		}
		if (Key == EKeys::Gamepad_DPad_Left)
		{
			OutKey = ELPH_Key::A;
			return ELPH_CatchAction::Relay;
		}
		if (Key == EKeys::Gamepad_DPad_Right)
		{
			OutKey = ELPH_Key::D;
			return ELPH_CatchAction::Relay;
		}
		return ELPH_CatchAction::Pass;
	}
}

class ULPH_KeyCatcher : UUserWidget
{
	// The minigame window's extension that made it: it does what the catcher decides.
	UPROPERTY()
	ULPH_LockPickExtension Owner;

	private FLPH_HeldKeys Held;

	// The catcher got the focus anew: a key that went up meanwhile went elsewhere.
	void ForgetHeld()
	{
		Held.Keys.Reset();
	}

	UFUNCTION(BlueprintOverride)
	FEventReply OnKeyDown(FGeometry MyGeometry, FKeyEvent InKeyEvent)
	{
		if (Owner == nullptr)
			return FEventReply::Unhandled();
		FKey Key = Input::GetKey(InKeyEvent);
		bool bRepeat = LPH::KeyDown(Held, Key);
		ELPH_Key Pad = ELPH_Key::W;
		ELPH_CatchAction Action = LPH::CatchAction(Key, bRepeat, Pad);
		Owner.Caught(Key, bRepeat, Action, Pad);
		if (Action == ELPH_CatchAction::Pass)
			return FEventReply::Unhandled();
		return FEventReply::Handled();
	}

	// The up of a key the catcher took is the catcher's too; the others go on to the minigame.
	UFUNCTION(BlueprintOverride)
	FEventReply OnKeyUp(FGeometry MyGeometry, FKeyEvent InKeyEvent)
	{
		FKey Key = Input::GetKey(InKeyEvent);
		LPH::KeyUp(Held, Key);
		ELPH_Key Pad = ELPH_Key::W;
		if (LPH::CatchAction(Key, false, Pad) == ELPH_CatchAction::Pass)
			return FEventReply::Unhandled();
		return FEventReply::Handled();
	}
}
