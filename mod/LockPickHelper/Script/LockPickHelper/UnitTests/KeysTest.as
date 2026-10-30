// Keys.as (letters of the keys, W/S vs A/D) and LPH::NowMs (Log.as).

void LPHTests_Keys(ULPH_TestRun T)
{
	T.Begin("Keys");

	// (An initialization list does not compile for a TArray of this enum.)
	TArray<ELPH_Key> Sequence;
	Sequence.Add(ELPH_Key::W);
	Sequence.Add(ELPH_Key::W);
	Sequence.Add(ELPH_Key::D);
	Sequence.Add(ELPH_Key::S);
	Sequence.Add(ELPH_Key::A);
	T.EqualStr(LPH::KeysText(Sequence), "WWDSA", "KeysText of W W D S A");
	TArray<ELPH_Key> Empty;
	T.EqualStr(LPH::KeysText(Empty), "", "KeysText of no keys");

	T.EqualStr(LPH::KeyLetter(ELPH_Key::W), "W", "KeyLetter of W");
	T.EqualStr(LPH::KeyLetter(ELPH_Key::S), "S", "KeyLetter of S");
	T.EqualStr(LPH::KeyLetter(ELPH_Key::A), "A", "KeyLetter of A");
	T.EqualStr(LPH::KeyLetter(ELPH_Key::D), "D", "KeyLetter of D");
	T.EqualStr(LPH::KeyLetter(ELPH_Key::R), "R", "KeyLetter of R");

	T.True(LPH::IsMove(ELPH_Key::A), "A is a move");
	T.True(LPH::IsMove(ELPH_Key::D), "D is a move");
	T.True(!LPH::IsMove(ELPH_Key::W), "W is not a move");
	T.True(!LPH::IsMove(ELPH_Key::S), "S is not a move");
	T.True(!LPH::IsMove(ELPH_Key::R), "R is not a move");

	// NowMs is a smoke check only: it is positive and does not go back across some work.
	int64 First = LPH::NowMs();
	int Count = 0;
	for (int i = 0; i < 100000; i++)
		Count++;
	int64 Second = LPH::NowMs();
	T.EqualInt(Count, 100000, "the NowMs loop ran");
	T.True(First > 0, "NowMs is positive");
	T.True(Second >= First, "NowMs does not go back");
}
