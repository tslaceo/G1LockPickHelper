// The keys of the lockpicking minigame as the mod's solver and hint see them: W/S move the pick between plates, A/D
// push the selected plate, R resets the lock. The letters are what the hint and the log show.

enum ELPH_Key
{
	W,
	S,
	A,
	D,
	R
}

namespace LPH
{
	FString KeyLetter(ELPH_Key Key)
	{
		// An if chain, not a switch: the compiler counts a switch over all the enum's values as complete and
		// calls a return after it unreachable code (which fails the whole script compile).
		if (Key == ELPH_Key::W)
			return "W";
		if (Key == ELPH_Key::S)
			return "S";
		if (Key == ELPH_Key::A)
			return "A";
		if (Key == ELPH_Key::D)
			return "D";
		if (Key == ELPH_Key::R)
			return "R";
		return "?";
	}

	// A and D change a plate and so can strain the pick; W, S and R do not.
	bool IsMove(ELPH_Key Key)
	{
		return Key == ELPH_Key::A || Key == ELPH_Key::D;
	}

	// The letters in a row: "WWDSA".
	FString KeysText(const TArray<ELPH_Key>& Keys)
	{
		FString Result;
		for (ELPH_Key Key : Keys)
			Result += KeyLetter(Key);
		return Result;
	}
}
