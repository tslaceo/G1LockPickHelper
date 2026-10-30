// Development only: with `-LPHPreview` the main menu shows the hint on the mod's viewport layer, so that its look can be
// checked on a picture of the game's window (internal/tools/dev/g1r-shot.ps1 -Title "Gothic 1 Remake  "). Every hint
// draws view.lua's SAMPLE (LPHTests_SampleView), in two columns, from the top:
//   the tape, plain style, on the dark plate              | the lines, plain style
//   the tape, gold letters, on the plate, auto-pick's text | the lines, gold letters
//   the tape with Xbox icons, on the plate                 | the lines with PlayStation icons
//   a message (Russian), on the plate                      | the lines with Switch icons, gold letters, on the plate
// The first tape is shown twice - one press and one miss before the SAMPLE, then the SAMPLE on the first frame (nothing
// ticks while the startup logos play, about 15 s after BeginPlay) - so it slides and shakes once; the log has the offsets
// of those frames. Saved/LockPickHelper-preview.log has `preview shown` once everything is on the screen (the logos still
// cover it then). The layer is the one the mod uses (LPH::NewViewportLayer, Z-order LPH::LayerZOrder).

class ULPH_PreviewWorld : UScriptWorldSubsystem
{
	UPROPERTY()
	ULPH_Log PreviewLog;

	UPROPERTY()
	ULPH_ViewportLayer Layer;

	UPROPERTY()
	TArray<ULPH_HintWidget> Hints;

	bool bActive = false;
	int Frames = 0;
	int64 ShownMs = 0;
	bool bAnimLogged = false;

	UFUNCTION(BlueprintOverride)
	void OnWorldBeginPlay()
	{
		FString Command = FCommandLine::Get();
		if (!Command.Contains("-LPHPreview") || World.Name != n"MenuMap")
			return;
		PreviewLog = Cast<ULPH_Log>(NewObject(this, ULPH_Log::StaticClass()));
		PreviewLog.Open("LockPickHelper-preview.log");
		PreviewLog.Line("preview start");
		Layer = LPH::NewViewportLayer(Gameplay::GetPlayerController(0));
		if (Layer == nullptr)
		{
			PreviewLog.Line("no viewport layer (no player controller, or the layer was not made)");
			PreviewLog.Flush();
			return;
		}
		bool bRoot = Layer.GetRootWidget() == Layer.LayerCanvas;
		PreviewLog.Line(f"layer in the viewport: {Layer.IsInViewport()}, root is its canvas: {bRoot}");
		bActive = true;
		ShowAll();
		PreviewLog.Line("preview shown");
		PreviewLog.Flush();
	}

	UFUNCTION(BlueprintOverride)
	void Tick(float DeltaTime)
	{
		if (!bActive)
			return;
		int64 Now = LPH::NowMs();
		Frames++;
		if (Frames == 1)
		{
			PreviewLog.Line(f"first frame; game paused: {Gameplay::IsGamePaused()}");
			// The press and the miss, now that frames run.
			ShownMs = Now;
			TArray<FString> Letters;
			FLPH_Values Defaults;
			Hints[0].ShowHint(LPH::Tape(LPHTests_SampleView(), Defaults.TapeNext, Defaults.TapeDone, Letters), Now);
		}
		if (!Layer.IsInViewport())
		{
			PreviewLog.Line("the layer left the viewport: added again");
			PreviewLog.Flush();
			Layer.Show();
		}
		for (ULPH_HintWidget Hint : Hints)
			Hint.Animate(Now);
		if (!bAnimLogged)
		{
			// The first tape: how far its body slid and its plate shook in this frame.
			float Slide = Hints[0].Body().GetRenderTransform().Translation.X;
			float Shake = Hints[0].PlateBorder().GetRenderTransform().Translation.X;
			PreviewLog.Line(f"anim {Now - ShownMs} ms: slide {Slide}, shake {Shake}");
			if (Now - ShownMs > LPH::ShakeMs + 100)
			{
				bAnimLogged = true;
				PreviewLog.Flush();
			}
		}
	}

	void ShowAll()
	{
		int64 Now = LPH::NowMs();
		ShownMs = Now;
		FLPH_TrackerView Sample = LPHTests_SampleView();
		TArray<FString> Letters;
		FLPH_Values Defaults;

		// The view one step earlier for the counts: the next show is a press and a miss.
		FLPH_HintModel Before = LPH::Tape(Sample, Defaults.TapeNext, Defaults.TapeDone, Letters);
		Before.Pressed = 3;
		Before.Misses = 0;
		// The left column (narrow hints: the menu's buttons are further left).
		AddHint(true, false, true, -1000, -330, ELPH_IconSet::Letters).ShowHint(Before, Now);
		FLPH_Values Gothic = PreviewValues(true, true, true, -1000, -90);
		Gothic.bCounter = false;
		FLPH_HintModel Auto = LPH::Tape(Sample, Gothic.TapeNext, Gothic.TapeDone, Letters);
		Auto.Counter = LPH::Fill(LPH::TextsRu().SolvingTime, "12");
		Auto.bCounterAlways = true;
		NewHint(Gothic, ELPH_IconSet::Letters).ShowHint(Auto, Now);
		FLPH_HintModel Tape = LPH::Tape(Sample, Defaults.TapeNext, Defaults.TapeDone, Letters);
		AddHint(true, false, true, -1000, 160, ELPH_IconSet::Xbox).ShowHint(Tape, Now);
		FString NotInDb = LPH::Fill(LPH::TextsRu().NotInDb, "BC_Chest_04_Lock");
		AddHint(true, false, true, -1000, 380, ELPH_IconSet::Letters).ShowMessage(NotInDb);

		// The right column: the lines.
		FLPH_HintModel Lines = LPH::Lines(Sample, Defaults.PerLine, Defaults.MaxLines, Defaults.CollapseMin, Letters);
		AddHint(false, false, false, -60, -330, ELPH_IconSet::Letters).ShowHint(Lines, Now);
		AddHint(false, true, false, -60, -90, ELPH_IconSet::Letters).ShowHint(Lines, Now);
		AddHint(false, false, false, -60, 160, ELPH_IconSet::PlayStation).ShowHint(Lines, Now);
		AddHint(false, true, true, -60, 380, ELPH_IconSet::Switch).ShowHint(Lines, Now);

		for (ULPH_HintWidget Hint : Hints)
			PreviewLog.Line(f"hint: builds {Hint.Builds}, tokens {Hint.TokensMade}, texts set {Hint.TextSets}");
	}

	FLPH_Values PreviewValues(bool bTape, bool bGothic, bool bPlate, int OffsetX, int OffsetY)
	{
		FLPH_Values Values;
		Values.bTape = bTape;
		Values.bGothic = bGothic;
		Values.bPlate = bPlate;
		Values.OffsetX = OffsetX;
		Values.OffsetY = OffsetY;
		return Values;
	}

	ULPH_HintWidget AddHint(bool bTape, bool bGothic, bool bPlate, int OffsetX, int OffsetY, ELPH_IconSet Icons)
	{
		return NewHint(PreviewValues(bTape, bGothic, bPlate, OffsetX, OffsetY), Icons);
	}

	ULPH_HintWidget NewHint(FLPH_Values Values, ELPH_IconSet Icons)
	{
		ULPH_HintWidget Hint = Cast<ULPH_HintWidget>(NewObject(this, ULPH_HintWidget::StaticClass()));
		Hint.UseLog(PreviewLog);
		Hint.Attach(Layer, Layer.LayerCanvas);
		Hint.Configure(Values);
		Hint.SetIcons(Icons);
		Hints.Add(Hint);
		return Hint;
	}
}
