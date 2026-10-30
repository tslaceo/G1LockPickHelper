// The lock database: the plates and connections of every lock of the game, looked up by the lock's name (without case,
// as FName compares). The data is generated from the Modkit sources into LockGraphs.as (tools/gen_lockgraphs.py) and
// put in by LPH_RegisterLockGraphs; this file only holds and finds it.

// One lock as the solver wants it. Plates are 0..Plates-1, front to back. Connection i is Src[i] -> Dst[i] with
// Dir[i] = +1 (the plate Dst moves with Src) or -1 (against), in the authored order.
struct FLPH_LockGraph
{
	int Plates = 0;
	TArray<int> Src;
	TArray<int> Dst;
	TArray<int> Dir;
}

class ULPH_LockDb : UObject
{
	TArray<FLPH_LockGraph> Locks;
	TMap<FName, int> Index; // lock name -> its place in Locks
	int Current = -1; // the lock of the last AddLock: AddEdge goes there

	// Starts a lock; AddEdge calls that follow belong to it. A lock whose name was added before (names are compared
	// without case) is replaced.
	void AddLock(FName Lock, int Plates)
	{
		FLPH_LockGraph Graph;
		Graph.Plates = Plates;
		int Place = -1;
		if (Index.Find(Lock, Place))
		{
			Locks[Place] = Graph;
		}
		else
		{
			Place = Locks.Num();
			Locks.Add(Graph);
			Index.Add(Lock, Place);
		}
		Current = Place;
	}

	// One more connection of the lock of the last AddLock (nothing happens before the first AddLock).
	void AddEdge(int Src, int Dst, int Dir)
	{
		if (Current < 0)
			return;
		Locks[Current].Src.Add(Src);
		Locks[Current].Dst.Add(Dst);
		Locks[Current].Dir.Add(Dir);
	}

	// The graph of the lock without its first `Removed` connections (the game drops the first round(LockpickPrecision) of
	// them when the minigame starts; `Removed` is clamped to 0..the number of connections). OutRemoved is how many were
	// dropped. False for a lock that is not in the database: OutGraph is then empty and OutRemoved 0.
	bool Find(FName Lock, int Removed, FLPH_LockGraph& OutGraph, int& OutRemoved) const
	{
		OutGraph.Plates = 0;
		OutGraph.Src.Reset();
		OutGraph.Dst.Reset();
		OutGraph.Dir.Reset();
		OutRemoved = 0;

		int Place = -1;
		if (!Index.Find(Lock, Place))
			return false;
		int Total = Locks[Place].Src.Num();
		int Skip = Math::Clamp(Removed, 0, Total);
		OutGraph.Plates = Locks[Place].Plates;
		for (int i = Skip; i < Total; i++)
		{
			OutGraph.Src.Add(Locks[Place].Src[i]);
			OutGraph.Dst.Add(Locks[Place].Dst[i]);
			OutGraph.Dir.Add(Locks[Place].Dir[i]);
		}
		OutRemoved = Skip;
		return true;
	}

	// How many locks there are.
	int Num() const
	{
		return Locks.Num();
	}
}

namespace LPH
{
	// How many connections the game drops at a lockpicking skill: round(Precision), half up; 0 for a skill below 0.5
	// (an unknown skill, NaN included, is 0 too). 1.x did the same: floor(max(Precision, 0) + 0.5).
	int ConnectionsRemoved(float Precision)
	{
		if (!(Precision > 0.0))
			return 0;
		// (The cap keeps the float -> int conversion inside the int range; no lock has a thousand connections.)
		return Math::FloorToInt(Math::Min(Precision, 1000.0) + 0.5);
	}
}
