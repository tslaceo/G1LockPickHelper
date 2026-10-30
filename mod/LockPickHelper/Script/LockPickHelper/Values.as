// The player's settings as plain numbers: what the rest of the mod reads (Settings.as holds the rows of the game's
// options menu and fills this struct). The defaults are those of settings.lua of 1.2.0; the rows in Settings.as repeat
// them as DefaultValue, and the limits as MinValue and MaxValue.

struct FLPH_Values
{
	int Language = 0; // 0 as in the game, 1 English, 2 Russian
	bool bTape = true; // tape instead of lines
	bool bGothic = false; // a golden letter in a frame instead of a simple key
	int Icons = 0; // 0 auto (by device), 1 letters, 2 gamepad icons
	int Gamepad = 0; // 0 as in the game, 1 PlayStation, 2 Xbox, 3 Switch
	int Scale = 100; // percent
	int OffsetX = -760; // from the right edge; smaller moves it left
	int OffsetY = 0; // bigger moves it down
	bool bCounter = true;
	bool bShake = true;
	int TapeNext = 5; // keys shown after the current one
	int TapeDone = 3; // pressed keys that stay on the left
	bool bSlide = true;
	bool bPlate = false; // dark background under the tape or the lines
	int PerLine = 16;
	int MaxLines = 6;
	int CollapseMin = 3; // N or more same keys in a row fold into "A×N"; 0 or 1: never
	bool bAutoPick = false;
	bool bDoubleReset = true;
	bool bTimer = true;
	bool bDebug = false;
}

namespace LPH
{
	// The same values brought into the limits of the rows (a hand-edited GameUserSettings.ini can hold anything).
	FLPH_Values Clamped(FLPH_Values Values)
	{
		FLPH_Values Result = Values;
		Result.Language = Math::Clamp(Values.Language, 0, 2);
		Result.Icons = Math::Clamp(Values.Icons, 0, 2);
		Result.Gamepad = Math::Clamp(Values.Gamepad, 0, 3);
		Result.Scale = Math::Clamp(Values.Scale, 50, 200);
		Result.OffsetX = Math::Clamp(Values.OffsetX, -3000, 3000);
		Result.OffsetY = Math::Clamp(Values.OffsetY, -2000, 2000);
		Result.TapeNext = Math::Clamp(Values.TapeNext, 1, 10);
		Result.TapeDone = Math::Clamp(Values.TapeDone, 0, 6);
		Result.PerLine = Math::Clamp(Values.PerLine, 4, 40);
		Result.MaxLines = Math::Clamp(Values.MaxLines, 1, 12);
		Result.CollapseMin = Math::Clamp(Values.CollapseMin, 0, 20);
		return Result;
	}
}
