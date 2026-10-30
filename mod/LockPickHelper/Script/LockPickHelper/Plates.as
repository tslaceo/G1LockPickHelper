// The minigame's plates as the mod reads them, without a game object: LPHGame::ReadPlates (Game.as) collects what the game
// says of each lock piece into FLPH_Pieces, LPH::ReadingOf turns them into an FLPH_Reading. The rules are here so that
// they can be tried in the tests.
//
// The game keeps 7 plates, 7 bars and 7 latches in the lock scene whatever the lock (m_PieceId 0..6, front to back). The
// plates the lock does not use are not hidden: they are shown at another place, far from the lock (probe-run1.log: the
// plates and bars of a 5-plate lock stand around X 109615, Y -256400, while ids 5 and 6 stand at X 5779, Y -198091, all
// "visible"). A plate counts as shown when it is not hidden and stands within LPH::PlatesNear of the lock's plate 0.

// What the game says of one lock piece (AGothicLockPieceActor).
struct FLPH_Piece
{
	int Kind = 0; // m_LockPieceType: 1 plate, 2 bar, 3 latch
	int Id = -1; // m_PieceId
	bool bHidden = false; // the actor's bHidden
	bool bHasLocation = false; // false: the piece has no root component to measure
	FVector Location; // the root component's relative location
	bool bHighlighted = false; // the plate's material paints it as the selected one (read for the plates 0..n-1 that are shown)
}

namespace LPH
{
	const float PlatesNear = 200.0; // a plate this close (on every axis) to plate 0 is at the lock
	const int MaxPlateIds = 16; // piece ids are 0..6; a lock asked for with more plates than this is not read

	// Whether two places are within PlatesNear of each other on every axis.
	bool IsNear(const FVector& A, const FVector& B)
	{
		return Math::Abs(A.X - B.X) <= PlatesNear && Math::Abs(A.Y - B.Y) <= PlatesNear
			&& Math::Abs(A.Z - B.Z) <= PlatesNear;
	}

	// One reading of the lock of Plates plates out of its pieces.
	// - Visible: the plates (kind 1) that are not hidden and stand at the lock, whatever their id: the controller compares
	//   it with the lock's plates in the database. The lock is where plate 0 stands (hidden or not); no plate 0 with a
	//   location: Visible 0 and not settled. A plate without a location cannot be placed: it is not counted and the
	//   reading is not settled.
	// - Holes: the holes of the shown plates with an id below Plates, in id order. A plate of the lock that is not shown
	//   has none (Holes is then shorter than Plates and the controller sees the mismatch); a higher id is not read.
	// - bSettled: false while a plate that is read is between holes (HoleOf -1) or has no bar (or the bar no location),
	//   when a shown plate has no location, when nothing is shown, and for Plates outside 1..MaxPlateIds; Holes is then
	//   empty.
	// - Cursor: the shown plate below Plates that is highlighted (the lowest id), -1 when none, and always -1 unless the
	//   look is settled.
	FLPH_Reading ReadingOf(const TArray<FLPH_Piece>& Pieces, int Plates)
	{
		FLPH_Reading Reading;
		if (Plates < 1 || Plates > MaxPlateIds)
			return Reading;

		bool bHasOrigin = false;
		FVector Origin;
		for (int i = 0; i < Pieces.Num(); i++)
		{
			if (Pieces[i].Kind == 1 && Pieces[i].Id == 0 && Pieces[i].bHasLocation)
			{
				Origin = Pieces[i].Location;
				bHasOrigin = true;
				break;
			}
		}
		if (!bHasOrigin)
			return Reading;

		// By id below Plates: where the shown plate and the bar are in Pieces (-1: none).
		TArray<int> PlateAt;
		TArray<int> BarAt;
		PlateAt.SetNum(Plates);
		BarAt.SetNum(Plates);
		for (int Id = 0; Id < Plates; Id++)
		{
			PlateAt[Id] = -1;
			BarAt[Id] = -1;
		}

		bool bBroken = false;
		for (int i = 0; i < Pieces.Num(); i++)
		{
			int Id = Pieces[i].Id;
			if (Pieces[i].Kind == 1)
			{
				if (Pieces[i].bHidden)
					continue;
				if (!Pieces[i].bHasLocation)
				{
					bBroken = true;
					continue;
				}
				if (!IsNear(Pieces[i].Location, Origin))
					continue;
				Reading.Visible++;
				if (Id >= 0 && Id < Plates && PlateAt[Id] < 0)
					PlateAt[Id] = i;
			}
			else if (Pieces[i].Kind == 2 && Id >= 0 && Id < Plates && BarAt[Id] < 0)
				BarAt[Id] = i;
		}
		if (Reading.Visible == 0)
			return Reading;

		bool bSettled = !bBroken;
		for (int Id = 0; Id < Plates && bSettled; Id++)
		{
			if (PlateAt[Id] < 0)
				continue;
			if (BarAt[Id] < 0 || !Pieces[BarAt[Id]].bHasLocation)
			{
				bSettled = false;
				break;
			}
			int Hole = HoleOf(Pieces[PlateAt[Id]].Location.X - Pieces[BarAt[Id]].Location.X);
			if (Hole < 0)
			{
				bSettled = false;
				break;
			}
			Reading.Holes.Add(Hole);
		}
		if (!bSettled)
		{
			Reading.Holes.Reset();
			return Reading;
		}
		Reading.bSettled = true;

		for (int Id = 0; Id < Plates; Id++)
		{
			if (PlateAt[Id] >= 0 && Pieces[PlateAt[Id]].bHighlighted)
			{
				Reading.Cursor = Id;
				break;
			}
		}
		return Reading;
	}
}
