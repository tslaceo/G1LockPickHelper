// HintWidget.as with real widgets on a viewport layer of the main menu (removed at the end): what overlay_test.lua of
// 1.2.0 checked that does not need eyes - a tree per shape, texts set only when they change, the frame on the current key,
// empty tape cells keeping their place, letters and icons switched without a rebuild, lines tokens made only as needed,
// the counter, the message, the slide and the shake. The look itself is checked on pictures (-LPHPreview).

void LPHTests_HintWidget(ULPH_TestRun T)
{
	T.Begin("HintWidget layer");
	ULPH_ViewportLayer Layer = LPH::NewViewportLayer(Gameplay::GetPlayerController(0));
	T.True(Layer != nullptr, "a viewport layer is made in the main menu");
	if (Layer == nullptr)
		return;
	T.True(Layer.LayerCanvas != nullptr && Layer.GetRootWidget() == Layer.LayerCanvas, "its root is its canvas");
	T.True(Layer.IsInViewport(), "it is in the viewport");

	T.Begin("HintWidget assets");
	FString Icon = LPH::KeyTexture(ELPH_IconSet::Switch, ELPH_Key::D);
	T.True(Cast<UTexture2D>(LPH::LoadGameAsset(Icon)) != nullptr, "an icon of the game loads");
	T.True(Cast<UFont>(LPH::LoadGameAsset(LPH::FontSimple)) != nullptr, "the simple font loads");
	T.True(Cast<UFont>(LPH::LoadGameAsset(LPH::FontGothic)) != nullptr, "the gothic font loads");
	FString NoIcon = LPH::IconDir + "T_LPH_None.T_LPH_None";
	T.True(LPH::LoadGameAsset(NoIcon) == nullptr, "a missing one is null, no crash");

	LPHTests_HintWidgetTape(T, Layer);
	LPHTests_HintWidgetLines(T, Layer);
	LPHTests_HintWidgetStyles(T, Layer);
	LPHTests_HintWidgetOther(T, Layer);
	LPHTests_HintWidgetRelease(T, Layer);

	Layer.RemoveFromParent();
}

ULPH_HintWidget LPHTests_HintWidgetNew(ULPH_TestRun T, ULPH_ViewportLayer Layer, FLPH_Values Values)
{
	ULPH_HintWidget Hint = Cast<ULPH_HintWidget>(NewObject(T, ULPH_HintWidget::StaticClass()));
	Hint.Attach(Layer, Layer.LayerCanvas);
	Hint.Configure(Values);
	return Hint;
}

FString LPHTests_HintText(UTextBlock Block)
{
	if (Block == nullptr)
		return "<none>";
	return Block.GetText().ToString();
}

bool LPHTests_HintShown(UWidget Widget)
{
	return Widget != nullptr && Widget.GetVisibility() == ESlateVisibility::HitTestInvisible;
}

void LPHTests_HintWidgetTape(ULPH_TestRun T, ULPH_ViewportLayer Layer)
{
	T.Begin("HintWidget tape: one tree, cells from the model");
	FLPH_Values Values;
	TArray<FString> Letters;
	ULPH_HintWidget Hint = LPHTests_HintWidgetNew(T, Layer, Values);
	FLPH_HintModel M = LPH::Tape(LPHTests_SampleView(), Values.TapeNext, Values.TapeDone, Letters);
	Hint.ShowHint(M, 1000);
	T.EqualInt(Hint.Builds, 1, "built on the first show");
	T.EqualInt(Hint.TokensMade, 9, "TapeDone + 1 + TapeNext cells");
	T.True(LPHTests_HintShown(Hint.PlateBorder()), "the plate is shown");
	FString Texts;
	for (int At = 0; At < 9; At++)
	{
		if (At > 0)
			Texts += " ";
		Texts += LPHTests_HintText(Hint.CellAt(At).Letter);
	}
	T.EqualStr(Texts, "W D A A A A W D D", "the letters (the miss, two done, the current, five next)");
	T.True(LPHTests_HintShown(Hint.CellAt(3).Frame), "the current cell is framed");
	T.True(!LPHTests_HintShown(Hint.CellAt(2).Frame) && !LPHTests_HintShown(Hint.CellAt(4).Frame), "its neighbours are not");
	T.True(Hint.CellAt(0).Color.R == LPH::ColorMiss.R, "the miss is red");
	T.True(Hint.CellAt(1).Color.R == LPH::ColorDone.R, "a done key is green");
	T.True(Hint.CellAt(4).Color.A > Hint.CellAt(8).Color.A, "the next keys fade");
	T.EqualStr(LPHTests_HintText(Hint.CounterBlock()), "2/20", "the counter");
	T.True(LPHTests_HintShown(Hint.CounterBlock()), "the counter is shown");

	T.Begin("HintWidget tape: the same model again changes nothing");
	int TextSets = Hint.TextSets;
	Hint.ShowHint(M, 1100);
	T.EqualInt(Hint.Builds, 1, "no rebuild");
	T.EqualInt(Hint.TextSets, TextSets, "no text set again");

	T.Begin("HintWidget tape: empty cells keep their place");
	Hint.ShowHint(LPH::Tape(LPHTests_ViewOf("WS", 0, ""), Values.TapeNext, Values.TapeDone, Letters), 1200);
	T.True(Hint.CellAt(0).Box.GetVisibility() == ESlateVisibility::Hidden, "an empty done cell is hidden, not collapsed");
	T.True(Hint.CellAt(8).Box.GetVisibility() == ESlateVisibility::Hidden, "an empty next cell too");
	T.EqualStr(LPHTests_HintText(Hint.CellAt(3).Letter), "W", "the current key");
	T.EqualInt(Hint.Builds, 1, "still one tree");

	T.Begin("HintWidget tape: icons and back to letters without a rebuild");
	Hint.ShowHint(M, 1300);
	Hint.SetIcons(ELPH_IconSet::PlayStation);
	ULPH_HintToken Current = Hint.CellAt(3);
	T.True(Current.IconRow != nullptr && LPHTests_HintShown(Current.IconRow), "the icon row is shown at once");
	T.True(Current.Letter.GetVisibility() == ESlateVisibility::Collapsed, "the letter is not");
	T.EqualStr(Current.BrushPath, LPH::KeyTexture(ELPH_IconSet::PlayStation, ELPH_Key::A), "the icon of A");
	T.True(Current.Tail.GetVisibility() == ESlateVisibility::Collapsed, "a tape cell has no count");
	T.True(Current.Color.R == LPH::SimpleCurrent.R && Current.Color.A == 1.0, "the icon takes the letter's colour");
	Hint.SetIcons(ELPH_IconSet::Letters);
	T.True(LPHTests_HintShown(Current.Letter) && !LPHTests_HintShown(Current.IconRow), "letters again");
	T.EqualInt(Hint.Builds, 1, "no rebuild for icons");

	T.Begin("HintWidget tape: the offset moves, a new size rebuilds");
	Values.OffsetX = -500;
	Hint.Configure(Values);
	Hint.ShowHint(M, 1400);
	T.EqualInt(Hint.Builds, 1, "an offset is no new shape");
	Values.Scale = 150;
	Hint.Configure(Values);
	T.True(Hint.PlateBorder() == nullptr, "a new shape removes the tree");
	Hint.ShowHint(M, 1500);
	T.EqualInt(Hint.Builds, 2, "and the next show builds one");

	T.Begin("HintWidget tape: slide after a press, shake after a miss");
	FLPH_HintModel Before = M;
	Before.Pressed = 3;
	Before.Misses = 0;
	Values.Scale = 100;
	Hint.Configure(Values);
	Hint.ShowHint(Before, 1000);
	Hint.Animate(5000); // nothing runs: settles both
	Hint.ShowHint(M, 2000);
	Hint.Animate(2060);
	T.True(Hint.Body().GetRenderTransform().Translation.X > 0.0, "the tape slides in from the right");
	T.True(Hint.PlateBorder().GetRenderTransform().Translation.X != 0.0, "the plate shakes");
	Hint.Animate(2400);
	T.True(Hint.Body().GetRenderTransform().Translation.X == 0.0, "the slide ends within SlideMs");
	T.True(Hint.PlateBorder().GetRenderTransform().Translation.X == 0.0, "the shake ends within ShakeMs");
	Values.bSlide = false;
	Values.bShake = false;
	Hint.Configure(Values);
	Hint.ShowHint(Before, 3000);
	Hint.ShowHint(M, 3100);
	Hint.Animate(3160);
	T.True(Hint.Body().GetRenderTransform().Translation.X == 0.0, "no slide when off");
	T.True(Hint.PlateBorder().GetRenderTransform().Translation.X == 0.0, "no shake when off");
	Hint.Hide();
	T.True(Hint.PlateBorder().GetVisibility() == ESlateVisibility::Collapsed, "Hide hides the plate");
}

void LPHTests_HintWidgetLines(ULPH_TestRun T, ULPH_ViewportLayer Layer)
{
	T.Begin("HintWidget lines: tokens made as needed");
	FLPH_Values Values;
	Values.bTape = false;
	TArray<FString> Letters;
	ULPH_HintWidget Hint = LPHTests_HintWidgetNew(T, Layer, Values);
	FLPH_HintModel M = LPH::Lines(LPHTests_SampleView(), Values.PerLine, Values.MaxLines, Values.CollapseMin, Letters);
	Hint.ShowHint(M, 1000);
	T.EqualInt(Hint.RowCount(), 2, "two rows");
	T.EqualInt(Hint.TokensMade, 17, "one token per token of the model, not PerLine x MaxLines");
	ULPH_HintToken Run = Hint.TokenAt(0, 3);
	T.EqualStr(LPHTests_HintText(Run.Letter), "A×3", "the run in progress");
	T.True(LPHTests_HintShown(Run.Frame), "is framed");
	T.True(Run.Color.R == LPH::SimpleCurrent.R, "in the current key's colour");
	T.True(Hint.TokenAt(0, 1).Color.R == LPH::ColorMiss.R, "the miss is red");

	T.Begin("HintWidget lines: a shorter model collapses the rest");
	Hint.ShowHint(LPH::Lines(LPHTests_ViewOf("WSAD", 0, ""), Values.PerLine, Values.MaxLines, Values.CollapseMin, Letters), 1100);
	T.True(Hint.TokenAt(0, 4).Box.GetVisibility() == ESlateVisibility::Collapsed, "an unused token is collapsed");
	T.True(Hint.TokenAt(1, 0).Box.GetParent().GetVisibility() == ESlateVisibility::Collapsed, "an unused row is collapsed");
	T.EqualInt(Hint.TokensMade, 17, "no new tokens");
	T.EqualInt(Hint.Builds, 1, "one tree");

	T.Begin("HintWidget lines: a run with icons is the icon and its count");
	Hint.ShowHint(M, 1200);
	Hint.SetIcons(ELPH_IconSet::Xbox);
	T.True(LPHTests_HintShown(Run.IconRow), "the icon row");
	T.EqualStr(LPHTests_HintText(Run.Tail), "×3", "the count after the icon");
	T.True(LPHTests_HintShown(Run.Tail), "shown");
	T.EqualInt(Hint.Builds, 1, "no rebuild");
}

bool LPHTests_Near(float A, float B)
{
	return Math::Abs(A - B) < 0.0001;
}

bool LPHTests_SameColor(FLinearColor Color, float R, float G, float B, float A)
{
	return LPHTests_Near(Color.R, R) && LPHTests_Near(Color.G, G) && LPHTests_Near(Color.B, B) && LPHTests_Near(Color.A, A);
}

// The drop shadow of a text as it is on the widget: shown (the colour of LPH::ColorShadow) or not (no opacity).
bool LPHTests_Shadowed(UTextBlock Block)
{
	return Block != nullptr && LPHTests_Near(Block.ShadowColorAndOpacity.A, LPH::ColorShadow.A);
}

bool LPHTests_NoShadow(UTextBlock Block)
{
	return Block != nullptr && LPHTests_Near(Block.ShadowColorAndOpacity.A, 0.0);
}

// The corners and the outline of the brush a Border (a key's frame, the plate) was drawn with.
float LPHTests_FrameRadius(UBorder Frame)
{
	return Frame.Background.OutlineSettings.CornerRadii.X;
}

float LPHTests_FrameWidth(UBorder Frame)
{
	return Frame.Background.OutlineSettings.Width;
}

void LPHTests_HintWidgetStyles(ULPH_TestRun T, ULPH_ViewportLayer Layer)
{
	T.Begin("HintWidget style: the plain style copies the minigame's key prompts");
	FLPH_Style Plain = LPH::StyleOf(false);
	T.True(LPHTests_SameColor(Plain.Current, 1.0, 0.68, 0.51, 1.0), "the current letter is sRGB #FFD7BD (linear 1, 0.68, 0.51)");
	T.True(LPHTests_SameColor(Plain.Next, 1.0, 0.68, 0.51, 1.0), "the other letters too");
	T.True(LPHTests_SameColor(Plain.Frame, 1.0, 0.68, 0.51, 1.0), "the border too");
	T.True(LPHTests_SameColor(Plain.Fill, 0.0065, 0.0061, 0.0065, 1.0), "the fill is sRGB #131213");
	T.True(Plain.FrameRadius == 0.0 && LPHTests_Near(Plain.FrameWidth, 1.5), "a square frame, 1.5 px");
	T.True(!Plain.bCurrentShadow, "no shadow under the current letter");
	FLPH_Style Gold = LPH::StyleOf(true);
	T.True(LPHTests_SameColor(Gold.Current, 1.0, 0.78, 0.1, 1.0), "gold letters: the current letter is gold");
	T.True(LPHTests_SameColor(Gold.Next, 1.0, 1.0, 1.0, 1.0), "the others white");
	T.True(Gold.FrameRadius == 3.0 && Gold.FrameWidth == 2.0 && Gold.bCurrentShadow, "a rounded frame of 2 px, the shadow as before");

	T.Begin("HintWidget style: plain tape - a square thin frame, no shadow under the current letter only");
	TArray<FString> Letters;
	FLPH_Values Values;
	Values.bPlate = true;
	ULPH_HintWidget Hint = LPHTests_HintWidgetNew(T, Layer, Values);
	FLPH_HintModel M = LPH::Tape(LPHTests_SampleView(), Values.TapeNext, Values.TapeDone, Letters);
	Hint.ShowHint(M, 1000);
	ULPH_HintToken Current = Hint.CellAt(3);
	T.True(LPHTests_FrameRadius(Current.Frame) == 0.0 && LPHTests_Near(LPHTests_FrameWidth(Current.Frame), 1.5), "the frame: square, 1.5 px");
	T.True(LPHTests_NoShadow(Current.Letter), "the current letter has no shadow");
	T.True(LPHTests_Shadowed(Hint.CellAt(4).Letter) && LPHTests_Shadowed(Hint.CellAt(8).Letter), "the next ones keep it");
	T.True(LPHTests_Shadowed(Hint.CellAt(1).Letter) && LPHTests_Shadowed(Hint.CellAt(0).Letter), "so do the done and the miss");
	T.True(LPHTests_Near(LPHTests_FrameRadius(Hint.PlateBorder()), 3.0), "the dark plate keeps radius 3");

	T.Begin("HintWidget style: gold letters keep the rounded frame and the shadow");
	Values.bGothic = true;
	ULPH_HintWidget GoldHint = LPHTests_HintWidgetNew(T, Layer, Values);
	GoldHint.ShowHint(M, 1000);
	ULPH_HintToken GoldCurrent = GoldHint.CellAt(3);
	T.True(LPHTests_Near(LPHTests_FrameRadius(GoldCurrent.Frame), 3.0) && LPHTests_Near(LPHTests_FrameWidth(GoldCurrent.Frame), 2.0), "the frame: radius 3, 2 px");
	T.True(LPHTests_Shadowed(GoldCurrent.Letter), "the current letter has its shadow");
	T.True(LPHTests_Near(LPHTests_FrameRadius(GoldHint.PlateBorder()), 3.0), "the dark plate: radius 3");

	T.Begin("HintWidget style: the shadow follows the current key through the lines");
	FLPH_Values LinesValues;
	LinesValues.bTape = false;
	ULPH_HintWidget Lines = LPHTests_HintWidgetNew(T, Layer, LinesValues);
	Lines.ShowHint(LPH::Lines(LPHTests_ViewOf("WSAD", 0, ""), LinesValues.PerLine, LinesValues.MaxLines, LinesValues.CollapseMin, Letters), 1000);
	T.True(LPHTests_NoShadow(Lines.TokenAt(0, 0).Letter) && LPHTests_Shadowed(Lines.TokenAt(0, 1).Letter), "the first key is the current one");
	Lines.ShowHint(LPH::Lines(LPHTests_ViewOf("WSAD", 1, "W+"), LinesValues.PerLine, LinesValues.MaxLines, LinesValues.CollapseMin, Letters), 1100);
	T.True(LPHTests_Shadowed(Lines.TokenAt(0, 0).Letter), "a key pressed gets its shadow back");
	T.True(LPHTests_NoShadow(Lines.TokenAt(0, 1).Letter), "the next one has none");
	T.EqualInt(Lines.Builds, 1, "without a rebuild");

	T.Begin("HintWidget style: the count after an icon of the current key has no shadow either");
	Lines.ShowHint(LPH::Lines(LPHTests_SampleView(), LinesValues.PerLine, LinesValues.MaxLines, LinesValues.CollapseMin, Letters), 1200);
	Lines.SetIcons(ELPH_IconSet::Xbox);
	ULPH_HintToken Run = Lines.TokenAt(0, 3);
	T.True(Run.Tail != nullptr && LPHTests_NoShadow(Run.Tail), "the current run's count");
	T.True(Lines.TokenAt(0, 1).Tail != nullptr && LPHTests_Shadowed(Lines.TokenAt(0, 1).Tail), "another key's count");
	Lines.SetIcons(ELPH_IconSet::Letters);
	T.True(LPHTests_NoShadow(Run.Letter), "back to letters: the current letter has none");
}

void LPHTests_HintWidgetOther(ULPH_TestRun T, ULPH_ViewportLayer Layer)
{
	T.Begin("HintWidget: the counter follows its setting and the model");
	FLPH_Values Values;
	Values.bCounter = false;
	TArray<FString> Letters;
	ULPH_HintWidget Hint = LPHTests_HintWidgetNew(T, Layer, Values);
	FLPH_HintModel M = LPH::Tape(LPHTests_SampleView(), Values.TapeNext, Values.TapeDone, Letters);
	Hint.ShowHint(M, 1000);
	T.True(Hint.CounterBlock().GetVisibility() == ESlateVisibility::Collapsed, "off");
	M.bCounterAlways = true;
	M.Counter = "Auto-picking";
	Hint.ShowHint(M, 1100);
	T.True(LPHTests_HintShown(Hint.CounterBlock()), "shown for the auto-pick");
	T.EqualStr(LPHTests_HintText(Hint.CounterBlock()), "Auto-picking", "its text");

	T.Begin("HintWidget: a message hides the keys and the counter");
	Hint.ShowMessage("Lock not in the database: X");
	T.True(LPHTests_HintShown(Hint.MessageBlock()), "the message");
	T.EqualStr(LPHTests_HintText(Hint.MessageBlock()), "Lock not in the database: X", "its text");
	T.True(Hint.Body().GetVisibility() == ESlateVisibility::Collapsed, "no keys");
	T.True(Hint.CounterBlock().GetVisibility() == ESlateVisibility::Collapsed, "no counter");
	Hint.ShowHint(M, 1200);
	T.True(Hint.MessageBlock().GetVisibility() == ESlateVisibility::Collapsed, "the hint hides the message");

	T.Begin("HintWidget: a model of the other layout is not drawn");
	FLPH_Values Tape;
	ULPH_HintWidget Other = LPHTests_HintWidgetNew(T, Layer, Tape);
	Other.ShowHint(LPH::Lines(LPHTests_SampleView(), 16, 6, 3, Letters), 1000);
	T.EqualInt(Other.Builds, 0, "no tree");

	T.Begin("HintWidget: nothing before Attach and Configure");
	ULPH_HintWidget Bare = Cast<ULPH_HintWidget>(NewObject(T, ULPH_HintWidget::StaticClass()));
	Bare.ShowHint(M, 1000);
	Bare.ShowMessage("x");
	Bare.Hide();
	Bare.Animate(1000);
	T.EqualInt(Bare.Builds, 0, "no tree");

	T.Begin("HintWidget: another canvas releases the old one");
	UBorder OldPlate = Hint.PlateBorder();
	Hint.Attach(Layer, nullptr);
	T.True(Hint.PlateBorder() == nullptr, "the tree is forgotten");
	T.True(OldPlate.GetParent() == nullptr, "its plate left the layer's canvas");
	Hint.ShowHint(M, 1300);
	T.EqualInt(Hint.Builds, 1, "and nothing is built without a canvas");
}

// A canvas of its own for a check that counts the canvas's children (the layer's canvas holds the other tests' hints).
UCanvasPanel LPHTests_HintCanvas(ULPH_ViewportLayer Layer)
{
	return Cast<UCanvasPanel>(Layer.ConstructWidget(UCanvasPanel));
}

void LPHTests_HintWidgetRelease(ULPH_TestRun T, ULPH_ViewportLayer Layer)
{
	T.Begin("HintWidget Release: off the canvas, and one plate after the next show");
	FLPH_Values Values;
	UCanvasPanel Canvas = LPHTests_HintCanvas(Layer);
	ULPH_HintWidget Hint = Cast<ULPH_HintWidget>(NewObject(T, ULPH_HintWidget::StaticClass()));
	Hint.Attach(Layer, Canvas);
	Hint.Configure(Values);
	Hint.ShowMessage("note");
	T.EqualInt(Canvas.GetChildrenCount(), 1, "the note is in the canvas");
	Hint.Release();
	T.EqualInt(Canvas.GetChildrenCount(), 0, "Release takes it off");
	T.True(Hint.PlateBorder() == nullptr, "and forgets the tree");
	Hint.ShowMessage("note");
	T.EqualInt(Canvas.GetChildrenCount(), 0, "nothing is shown until the next Attach");
	Hint.Attach(Layer, Canvas);
	Hint.ShowMessage("note");
	T.EqualInt(Canvas.GetChildrenCount(), 1, "attached again: one plate");

	T.Begin("HintWidget Release: Attach twice to the same canvas");
	Hint.Attach(Layer, Canvas);
	Hint.ShowMessage("note 2");
	T.EqualInt(Canvas.GetChildrenCount(), 1, "still one plate");
	T.EqualInt(Hint.Builds, 2, "the same tree");

	T.Begin("HintWidget Release: Attach to another canvas releases the old one");
	UCanvasPanel Other = LPHTests_HintCanvas(Layer);
	Hint.Attach(Layer, Other);
	T.EqualInt(Canvas.GetChildrenCount(), 0, "the old canvas is empty");
	Hint.ShowMessage("note");
	T.EqualInt(Other.GetChildrenCount(), 1, "the new one has the plate");

	T.Begin("HintWidget Detach: no call into the old canvas, one plate in the next");
	Hint.Detach();
	T.True(Hint.PlateBorder() == nullptr, "the tree is forgotten");
	T.EqualInt(Other.GetChildrenCount(), 1, "the old plate stays where it was (that canvas goes with its world)");
	UCanvasPanel Fresh = LPHTests_HintCanvas(Layer);
	Hint.Attach(Layer, Fresh);
	Hint.ShowMessage("note");
	T.EqualInt(Fresh.GetChildrenCount(), 1, "the fresh canvas has one plate");
	T.EqualInt(Other.GetChildrenCount(), 1, "and the old one is not touched");
}
