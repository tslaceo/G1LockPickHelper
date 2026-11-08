// The mod's rows in the game's options ("Game" tab, block "[Mod] LockPick Helper"). The game keeps them in
// GameUserSettings.ini under [/Script/Angelscript.LPH_Settings]: the class name and the property names are part of the
// player's files and must not change. A label is the text of "LPH_Row_<row>" in the game's text database (Texts.as), so it
// follows the game's language in the open menu; Initialize puts the English of LPH::LabelsEn in when the database has
// nothing for a row. The Language row of 2.0 is gone: the mod speaks the game's language. Its line in the players' files
// is left alone (nothing reads it).
// The rest of the mod reads LPH::ReadValues().
//
// The defaults and the limits below repeat FLPH_Values / LPH::Clamped (Values.as): the script cannot read DefaultValue,
// MinValue or MaxValue back from a row, so a change has to be made in all three places.

UCLASS(Config=GameUserSettings)
class ULPH_Settings : UGothicModExt_UserSettings
{
	default CategoryName = FText::FromString("LockPick Helper");

	UPROPERTY(Config)
	FModUserSettingsBool Tape = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = LocText("LPH_Row_Tape"));

	UPROPERTY(Config)
	FModUserSettingsBool Gothic = FModUserSettingsBool(
		Value = false,
		DefaultValue = false,
		DisplayText = LocText("LPH_Row_Gothic"));

	UPROPERTY(Config)
	FModUserSettingsInt Icons = FModUserSettingsInt(
		Value = 0,
		DefaultValue = 0,
		DisplayText = LocText("LPH_Row_Icons"),
		MinValue = 0,
		MaxValue = 2);

	UPROPERTY(Config)
	FModUserSettingsInt Gamepad = FModUserSettingsInt(
		Value = 0,
		DefaultValue = 0,
		DisplayText = LocText("LPH_Row_Gamepad"),
		MinValue = 0,
		MaxValue = 3);

	UPROPERTY(Config)
	FModUserSettingsInt Scale = FModUserSettingsInt(
		Value = 100,
		DefaultValue = 100,
		DisplayText = LocText("LPH_Row_Scale"),
		MinValue = 50,
		MaxValue = 200);

	UPROPERTY(Config)
	FModUserSettingsInt OffsetX = FModUserSettingsInt(
		Value = -760,
		DefaultValue = -760,
		DisplayText = LocText("LPH_Row_OffsetX"),
		MinValue = -3000,
		MaxValue = 3000);

	UPROPERTY(Config)
	FModUserSettingsInt OffsetY = FModUserSettingsInt(
		Value = 0,
		DefaultValue = 0,
		DisplayText = LocText("LPH_Row_OffsetY"),
		MinValue = -2000,
		MaxValue = 2000);

	UPROPERTY(Config)
	FModUserSettingsBool Counter = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = LocText("LPH_Row_Counter"));

	UPROPERTY(Config)
	FModUserSettingsBool Shake = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = LocText("LPH_Row_Shake"));

	UPROPERTY(Config)
	FModUserSettingsInt TapeNext = FModUserSettingsInt(
		Value = 5,
		DefaultValue = 5,
		DisplayText = LocText("LPH_Row_TapeNext"),
		MinValue = 1,
		MaxValue = 10);

	UPROPERTY(Config)
	FModUserSettingsInt TapeDone = FModUserSettingsInt(
		Value = 3,
		DefaultValue = 3,
		DisplayText = LocText("LPH_Row_TapeDone"),
		MinValue = 0,
		MaxValue = 6);

	UPROPERTY(Config)
	FModUserSettingsBool Slide = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = LocText("LPH_Row_Slide"));

	UPROPERTY(Config)
	FModUserSettingsBool Plate = FModUserSettingsBool(
		Value = false,
		DefaultValue = false,
		DisplayText = LocText("LPH_Row_Plate"));

	UPROPERTY(Config)
	FModUserSettingsInt PerLine = FModUserSettingsInt(
		Value = 16,
		DefaultValue = 16,
		DisplayText = LocText("LPH_Row_PerLine"),
		MinValue = 4,
		MaxValue = 40);

	UPROPERTY(Config)
	FModUserSettingsInt MaxLines = FModUserSettingsInt(
		Value = 6,
		DefaultValue = 6,
		DisplayText = LocText("LPH_Row_MaxLines"),
		MinValue = 1,
		MaxValue = 12);

	UPROPERTY(Config)
	FModUserSettingsInt CollapseMin = FModUserSettingsInt(
		Value = 3,
		DefaultValue = 3,
		DisplayText = LocText("LPH_Row_CollapseMin"),
		MinValue = 0,
		MaxValue = 20);

	UPROPERTY(Config)
	FModUserSettingsBool AutoPick = FModUserSettingsBool(
		Value = false,
		DefaultValue = false,
		DisplayText = LocText("LPH_Row_AutoPick"));

	UPROPERTY(Config)
	FModUserSettingsBool DoubleReset = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = LocText("LPH_Row_DoubleReset"));

	UPROPERTY(Config)
	FModUserSettingsBool Timer = FModUserSettingsBool(
		Value = true,
		DefaultValue = true,
		DisplayText = LocText("LPH_Row_Timer"));

	// Not a row: saved in GameUserSettings.ini, never shown in the menu. Whoever asks for a bug report sets it by hand.
	UPROPERTY(Config)
	bool Debug = false;

	// Gives a row whose Text-ID the text database does not answer its English label (a row has no way to change only its
	// label: each one is assigned a new struct with the value it has now). The game calls it at a save load or at a game
	// start. When the database answers, every row keeps the text of its Text-ID, which follows the game's language.
	UFUNCTION(BlueprintOverride)
	void Initialize()
	{
		FLPH_Values D;
		FLPH_Labels L = LPH::LabelsEn();

		Tape = FModUserSettingsBool(
			Value = Tape.bValue,
			DefaultValue = D.bTape,
			DisplayText = LPH::RowText("LPH_Row_Tape", L.Tape));
		Gothic = FModUserSettingsBool(
			Value = Gothic.bValue,
			DefaultValue = D.bGothic,
			DisplayText = LPH::RowText("LPH_Row_Gothic", L.Gothic));
		Icons = FModUserSettingsInt(
			Value = Icons.Value,
			DefaultValue = D.Icons,
			DisplayText = LPH::RowText("LPH_Row_Icons", L.Icons),
			MinValue = 0,
			MaxValue = 2);
		Gamepad = FModUserSettingsInt(
			Value = Gamepad.Value,
			DefaultValue = D.Gamepad,
			DisplayText = LPH::RowText("LPH_Row_Gamepad", L.Gamepad),
			MinValue = 0,
			MaxValue = 3);
		Scale = FModUserSettingsInt(
			Value = Scale.Value,
			DefaultValue = D.Scale,
			DisplayText = LPH::RowText("LPH_Row_Scale", L.Scale),
			MinValue = 50,
			MaxValue = 200);
		OffsetX = FModUserSettingsInt(
			Value = OffsetX.Value,
			DefaultValue = D.OffsetX,
			DisplayText = LPH::RowText("LPH_Row_OffsetX", L.OffsetX),
			MinValue = -3000,
			MaxValue = 3000);
		OffsetY = FModUserSettingsInt(
			Value = OffsetY.Value,
			DefaultValue = D.OffsetY,
			DisplayText = LPH::RowText("LPH_Row_OffsetY", L.OffsetY),
			MinValue = -2000,
			MaxValue = 2000);
		Counter = FModUserSettingsBool(
			Value = Counter.bValue,
			DefaultValue = D.bCounter,
			DisplayText = LPH::RowText("LPH_Row_Counter", L.Counter));
		Shake = FModUserSettingsBool(
			Value = Shake.bValue,
			DefaultValue = D.bShake,
			DisplayText = LPH::RowText("LPH_Row_Shake", L.Shake));
		TapeNext = FModUserSettingsInt(
			Value = TapeNext.Value,
			DefaultValue = D.TapeNext,
			DisplayText = LPH::RowText("LPH_Row_TapeNext", L.TapeNext),
			MinValue = 1,
			MaxValue = 10);
		TapeDone = FModUserSettingsInt(
			Value = TapeDone.Value,
			DefaultValue = D.TapeDone,
			DisplayText = LPH::RowText("LPH_Row_TapeDone", L.TapeDone),
			MinValue = 0,
			MaxValue = 6);
		Slide = FModUserSettingsBool(
			Value = Slide.bValue,
			DefaultValue = D.bSlide,
			DisplayText = LPH::RowText("LPH_Row_Slide", L.Slide));
		Plate = FModUserSettingsBool(
			Value = Plate.bValue,
			DefaultValue = D.bPlate,
			DisplayText = LPH::RowText("LPH_Row_Plate", L.Plate));
		PerLine = FModUserSettingsInt(
			Value = PerLine.Value,
			DefaultValue = D.PerLine,
			DisplayText = LPH::RowText("LPH_Row_PerLine", L.PerLine),
			MinValue = 4,
			MaxValue = 40);
		MaxLines = FModUserSettingsInt(
			Value = MaxLines.Value,
			DefaultValue = D.MaxLines,
			DisplayText = LPH::RowText("LPH_Row_MaxLines", L.MaxLines),
			MinValue = 1,
			MaxValue = 12);
		CollapseMin = FModUserSettingsInt(
			Value = CollapseMin.Value,
			DefaultValue = D.CollapseMin,
			DisplayText = LPH::RowText("LPH_Row_CollapseMin", L.CollapseMin),
			MinValue = 0,
			MaxValue = 20);
		AutoPick = FModUserSettingsBool(
			Value = AutoPick.bValue,
			DefaultValue = D.bAutoPick,
			DisplayText = LPH::RowText("LPH_Row_AutoPick", L.AutoPick));
		DoubleReset = FModUserSettingsBool(
			Value = DoubleReset.bValue,
			DefaultValue = D.bDoubleReset,
			DisplayText = LPH::RowText("LPH_Row_DoubleReset", L.DoubleReset));
		Timer = FModUserSettingsBool(
			Value = Timer.bValue,
			DefaultValue = D.bTimer,
			DisplayText = LPH::RowText("LPH_Row_Timer", L.Timer));
	}
}

namespace LPH
{
	// The rows of one settings object as FLPH_Values, brought into the limits.
	FLPH_Values ValuesOf(const ULPH_Settings Settings)
	{
		FLPH_Values V;
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
