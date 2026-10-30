// Icons.as (the pad_test.lua cases of 1.2.0 through LPH::IconSet, the icon textures) and the pure parts of Game.as: the hole
// a plate stands in (LPH::HoleOf) and the build number out of version.txt (LPH::ParseBuild). No game objects.

FString LPHTests_SetName(ELPH_IconSet Set)
{
	if (Set == ELPH_IconSet::Letters)
		return "Letters";
	if (Set == ELPH_IconSet::PlayStation)
		return "PlayStation";
	if (Set == ELPH_IconSet::Xbox)
		return "Xbox";
	if (Set == ELPH_IconSet::Switch)
		return "Switch";
	return "?";
}

// One IconSet call and what it must give. The arguments are the settings and the game's state, in IconSet's order.
void LPHTests_CheckSet(ULPH_TestRun T, ELPH_IconSet Want, int IconsSetting, int GamepadSetting, int InputType,
	int ButtonGraphics, FName GamepadName, FString What)
{
	ELPH_IconSet Got = LPH::IconSet(IconsSetting, GamepadSetting, InputType, ButtonGraphics, GamepadName);
	T.EqualStr(LPHTests_SetName(Got), LPHTests_SetName(Want), What);
}

// One IconSetNow call (Ruling R15): the set drawn now, then IconSet's arguments, then the time on the gamepad.
void LPHTests_CheckNow(ULPH_TestRun T, ELPH_IconSet Want, ELPH_IconSet Current, int IconsSetting, int GamepadSetting,
	int InputType, int ButtonGraphics, FName GamepadName, int MsSincePad, FString What)
{
	ELPH_IconSet Got = LPH::IconSetNow(Current, IconsSetting, GamepadSetting, InputType, ButtonGraphics, GamepadName,
		MsSincePad);
	T.EqualStr(LPHTests_SetName(Got), LPHTests_SetName(Want), What);
}

// R15: after a switch to the gamepad, icons that go by its name wait up to PadNameWaitMs for the name.
void LPHTests_IconsWait(ULPH_TestRun T)
{
	T.Begin("Icons: waiting for the pad's name");
	ELPH_IconSet L = ELPH_IconSet::Letters;
	ELPH_IconSet P = ELPH_IconSet::PlayStation;
	ELPH_IconSet X = ELPH_IconSet::Xbox;
	ELPH_IconSet S = ELPH_IconSet::Switch;
	int Wait = LPH::PadNameWaitMs;

	// By name (the mod's set as in the game, the game's option auto).
	LPHTests_CheckNow(T, L, L, 0, 0, 1, 1, n"Generic", 0, "the first switch keeps the letters while the pad is Generic");
	LPHTests_CheckNow(T, L, L, 0, 0, 1, 1, n"Generic", Wait - 1, "until just before the wait ends");
	LPHTests_CheckNow(T, X, L, 0, 0, 1, 1, n"Generic", Wait, "then Generic is Xbox");
	LPHTests_CheckNow(T, L, L, 0, 0, 1, 1, NAME_None, 0, "no name yet: the letters");
	LPHTests_CheckNow(T, X, L, 0, 0, 1, 1, NAME_None, Wait + 500, "no name after the wait: Xbox");
	LPHTests_CheckNow(T, P, L, 0, 0, 1, 1, n"PS5", 0, "PS5 applies at once");
	LPHTests_CheckNow(T, P, L, 0, 0, 1, 1, n"PS5", 1400, "PS5 named 1.4 s after the switch");
	LPHTests_CheckNow(T, X, L, 0, 0, 1, 1, n"XSX", 0, "XSX applies at once");
	LPHTests_CheckNow(T, S, L, 0, 0, 1, 1, n"SWITCH", 0, "SWITCH applies at once");
	LPHTests_CheckNow(T, P, P, 0, 0, 1, 1, n"Generic", 200, "a set shown already is kept while the name is Generic");

	// Not by name: at once, whatever the name.
	LPHTests_CheckNow(T, P, L, 0, 1, 1, 1, n"Generic", 0, "the mod's PlayStation at once");
	LPHTests_CheckNow(T, S, L, 0, 3, 1, 1, NAME_None, 0, "the mod's Switch at once");
	LPHTests_CheckNow(T, X, L, 0, 0, 1, 2, n"Generic", 0, "the game's Xbox option at once");
	LPHTests_CheckNow(T, P, L, 0, 0, 1, 3, n"Generic", 0, "the game's PS5 option at once");
	LPHTests_CheckNow(T, X, L, 0, 0, 1, -1, n"Generic", 0, "an unread option is Xbox at once");
	LPHTests_CheckNow(T, L, P, 0, 0, 1, 0, n"Generic", 0, "the game's do not use: the letters");
	LPHTests_CheckNow(T, L, P, 1, 0, 1, 1, n"Generic", 0, "the letters setting: the letters");

	// The keyboard.
	LPHTests_CheckNow(T, L, P, 0, 0, 0, 1, n"PS5", 0, "back to the keyboard: the letters at once");
	LPHTests_CheckNow(T, X, L, 2, 0, 0, 1, n"Generic", 0, "icons always, keyboard input: no wait (Generic is Xbox)");
	LPHTests_CheckNow(T, X, X, 2, 0, 1, 1, n"Generic", 100, "icons always, a fresh gamepad: Xbox kept");
	LPHTests_CheckNow(T, P, X, 2, 0, 1, 1, n"PS5", 100, "icons always, the pad named PS5: PlayStation");

	T.True(LPH::KnownPadName(n"PS5") && LPH::KnownPadName(n"XSX") && LPH::KnownPadName(n"SWITCH"), "known names");
	T.True(!LPH::KnownPadName(n"Generic") && !LPH::KnownPadName(n"generic") && !LPH::KnownPadName(NAME_None),
		"Generic and no name are not");
}

void LPHTests_Icons(ULPH_TestRun T)
{
	LPHTests_IconsWait(T);

	// The numbers below: Icons 0 auto, 1 letters, 2 gamepad; Gamepad 0 as in the game, 1 PlayStation, 2 Xbox, 3 Switch;
	// input type 0 keyboard, 1 gamepad, 2 touch, -1 unread; ButtonGraphics 0 do not use, 1 auto, 2 Xbox, 3 PS5, 4 Switch,
	// -1 unread. The names: PS5, SWITCH, XSX, Generic as the CommonUI reports them.

	// pad_test.lua 1: mode - letters always with "letters", icons always with "gamepad", auto follows the input type.
	T.Begin("Icons: mode");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 1, 0, 1, 3, n"PS5", "letters setting + gamepad input");
	LPHTests_CheckSet(T, ELPH_IconSet::Switch, 2, 0, 0, 4, NAME_None, "gamepad setting + keyboard input");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 2, 0, -1, 2, NAME_None, "gamepad setting, input type unread");
	LPHTests_CheckSet(T, ELPH_IconSet::PlayStation, 0, 0, 1, 3, NAME_None, "auto + gamepad input");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 0, 0, 0, 3, NAME_None, "auto + keyboard input");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 0, 0, 2, 3, NAME_None, "auto + touch input");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 0, 0, -1, 3, NAME_None, "auto, input type unread");

	// 2: the game's "Button icons" 2/3/4 is Xbox/PlayStation/Switch, whatever the gamepad is called.
	T.Begin("Icons: the game's choice");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 0, 0, 1, 2, n"PS5", "Xbox option wins over the name");
	LPHTests_CheckSet(T, ELPH_IconSet::PlayStation, 0, 0, 1, 3, n"XSX", "PS5 option");
	LPHTests_CheckSet(T, ELPH_IconSet::Switch, 0, 0, 1, 4, NAME_None, "Switch option");

	// 3: the game's Auto takes the gamepad's name; anything but PS5 and SWITCH is Xbox.
	T.Begin("Icons: the game's auto");
	LPHTests_CheckSet(T, ELPH_IconSet::PlayStation, 0, 0, 1, 1, n"PS5", "auto, PS5");
	LPHTests_CheckSet(T, ELPH_IconSet::Switch, 0, 0, 1, 1, n"SWITCH", "auto, SWITCH");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 0, 0, 1, 1, n"XSX", "auto, XSX");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 0, 0, 1, 1, n"Generic", "auto, Generic");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 0, 0, 1, 1, NAME_None, "auto, no name");

	// 4: "do not use" gives letters with the auto setting, a set with the gamepad setting.
	T.Begin("Icons: do not use");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 0, 0, 1, 0, n"NULL", "auto: letters");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 0, 1, 1, 0, n"NULL", "auto: letters even with a set chosen");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 2, 0, 1, 0, n"NULL", "gamepad setting: Xbox");
	LPHTests_CheckSet(T, ELPH_IconSet::Switch, 2, 3, 1, 0, n"NULL", "gamepad setting: the chosen set");

	// 5: the mod's own set choice wins over the game.
	T.Begin("Icons: the mod's choice");
	LPHTests_CheckSet(T, ELPH_IconSet::PlayStation, 0, 1, 1, 2, n"XSX", "PlayStation chosen");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 0, 2, 1, 3, n"PS5", "Xbox chosen");
	LPHTests_CheckSet(T, ELPH_IconSet::Switch, 2, 3, 1, 1, n"PS5", "Switch chosen with the gamepad setting");

	// 6: an unread or unknown option is Xbox.
	T.Begin("Icons: unread options");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 0, 0, 1, -1, NAME_None, "nothing read");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 0, 0, 1, 7, n"PS5", "an unknown value");

	// 7: resolve - letters or the set the hint draws.
	T.Begin("Icons: resolve");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 0, 0, 0, 3, NAME_None, "keyboard");
	LPHTests_CheckSet(T, ELPH_IconSet::PlayStation, 0, 0, 1, 3, NAME_None, "gamepad, PS5");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 0, 0, 1, 0, NAME_None, "gamepad, do not use");
	LPHTests_CheckSet(T, ELPH_IconSet::Xbox, 2, 0, -1, -1, NAME_None, "icons forced, nothing read");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 1, 1, 1, 2, NAME_None, "letters");
	LPHTests_CheckSet(T, ELPH_IconSet::Letters, 0, 0, -1, -1, NAME_None, "no state");

	// 8: the textures of the 12 combinations; the other key and the letters have none.
	T.Begin("Icons: textures");
	FString Dir = "/Game/UI/Textures/Common/HotkeysIcons/";
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::PlayStation, ELPH_Key::W), Dir + "T_Icon_PS_DpadUp.T_Icon_PS_DpadUp", "PS W");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::PlayStation, ELPH_Key::S), Dir + "T_Icon_PS_DpadDown.T_Icon_PS_DpadDown", "PS S");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::PlayStation, ELPH_Key::A), Dir + "T_Icon_PS_DpadLeft.T_Icon_PS_DpadLeft", "PS A");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::PlayStation, ELPH_Key::D), Dir + "T_Icon_PS_DpadRight.T_Icon_PS_DpadRight", "PS D");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Xbox, ELPH_Key::W), Dir + "T_Icon_Xbox_DpadUp.T_Icon_Xbox_DpadUp", "Xbox W");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Xbox, ELPH_Key::S), Dir + "T_Icon_Xbox_DpadDown.T_Icon_Xbox_DpadDown", "Xbox S");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Xbox, ELPH_Key::A), Dir + "T_Icon_Xbox_DpadLeft.T_Icon_Xbox_DpadLeft", "Xbox A");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Xbox, ELPH_Key::D), Dir + "T_Icon_Xbox_DpadRight.T_Icon_Xbox_DpadRight", "Xbox D");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Switch, ELPH_Key::W), Dir + "T_Icon_Switch_Up.T_Icon_Switch_Up", "Switch W");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Switch, ELPH_Key::S), Dir + "T_Icon_Switch_Down.T_Icon_Switch_Down", "Switch S");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Switch, ELPH_Key::A), Dir + "T_Icon_Switch_Left.T_Icon_Switch_Left", "Switch A");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Switch, ELPH_Key::D), Dir + "T_Icon_Switch_Right.T_Icon_Switch_Right", "Switch D");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::PlayStation, ELPH_Key::R), "", "PS R has none");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Xbox, ELPH_Key::R), "", "Xbox R has none");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Switch, ELPH_Key::R), "", "Switch R has none");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Letters, ELPH_Key::W), "", "letters have none (W)");
	T.EqualStr(LPH::KeyTexture(ELPH_IconSet::Letters, ELPH_Key::D), "", "letters have none (D)");

	LPHTests_HoleOf(T);
	LPHTests_ParseBuild(T);
}

void LPHTests_HoleOf(ULPH_TestRun T)
{
	T.Begin("Game: HoleOf");
	// The settled offsets of holes 1..7 measured in the game, exactly and a little off.
	T.EqualInt(LPH::HoleOf(-18.5), 1, "hole 1 centre");
	T.EqualInt(LPH::HoleOf(-12.2), 2, "hole 2 centre");
	T.EqualInt(LPH::HoleOf(-6.1), 3, "hole 3 centre");
	T.EqualInt(LPH::HoleOf(0.0), 4, "hole 4 centre");
	T.EqualInt(LPH::HoleOf(6.3), 5, "hole 5 centre");
	T.EqualInt(LPH::HoleOf(12.5), 6, "hole 6 centre");
	T.EqualInt(LPH::HoleOf(18.7), 7, "hole 7 centre");
	T.EqualInt(LPH::HoleOf(0.1), 4, "0.1 off the centre of hole 4");
	T.EqualInt(LPH::HoleOf(-18.4), 1, "0.1 off the centre of hole 1");
	T.EqualInt(LPH::HoleOf(18.6), 7, "0.1 off the centre of hole 7");
	T.EqualInt(LPH::HoleOf(-0.25), 4, "just inside 0.3");
	T.EqualInt(LPH::HoleOf(6.54), 5, "just inside 0.3 on the other side");

	// Between the holes a plate is moving; so is anything outside the lock.
	T.EqualInt(LPH::HoleOf(3.0), -1, "between holes 4 and 5");
	T.EqualInt(LPH::HoleOf(-15.0), -1, "between holes 1 and 2");
	T.EqualInt(LPH::HoleOf(0.35), -1, "just outside 0.3");
	T.EqualInt(LPH::HoleOf(-0.35), -1, "just outside 0.3, below");
	T.EqualInt(LPH::HoleOf(-30.0), -1, "far below hole 1");
	T.EqualInt(LPH::HoleOf(30.0), -1, "far above hole 7");
}

void LPHTests_ParseBuild(ULPH_TestRun T)
{
	T.Begin("Game: ParseBuild");
	T.EqualStr(LPH::ParseBuild("Build102_CL175960"), "Build102_CL175960", "the file's text");
	T.EqualStr(LPH::ParseBuild("Build102_CL175960\r\n"), "Build102_CL175960", "with the line end");
	T.EqualStr(LPH::ParseBuild("xx Build102_CL175960 yy"), "Build102_CL175960", "inside other text");
	T.EqualStr(LPH::ParseBuild("Build83_CL12"), "Build83_CL12", "other numbers");
	T.EqualStr(LPH::ParseBuild("Build7_CL1234567890"), "Build7_CL1234567890", "a long change list");
	T.EqualStr(LPH::ParseBuild("Buildx Build5_CL7"), "Build5_CL7", "the first Build is not a build number");
	T.EqualStr(LPH::ParseBuild("Build102_CL175960_extra"), "Build102_CL175960", "stops after the digits");
	T.EqualStr(LPH::ParseBuild(""), "", "empty");
	T.EqualStr(LPH::ParseBuild("garbage"), "", "garbage");
	T.EqualStr(LPH::ParseBuild("Build"), "", "Build alone");
	T.EqualStr(LPH::ParseBuild("Build_CL1"), "", "no build number");
	T.EqualStr(LPH::ParseBuild("Build102_CL"), "", "no change list");
	T.EqualStr(LPH::ParseBuild("Build102CL175960"), "", "no underscore");
	T.EqualStr(LPH::ParseBuild("1.2.3.4"), "", "a plain version");
}
