// The hint's model: turns the tracker's view into what the overlay draws (view.lua of 1.2.0, ported by meaning) - a tape
// (the current key with fading neighbours) or lines (the whole sequence, long runs folded into "K×N"). No game here, so
// the tests run it with views made by hand.
//
// The tracker's Index is 0-based (1.x counted from 1): the current key is Keys[Index], the keys pressed so far are
// History, and the counter is "Min(Index, total)/total".
//
// Labels is what the overlay writes instead of the letters: Labels[0..3] for W, S, A, D (the ELPH_Key order). An empty
// array means letters; a key without a label (the array is short, or its entry is empty) shows its letter.

enum ELPH_Role
{
	Done, // a key that was pressed, and it was the hinted one
	Miss, // a key that was pressed, and it was not
	Current, // the key to press now
	Next, // tape: a key after the current one
	Todo, // lines: a key after the current one
	Empty // tape: nothing here (not pressed yet, or the plan has ended)
}

// One cell of the tape. Key is meaningful only when bHasKey (an empty cell has none): the overlay draws the key's icon
// instead of Text.
struct FLPH_Cell
{
	FString Text;
	ELPH_Key Key = ELPH_Key::W;
	bool bHasKey = false;
	ELPH_Role Role = ELPH_Role::Empty;
	float Alpha = 0.0;
}

// One token of a line: a key, or a run of one key written "K×N" (Count = N; 0 for a single key).
struct FLPH_Token
{
	FString Text;
	ELPH_Key Key = ELPH_Key::W;
	int Count = 0;
	ELPH_Role Role = ELPH_Role::Todo;
}

struct FLPH_Line
{
	TArray<FLPH_Token> Tokens;
}

// What Tape and Lines return: a tape has Cells (Done + 1 + Next of them, the current key always the one at Done), lines
// have Lines (at most MaxLines of them). bCounterAlways is for the controller: it shows the counter whatever the
// player's setting (the autosolver's text), the model never sets it.
struct FLPH_HintModel
{
	bool bLines = false;
	FString Counter;
	bool bCounterAlways = false;
	int Pressed = 0;
	int Misses = 0;
	TArray<FLPH_Cell> Cells;
	TArray<FLPH_Line> Lines;
}

// An item of the whole sequence (the history, then the plan from the current key) before it is folded into tokens.
struct FLPH_ViewItem
{
	ELPH_Key Key = ELPH_Key::W;
	ELPH_Role Role = ELPH_Role::Todo;
}

namespace LPH
{
	const float TapeNextFirst = 0.85; // alpha of the first next key on the tape
	const float TapeNextLast = 0.15; // alpha of the last next key
	const float TapeDoneFirst = 0.75; // alpha of the nearest pressed key
	const float TapeDoneLast = 0.28; // alpha of the furthest pressed key
	const FString RunSign = "×"; // U+00D7: the run text is "K×N"

	// The alpha of the I-th of N cells (I counts from 1): First for the 1st, Last for the N-th, evenly between.
	float FadeAlpha(int I, int N, float First, float Last)
	{
		if (N <= 1)
			return First;
		return First - float(I - 1) * (First - Last) / float(N - 1);
	}

	// What the overlay writes for a key: its label, or its letter when it has none.
	FString KeyLabel(ELPH_Key Key, const TArray<FString>& Labels)
	{
		int Slot = -1;
		if (Key == ELPH_Key::W)
			Slot = 0;
		else if (Key == ELPH_Key::S)
			Slot = 1;
		else if (Key == ELPH_Key::A)
			Slot = 2;
		else if (Key == ELPH_Key::D)
			Slot = 3;
		if (Slot >= 0 && Slot < Labels.Num() && Labels[Slot].Len() > 0)
			return Labels[Slot];
		return KeyLetter(Key);
	}

	// "done/total": how many keys of the plan the player is past, of how many it has.
	FString HintCounter(const FLPH_TrackerView& V)
	{
		int Total = V.Keys.Num();
		int Past = Math::Clamp(V.Index, 0, Total);
		return f"{Past}/{Total}";
	}

	// A cell with nothing to show (the struct's defaults).
	FLPH_Cell EmptyCell()
	{
		FLPH_Cell Cell;
		return Cell;
	}

	FLPH_Cell KeyCell(ELPH_Key Key, ELPH_Role Role, float Alpha, const TArray<FString>& Labels)
	{
		FLPH_Cell Cell;
		Cell.Text = KeyLabel(Key, Labels);
		Cell.Key = Key;
		Cell.bHasKey = true;
		Cell.Role = Role;
		Cell.Alpha = Alpha;
		return Cell;
	}

	// The tape: Done cells of the last presses (the nearest to the current key last), the current key, Next cells of
	// the plan. A cell with nothing to show is empty (so the current key keeps its place on the tape).
	FLPH_HintModel Tape(const FLPH_TrackerView& V, int Next, int Done, const TArray<FString>& Labels)
	{
		FLPH_HintModel Model;
		Model.Counter = HintCounter(V);
		Model.Pressed = V.Pressed;
		Model.Misses = V.Misses;

		for (int Back = Done; Back >= 1; Back--) // Back: how many presses back
		{
			int At = V.History.Num() - Back;
			if (At >= 0)
			{
				ELPH_Role Role = ELPH_Role::Miss;
				if (V.History[At].bOk)
					Role = ELPH_Role::Done;
				Model.Cells.Add(KeyCell(V.History[At].Key, Role, FadeAlpha(Back, Done, TapeDoneFirst, TapeDoneLast), Labels));
			}
			else
			{
				Model.Cells.Add(EmptyCell());
			}
		}

		if (V.Index >= 0 && V.Index < V.Keys.Num())
			Model.Cells.Add(KeyCell(V.Keys[V.Index], ELPH_Role::Current, 1.0, Labels));
		else
			Model.Cells.Add(EmptyCell());

		for (int Ahead = 1; Ahead <= Next; Ahead++)
		{
			int At = V.Index + Ahead;
			if (At >= 0 && At < V.Keys.Num())
				Model.Cells.Add(KeyCell(V.Keys[At], ELPH_Role::Next, FadeAlpha(Ahead, Next, TapeNextFirst, TapeNextLast), Labels));
			else
				Model.Cells.Add(EmptyCell());
		}
		return Model;
	}

	// The whole sequence: the history, then the plan from the current key (the current key is the one at History.Num()).
	TArray<FLPH_ViewItem> ViewItems(const FLPH_TrackerView& V)
	{
		TArray<FLPH_ViewItem> Items;
		for (int At = 0; At < V.History.Num(); At++)
		{
			FLPH_ViewItem Item;
			Item.Key = V.History[At].Key;
			if (V.History[At].bOk)
				Item.Role = ELPH_Role::Done;
			else
				Item.Role = ELPH_Role::Miss;
			Items.Add(Item);
		}
		for (int At = Math::Max(V.Index, 0); At < V.Keys.Num(); At++)
		{
			FLPH_ViewItem Item;
			Item.Key = V.Keys[At];
			if (At == V.Index)
				Item.Role = ELPH_Role::Current;
			else
				Item.Role = ELPH_Role::Todo;
			Items.Add(Item);
		}
		return Items;
	}

	FLPH_Token KeyToken(ELPH_Key Key, ELPH_Role Role, const TArray<FString>& Labels)
	{
		FLPH_Token Token;
		Token.Text = KeyLabel(Key, Labels);
		Token.Key = Key;
		Token.Role = Role;
		return Token;
	}

	FLPH_Token RunToken(ELPH_Key Key, ELPH_Role Role, int Count, const TArray<FString>& Labels)
	{
		FLPH_Token Token;
		FString Label = KeyLabel(Key, Labels);
		Token.Text = f"{Label}{RunSign}{Count}";
		Token.Key = Key;
		Token.Count = Count;
		Token.Role = Role;
		return Token;
	}

	// Folds the items into tokens: a run of one key with one role becomes "K×N" (Count = N) when it has MinRun items or
	// more. The run of the current key (its pressed part at the end of the history, then the rest of the plan) is one
	// current token "K×left" - left counts down to 1 - when the whole run is long enough. CurAt is where the current item
	// is; returns the index of the current token in Tokens (-1: there is none).
	int FoldTokens(const TArray<FLPH_ViewItem>& Items, int CurAt, int MinRun, const TArray<FString>& Labels, TArray<FLPH_Token>& Tokens)
	{
		int RunFrom = -1;
		int RunTo = -1;
		if (CurAt >= 0 && CurAt < Items.Num() && Items[CurAt].Role == ELPH_Role::Current)
		{
			ELPH_Key Key = Items[CurAt].Key;
			int From = CurAt;
			int To = CurAt;
			while (From > 0 && Items[From - 1].Role == ELPH_Role::Done && Items[From - 1].Key == Key)
				From--;
			while (To + 1 < Items.Num() && Items[To + 1].Key == Key)
				To++;
			if (To - From + 1 >= MinRun)
			{
				RunFrom = From;
				RunTo = To;
			}
		}

		int CurToken = -1;
		int At = 0;
		while (At < Items.Num())
		{
			if (At == RunFrom)
			{
				Tokens.Add(RunToken(Items[At].Key, ELPH_Role::Current, RunTo - CurAt + 1, Labels));
				CurToken = Tokens.Num() - 1;
				At = RunTo + 1;
				continue;
			}
			int End = At;
			while (End + 1 < Items.Num() && End + 1 != RunFrom && Items[End + 1].Key == Items[At].Key && Items[End + 1].Role == Items[At].Role)
				End++;
			if (End - At + 1 >= MinRun)
			{
				Tokens.Add(RunToken(Items[At].Key, Items[At].Role, End - At + 1, Labels));
			}
			else
			{
				for (int Single = At; Single <= End; Single++)
					Tokens.Add(KeyToken(Items[Single].Key, Items[Single].Role, Labels));
			}
			if (Items[At].Role == ELPH_Role::Current)
				CurToken = Tokens.Num() - 1;
			At = End + 1;
		}
		return CurToken;
	}

	// The lines: the tokens PerLine to a line, at most MaxLines lines. The window keeps the current token's line in view
	// and starts one line above it when it can. CollapseMin below 2 folds nothing.
	FLPH_HintModel Lines(const FLPH_TrackerView& V, int PerLine, int MaxLines, int CollapseMin, const TArray<FString>& Labels)
	{
		FLPH_HintModel Model;
		Model.bLines = true;
		Model.Counter = HintCounter(V);
		Model.Pressed = V.Pressed;
		Model.Misses = V.Misses;

		int MinRun = 2147483647;
		if (CollapseMin >= 2)
			MinRun = CollapseMin;
		TArray<FLPH_ViewItem> Items = ViewItems(V);
		TArray<FLPH_Token> Tokens;
		int CurToken = FoldTokens(Items, V.History.Num(), MinRun, Labels, Tokens);

		int Per = Math::Max(PerLine, 1);
		int Rows = Math::Max(MaxLines, 1);
		int Count = Math::IntegerDivisionTrunc(Tokens.Num() + Per - 1, Per); // lines in all
		if (Count == 0)
			return Model;
		int CurLine = Count - 1;
		if (CurToken >= 0)
			CurLine = Math::IntegerDivisionTrunc(CurToken, Per);
		int First = Math::Max(0, Math::Max(CurLine - Rows + 1, Math::Min(CurLine - 1, Count - Rows)));
		int Last = Math::Min(Count - 1, First + Rows - 1);
		for (int Row = First; Row <= Last; Row++)
		{
			FLPH_Line Line;
			int Upto = Math::Min((Row + 1) * Per, Tokens.Num());
			for (int At = Row * Per; At < Upto; At++)
				Line.Tokens.Add(Tokens[At]);
			Model.Lines.Add(Line);
		}
		return Model;
	}
}
