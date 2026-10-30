// The words the mod shows, in two languages: the notes of the hint (lang/en.lua and lang/ru.lua of 1.2.0, `text`) and the
// labels of the rows in the game's options (the same files, `menu.items`, with the numbered `menu.desc` added where a
// row is a choice). Nothing about Shared Mod Menu, settings.ini or UE4SS: 2.0 has none of them. %s and %d of the Lua
// files are {0} here (LPH::Fill). The player-facing name of the autosolver is "auto-pick" / "автовзлом".
// Another language needs a value of ELPH_Lang, its two tables below and a branch in LPH::LangFor.

enum ELPH_Lang
{
	En,
	Ru
}

struct FLPH_Texts
{
	FString NotInDb; // {0}: the lock's name
	FString NoSafePath;
	FString BadState;
	FString HintOn; // {0}: the key's name
	FString HintOff; // {0}: the key's name
	FString Solving; // instead of the counter while the autosolver presses
	FString SolvingTime; // the same with the timer; {0}: about the seconds left
	FString SolveArmed; // F3 or auto-pick before the minigame is ready
	FString SolveStopped; // the autosolver stopped by itself
	FString SolveUnavailable;
	FString SolveOn; // {0}: the key's name, or DoubleReset
	FString SolveOff; // {0}: the key's name
	FString DoubleReset;
	FString Thinking; // new in 2.0: the solver is still preparing the lock
}

// The labels of the rows of ULPH_Settings, one field per row, named like the row.
struct FLPH_Labels
{
	FString Language;
	FString Tape;
	FString Gothic;
	FString Icons;
	FString Gamepad;
	FString Scale;
	FString OffsetX;
	FString OffsetY;
	FString Counter;
	FString Shake;
	FString TapeNext;
	FString TapeDone;
	FString Slide;
	FString Plate;
	FString PerLine;
	FString MaxLines;
	FString CollapseMin;
	FString AutoPick;
	FString DoubleReset;
	FString Timer;
}

namespace LPH
{
	// The language of the mod's texts: Setting is the Language row (1 English, 2 Russian, anything else as in the game);
	// "as in the game" is Russian when the game's interface is Russian, English otherwise.
	ELPH_Lang LangFor(int Setting, FName DisplayLanguage)
	{
		if (Setting == 1)
			return ELPH_Lang::En;
		if (Setting == 2)
			return ELPH_Lang::Ru;
		if (DisplayLanguage == n"Russian")
			return ELPH_Lang::Ru;
		return ELPH_Lang::En;
	}

	// The template with its {0} replaced by Value.
	FString Fill(FString Template, FString Value)
	{
		return Template.Replace("{0}", Value);
	}

	FLPH_Texts TextsEn()
	{
		FLPH_Texts X;
		X.NotInDb = "Lock not in the database: {0}";
		X.NoSafePath = "Can't open without risking the pick";
		X.BadState = "Can't read the lock";
		X.HintOn = "Hint shown ({0})";
		X.HintOff = "Hint hidden ({0})";
		X.Solving = "Auto-picking…";
		X.SolvingTime = "Auto-picking… {0} s";
		X.SolveArmed = "Auto-pick: waiting for the lock";
		X.SolveStopped = "Auto-pick stopped";
		X.SolveUnavailable = "Auto-pick unavailable";
		X.SolveOn = "Auto-pick on ({0})";
		X.SolveOff = "Auto-pick off ({0})";
		X.DoubleReset = "double reset";
		X.Thinking = "Thinking…";
		return X;
	}

	FLPH_Texts TextsRu()
	{
		FLPH_Texts X;
		X.NotInDb = "Замка нет в базе: {0}";
		X.NoSafePath = "Без риска для отмычки не открыть";
		X.BadState = "Не удалось прочитать замок";
		X.HintOn = "Подсказка видна ({0})";
		X.HintOff = "Подсказка скрыта ({0})";
		X.Solving = "Автовзлом…";
		X.SolvingTime = "Автовзлом… {0} с";
		X.SolveArmed = "Автовзлом ждёт замок";
		X.SolveStopped = "Автовзлом остановлен";
		X.SolveUnavailable = "Автовзлом недоступен";
		X.SolveOn = "Автовзлом включён ({0})";
		X.SolveOff = "Автовзлом выключен ({0})";
		X.DoubleReset = "двойной сброс";
		X.Thinking = "Считаю…";
		return X;
	}

	FLPH_Texts Texts(ELPH_Lang Lang)
	{
		if (Lang == ELPH_Lang::Ru)
			return TextsRu();
		return TextsEn();
	}

	FLPH_Labels LabelsEn()
	{
		FLPH_Labels L;
		L.Language = "Language (0 as in the game, 1 English, 2 Русский)";
		L.Tape = "Tape layout";
		L.Gothic = "Gothic style";
		L.Icons = "Letters or icons (0 auto, 1 letters, 2 gamepad icons)";
		L.Gamepad = "Gamepad icon set (0 as in game, 1 PlayStation, 2 Xbox, 3 Switch)";
		L.Scale = "Size, %";
		L.OffsetX = "Position X";
		L.OffsetY = "Position Y";
		L.Counter = "Counter";
		L.Shake = "Shake on a miss";
		L.TapeNext = "Upcoming keys";
		L.TapeDone = "Pressed keys";
		L.Slide = "Smooth scroll";
		L.Plate = "Dark background";
		L.PerLine = "Keys per line";
		L.MaxLines = "Lines on screen";
		L.CollapseMin = "Fold repeats from";
		L.AutoPick = "Always auto-pick";
		L.DoubleReset = "Double reset";
		L.Timer = "Countdown";
		return L;
	}

	FLPH_Labels LabelsRu()
	{
		FLPH_Labels L;
		L.Language = "Язык (0 авто, 1 English, 2 Русский)";
		L.Tape = "Лента вместо строк";
		L.Gothic = "Готический стиль";
		L.Icons = "Буквы или значки (0 авто, 1 буквы, 2 значки)";
		L.Gamepad = "Набор значков (0 как в игре, 1 PS, 2 Xbox, 3 Switch)";
		L.Scale = "Размер, %";
		L.OffsetX = "Положение по X";
		L.OffsetY = "Положение по Y";
		L.Counter = "Счётчик";
		L.Shake = "Тряска при промахе";
		L.TapeNext = "Следующих клавиш";
		L.TapeDone = "Нажатых клавиш";
		L.Slide = "Плавная прокрутка";
		L.Plate = "Тёмный фон";
		L.PerLine = "Клавиш в строке";
		L.MaxLines = "Строк на экране";
		L.CollapseMin = "Сжимать повторы от";
		L.AutoPick = "Автовзлом всегда";
		L.DoubleReset = "Двойной сброс";
		L.Timer = "Таймер";
		return L;
	}

	FLPH_Labels Labels(ELPH_Lang Lang)
	{
		if (Lang == ELPH_Lang::Ru)
			return LabelsRu();
		return LabelsEn();
	}
}
