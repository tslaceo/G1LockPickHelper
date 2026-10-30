// Game.as against the game, in the main menu (no hero, no lock scene, no minigame): every read must come back empty and
// none may throw. What it gives inside a minigame (the lock of a chest, the plates, the cursor) cannot be tried here.

void LPHTests_Game(ULPH_TestRun T)
{
	T.Begin("Game: the main menu");

	// No hero: no lock, and the fallback has no position to search from.
	FName Lock = n"SomeLock";
	T.True(!LPHGame::FindLock(Lock), "FindLock finds no lock in the main menu");
	T.True(Lock.IsNone(), "FindLock leaves the lock empty");

	// No lock scene: nothing visible, nothing settled, nothing highlighted.
	FLPH_Reading Reading = LPHGame::ReadPlates(5);
	T.True(!Reading.bSettled, "ReadPlates(5) is not settled");
	T.EqualInt(Reading.Visible, 0, "ReadPlates(5) sees no plates");
	T.EqualInt(Reading.Holes.Num(), 0, "ReadPlates(5) has no holes");
	T.EqualInt(Reading.Cursor, -1, "ReadPlates(5) has no cursor");
	FLPH_Reading Seven = LPHGame::ReadPlates(7);
	T.True(!Seven.bSettled && Seven.Visible == 0, "ReadPlates(7) is empty too");
	FLPH_Reading Zero = LPHGame::ReadPlates(0);
	T.True(!Zero.bSettled && Zero.Visible == 0, "ReadPlates(0) is empty");
	FLPH_Reading TooMany = LPHGame::ReadPlates(100);
	T.True(!TooMany.bSettled && TooMany.Visible == 0, "ReadPlates(100) is empty");

	T.True(LPHGame::Precision() == 0.0, "Precision is 0 without a hero");

	// The game's own state.
	FString Build = LPHGame::GameBuild();
	T.True(Build.Mid(0, 5) == "Build" && Build.Contains("_CL"), "GameBuild is Build<n>_CL<n>");
	FName Language = LPHGame::DisplayLanguage();
	T.True(!Language.IsNone(), "DisplayLanguage is not None");
	int Graphics = LPHGame::ButtonGraphics();
	T.True(Graphics >= 0 && Graphics <= 4, "ButtonGraphics is 0..4");
	int Input = LPHGame::InputType();
	T.True(Input == 0 || Input == 1, "InputType is 0 or 1");
	FName Gamepad = LPHGame::GamepadName();
	T.True(!Gamepad.IsNone(), "GamepadName is read (the player controller and CommonUI answer in the menu)");

	// The reads above ask the world for actors from global functions: that must find the menu world's actors, or the
	// empty readings above would prove nothing.
	TArray<AActor> Actors;
	GetAllActorsOfClass(AActor::StaticClass(), Actors);
	T.True(Actors.Num() > 0, "GetAllActorsOfClass finds the menu world's actors from a global function");
	TArray<AGothicLockPieceActor> Pieces;
	GetAllActorsOfClass(AGothicLockPieceActor::StaticClass(), Pieces);
	T.EqualInt(Pieces.Num(), 0, "no lock pieces in the main menu");

	if (T.Output != nullptr)
		T.Output.Line(f"game: build {Build}, language {Language}, button graphics {Graphics}, input type {Input}, gamepad {Gamepad}, actors {Actors.Num()}");
}
