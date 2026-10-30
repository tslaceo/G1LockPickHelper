// The tracker: follows the player through the hint (tracker.lua of 1.2.0, ported by meaning).
//
// The game shows the plates' holes but not which plate the pick is on, so the cursor is followed from the W/S presses as
// an interval Lo..Hi of possible plates (Lo == Hi when it is known). A press updates the expected holes at once; the
// settled holes read from the game confirm them. When the game disagrees, the tracker takes the game's holes and infers
// the cursor from the plate that moved; when that is impossible the new hint starts with enough S presses to park the
// cursor on plate 0 (S does not wrap), so a hint never relies on a guessed cursor. A strained move may break the pick,
// which resets the lock and puts the cursor on plate 0, so strains and a return to the starting holes forget the cursor.
//
// New in 2.0: the game's own highlight shows the selected plate. Observe is given it, and when the cursor is not known
// and no press is waiting for the game, the highlight is the cursor (no parking).
//
// Plates and the cursor are 0-based here (1.x counted from 1); the hint is Keys[Index] and on.

enum ELPH_Status
{
	Ok, // the hint is Keys, its current key Keys[Index] (Index == Keys.Num(): the keys are used up, the game has not shown the open lock yet)
	Solved, // the game shows every hole at 4
	NoSafePath, // no sequence of keys opens the lock from here without a strain
	BadState // the holes do not fit the lock (or the solver is not ready)
}

// A W/S/A/D that was pressed while a hint was shown, and whether it was the key the hint showed.
struct FLPH_Press
{
	ELPH_Key Key;
	bool bOk = false;
}

// What the hint shows. Plan grows by one every time the keys are worked out again (1.x: the keys list was a new table
// then); it only ever grows, also across Init calls of one tracker.
struct FLPH_TrackerView
{
	ELPH_Status Status = ELPH_Status::BadState;
	TArray<ELPH_Key> Keys; // empty unless Status is Ok
	int Index = 0; // the current key is Keys[Index]
	TArray<FLPH_Press> History; // the last LPH::TrackerHistoryMax presses (R clears it)
	int Misses = 0; // presses that were not the hinted key (only grows)
	int Pressed = 0; // presses added to the history (only grows; the history itself is capped)
	int Plan = 0;
}

namespace LPH
{
	const int TrackerHistoryMax = 512; // presses kept for the hint's "done" part
	const int64 NeverMs = -1000000000000; // a time long before any press

	bool SameHoles(const TArray<int>& A, const TArray<int>& B)
	{
		if (A.Num() != B.Num())
			return false;
		for (int i = 0; i < A.Num(); i++)
		{
			if (A[i] != B[i])
				return false;
		}
		return true;
	}

	// True when there is a reading and every hole in it is at 4.
	bool AllAtGoal(const TArray<int>& Holes)
	{
		if (Holes.Num() == 0)
			return false;
		for (int Hole : Holes)
		{
			if (Hole != HoleGoal)
				return false;
		}
		return true;
	}
}

// The expected holes after an A/D, and how many presses of Since there were by then.
struct FLPH_TrailStep
{
	TArray<int> Holes;
	int Count = 0;
}

class ULPH_Tracker : UObject
{
	UPROPERTY()
	ULPH_Solver Solver;

	int PlateCount = 0;
	int GraceWindowMs = 1200; // how long a press may stay invisible before the game is believed
	TArray<int> StartHoles; // the holes the lock returns to when the pick breaks or on R
	TArray<int> Expected; // the holes expected after every press so far
	TArray<int> Seen; // the last holes confirmed by the game
	TArray<ELPH_Key> Since; // the presses after Seen was confirmed
	TArray<FLPH_TrailStep> Trail; // the expected holes after each A/D since Seen
	int64 LastMoveMs = 0;
	bool bDone = false;
	TArray<FLPH_Press> History;
	int Misses = 0;
	int Pressed = 0;
	int Lo = 0; // the cursor is on one of the plates Lo..Hi
	int Hi = 0;
	TArray<ELPH_Key> Keys;
	int Index = 0;
	ELPH_Status Status = ELPH_Status::BadState;
	int Plan = 0;

	// Starts following a lock: Prepared is the lock's ready solver, Holes the settled holes when the minigame became
	// playable, bCursorKnown false when W/S may have been pressed before (the cursor is then not trusted), GraceMs how
	// long a press may stay invisible (LPH::GraceMs). Calling it again starts afresh (Plan keeps growing).
	void Init(ULPH_Solver Prepared, const TArray<int>& Holes, bool bCursorKnown, int GraceMs)
	{
		Solver = Prepared;
		PlateCount = 0;
		if (Prepared != nullptr)
			PlateCount = Prepared.Plates();
		GraceWindowMs = GraceMs;
		StartHoles = Holes;
		Expected = Holes;
		Seen = Holes;
		Since.Reset();
		Trail.Reset();
		LastMoveMs = LPH::NeverMs;
		bDone = false;
		History.Reset();
		Misses = 0;
		Pressed = 0;
		Lo = 0;
		Hi = 0;
		if (!bCursorKnown)
			Hi = LastPlate();
		Replan();
	}

	// A press of the player or of the autosolver; Now is the time of the press (LPH::NowMs()).
	void Key(ELPH_Key Key, int64 Now)
	{
		if (bDone)
			return;
		if (Key != ELPH_Key::R && Status == ELPH_Status::Ok && Index < Keys.Num())
		{
			FLPH_Press Press;
			Press.Key = Key;
			Press.bOk = Key == Keys[Index];
			History.Add(Press);
			if (History.Num() > LPH::TrackerHistoryMax)
				History.RemoveAt(0);
			Pressed++;
			if (!Press.bOk)
				Misses++;
		}
		Since.Add(Key);

		if (Key == ELPH_Key::W || Key == ELPH_Key::S)
		{
			Shift(Key);
		}
		else if (Key == ELPH_Key::A || Key == ELPH_Key::D)
		{
			LastMoveMs = Now;
			if (Lo == Hi)
			{
				TArray<int> Moved;
				int MovedCursor = Lo;
				if (Solver != nullptr && Solver.Apply(Expected, Lo, Key, Moved, MovedCursor))
				{
					Expected = Moved;
					FLPH_TrailStep Step;
					Step.Holes = Moved;
					Step.Count = Since.Num();
					Trail.Add(Step);
				}
				else
				{
					// A strain: the pick may break and reset the cursor.
					Lo = 0;
					Hi = LastPlate();
				}
			}
		}
		else
		{
			// R: the lock goes back to the start and the cursor to plate 0 (the game animates it, pending counts it).
			LastMoveMs = Now;
			Lo = 0;
			Hi = LastPlate();
			Expected = StartHoles;
			Trail.Reset();
			History.Reset();
			Replan();
			return;
		}

		if (Index < Keys.Num() && Keys[Index] == Key)
			Index++;
		else
			Replan();
	}

	// The game's reading: the settled holes of the plates, the plate the game highlights (0..plates - 1; -1: no reading
	// of it), and the time of the reading. If the cursor is not known and no press was waiting for the game when the
	// reading came, the highlight is the cursor from now on and the hint is worked out again without parking. (A highlight
	// is believed only in that case: with a known cursor the presses are the better witness, with a press in flight the
	// highlight may not show it yet.)
	void Observe(const TArray<int>& Holes, int Cursor, int64 Now)
	{
		bool bIdle = Since.Num() == 0;
		ReadHoles(Holes, Now);
		if (bDone || !bIdle || Lo == Hi || Cursor < 0 || Cursor >= PlateCount)
			return;
		Lo = Cursor;
		Hi = Cursor;
		Replan();
	}

	// Moves the game has not confirmed yet: A/D and R (R animates the lock back to the start). 0: the plates show every
	// move so far; the autosolver sends the next key only at 0.
	int Pending() const
	{
		if (bDone)
			return 0;
		int Count = 0;
		for (ELPH_Key Each : Since)
		{
			if (Each == ELPH_Key::A || Each == ELPH_Key::D || Each == ELPH_Key::R)
				Count++;
		}
		return Count;
	}

	FLPH_TrackerView View() const
	{
		FLPH_TrackerView Result;
		Result.Status = Status;
		Result.Keys = Keys;
		Result.Index = Index;
		Result.History = History;
		Result.Misses = Misses;
		Result.Pressed = Pressed;
		Result.Plan = Plan;
		if (bDone)
		{
			Result.Status = ELPH_Status::Solved;
			Result.Keys.Reset();
			Result.Index = 0;
		}
		return Result;
	}

	// The last plate (0 for a lock without plates).
	int LastPlate() const
	{
		return Math::Max(PlateCount - 1, 0);
	}

	// A new hint from the expected holes: Index 0; Ok, NoSafePath or BadState. When the cursor is only known to be among
	// Lo..Hi the hint starts with Hi S presses (the cursor may be on plate Hi and S does not wrap) and then goes on from
	// plate 0.
	void Replan()
	{
		Plan++;
		Index = 0;
		Keys.Reset();

		int At = 0;
		if (Lo == Hi)
			At = Lo;
		ELPH_SolveStatus Reason = ELPH_SolveStatus::BadState;
		TArray<ELPH_Key> Found;
		if (Solver != nullptr)
			Reason = Solver.Solve(Expected, At, Found);

		if (Reason != ELPH_SolveStatus::Ok)
		{
			if (Reason == ELPH_SolveStatus::NoSafePath)
				Status = ELPH_Status::NoSafePath;
			else
				Status = ELPH_Status::BadState;
			return;
		}
		if (Lo != Hi)
		{
			for (int i = 0; i < Hi; i++)
				Keys.Add(ELPH_Key::S);
		}
		for (ELPH_Key Each : Found)
			Keys.Add(Each);
		Status = ELPH_Status::Ok;
	}

	// W/S move the cursor interval one plate (it stops at the ends).
	void Shift(ELPH_Key Key)
	{
		int Step = 1;
		if (Key == ELPH_Key::S)
			Step = -1;
		Lo = Math::Clamp(Lo + Step, 0, LastPlate());
		Hi = Math::Clamp(Hi + Step, 0, LastPlate());
	}

	// The game's holes are the truth now: nothing is waiting for it any more.
	void Confirm(const TArray<int>& Holes)
	{
		Seen = Holes;
		Since.Reset();
		Trail.Reset();
	}

	// The game disagrees with the expected state: take its holes and infer the cursor from the plate that moved.
	void Resync(const TArray<int>& Holes)
	{
		int Moves = 0;
		TArray<ELPH_Key> After; // the W/S after the last A/D
		for (ELPH_Key Each : Since)
		{
			if (Each == ELPH_Key::A || Each == ELPH_Key::D)
			{
				Moves++;
				After.Reset();
			}
			else if (Each == ELPH_Key::R)
			{
				Moves += 2;
			}
			else
			{
				After.Add(Each);
			}
		}

		// One move since the confirmed holes: the cursor was on a plate where A or D gives what the game shows.
		bool bFound = false;
		int Low = 0;
		int High = 0;
		if (Moves == 1 && Solver != nullptr && !LPH::SameHoles(Holes, StartHoles))
		{
			for (int Plate = 0; Plate < PlateCount; Plate++)
			{
				for (int Side = 0; Side < 2; Side++)
				{
					ELPH_Key Try = ELPH_Key::A;
					if (Side == 1)
						Try = ELPH_Key::D;
					TArray<int> Moved;
					int MovedCursor = Plate;
					if (!Solver.Apply(Seen, Plate, Try, Moved, MovedCursor) || !LPH::SameHoles(Moved, Holes))
						continue;
					if (bFound)
					{
						Low = Math::Min(Low, Plate);
						High = Math::Max(High, Plate);
					}
					else
					{
						Low = Plate;
						High = Plate;
						bFound = true;
					}
				}
			}
		}

		if (bFound)
		{
			Lo = Low;
			Hi = High;
			for (ELPH_Key Each : After)
				Shift(Each);
		}
		else
		{
			Lo = 0;
			Hi = LastPlate();
		}
		Expected = Holes;
		Confirm(Holes);
		Replan();
	}

	// The settled holes read from the game against what the presses expect.
	void ReadHoles(const TArray<int>& Holes, int64 Now)
	{
		if (bDone)
			return;
		if (LPH::AllAtGoal(Holes))
		{
			bDone = true;
			return;
		}
		if (LPH::SameHoles(Holes, Expected))
		{
			Confirm(Holes);
			return;
		}
		if (LPH::SameHoles(Holes, Seen))
		{
			if (Now - LastMoveMs < GraceWindowMs)
				return;
			// The presses since Seen did not move the plates: swallowed by the game, or strained. A strain may break
			// the pick (cursor back on plate 0), and if the game dropped a W/S the tracker counted, the cursor is wrong
			// as well, so it is forgotten (parking costs at most plates - 1 S presses).
			Lo = 0;
			Hi = LastPlate();
			Expected = Holes;
			Confirm(Holes);
			Replan();
			return;
		}
		for (int i = 0; i < Trail.Num(); i++)
		{
			if (!LPH::SameHoles(Holes, Trail[i].Holes))
				continue;
			// The game finished the first i + 1 moves; later presses are still animating.
			Seen = Holes;
			int Count = Trail[i].Count;
			TArray<ELPH_Key> Rest;
			for (int j = Count; j < Since.Num(); j++)
				Rest.Add(Since[j]);
			Since = Rest;
			TArray<FLPH_TrailStep> Later;
			for (int j = i + 1; j < Trail.Num(); j++)
			{
				FLPH_TrailStep Step;
				Step.Holes = Trail[j].Holes;
				Step.Count = Trail[j].Count - Count;
				Later.Add(Step);
			}
			Trail = Later;
			return;
		}
		Resync(Holes);
	}
}
