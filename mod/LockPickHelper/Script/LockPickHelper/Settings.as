// The mod's rows in the game's options ("Game" tab, block "[Mod] LockPick Helper"). The game keeps them in
// GameUserSettings.ini under [/Script/Angelscript.LPH_Settings]: the class name and the property names are part of the
// player's files and must not change. The labels are set in Initialize, in the language of LPH::LangFor
// (whether a change of the Language row relabels an open menu is up to the game: check it in the menu).
// The rest of the mod reads LPH::ReadValues().
//
// The defaults and the limits below repeat FLPH_Values / LPH::Clamped (Values.as): the script cannot read DefaultValue,
// MinValue or MaxValue back from a row, so a change has to be made in all three places.

UCLASS(Config=GameUserSettings)
class ULPH_Settings : UGothicModExt_UserSettings
{
	default CategoryName = FText::FromString("LockPick Helper");

	UPROPERTY(Config)
	FModUserSettingsInt Language = FModUserSettingsInt(
		Value = 0,
		DefaultValue = 0,
		DisplayText = FText::FromString("Language (0 as in the game, 1 English, 2 Русский)"),
		MinValue = 0,
		MaxValue = 2);

	UPROPERTY(Config)
	FModUserSettingsBool Tape = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = FText::FromString("Tape layout"));

	UPROPERTY(Config)
	FModUserSettingsBool Gothic = FModUserSettingsBool(
		Value = false,
		DefaultValue = false,
		DisplayText = FText::FromString("Gothic style"));

	UPROPERTY(Config)
	FModUserSettingsInt Icons = FModUserSettingsInt(
		Value = 0,
		DefaultValue = 0,
		DisplayText = FText::FromString("Icons (0 auto, 1 letters, 2 icons)"),
		MinValue = 0,
		MaxValue = 2);

	UPROPERTY(Config)
	FModUserSettingsInt Gamepad = FModUserSettingsInt(
		Value = 0,
		DefaultValue = 0,
		DisplayText = FText::FromString("Icon set (0 game, 1 PS, 2 Xbox, 3 Switch)"),
		MinValue = 0,
		MaxValue = 3);

	UPROPERTY(Config)
	FModUserSettingsInt Scale = FModUserSettingsInt(
		Value = 100,
		DefaultValue = 100,
		DisplayText = FText::FromString("Size, %"),
		MinValue = 50,
		MaxValue = 200);

	UPROPERTY(Config)
	FModUserSettingsInt OffsetX = FModUserSettingsInt(
		Value = -760,
		DefaultValue = -760,
		DisplayText = FText::FromString("Position X"),
		MinValue = -3000,
		MaxValue = 3000);

	UPROPERTY(Config)
	FModUserSettingsInt OffsetY = FModUserSettingsInt(
		Value = 0,
		DefaultValue = 0,
		DisplayText = FText::FromString("Position Y"),
		MinValue = -2000,
		MaxValue = 2000);

	UPROPERTY(Config)
	FModUserSettingsBool Counter = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = FText::FromString("Counter"));

	UPROPERTY(Config)
	FModUserSettingsBool Shake = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = FText::FromString("Shake on a miss"));

	UPROPERTY(Config)
	FModUserSettingsInt TapeNext = FModUserSettingsInt(
		Value = 5,
		DefaultValue = 5,
		DisplayText = FText::FromString("Upcoming keys"),
		MinValue = 1,
		MaxValue = 10);

	UPROPERTY(Config)
	FModUserSettingsInt TapeDone = FModUserSettingsInt(
		Value = 3,
		DefaultValue = 3,
		DisplayText = FText::FromString("Pressed keys"),
		MinValue = 0,
		MaxValue = 6);

	UPROPERTY(Config)
	FModUserSettingsBool Slide = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = FText::FromString("Smooth scroll"));

	UPROPERTY(Config)
	FModUserSettingsBool Plate = FModUserSettingsBool(
		Value = false,
		DefaultValue = false,
		DisplayText = FText::FromString("Dark background"));

	UPROPERTY(Config)
	FModUserSettingsInt PerLine = FModUserSettingsInt(
		Value = 16,
		DefaultValue = 16,
		DisplayText = FText::FromString("Keys per line"),
		MinValue = 4,
		MaxValue = 40);

	UPROPERTY(Config)
	FModUserSettingsInt MaxLines = FModUserSettingsInt(
		Value = 6,
		DefaultValue = 6,
		DisplayText = FText::FromString("Lines on screen"),
		MinValue = 1,
		MaxValue = 12);

	UPROPERTY(Config)
	FModUserSettingsInt CollapseMin = FModUserSettingsInt(
		Value = 3,
		DefaultValue = 3,
		DisplayText = FText::FromString("Fold repeats from"),
		MinValue = 0,
		MaxValue = 20);

	UPROPERTY(Config)
	FModUserSettingsBool AutoPick = FModUserSettingsBool(
		Value = false,
		DefaultValue = false,
		DisplayText = FText::FromString("Always auto-pick"));

	UPROPERTY(Config)
	FModUserSettingsBool DoubleReset = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = FText::FromString("Double reset"));

	UPROPERTY(Config)
	FModUserSettingsBool Timer = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = FText::FromString("Countdown"));

	// Not a row: saved in GameUserSettings.ini, never shown in the menu. Whoever asks for a bug report sets it by hand.
	UPROPERTY(Config)
	bool Debug = false;

	// Gives every row its label in the player's language (a row has no way to change only its label: each one is
	// assigned a new struct with the value it has now). The game calls it when it builds its options. In the test runs it
	// had not touched the class default object by the time the main menu world started, so a test cannot see it work:
	// look at the options menu itself.
	UFUNCTION(BlueprintOverride)
	void Initialize()
	{
		FLPH_Values D;
		FLPH_Labels L = LPH::Labels(LPH::LangFor(Language.Value, LPH::GameDisplayLanguage()));

		Language = FModUserSettingsInt(
			Value = Language.Value,
			DefaultValue = D.Language,
			DisplayText = FText::FromString(L.Language),
			MinValue = 0,
			MaxValue = 2);
		Tape = FModUserSettingsBool(
			Value = Tape.bValue,
			DefaultValue = D.bTape,
			DisplayText = FText::FromString(L.Tape));
		Gothic = FModUserSettingsBool(
			Value = Gothic.bValue,
			DefaultValue = D.bGothic,
			DisplayText = FText::FromString(L.Gothic));
		Icons = FModUserSettingsInt(
			Value = Icons.Value,
			DefaultValue = D.Icons,
			DisplayText = FText::FromString(L.Icons),
			MinValue = 0,
			MaxValue = 2);
		Gamepad = FModUserSettingsInt(
			Value = Gamepad.Value,
			DefaultValue = D.Gamepad,
			DisplayText = FText::FromString(L.Gamepad),
			MinValue = 0,
			MaxValue = 3);
		Scale = FModUserSettingsInt(
			Value = Scale.Value,
			DefaultValue = D.Scale,
			DisplayText = FText::FromString(L.Scale),
			MinValue = 50,
			MaxValue = 200);
		OffsetX = FModUserSettingsInt(
			Value = OffsetX.Value,
			DefaultValue = D.OffsetX,
			DisplayText = FText::FromString(L.OffsetX),
			MinValue = -3000,
			MaxValue = 3000);
		OffsetY = FModUserSettingsInt(
			Value = OffsetY.Value,
			DefaultValue = D.OffsetY,
			DisplayText = FText::FromString(L.OffsetY),
			MinValue = -2000,
			MaxValue = 2000);
		Counter = FModUserSettingsBool(
			Value = Counter.bValue,
			DefaultValue = D.bCounter,
			DisplayText = FText::FromString(L.Counter));
		Shake = FModUserSettingsBool(
			Value = Shake.bValue,
			DefaultValue = D.bShake,
			DisplayText = FText::FromString(L.Shake));
		TapeNext = FModUserSettingsInt(
			Value = TapeNext.Value,
			DefaultValue = D.TapeNext,
			DisplayText = FText::FromString(L.TapeNext),
			MinValue = 1,
			MaxValue = 10);
		TapeDone = FModUserSettingsInt(
			Value = TapeDone.Value,
			DefaultValue = D.TapeDone,
			DisplayText = FText::FromString(L.TapeDone),
			MinValue = 0,
			MaxValue = 6);
		Slide = FModUserSettingsBool(
			Value = Slide.bValue,
			DefaultValue = D.bSlide,
			DisplayText = FText::FromString(L.Slide));
		Plate = FModUserSettingsBool(
			Value = Plate.bValue,
			DefaultValue = D.bPlate,
			DisplayText = FText::FromString(L.Plate));
		PerLine = FModUserSettingsInt(
			Value = PerLine.Value,
			DefaultValue = D.PerLine,
			DisplayText = FText::FromString(L.PerLine),
			MinValue = 4,
			MaxValue = 40);
		MaxLines = FModUserSettingsInt(
			Value = MaxLines.Value,
			DefaultValue = D.MaxLines,
			DisplayText = FText::FromString(L.MaxLines),
			MinValue = 1,
			MaxValue = 12);
		CollapseMin = FModUserSettingsInt(
			Value = CollapseMin.Value,
			DefaultValue = D.CollapseMin,
			DisplayText = FText::FromString(L.CollapseMin),
			MinValue = 0,
			MaxValue = 20);
		AutoPick = FModUserSettingsBool(
			Value = AutoPick.bValue,
			DefaultValue = D.bAutoPick,
			DisplayText = FText::FromString(L.AutoPick));
		DoubleReset = FModUserSettingsBool(
			Value = DoubleReset.bValue,
			DefaultValue = D.bDoubleReset,
			DisplayText = FText::FromString(L.DoubleReset));
		Timer = FModUserSettingsBool(
			Value = Timer.bValue,
			DefaultValue = D.bTimer,
			DisplayText = FText::FromString(L.Timer));
	}
}

namespace LPH
{
	// The language of the game's own interface (Options > Language); NAME_None when the game's settings are not there.
	FName GameDisplayLanguage()
	{
		UGothicGameUserSettings Game = Cast<UGothicGameUserSettings>(UGameUserSettings::GetGameUserSettings());
		if (Game == nullptr)
			return NAME_None;
		return Game.DisplayLanguage;
	}

	// The rows of one settings object as FLPH_Values, brought into the limits.
	FLPH_Values ValuesOf(const ULPH_Settings Settings)
	{
		FLPH_Values V;
		V.Language = Settings.Language.Value;
		V.bTape = Settings.Tape.bValue;
		V.bGothic = Settings.Gothic.bValue;
		V.Icons = Settings.Icons.Value;
		V.Gamepad = Settings.Gamepad.Value;
		V.Scale = Settings.Scale.Value;
		V.OffsetX = Settings.OffsetX.Value;
		V.OffsetY = Settings.OffsetY.Value;
		V.bCounter = Settings.Counter.bValue;
		V.bShake = Settings.Shake.bValue;
		V.TapeNext = Settings.TapeNext.Value;
		V.TapeDone = Settings.TapeDone.Value;
		V.bSlide = Settings.Slide.bValue;
		V.bPlate = Settings.Plate.bValue;
		V.PerLine = Settings.PerLine.Value;
		V.MaxLines = Settings.MaxLines.Value;
		V.CollapseMin = Settings.CollapseMin.Value;
		V.bAutoPick = Settings.AutoPick.bValue;
		V.bDoubleReset = Settings.DoubleReset.bValue;
		V.bTimer = Settings.Timer.bValue;
		V.bDebug = Settings.Debug;
		return Clamped(V);
	}

	// What the player has set, now (the game keeps the settings on the class default object).
	FLPH_Values ReadValues()
	{
		return ValuesOf(ULPH_Settings.DefaultObject);
	}
}
