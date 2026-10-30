// Plates.as: LPH::ReadingOf, the part of reading the minigame's plates that needs no game object. The pieces are laid out
// as the probe logged them (probe-run1.log, a 5-plate chest lock): the plates and bars of the lock stand together far from
// the origin, the ones the lock does not use (ids 5 and 6) stand elsewhere, shown all the same, and every piece has a latch.

// The settled offset of a hole's plate from its bar, measured in the game (written out here again on purpose).
float LPHTests_Centre(int Hole)
{
	TArray<float> Centres;
	Centres.Add(-18.5);
	Centres.Add(-12.2);
	Centres.Add(-6.1);
	Centres.Add(0.0);
	Centres.Add(6.3);
	Centres.Add(12.5);
	Centres.Add(18.7);
	return Centres[Hole - 1];
}

void LPHTests_AddPiece(TArray<FLPH_Piece>& Pieces, int Kind, int Id, float X, float Y, float Z)
{
	FLPH_Piece Piece;
	Piece.Kind = Kind;
	Piece.Id = Id;
	Piece.bHasLocation = true;
	Piece.Location = FVector(X, Y, Z);
	Pieces.Add(Piece);
}

// Where a piece is in the pieces (-1: there is none).
int LPHTests_IndexOf(const TArray<FLPH_Piece>& Pieces, int Kind, int Id)
{
	for (int i = 0; i < Pieces.Num(); i++)
	{
		if (Pieces[i].Kind == Kind && Pieces[i].Id == Id)
			return i;
	}
	return -1;
}

// The pieces of a lock scene: the plates 0..Holes.Num()-1 stand in the holes Holes at the lock (a plate's X is its bar's X
// plus its hole's offset, Y steps by 10 as in the game); the plates up to Total-1 stand far away as the unused ones do
// (their bars at the same X, so that they would read as hole 4). Each id has a latch, at the far place.
void LPHTests_Scene(TArray<FLPH_Piece>& Pieces, const TArray<int>& Holes, int Total)
{
	Pieces.Reset();
	for (int Id = 0; Id < Total; Id++)
	{
		if (Id < Holes.Num())
		{
			float Y = -256381.0 - 10.0 * float(Id);
			LPHTests_AddPiece(Pieces, 1, Id, 109609.331256 + LPHTests_Centre(Holes[Id]), Y, 18094.142211);
			LPHTests_AddPiece(Pieces, 2, Id, 109609.331256, Y, 18111.66584);
		}
		else
		{
			float Y = -198091.0 - 10.0 * float(Id - 5);
			LPHTests_AddPiece(Pieces, 1, Id, 5779.331256, Y, 15684.142211);
			LPHTests_AddPiece(Pieces, 2, Id, 5779.331256, Y, 15701.66584);
		}
		LPHTests_AddPiece(Pieces, 3, Id, 5744.331256, -198041.0 - 10.0 * float(Id), 15736.142311);
	}
}

// The five holes the probe saw at the start of the chest lock (7 5 7 7 5).
void LPHTests_ProbeHoles(TArray<int>& Holes)
{
	Holes.Reset();
	Holes.Add(7);
	Holes.Add(5);
	Holes.Add(7);
	Holes.Add(7);
	Holes.Add(5);
}

void LPHTests_Highlight(TArray<FLPH_Piece>& Pieces, int Id)
{
	int At = LPHTests_IndexOf(Pieces, 1, Id);
	if (At >= 0)
		Pieces[At].bHighlighted = true;
}

void LPHTests_Plates(ULPH_TestRun T)
{
	TArray<int> Holes;
	TArray<FLPH_Piece> Pieces;

	T.Begin("Plates: the probe's 5-plate lock, the unused plates far away");
	LPHTests_ProbeHoles(Holes);
	LPHTests_Scene(Pieces, Holes, 7);
	LPHTests_Highlight(Pieces, 1);
	FLPH_Reading Reading = LPH::ReadingOf(Pieces, 5);
	T.True(Reading.bSettled, "settled");
	T.EqualInt(Reading.Visible, 5, "the unused plates 5 and 6 are not counted, shown as they are");
	T.EqualStr(LPH::HolesText(Reading.Holes), "7 5 7 7 5", "the holes the offsets give (18.7 is 7, 6.3 is 5)");
	T.EqualInt(Reading.Cursor, 1, "the cursor is the highlighted plate");

	T.Begin("Plates: the database says 7 plates, the game shows 5");
	Reading = LPH::ReadingOf(Pieces, 7);
	T.True(Reading.bSettled, "the plates that are shown are settled");
	T.EqualInt(Reading.Visible, 5, "5 plates shown");
	T.EqualStr(LPH::HolesText(Reading.Holes), "7 5 7 7 5", "only the shown plates have holes");
	T.EqualInt(Reading.Cursor, 1, "the cursor all the same");

	T.Begin("Plates: a 7-plate lock, all near");
	Holes.Reset();
	for (int Hole = 1; Hole <= 7; Hole++)
		Holes.Add(Hole);
	LPHTests_Scene(Pieces, Holes, 7);
	Reading = LPH::ReadingOf(Pieces, 7);
	T.True(Reading.bSettled, "settled");
	T.EqualInt(Reading.Visible, 7, "7 plates shown");
	T.EqualStr(LPH::HolesText(Reading.Holes), "1 2 3 4 5 6 7", "every hole from its own offset");
	T.EqualInt(Reading.Cursor, -1, "no plate highlighted: no cursor (a reset in progress)");

	T.Begin("Plates: an extra plate near the lock (another mod's lock) counts in Visible");
	Holes.Reset();
	LPHTests_ProbeHoles(Holes);
	Holes.Add(4);
	LPHTests_Scene(Pieces, Holes, 7); // 6 plates at the lock, id 6 far away
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(Reading.bSettled, "the 5 plates of the database are settled");
	T.EqualInt(Reading.Visible, 6, "6 plates shown");
	T.EqualStr(LPH::HolesText(Reading.Holes), "7 5 7 7 5", "the holes of ids 0..4 only");
	LPHTests_Highlight(Pieces, 5);
	Reading = LPH::ReadingOf(Pieces, 5);
	T.EqualInt(Reading.Cursor, -1, "a highlight on the extra plate is no cursor of the database's lock");

	T.Begin("Plates: a plate that is hidden is not shown");
	LPHTests_ProbeHoles(Holes);
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces[LPHTests_IndexOf(Pieces, 1, 2)].bHidden = true;
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(Reading.bSettled, "the plates that are shown are settled");
	T.EqualInt(Reading.Visible, 4, "4 plates shown");
	T.EqualStr(LPH::HolesText(Reading.Holes), "7 5 7 5", "the hidden plate has no hole: the controller sees 4 holes for 5 plates");
	// Hidden or not, plate 0 is where the lock is.
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces[LPHTests_IndexOf(Pieces, 1, 0)].bHidden = true;
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(Reading.bSettled, "a hidden plate 0 still marks the lock's place");
	T.EqualInt(Reading.Visible, 4, "4 plates shown");
	T.EqualStr(LPH::HolesText(Reading.Holes), "5 7 7 5", "the holes of ids 1..4");

	T.Begin("Plates: a plate between holes is moving");
	LPHTests_Scene(Pieces, Holes, 7);
	LPHTests_Highlight(Pieces, 2);
	Pieces[LPHTests_IndexOf(Pieces, 1, 3)].Location.X = 109609.331256 + 3.0;
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(!Reading.bSettled, "not settled");
	T.EqualInt(Reading.Holes.Num(), 0, "no holes");
	T.EqualInt(Reading.Visible, 5, "the plates are still counted");
	T.EqualInt(Reading.Cursor, -1, "the highlight is read for a settled look only");
	// A moving plate that the database does not use does not matter.
	Holes.Add(4);
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces[LPHTests_IndexOf(Pieces, 1, 5)].Location.X = 109609.331256 + 3.0;
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(Reading.bSettled, "a moving plate of id 5 is not read when the lock has 5");
	T.EqualInt(Reading.Visible, 6, "but it is shown");
	LPHTests_ProbeHoles(Holes);

	T.Begin("Plates: a plate without its bar cannot be measured");
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces.RemoveAt(LPHTests_IndexOf(Pieces, 2, 2));
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(!Reading.bSettled, "not settled");
	T.EqualInt(Reading.Holes.Num(), 0, "no holes");
	T.EqualInt(Reading.Visible, 5, "the plates are counted");
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces[LPHTests_IndexOf(Pieces, 2, 4)].bHasLocation = false;
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(!Reading.bSettled, "a bar without a root is not settled either");
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces[LPHTests_IndexOf(Pieces, 1, 3)].bHasLocation = false;
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(!Reading.bSettled, "a shown plate without a root is not settled");
	T.EqualInt(Reading.Holes.Num(), 0, "no holes");
	T.EqualInt(Reading.Visible, 4, "and cannot be placed at the lock, so it is not counted");

	T.Begin("Plates: no plate 0, no lock");
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces.RemoveAt(LPHTests_IndexOf(Pieces, 1, 0));
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(!Reading.bSettled, "not settled");
	T.EqualInt(Reading.Visible, 0, "nothing to place the others by: nothing shown");
	T.EqualInt(Reading.Holes.Num(), 0, "no holes");
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces[LPHTests_IndexOf(Pieces, 1, 0)].bHasLocation = false;
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(!Reading.bSettled && Reading.Visible == 0, "a plate 0 without a root is no plate 0");
	Pieces.Reset();
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(!Reading.bSettled && Reading.Visible == 0 && Reading.Cursor == -1, "no pieces at all");
	// Only a latch with id 0 near: it is no plate.
	LPHTests_AddPiece(Pieces, 3, 0, 109609.0, -256381.0, 18094.0);
	Reading = LPH::ReadingOf(Pieces, 5);
	T.True(!Reading.bSettled && Reading.Visible == 0, "a latch is no plate");
	LPHTests_Scene(Pieces, Holes, 7);
	Reading = LPH::ReadingOf(Pieces, 0);
	T.True(!Reading.bSettled && Reading.Visible == 0, "no plates asked for");
	Reading = LPH::ReadingOf(Pieces, 100);
	T.True(!Reading.bSettled && Reading.Visible == 0, "too many plates asked for");

	T.Begin("Plates: the cursor");
	LPHTests_Scene(Pieces, Holes, 7);
	Reading = LPH::ReadingOf(Pieces, 5);
	T.EqualInt(Reading.Cursor, -1, "no highlight: no cursor");
	LPHTests_Highlight(Pieces, 0);
	T.EqualInt(LPH::ReadingOf(Pieces, 5).Cursor, 0, "plate 0");
	LPHTests_Scene(Pieces, Holes, 7);
	LPHTests_Highlight(Pieces, 4);
	T.EqualInt(LPH::ReadingOf(Pieces, 5).Cursor, 4, "plate 4");
	// A highlight on a far plate (a scene that is taken down), a latch or a hidden plate is no cursor.
	LPHTests_Scene(Pieces, Holes, 7);
	LPHTests_Highlight(Pieces, 6);
	T.EqualInt(LPH::ReadingOf(Pieces, 7).Cursor, -1, "a far plate's highlight");
	LPHTests_Scene(Pieces, Holes, 7);
	Pieces[LPHTests_IndexOf(Pieces, 3, 1)].bHighlighted = true;
	T.EqualInt(LPH::ReadingOf(Pieces, 5).Cursor, -1, "a latch's highlight");
	LPHTests_Scene(Pieces, Holes, 7);
	LPHTests_Highlight(Pieces, 2);
	Pieces[LPHTests_IndexOf(Pieces, 1, 2)].bHidden = true;
	T.EqualInt(LPH::ReadingOf(Pieces, 5).Cursor, -1, "a hidden plate's highlight");
	// Two highlighted plates (the game never does this): the lower id.
	LPHTests_Scene(Pieces, Holes, 7);
	LPHTests_Highlight(Pieces, 3);
	LPHTests_Highlight(Pieces, 1);
	T.EqualInt(LPH::ReadingOf(Pieces, 5).Cursor, 1, "the lower id of two");

	T.Begin("Plates: near is 200 units on every axis of plate 0");
	// Plate 0 stands at (109628.03, -256381, 18094.14); plate 4 is put 199 or 201 away from it along one axis.
	TArray<float> Offsets;
	Offsets.Add(199.0);
	Offsets.Add(-199.0);
	Offsets.Add(201.0);
	Offsets.Add(-201.0);
	for (int Axis = 0; Axis < 3; Axis++)
	{
		for (int Case = 0; Case < Offsets.Num(); Case++)
		{
			LPHTests_Scene(Pieces, Holes, 7);
			FVector Origin = Pieces[LPHTests_IndexOf(Pieces, 1, 0)].Location;
			int Four = LPHTests_IndexOf(Pieces, 1, 4);
			Pieces[Four].Location = Origin;
			if (Axis == 0)
				Pieces[Four].Location.X += Offsets[Case];
			else if (Axis == 1)
				Pieces[Four].Location.Y += Offsets[Case];
			else
				Pieces[Four].Location.Z += Offsets[Case];
			int Want = Math::Abs(Offsets[Case]) < 200.0 ? 5 : 4;
			FString AxisName = Axis == 0 ? "X" : (Axis == 1 ? "Y" : "Z");
			FString OffsetText = f"{Offsets[Case]}";
			T.EqualInt(LPH::ReadingOf(Pieces, 5).Visible, Want, f"{OffsetText} away in {AxisName}");
		}
	}
	// The lock may stand anywhere in the world: it is plate 0 that places it.
	LPHTests_Scene(Pieces, Holes, 7);
	for (int i = 0; i < Pieces.Num(); i++)
		Pieces[i].Location.X += 5000.0;
	Reading = LPH::ReadingOf(Pieces, 5);
	T.EqualInt(Reading.Visible, 5, "the whole scene moved: the same plates");
	T.EqualStr(LPH::HolesText(Reading.Holes), "7 5 7 7 5", "and the same holes");
}
