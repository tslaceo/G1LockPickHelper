// What the hint draws for W, S, A, D: the letters or the game's own D-pad icons of a gamepad (pad.lua of 1.2.0, ported by
// meaning: mode, set, resolve and key_texture). The glue reads the settings and the game's state (LPHGame::InputType,
// ButtonGraphics, GamepadName) and asks IconSet; the hint widget asks KeyTexture for the picture of a key.

enum ELPH_IconSet
{
	Letters,
	PlayStation,
	Xbox,
	Switch
}

namespace LPH
{
	// The "Icons" setting (Values.Icons): letters or icons.
	const int IconsAuto = 0; // by the device of the last input
	const int IconsLetters = 1;
	const int IconsGamepad = 2;

	// The "Icon set" setting (Values.Gamepad).
	const int GamepadAsInGame = 0;
	const int GamepadPlayStation = 1;
	const int GamepadXbox = 2;
	const int GamepadSwitch = 3;

	// UCommonInputSubsystem.GetCurrentInputType (ECommonInputType); touch (2) counts as the keyboard.
	const int InputKeyboard = 0;
	const int InputGamepad = 1;

	// UGothicGameUserSettings.ButtonGraphics, the game's "Button icons" option.
	const int GraphicsNone = 0; // "do not use"
	const int GraphicsAuto = 1;
	const int GraphicsXbox = 2;
	const int GraphicsPlayStation = 3;
	const int GraphicsSwitch = 4;

	const FString IconDir = "/Game/UI/Textures/Common/HotkeysIcons/";

	// What the hint draws. IconsSetting and GamepadSetting are the mod's settings; InputType, ButtonGraphics and
	// GamepadName are what the game says now (-1 for an input type or button option that could not be read; NAME_None for
	// a name that could not be read). Letters unless the setting asks for icons, or is auto and the last input was the
	// gamepad's. The game's "do not use" gives the letters with the auto setting, as the game itself draws letters then.
	// Otherwise the mod's own set wins, then the game's option, then (the game's auto) the gamepad's name: PS5 is
	// PlayStation, SWITCH is Switch, any other name is Xbox; an unread or unknown option is Xbox.
	ELPH_IconSet IconSet(int IconsSetting, int GamepadSetting, int InputType, int ButtonGraphics, FName GamepadName)
	{
		bool bIcons = IconsSetting == IconsGamepad || (IconsSetting == IconsAuto && InputType == InputGamepad);
		if (!bIcons)
			return ELPH_IconSet::Letters;
		if (ButtonGraphics == GraphicsNone && IconsSetting == IconsAuto)
			return ELPH_IconSet::Letters;

		if (GamepadSetting == GamepadPlayStation)
			return ELPH_IconSet::PlayStation;
		if (GamepadSetting == GamepadXbox)
			return ELPH_IconSet::Xbox;
		if (GamepadSetting == GamepadSwitch)
			return ELPH_IconSet::Switch;

		if (ButtonGraphics == GraphicsPlayStation)
			return ELPH_IconSet::PlayStation;
		if (ButtonGraphics == GraphicsXbox)
			return ELPH_IconSet::Xbox;
		if (ButtonGraphics == GraphicsSwitch)
			return ELPH_IconSet::Switch;
		if (ButtonGraphics == GraphicsAuto)
		{
			if (GamepadName == n"PS5")
				return ELPH_IconSet::PlayStation;
			if (GamepadName == n"SWITCH")
				return ELPH_IconSet::Switch;
		}
		return ELPH_IconSet::Xbox;
	}

	// Whether the game's name for the gamepad is a real one: CommonUI says "Generic" (or nothing) until the pad has been
	// named, which comes about 1.4 s after its first press.
	bool KnownPadName(FName GamepadName)
	{
		return !GamepadName.IsNone() && GamepadName != n"Generic";
	}

	// Whether IconSet takes the set from the gamepad's name with these settings: icons are drawn, the mod's set is "as in
	// the game" and the game's button icons option is auto.
	bool IconSetByName(int IconsSetting, int GamepadSetting, int InputType, int ButtonGraphics)
	{
		bool bIcons = IconsSetting == IconsGamepad || (IconsSetting == IconsAuto && InputType == InputGamepad);
		return bIcons && ButtonGraphics == GraphicsAuto && GamepadSetting != GamepadPlayStation
			&& GamepadSetting != GamepadXbox && GamepadSetting != GamepadSwitch;
	}

	// IconSet over time (Ruling R15): right after a switch to the gamepad the game has not named it yet, and a set that
	// goes by the name would show Xbox for a moment before the right one. So while the input is the gamepad's for less
	// than PadNameWaitMs (MsSincePad) and its name is not known, such a set keeps Current (the letters on the first
	// switch); after that the name decides (Generic: Xbox). A known name, and a set that does not go by the name, apply
	// at once.
	ELPH_IconSet IconSetNow(ELPH_IconSet Current, int IconsSetting, int GamepadSetting, int InputType, int ButtonGraphics,
		FName GamepadName, int MsSincePad)
	{
		if (InputType == InputGamepad && MsSincePad < PadNameWaitMs && !KnownPadName(GamepadName)
			&& IconSetByName(IconsSetting, GamepadSetting, InputType, ButtonGraphics))
			return Current;
		return IconSet(IconsSetting, GamepadSetting, InputType, ButtonGraphics, GamepadName);
	}

	// The object path of the game's icon of a key in a set (what a TSoftObjectPtr<UTexture2D> is made from): W is the
	// D-pad up, S down, A left, D right. Empty for the letters and for R, which has no icon.
	FString KeyTexture(ELPH_IconSet Set, ELPH_Key Key)
	{
		FString Direction;
		if (Key == ELPH_Key::W)
			Direction = "Up";
		else if (Key == ELPH_Key::S)
			Direction = "Down";
		else if (Key == ELPH_Key::A)
			Direction = "Left";
		else if (Key == ELPH_Key::D)
			Direction = "Right";
		else
			return "";

		FString Asset;
		if (Set == ELPH_IconSet::PlayStation)
			Asset = "T_Icon_PS_Dpad" + Direction;
		else if (Set == ELPH_IconSet::Xbox)
			Asset = "T_Icon_Xbox_Dpad" + Direction;
		else if (Set == ELPH_IconSet::Switch)
			Asset = "T_Icon_Switch_" + Direction;
		else
			return "";
		return IconDir + Asset + "." + Asset;
	}
}
