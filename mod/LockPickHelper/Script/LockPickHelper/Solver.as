// The solver: the safe sequence of keys with the fewest A/D presses that opens a lock, found like 1.2.0 did (solver.lua).
//
// Plates are 0..Plates-1 front to back, the hole of a plate is 1..7 and the lock is open when every hole is 4. A press
// of A (-1) or D (+1) moves the selected plate and the plates it is connected with (a connection moves its plate the
// way the selected one goes, or the opposite way); a hole that would leave 1..7 strains the pick, so such a press is not
// a move. Moves can be undone, so one search from the open lock (every hole 4) gives the distance of every state to it.
// A state is the number code = sum((hole - 1) * 7^plate); Dist is indexed by code, -1 is "not reached". Begin only builds
// the moves (a few hundred operations); Step does all the work that grows with the number of states (7^plates, 823,543
// for 7 plates): filling Dist with -1, then the search. Both go in pieces of LPH::SolverChunk, so a lock is prepared over
// several frames, each taking the time it is given.
//
// To keep the search fast every state also travels as a packed number (4 bits per plate, hole - 1), from which one table
// lookup per two plates says which of the moves are open; the move's change of the code and of the packed number are
// computed once, from the connections.

enum ELPH_SolveStatus
{
	Ok,
	NoSafePath,
	BadState
}

namespace LPH
{
	const int HoleMin = 1;
	const int HoleMax = 7;
	const int HoleGoal = 4;
	const int SolverMaxPlates = 7; // 7^7 states is the biggest search (all the locks of the game have 4 to 7 plates)
	const int SolverChunk = 1000; // states filled or searched between two looks at the clock
}

class ULPH_Solver : UObject
{
	int PlateCount = 0; // 0: no lock (or one that the solver cannot take)
	int MoveCount = 0; // 2 * PlateCount
	bool bReady = false;

	// The moves, in the order the choice among equal ones walks them: plate 0 A, plate 0 D, plate 1 A, plate 1 D, ...
	// (move = plate * 2 + (D ? 1 : 0)). Move m changes the holes at EffectPlate[e] by EffectDelta[e] for e in
	// EffectFirst[m] .. EffectFirst[m + 1] - 1 (the plates with a change other than 0, front to back).
	TArray<int> Weights; // 7^plate
	TArray<int> MoveOffset; // the change of the code
	TArray<int> MovePacked; // the change of the packed number
	TArray<int> EffectFirst;
	TArray<int> EffectPlate;
	TArray<int> EffectDelta;

	// OpenBy[group * 256 + byte]: the moves that the holes of the plates 2*group (low 4 bits of the byte) and
	// 2*group + 1 (high 4 bits) leave open (bit m is move m).
	TArray<int> OpenBy;

	int StateCount = 0; // 7^PlateCount
	int GoalCode = 0; // the code and the packed number of the open lock (every hole 4)
	int GoalPacked = 0;

	// The work of Step. Dist grows to StateCount entries of -1 (its length says how far the fill is), then the queue gets
	// the goal and the search goes on until the queue is used up.
	TArray<int> Dist;
	TArray<int> Queue; // the codes found, in the order of the search
	TArray<int> QueuePacked; // and the same states, packed
	int Head = 0; // the next of them to look at
	int Tail = 0; // how many there are (0: the search has not started)

	// Starts the preparation for this lock; Step does the work (Begin is quick: it builds the moves and nothing the size of
	// the state space). A solver is used for one lock after another: what it had is dropped (and its memory freed). A graph with no plates or more than LPH::SolverMaxPlates cannot be searched:
	// the solver is then ready at once with no plates, and every Solve says BadState. Connections that name a plate the
	// lock does not have are skipped.
	void Begin(FLPH_LockGraph Graph)
	{
		Clear();
		if (Graph.Plates < 1 || Graph.Plates > LPH::SolverMaxPlates)
		{
			bReady = true;
			return;
		}
		PlateCount = Graph.Plates;
		MoveCount = PlateCount * 2;

		int Size = 1;
		for (int Plate = 0; Plate < PlateCount; Plate++)
		{
			Weights.Add(Size);
			Size *= 7;
		}

		int Edges = Math::Min(Graph.Src.Num(), Math::Min(Graph.Dst.Num(), Graph.Dir.Num()));
		for (int Move = 0; Move < MoveCount; Move++)
		{
			int Selected = Move >> 1;
			int Dir = -1;
			if ((Move & 1) != 0)
				Dir = 1;

			// The change of every plate: the selected one by Dir, the ones it is connected with by Dir times the
			// connection's direction (connections to one plate add up).
			TArray<int> Delta;
			for (int Plate = 0; Plate < PlateCount; Plate++)
				Delta.Add(0);
			Delta[Selected] = Dir;
			for (int Edge = 0; Edge < Edges; Edge++)
			{
				int To = Graph.Dst[Edge];
				if (Graph.Src[Edge] == Selected && To >= 0 && To < PlateCount)
					Delta[To] += Dir * Graph.Dir[Edge];
			}

			EffectFirst.Add(EffectPlate.Num());
			int Offset = 0;
			int Packed = 0;
			for (int Plate = 0; Plate < PlateCount; Plate++)
			{
				if (Delta[Plate] == 0)
					continue;
				EffectPlate.Add(Plate);
				EffectDelta.Add(Delta[Plate]);
				Offset += Delta[Plate] * Weights[Plate];
				Packed += Delta[Plate] * (1 << (4 * Plate));
			}
			MoveOffset.Add(Offset);
			MovePacked.Add(Packed);
		}
		EffectFirst.Add(EffectPlate.Num());

		// Which moves each pair of plates leaves open: all of them, less those that would take one of the pair's holes
		// out of 1..7.
		int AllMoves = (1 << MoveCount) - 1;
		for (int Entry = 0; Entry < 4 * 256; Entry++)
			OpenBy.Add(AllMoves);
		for (int Move = 0; Move < MoveCount; Move++)
		{
			for (int Effect = EffectFirst[Move]; Effect < EffectFirst[Move + 1]; Effect++)
			{
				int Plate = EffectPlate[Effect];
				for (int Value = 0; Value <= LPH::HoleMax - LPH::HoleMin; Value++)
				{
					int After = Value + EffectDelta[Effect];
					if (After >= 0 && After <= LPH::HoleMax - LPH::HoleMin)
						continue;
					for (int Other = 0; Other <= LPH::HoleMax - LPH::HoleMin; Other++)
					{
						int Byte = (Other << 4) | Value;
						if ((Plate & 1) != 0)
							Byte = (Value << 4) | Other;
						int Entry = (Plate >> 1) * 256 + Byte;
						OpenBy[Entry] = OpenBy[Entry] & ~(1 << Move);
					}
				}
			}
		}

		StateCount = Size;
		for (int Plate = 0; Plate < PlateCount; Plate++)
		{
			GoalCode += (LPH::HoleGoal - LPH::HoleMin) * Weights[Plate];
			GoalPacked += (LPH::HoleGoal - LPH::HoleMin) * (1 << (4 * Plate));
		}
	}

	// Goes on with the preparation for about BudgetMs milliseconds (the clock is looked at once in LPH::SolverChunk
	// states, in the fill and in the search alike). At least one such piece is done even with 0 ms, so that repeated
	// calls always come to an end. True when the solver is ready (and for one that was ready already). False also for a
	// solver that was never given a lock.
	bool Step(int BudgetMs)
	{
		if (bReady)
			return true;
		if (PlateCount == 0)
			return false;

		int64 Started = LPH::NowMs();
		do
		{
			if (Dist.Num() < StateCount)
				FillPiece();
			else
				SearchPiece();
		}
		while (!bReady && LPH::NowMs() - Started < BudgetMs);
		return bReady;
	}

	// Adds up to LPH::SolverChunk entries of "not reached" to Dist.
	void FillPiece()
	{
		int Count = Math::Min(LPH::SolverChunk, StateCount - Dist.Num());
		for (int i = 0; i < Count; i++)
			Dist.Add(-1);
	}

	// Looks at up to LPH::SolverChunk states of the queue and puts the states one move away that were not reached yet
	// at its end: their distance is one more. The first piece starts the queue with the open lock; the one that uses
	// the queue up makes the solver ready (and frees the queue).
	void SearchPiece()
	{
		if (Tail == 0)
		{
			Dist[GoalCode] = 0;
			Queue.Add(GoalCode);
			QueuePacked.Add(GoalPacked);
			Tail = 1;
		}
		int Left = LPH::SolverChunk;
		while (Head < Tail && Left > 0)
		{
			Left--;
			int Code = Queue[Head];
			int Packed = QueuePacked[Head];
			Head++;

			int Open = OpenBy[Packed & 255] & OpenBy[256 + ((Packed >> 8) & 255)] & OpenBy[512 + ((Packed >> 16) & 255)] & OpenBy[768 + ((Packed >> 24) & 255)];
			int Next = Dist[Code] + 1;
			int Move = 0;
			while (Open != 0)
			{
				if ((Open & 1) != 0)
				{
					int To = Code + MoveOffset[Move];
					if (Dist[To] < 0)
					{
						Dist[To] = Next;
						Queue.Add(To);
						QueuePacked.Add(Packed + MovePacked[Move]);
						Tail++;
					}
				}
				Open = Open >> 1;
				Move++;
			}
		}

		if (Head >= Tail)
		{
			Queue.Empty();
			QueuePacked.Empty();
			bReady = true;
		}
	}

	// True when the preparation is done (the fill and the search): Solve works.
	bool IsReady() const
	{
		return bReady;
	}

	// How many plates the lock has (0 before Begin and for a graph the solver cannot take).
	int Plates() const
	{
		return PlateCount;
	}

	// The keys that open the lock from this state: Holes (1..7 for plate 0..Plates-1) and Cursor (the selected plate,
	// 0..Plates-1). Among the paths with the fewest A/D presses the one of 1.2.0 is chosen: at every step the moves
	// that come closer to the goal are looked at plate by plate (A before D) and the first with the least cursor travel
	// wins; W/S walk the cursor to its plate first. Ok with no keys: the lock is open. NoSafePath: no sequence gets
	// there without a strain. BadState: not the lock's number of holes, a hole outside 1..7, the cursor outside the
	// plates, or the preparation is not done yet. OutKeys is empty unless the answer is Ok.
	ELPH_SolveStatus Solve(const TArray<int>& Holes, int Cursor, TArray<ELPH_Key>& OutKeys) const
	{
		OutKeys.Reset();
		if (!bReady || !IsValidState(Holes, Cursor))
			return ELPH_SolveStatus::BadState;

		int Code = 0;
		for (int Plate = 0; Plate < PlateCount; Plate++)
			Code += (Holes[Plate] - LPH::HoleMin) * Weights[Plate];
		int Left = Dist[Code];
		if (Left < 0)
			return ELPH_SolveStatus::NoSafePath;

		TArray<int> Now = Holes;
		int At = Cursor;
		while (Left > 0)
		{
			int Best = -1;
			int BestCost = 0;
			for (int Move = 0; Move < MoveCount; Move++)
			{
				if (!CanMove(Move, Now) || Dist[Code + MoveOffset[Move]] != Left - 1)
					continue;
				int Cost = At - (Move >> 1);
				if (Cost < 0)
					Cost = -Cost;
				if (Best < 0 || Cost < BestCost)
				{
					Best = Move;
					BestCost = Cost;
				}
			}
			if (Best < 0)
			{
				// (Cannot happen: a state at distance Left has a neighbour at Left - 1.)
				OutKeys.Reset();
				return ELPH_SolveStatus::NoSafePath;
			}

			int Target = Best >> 1;
			while (At < Target)
			{
				OutKeys.Add(ELPH_Key::W);
				At++;
			}
			while (At > Target)
			{
				OutKeys.Add(ELPH_Key::S);
				At--;
			}
			if ((Best & 1) == 0)
				OutKeys.Add(ELPH_Key::A);
			else
				OutKeys.Add(ELPH_Key::D);
			for (int Effect = EffectFirst[Best]; Effect < EffectFirst[Best + 1]; Effect++)
				Now[EffectPlate[Effect]] += EffectDelta[Effect];
			Code += MoveOffset[Best];
			Left--;
		}
		return ELPH_SolveStatus::Ok;
	}

	// What a key does to the lock: W/S move the cursor one plate (back / front) and stay at the end; A/D move the
	// selected plate and the plates connected with it. False for a strain (a hole would leave 1..7), and also for a
	// state that does not fit the lock (as Solve's BadState); OutHoles and OutCursor are then the state given. R is no
	// move of the solver (it does not know the starting holes): the state stays as it is.
	bool Apply(const TArray<int>& Holes, int Cursor, ELPH_Key Key, TArray<int>& OutHoles, int& OutCursor) const
	{
		// (Worked out on copies: the caller may hand the same variables over as the state and as the result.)
		TArray<int> Result = Holes;
		int NewCursor = Cursor;
		bool bMoved = IsValidState(Holes, Cursor);

		if (bMoved && (Key == ELPH_Key::W || Key == ELPH_Key::S))
		{
			int Along = 1;
			if (Key == ELPH_Key::S)
				Along = -1;
			if (Cursor + Along >= 0 && Cursor + Along < PlateCount)
				NewCursor = Cursor + Along;
		}
		else if (bMoved && (Key == ELPH_Key::A || Key == ELPH_Key::D))
		{
			int Move = Cursor * 2;
			if (Key == ELPH_Key::D)
				Move++;
			if (CanMove(Move, Holes))
			{
				for (int Effect = EffectFirst[Move]; Effect < EffectFirst[Move + 1]; Effect++)
					Result[EffectPlate[Effect]] += EffectDelta[Effect];
			}
			else
			{
				bMoved = false;
			}
		}

		OutHoles = Result;
		OutCursor = NewCursor;
		return bMoved;
	}

	// The lock's number of holes, each in 1..7, the cursor on a plate. (False for a solver without a lock.)
	bool IsValidState(const TArray<int>& Holes, int Cursor) const
	{
		if (PlateCount == 0 || Holes.Num() != PlateCount || Cursor < 0 || Cursor >= PlateCount)
			return false;
		for (int Hole : Holes)
		{
			if (Hole < LPH::HoleMin || Hole > LPH::HoleMax)
				return false;
		}
		return true;
	}

	// Whether the move keeps every hole it changes in 1..7.
	bool CanMove(int Move, const TArray<int>& Holes) const
	{
		for (int Effect = EffectFirst[Move]; Effect < EffectFirst[Move + 1]; Effect++)
		{
			int After = Holes[EffectPlate[Effect]] + EffectDelta[Effect];
			if (After < LPH::HoleMin || After > LPH::HoleMax)
				return false;
		}
		return true;
	}

	// Forgets the lock and frees what it held.
	void Clear()
	{
		PlateCount = 0;
		MoveCount = 0;
		bReady = false;
		StateCount = 0;
		GoalCode = 0;
		GoalPacked = 0;
		Weights.Empty();
		MoveOffset.Empty();
		MovePacked.Empty();
		EffectFirst.Empty();
		EffectPlate.Empty();
		EffectDelta.Empty();
		OpenBy.Empty();
		Dist.Empty();
		Queue.Empty();
		QueuePacked.Empty();
		Head = 0;
		Tail = 0;
	}
}
