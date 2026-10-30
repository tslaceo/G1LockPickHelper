// The autosolver: presses the hint's keys for the player (autosolve.lua of 1.2.0, ported by meaning).
//
// States: Off -> Armed (waits for the tracker: the minigame is not ready yet) -> Running -> Off. Every frame Step gets the
// tracker's view and how many A/D the plates have not shown yet, and says which key to press now: the hint's current key.
// After a W/S it waits the W/S gap; after an A/D, until the tracker has confirmed it from the plates. The press itself goes
// through the game (the caller's business), so the tracker follows it like any press and a replan is simply picked up
// (View.Plan changes). It never presses R and never presses while an A/D is unconfirmed. It stops by itself when the lock
// is open, when there is no hint (NoSafePath / BadState), when an A/D stays unconfirmed for the timeout, and after the
// replan limit of hint replans in a row (the model and the game disagree).

enum ELPH_AutoState
{
	Off,
	Armed, // F3 (or the auto-pick setting) came before the tracker exists: Step starts it when the view is there
	Running
}

// Why the autosolver stopped by itself.
enum ELPH_AutoStop
{
	None, // it has not stopped
	Solved, // the lock is open
	NoSafePath, // the hint has no safe path
	BadState, // the holes do not fit the lock
	Timeout, // an A/D did not show on the plates in time
	Replans // the hint was replanned the limit of times in a row
}

namespace LPH
{
	// How long the autosolver needs for Keys[From] and on: each A/D waits for the plates (AdMs), each W/S for its gap
	// (WsMs). Milliseconds. From is 0-based.
	int EtaMs(const TArray<ELPH_Key>& Keys, int From, int AdMs, int WsMs)
	{
		int Ms = 0;
		for (int i = Math::Max(From, 0); i < Keys.Num(); i++)
		{
			if (IsMove(Keys[i]))
				Ms += AdMs;
			else
				Ms += WsMs;
		}
		return Ms;
	}
}

class ULPH_AutoSolve : UObject
{
	ELPH_AutoState State = ELPH_AutoState::Off;
	int GapMs = 60; // the pause after its W/S
	int LimitMs = 2500; // an A/D unconfirmed for longer stops it
	int ReplanLimit = 3; // this many replans in a row stop it

	bool bPlanSeen = false; // LastPlan is the tracker's Plan seen last (none yet since Stop: the first one is no replan)
	int LastPlan = 0;
	int ReplanCount = 0; // replans since the last A/D the plates confirmed as planned
	bool bAdWaiting = false; // a move waits for the plates, since AdAtMs
	int64 AdAtMs = 0; // when our last A/D was pressed (or when a move we did not make was first seen waiting)
	bool bAdOk = false; // no replan since that A/D
	int64 NextAtMs = 0; // no press before this time (the pause after a W/S)

	// The settings (LPH::SolveWsGapMs, LPH::SolveTimeoutMs, LPH::SolveMaxReplans in the mod). Leaves it off.
	void Init(int WsGapMs, int TimeoutMs, int MaxReplans)
	{
		GapMs = WsGapMs;
		LimitMs = TimeoutMs;
		ReplanLimit = MaxReplans;
		Stop();
	}

	// Off, and everything it knew about the lock forgotten.
	void Stop()
	{
		State = ELPH_AutoState::Off;
		bPlanSeen = false;
		LastPlan = 0;
		ReplanCount = 0;
		bAdWaiting = false;
		AdAtMs = 0;
		bAdOk = false;
		NextAtMs = 0;
	}

	// From Off: wait for the tracker (the auto-pick setting at the minigame start).
	void Arm()
	{
		if (State == ELPH_AutoState::Off)
			State = ELPH_AutoState::Armed;
	}

	// F3. bTracking: the tracker exists (the minigame is ready). Returns the new state.
	ELPH_AutoState Toggle(bool bTracking)
	{
		if (State != ELPH_AutoState::Off)
			Stop();
		else if (bTracking)
			State = ELPH_AutoState::Running;
		else
			State = ELPH_AutoState::Armed;
		return State;
	}

	// A press the autosolver did not make (the player's). True when it stopped the autosolver.
	bool PlayerPressed()
	{
		if (State == ELPH_AutoState::Off)
			return false;
		Stop();
		return true;
	}

	ELPH_AutoState GetState() const
	{
		return State;
	}

	// View: the tracker's view (bHasView false while there is no tracker); Pending: the tracker's Pending(); NowMs:
	// LPH::NowMs(). True: press OutKey now (W, S, A or D). False: nothing to press; OutStop is then not None when it has
	// just stopped itself (the reason), and None when it merely waits (or is off). OutStop is always set; OutKey only
	// when it says to press.
	bool Step(const FLPH_TrackerView& View, bool bHasView, int Pending, int64 NowMs, ELPH_Key& OutKey, ELPH_AutoStop& OutStop)
	{
		OutStop = ELPH_AutoStop::None;
		if (State == ELPH_AutoState::Off || !bHasView)
			return false;
		State = ELPH_AutoState::Running;

		if (View.Status == ELPH_Status::Solved)
			return Halt(ELPH_AutoStop::Solved, OutStop);
		if (View.Status != ELPH_Status::Ok)
		{
			if (View.Status == ELPH_Status::NoSafePath)
				return Halt(ELPH_AutoStop::NoSafePath, OutStop);
			return Halt(ELPH_AutoStop::BadState, OutStop);
		}

		if (!bPlanSeen || View.Plan != LastPlan)
		{
			if (bPlanSeen)
			{
				ReplanCount++;
				bAdOk = false;
				if (ReplanCount >= ReplanLimit)
					return Halt(ELPH_AutoStop::Replans, OutStop);
			}
			bPlanSeen = true;
			LastPlan = View.Plan;
		}

		if (Pending > 0)
		{
			// A move it did not make (in flight at F3) waits under the same timeout.
			if (!bAdWaiting)
			{
				bAdWaiting = true;
				AdAtMs = NowMs;
			}
			if (NowMs - AdAtMs > LimitMs)
				return Halt(ELPH_AutoStop::Timeout, OutStop);
			return false;
		}
		if (bAdWaiting)
		{
			if (bAdOk)
				ReplanCount = 0;
			bAdWaiting = false;
		}

		if (NowMs < NextAtMs)
			return false;
		if (View.Index < 0 || View.Index >= View.Keys.Num())
			return false;
		ELPH_Key Key = View.Keys[View.Index];
		if (LPH::IsMove(Key))
		{
			bAdWaiting = true;
			AdAtMs = NowMs;
			bAdOk = true;
		}
		else
		{
			NextAtMs = NowMs + GapMs;
		}
		OutKey = Key;
		return true;
	}

	// Stops itself for a reason: Step says "nothing to press" and why.
	bool Halt(ELPH_AutoStop Reason, ELPH_AutoStop& OutStop)
	{
		Stop();
		OutStop = Reason;
		return false;
	}
}
