// What the mod reads from the game: the lock the hero is picking, the hero's lockpicking skill, the minigame's plates and the
// plate the game highlights, the interface language, the button graphics, the last input device, the game's build
// (lock_reader.lua of 1.2.0 and the reading parts of main.lua, redone on the Modkit's script API; the calls are those of the
// probe's LogHero and ReadHighlight). LPHGame is the only place that touches game objects other than the minigame's window.
// Every read checks for a missing object and comes back empty rather than failing: in the main menu there is no hero, no
// lock scene and no minigame.

namespace LPH
{
	const float HoleTolerance = 0.3; // a plate this close to a hole's centre stands in it

	// The settled offset (the plate's X minus its bar's X) of hole 1..7, measured in the game; D moves toward hole 7.
	float HoleCentre(int Hole)
	{
		if (Hole == 1)
			return -18.5;
		if (Hole == 2)
			return -12.2;
		if (Hole == 3)
			return -6.1;
		if (Hole == 4)
			return 0.0;
		if (Hole == 5)
			return 6.3;
		if (Hole == 6)
			return 12.5;
		return 18.7;
	}

	// The hole (1..7) a plate stands in, given its offset from its bar, or -1 while the plate is between holes (the game
	// animates every move for about a second).
	int HoleOf(float Dx)
	{
		for (int Hole = HoleMin; Hole <= HoleMax; Hole++)
		{
			if (Math::Abs(Dx - HoleCentre(Hole)) < HoleTolerance)
				return Hole;
		}
		return -1;
	}

	// The build out of the text of version.txt: Build<digits>_CL<digits> (the first such place in the text), or empty.
	FString ParseBuild(FString Raw)
	{
		const FString Digits = "0123456789";
		int Length = Raw.Len();
		for (int Start = 0; Start + 5 <= Length; Start++)
		{
			if (Raw.Mid(Start, 5) != "Build")
				continue;
			int At = Start + 5;
			int Count = 0;
			while (At + Count < Length && Digits.Contains(Raw.Mid(At + Count, 1)))
				Count++;
			if (Count == 0)
				continue;
			At += Count;
			if (At + 3 > Length || Raw.Mid(At, 3) != "_CL")
				continue;
			At += 3;
			Count = 0;
			while (At + Count < Length && Digits.Contains(Raw.Mid(At + Count, 1)))
				Count++;
			if (Count == 0)
				continue;
			return Raw.Mid(Start, At + Count - Start);
		}
		return "";
	}
}

namespace LPHGame
{
	const float LockSearchCm = 400.0; // the fallback looks for the lock among the objects this close to the hero

	AGothicCharacter Hero()
	{
		return Cast<AGothicCharacter>(Gameplay::GetPlayerCharacter(0));
	}

	FName LockOf(AInteractiveObjectActor Object)
	{
		if (Object == nullptr)
			return NAME_None;
		const UInteractiveObjectDefinition Definition = Object.GetInteractiveObjectDefinition();
		if (Definition == nullptr)
			return NAME_None;
		return Definition.m_Lock;
	}

	// The lock of the chest or door the hero is picking (the m_Lock of its definition). First the hero's interaction
	// ability that is not over and holds an object (GA_Human_OpenContainer for a chest); there is no IsActive() in the
	// script API, and an ability that has ended may still point at the last object it used. An object with no lock (a
	// chest or door that is not locked) gives false and no fallback: the lock of another chest nearby is not its lock.
	// With no such ability: the nearest object with a lock within LockSearchCm. False when there is no hero or no lock.
	bool FindLock(FName& OutLock)
	{
		OutLock = NAME_None;
		AGothicCharacter Player = Hero();
		if (Player == nullptr)
			return false;

		bool bHeldUnlocked = false;
		UAbilitySystemComponent Abilities = Player.GetAbilitySystemComponent();
		if (Abilities != nullptr)
		{
			TArray<FGameplayAbilitySpecHandle> Handles;
			Abilities.GetAllAbilities(Handles);
			for (FGameplayAbilitySpecHandle Handle : Handles)
			{
				FGameplayAbilitySpec Spec;
				if (!Abilities.FindAbilitySpecFromHandle(Handle, Spec))
					continue;
				TArray<UGameplayAbility> Instances = Spec.GetAbilityInstances();
				for (UGameplayAbility Ability : Instances)
				{
					UGameplayAbilityInteractionBase Interaction = Cast<UGameplayAbilityInteractionBase>(Ability);
					if (Interaction == nullptr || Interaction.m_AbilityEnded)
						continue;
					AInteractiveObjectActor Object = Cast<AInteractiveObjectActor>(Interaction.m_InteractiveActor.Get());
					if (Object == nullptr)
						continue;
					FName Lock = LockOf(Object);
					if (!Lock.IsNone())
					{
						OutLock = Lock;
						return true;
					}
					bHeldUnlocked = true;
				}
			}
		}
		if (bHeldUnlocked)
			return false;

		TArray<AInteractiveObjectActor> Objects;
		GetAllActorsOfClass(AInteractiveObjectActor::StaticClass(), Objects);
		float Nearest = LockSearchCm;
		bool bFound = false;
		for (AInteractiveObjectActor Object : Objects)
		{
			if (Object == nullptr)
				continue;
			FName Lock = LockOf(Object);
			if (Lock.IsNone())
				continue;
			float Distance = Object.ActorLocation.Distance(Player.ActorLocation);
			if (Distance > Nearest)
				continue;
			Nearest = Distance;
			OutLock = Lock;
			bFound = true;
		}
		return bFound;
	}

	// The hero's lockpicking skill (LockpickPrecision: the game removes round(precision) connections of the lock's list);
	// 0 without a skill, and when it cannot be read.
	float Precision()
	{
		AGothicCharacter Player = Hero();
		if (Player == nullptr)
			return 0.0;
		float32 Value = Player.GetAttributeValue(UAttributeSet_Lockpicking, n"LockpickPrecision", 0.0f);
		return Value;
	}

	// True when the game paints this plate as the selected one: HighlightColor of its material, white (R 1) for the
	// others, (0.65, 0.70, 1.0) for the selected.
	bool IsHighlighted(AGothicLockPieceActor Piece)
	{
		TArray<UActorComponent> Components = Piece.GetComponentsByClass(UPrimitiveComponent::StaticClass());
		for (UActorComponent Component : Components)
		{
			UPrimitiveComponent Primitive = Cast<UPrimitiveComponent>(Component);
			if (Primitive == nullptr)
				continue;
			UMaterialInstance Instance = Cast<UMaterialInstance>(Primitive.GetMaterial(0));
			if (Instance == nullptr)
				continue;
			for (int i = 0; i < Instance.VectorParameterValues.Num(); i++)
			{
				FVectorParameterValue Parameter = Instance.VectorParameterValues[i];
				if (Parameter.ParameterInfo.Name == n"HighlightColor" && Parameter.ParameterValue.R < 0.9)
					return true;
			}
		}
		return false;
	}

	// One look at the minigame's plates: the lock scene's pieces (type 1 a plate, 2 its bar, 3 the latch; m_PieceId 0..6
	// front to back) are collected as FLPH_Pieces and read by LPH::ReadingOf (Plates.as has the rules: which plates are shown,
	// the holes, the settled look, the cursor). Only the plates below Plates that are not hidden are asked for their
	// highlight (the material of each is read).
	FLPH_Reading ReadPlates(int Plates)
	{
		TArray<FLPH_Piece> Pieces;
		if (Plates >= 1 && Plates <= LPH::MaxPlateIds)
		{
			TArray<AGothicLockPieceActor> Actors;
			GetAllActorsOfClass(AGothicLockPieceActor::StaticClass(), Actors);
			for (AGothicLockPieceActor Actor : Actors)
			{
				if (Actor == nullptr)
					continue;
				FLPH_Piece Piece;
				Piece.Kind = int(Actor.m_LockPieceType);
				Piece.Id = Actor.m_PieceId;
				Piece.bHidden = Actor.bHidden;
				USceneComponent Root = Actor.RootComponent;
				if (Root != nullptr)
				{
					Piece.bHasLocation = true;
					Piece.Location = Root.GetRelativeLocation();
				}
				if (Piece.Kind == 1 && !Piece.bHidden && Piece.Id >= 0 && Piece.Id < Plates)
					Piece.bHighlighted = IsHighlighted(Actor);
				Pieces.Add(Piece);
			}
		}
		return LPH::ReadingOf(Pieces, Plates);
	}

	UGothicGameUserSettings GameSettings()
	{
		return Cast<UGothicGameUserSettings>(UGameUserSettings::GetGameUserSettings());
	}

	UCommonInputSubsystem InputSubsystem()
	{
		APlayerController Controller = Gameplay::GetPlayerController(0);
		if (Controller == nullptr)
			return nullptr;
		return UCommonInputSubsystem::Get(Controller);
	}

	// The interface language of the game ("Russian", ...; Internationalization::GetCurrentCulture is not it: in the main
	// menu it says en-US-POSIX). NAME_None when it cannot be read.
	FName DisplayLanguage()
	{
		UGothicGameUserSettings Settings = GameSettings();
		if (Settings == nullptr)
			return NAME_None;
		return Settings.DisplayLanguage;
	}

	// The game's "Button icons" option: 0 do not use, 1 auto, 2 Xbox, 3 PS5, 4 Switch; -1 when it cannot be read.
	int ButtonGraphics()
	{
		UGothicGameUserSettings Settings = GameSettings();
		if (Settings == nullptr)
			return -1;
		return int(Settings.ButtonGraphics);
	}

	// The device of the last input: 0 keyboard and mouse, 1 gamepad (2 touch); 0 when it cannot be read.
	int InputType()
	{
		UCommonInputSubsystem Input = InputSubsystem();
		if (Input == nullptr)
			return LPH::InputKeyboard;
		return int(Input.GetCurrentInputType());
	}

	// The name CommonUI gives the gamepad in use (PS5, SWITCH, XSX, Generic, ...); NAME_None when it cannot be read.
	FName GamepadName()
	{
		UCommonInputSubsystem Input = InputSubsystem();
		if (Input == nullptr)
			return NAME_None;
		return Input.GetCurrentGamepadName();
	}

	// The game's build, "Build102_CL175960", out of G1R/Version/version.txt (UTF-16 with a byte order mark; the engine's
	// file reader takes care of that); empty when the file is missing or says nothing like a build.
	FString GameBuild()
	{
		FString Raw;
		if (!FFileHelper::LoadFileToString(Raw, FPaths::ProjectDir() + "Version/version.txt"))
			return "";
		return LPH::ParseBuild(Raw);
	}
}
