// F3 and F4 outside the minigame, and what they say there. Both are world subsystems: made anew in every world (a load is a
// new world, with a new hero), they die with it, so nothing here outlives its world.
// - ULPH_Hotkeys binds F3/F4 on the hero's input component when the world is ready for play (probe run 6; inside the
//   minigame no key reaches the player's input: the key catcher of KeyCatcher.as has them there).
// - ULPH_NoteLayer draws the notes outside the minigame (F3 "auto-pick waits for the next lock" / "skipped", F4 on/off;
//   Ruling R11) on the mod's viewport layer (ViewportLayer.as) with its own hint, messages only. While a minigame is open
//   its window shows them, so the layer's note hides then. The layer is made the first time a note shows in this world;
//   the engine takes it out of the viewport when the world goes.

class ULPH_Hotkeys : UGothicModExt_WorldSubsystem
{
	private bool bBound = false;

	UFUNCTION(BlueprintOverride)
	void HandleReadyForPlay()
	{
		ULPH_Mod Main = LPH::Mod();
		if (Main == nullptr)
			return;
		Main.WorldReady(f"{World.Name}");
		if (bBound)
			return;
		AActor Hero = Gameplay::GetPlayerCharacter(0);
		if (Hero == nullptr)
		{
			Main.ModLog.Line("F3/F4: no hero in this world, not bound");
			return;
		}
		UInputComponent Bindings = UInputComponent::Get(Hero);
		if (Bindings == nullptr)
		{
			Main.ModLog.Line("F3/F4: the hero has no input component, not bound");
			return;
		}
		FInputActionHandlerDynamicSignature Handler = FInputActionHandlerDynamicSignature(this, n"OnKey");
		Bindings.BindKey(EKeys::F3, EInputEvent::IE_Pressed, Handler, false);
		Bindings.BindKey(EKeys::F4, EInputEvent::IE_Pressed, Handler, false);
		bBound = true;
		Main.ModLog.Debug(f"F3/F4 bound on the hero ({Bindings.Name})");
	}

	UFUNCTION()
	private void OnKey(FKey Key)
	{
		ULPH_Mod Main = LPH::Mod();
		if (Main == nullptr)
			return;
		if (Key == EKeys::F3)
			Main.Hotkey(true, "key binding");
		else if (Key == EKeys::F4)
			Main.Hotkey(false, "key binding");
	}
}

class ULPH_NoteLayer : UScriptWorldSubsystem
{
	UPROPERTY()
	private ULPH_ViewportLayer Layer;

	UPROPERTY()
	private ULPH_HintWidget Note;

	private FString LastSig;
	private bool bShown = false;

	UFUNCTION(BlueprintOverride)
	void Tick(float DeltaTime)
	{
		ULPH_Mod Main = LPH::Mod();
		if (Main == nullptr)
			return;
		if (Main.bMinigameOpen)
		{
			// The window shows the notes now; once it closes, whatever is to be shown is drawn here afresh.
			if (bShown)
				Note.Hide();
			bShown = false;
			LastSig = "";
			return;
		}
		if (Gameplay::GetPlayerCharacter(0) == nullptr)
			return; // the main menu (the tests run there): no F3/F4, nothing to show
		int64 Now = LPH::NowMs();
		FString Sig = Main.Controller.DisplaySig(Now);
		if (Sig != LastSig)
		{
			FLPH_Display Shown = Main.Controller.Display(Now);
			LastSig = Shown.Sig;
			if (Shown.Kind == ELPH_DisplayKind::Message)
			{
				ShowNote(Main, Shown.Message);
			}
			else if (bShown)
			{
				Note.Hide();
				bShown = false;
			}
			Main.ModLog.Debug("draw outside the minigame " + Shown.Sig);
		}
		Main.ModLog.FlushIfDue();
	}

	private void ShowNote(ULPH_Mod Main, FString Text)
	{
		if (Layer == nullptr)
		{
			Layer = LPH::NewViewportLayer(Gameplay::GetPlayerController(0));
			if (Layer == nullptr)
			{
				Main.ModLog.Line("no viewport layer: a note outside the minigame is not shown");
				return;
			}
			Note = Cast<ULPH_HintWidget>(NewObject(this, ULPH_HintWidget::StaticClass()));
			Note.UseLog(Main.ModLog);
			Note.Attach(Layer, Layer.LayerCanvas);
		}
		Layer.Show();
		Note.Configure(Main.Values);
		Note.ShowMessage(Text);
		bShown = true;
	}
}
