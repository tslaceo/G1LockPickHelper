// The hint on screen (overlay.lua of 1.2.0, ported by meaning): UMG widgets built from script inside a canvas of another
// widget - the minigame's window, or the mod's own viewport layer (ViewportLayer.as). What to draw comes from View.as
// (FLPH_HintModel), the shape and the place from the player's settings (Configure), letters or the game's gamepad icons
// from SetIcons.
//
// The tree: the canvas -> the plate (a Border: a dark rounded box with a gold outline with Values.bPlate, clear without;
// its canvas slot holds the anchor, the pivot and the offset) -> a column of the counter, the message and the body. The
// body is the tape (a row of cells of a fixed width, known without measuring, which the slide relies on; the current cell
// is wider and its letter 1.3 times bigger) or the lines (rows of tokens, each as wide as its text). A cell or token is an
// Overlay: the frame (shown on the current key only), the letter and, once an icon is drawn there, the icon row (the icon
// and, for a run of the lines, "×N").
//
// A new shape (layout, style, size, the tape's cells, the lines' size, the plate) builds the tree anew; anything else -
// texts, colours, alphas, letters and icons, the offset - changes the built widgets, and only where it changed. The lines'
// tokens are made when a model first needs them and the icon rows when an icon is first drawn, so a short plan costs a
// few widgets, not PerLine x MaxLines of them. A font or an icon texture loads once per path; one that does not load gives
// the engine font or the letter, with one log line per path.
//
// The caller: UseLog, Attach (the owner makes the widgets, the canvas holds them), Configure, SetIcons, then ShowHint /
// ShowMessage / Hide when what is shown changes (not every frame) and Animate every frame (the tape slides back after a
// press, the hint shakes after a miss). The end depends on the canvas:
// - one that goes with its world (the minigame window): Detach on its Destruct and when a save loads - no call into it;
// - one that stays (the mod's viewport layer, ViewportLayer.as): Hide to take the hint off the screen, Release to take
//   it off the layer - never a plain Detach, which would leave the plate in the layer (and a second one after the next
//   show).
// Attach to another canvas releases the hint from the old one when that one is still valid.

namespace LPH
{
	// A game asset by its object path ("/Game/Dir/Name.Name"), loaded now; null when there is none.
	UObject LoadGameAsset(FString Path)
	{
		TSoftObjectPtr<UObject> Ref = System::Conv_SoftObjPathToSoftObjRef(System::MakeSoftObjectPath(Path));
		return FAssetPreload::BlockingLoad(Ref);
	}
}

// One key of the hint - a cell of the tape or a token of the lines - and what it shows now (the widgets are called only
// for a change).
class ULPH_HintToken : UObject
{
	UPROPERTY()
	UOverlay Box;

	UPROPERTY()
	UBorder Frame;

	UPROPERTY()
	UTextBlock Letter;

	// The icon row and its parts: null until an icon is first drawn in this token.
	UPROPERTY()
	UHorizontalBox IconRow;

	UPROPERTY()
	UImage Icon;

	UPROPERTY()
	UTextBlock Tail;

	bool bKeepSpace = false; // empty: hidden, keeping its width (a tape cell), or collapsed (a token of the lines)
	int LetterSize = 0;
	FMargin Pad;

	// What is shown; -1 or false: nothing set yet.
	int ShownState = -1;
	int IconicState = -1;
	int FramedState = -1;
	bool bLetterSet = false;
	FString LetterText;
	FString BrushPath;
	bool bTailSet = false;
	FString TailText;
	bool bColorSet = false;
	bool bColorIconic = false;
	FLinearColor Color;
}

// A row of the lines.
class ULPH_HintRow : UObject
{
	UPROPERTY()
	UHorizontalBox Box;

	UPROPERTY()
	TArray<ULPH_HintToken> Tokens;
}

class ULPH_HintWidget : UObject
{
	// What the tests look at.
	int Builds = 0; // trees built
	int TextSets = 0; // SetText calls
	int TokensMade = 0; // cells and tokens made, in all trees

	UPROPERTY()
	private UUserWidget Owner;

	UPROPERTY()
	private UCanvasPanel Canvas;

	UPROPERTY()
	private ULPH_Log ModLog;

	// The fonts and icon textures loaded, by path; Missing: the paths that did not load.
	UPROPERTY()
	private TMap<FString, UObject> Assets;

	private TArray<FString> Missing;

	// From Configure.
	private bool bConfigured = false;
	private FLPH_Values Opts;
	private int Size = LPH::BaseFontSize; // the letter size
	private FString Shape;

	private ELPH_IconSet IconSet = ELPH_IconSet::Letters;

	// The tree (Plate null: none built).
	UPROPERTY()
	private UBorder Plate;

	UPROPERTY()
	private UCanvasPanelSlot PlateSlot;

	UPROPERTY()
	private UTextBlock Counter;

	UPROPERTY()
	private UTextBlock Message;

	UPROPERTY()
	private UHorizontalBox Tape;

	UPROPERTY()
	private UVerticalBox LineBox;

	UPROPERTY()
	private TArray<ULPH_HintToken> Cells;

	UPROPERTY()
	private TArray<ULPH_HintRow> Rows;

	private FString BuiltShape;
	private FLPH_Style BuiltStyle;
	private float StepPx = 0.0; // the width of a tape cell: how far the tape slides
	private bool bCounterSet = false;
	private FString CounterText;
	private bool bMessageSet = false;
	private FString MessageText;

	// The hint shown (SetIcons draws it again); false while a message is shown, or nothing.
	private bool bHintShown = false;
	private FLPH_HintModel LastModel;

	// The counts seen last, and the start of the running slide and shake (-1: none).
	private int AnimPressed = 0;
	private int AnimMisses = 0;
	private int64 SlideStart = -1;
	private int64 ShakeStart = -1;

	// Where "font not found" and "icon not found" go.
	void UseLog(ULPH_Log InLog)
	{
		ModLog = InLog;
	}

	// The widget that makes the hint's widgets (ConstructWidget) and the canvas that holds them; the next show builds the
	// tree there. Another owner or canvas releases the hint from the one it is attached to first (Release), so a canvas
	// that is still valid keeps no orphan of it; after Detach there is nothing to release.
	void Attach(UUserWidget InOwner, UCanvasPanel InCanvas)
	{
		if (InOwner == Owner && InCanvas == Canvas)
			return;
		Release();
		Owner = InOwner;
		Canvas = InCanvas;
	}

	// Takes the hint off its canvas (the plate leaves it, when both are still valid) and forgets the owner, the canvas and
	// the tree. For a canvas that outlives the hint's use - the mod's viewport layer, which a load does not take down:
	// Hide() takes the hint off the screen, Release() off the layer. Never a plain Detach there: the plate would stay in
	// the layer as it was (a note shown at the moment stays on the screen) and the next show would add another one.
	void Release()
	{
		if (IsValid(Plate) && IsValid(Canvas))
			Plate.RemoveFromParent();
		Detach();
	}

	// Forgets the owner, the canvas and the tree without a call into them, leaving the plate where it is: for a canvas
	// that goes with its world - the minigame window on its Destruct or when a save loads (a call into its widgets then
	// may not be safe).
	void Detach()
	{
		ForgetTree();
		Owner = nullptr;
		Canvas = nullptr;
		AnimPressed = 0;
		AnimMisses = 0;
	}

	// The player's settings. A new shape removes the tree (the next show builds a new one); a new offset moves the hint
	// at once.
	void Configure(FLPH_Values InValues)
	{
		FLPH_Values V = LPH::Clamped(InValues);
		int NewSize = Math::Max(8, Px(float(LPH::BaseFontSize) * float(V.Scale) / 100.0));
		FString NewShape = f"{V.bTape}|{V.bGothic}|{NewSize}|{V.TapeNext}|{V.TapeDone}|{V.PerLine}|{V.MaxLines}|{V.bPlate}";
		if (Plate != nullptr && NewShape != BuiltShape)
			DropTree();
		Opts = V;
		Size = NewSize;
		Shape = NewShape;
		bConfigured = true;
		if (PlateSlot != nullptr)
			PlateSlot.SetPosition(FVector2D(float(Opts.OffsetX), float(Opts.OffsetY)));
	}

	// Letters or the icons of a gamepad: the hint shown is drawn again at once, without a rebuild.
	void SetIcons(ELPH_IconSet NewSet)
	{
		if (NewSet == IconSet)
			return;
		IconSet = NewSet;
		if (bHintShown && Plate != nullptr)
			DrawHint(LastModel);
	}

	// A model of LPH::Tape or LPH::Lines for the configured layout (another one is not drawn: the settings changed after
	// it was made). Model.bCounterAlways shows the counter whatever the setting. Now starts the slide and the shake.
	void ShowHint(const FLPH_HintModel& Model, int64 Now)
	{
		if (Model.bLines == Opts.bTape)
			return;
		if (!Ensure())
			return;
		LastModel = Model;
		bHintShown = true;
		DrawHint(Model);
		if (Model.Pressed > AnimPressed && !Model.bLines && Opts.bSlide)
			SlideStart = Now;
		if (Model.Misses > AnimMisses && Opts.bShake)
			ShakeStart = Now;
		AnimPressed = Model.Pressed;
		AnimMisses = Model.Misses;
		Plate.SetVisibility(ESlateVisibility::HitTestInvisible);
	}

	// A text in place of the hint.
	void ShowMessage(FString Text)
	{
		if (!Ensure())
			return;
		bHintShown = false;
		if (!bMessageSet || MessageText != Text)
		{
			SetBlockText(Message, Text);
			MessageText = Text;
			bMessageSet = true;
		}
		Message.SetVisibility(ESlateVisibility::HitTestInvisible);
		Counter.SetVisibility(ESlateVisibility::Collapsed);
		Body().SetVisibility(ESlateVisibility::Collapsed);
		Plate.SetVisibility(ESlateVisibility::HitTestInvisible);
	}

	void Hide()
	{
		bHintShown = false;
		if (Plate != nullptr)
			Plate.SetVisibility(ESlateVisibility::Collapsed);
	}

	// Every frame: the tape slides back into place after a press; the plate shakes after a miss.
	void Animate(int64 Now)
	{
		if (Plate == nullptr)
			return;
		if (SlideStart >= 0)
		{
			float T = float(int(Now - SlideStart)) / float(LPH::SlideMs);
			if (T >= 1.0)
			{
				SlideStart = -1;
				Body().SetRenderTranslation(FVector2D(0.0, 0.0));
			}
			else
			{
				Body().SetRenderTranslation(FVector2D(StepPx * (1.0 - EaseOut(Math::Max(0.0, T))), 0.0));
			}
		}
		if (ShakeStart >= 0)
		{
			float T = float(int(Now - ShakeStart)) / float(LPH::ShakeMs);
			if (T >= 1.0)
			{
				ShakeStart = -1;
				Plate.SetRenderTranslation(FVector2D(0.0, 0.0));
			}
			else
			{
				float Amplitude = float(LPH::ShakePx) * float(Opts.Scale) / 100.0;
				Plate.SetRenderTranslation(FVector2D(Amplitude * Math::Sin(T * 6.0 * PI) * (1.0 - T), 0.0));
			}
		}
	}

	// For the tests: the cell of the tape at Index, or the token of the lines at Row/Column (null: not made).
	ULPH_HintToken CellAt(int Index)
	{
		if (Index < 0 || Index >= Cells.Num())
			return nullptr;
		return Cells[Index];
	}

	ULPH_HintToken TokenAt(int Row, int Column)
	{
		if (Row < 0 || Row >= Rows.Num() || Column < 0 || Column >= Rows[Row].Tokens.Num())
			return nullptr;
		return Rows[Row].Tokens[Column];
	}

	// For the tests and the preview: the counter and message blocks, the plate, the body (null: no tree).
	UTextBlock CounterBlock()
	{
		return Counter;
	}

	UTextBlock MessageBlock()
	{
		return Message;
	}

	UBorder PlateBorder()
	{
		return Plate;
	}

	int RowCount() const
	{
		return Rows.Num();
	}

	// The tape or the lines (null: no tree).
	UPanelWidget Body()
	{
		if (Tape != nullptr)
			return Tape;
		return LineBox;
	}

	private int Px(float X) const
	{
		return Math::FloorToInt(X + 0.5);
	}

	private float EaseOut(float T) const
	{
		return 1.0 - (1.0 - T) * (1.0 - T);
	}

	// Builds the tree on the first show and after a new shape.
	private bool Ensure()
	{
		if (Owner == nullptr || Canvas == nullptr || !bConfigured)
			return false;
		if (Plate != nullptr && BuiltShape == Shape)
			return true;
		if (Plate != nullptr)
			DropTree();
		return Build();
	}

	private void DropTree()
	{
		if (Plate != nullptr)
			Plate.RemoveFromParent();
		ForgetTree();
	}

	private void ForgetTree()
	{
		Plate = nullptr;
		PlateSlot = nullptr;
		Counter = nullptr;
		Message = nullptr;
		Tape = nullptr;
		LineBox = nullptr;
		Cells.Reset();
		Rows.Reset();
		BuiltShape = "";
		bCounterSet = false;
		bMessageSet = false;
		bHintShown = false;
		SlideStart = -1;
		ShakeStart = -1;
	}

	private bool Build()
	{
		int F = Size;
		BuiltStyle = LPH::StyleOf(Opts.bGothic);
		Plate = Cast<UBorder>(Owner.ConstructWidget(UBorder));
		UVerticalBox Column = Cast<UVerticalBox>(Owner.ConstructWidget(UVerticalBox));
		if (Plate == nullptr || Column == nullptr)
		{
			Warn("cannot build the hint: a widget was not made");
			Plate = nullptr;
			return false;
		}
		if (Opts.bPlate)
			Rounded(Plate, FLinearColor(0.0, 0.0, 0.0, LPH::PlateAlpha), LPH::ColorPlateFrame, 1.5);
		else
			Plate.SetBrushColor(FLinearColor(0.0, 0.0, 0.0, 0.0));
		Plate.SetPadding(FMargin(Px(F * 0.4), Px(F * 0.2), Px(F * 0.4), Px(F * 0.2)));
		Plate.SetVisibility(ESlateVisibility::Collapsed);
		PlateSlot = Canvas.AddChildToCanvas(Plate);
		PlateSlot.SetAnchors(FAnchors(LPH::AnchorX, LPH::AnchorY, LPH::AnchorX, LPH::AnchorY));
		PlateSlot.SetAlignment(FVector2D(LPH::PivotX, LPH::PivotY));
		PlateSlot.SetPosition(FVector2D(float(Opts.OffsetX), float(Opts.OffsetY)));
		PlateSlot.SetAutoSize(true);
		PlateSlot.SetZOrder(LPH::ZOrder);
		Plate.SetContent(Column);

		Counter = NewText(LPH::FontText, LPH::FontTextFace, Math::Max(10, Px(F * 0.6)), LPH::ColorCounter);
		Column.AddChildToVerticalBox(Counter);
		Message = NewText(LPH::FontText, LPH::FontTextFace, F, LPH::ColorMessage);
		Column.AddChildToVerticalBox(Message);

		if (Opts.bTape)
		{
			Tape = Cast<UHorizontalBox>(Owner.ConstructWidget(UHorizontalBox));
			int Width = Px(F * 1.4);
			int Height = Px(F * 1.8);
			StepPx = float(Width);
			int Count = Opts.TapeDone + 1 + Opts.TapeNext;
			for (int At = 0; At < Count; At++)
			{
				bool bCurrent = At == Opts.TapeDone;
				int LetterSize = F;
				int CellWidth = Width;
				if (bCurrent)
				{
					LetterSize = Px(F * 1.3);
					CellWidth = Px(F * 2.0);
				}
				ULPH_HintToken Token = NewToken(LetterSize, FMargin(0.0, 0.0, 0.0, 0.0), true);
				// The height is a minimum only: the gothic font has a taller line than the simple one, and the row
				// stretches every cell to the tallest, so the current cell's frame (Fill) encloses its letter.
				USizeBox Cell = Cast<USizeBox>(Owner.ConstructWidget(USizeBox));
				Cell.SetWidthOverride(CellWidth);
				Cell.SetMinDesiredHeight(Height);
				USizeBoxSlot CellSlot = Cast<USizeBoxSlot>(Cell.SetContent(Token.Box));
				if (CellSlot != nullptr)
				{
					CellSlot.SetHorizontalAlignment(EHorizontalAlignment::HAlign_Fill);
					CellSlot.SetVerticalAlignment(EVerticalAlignment::VAlign_Fill);
				}
				Tape.AddChildToHorizontalBox(Cell);
				Cells.Add(Token);
			}
			Column.AddChildToVerticalBox(Tape);
		}
		else
		{
			LineBox = Cast<UVerticalBox>(Owner.ConstructWidget(UVerticalBox));
			Column.AddChildToVerticalBox(LineBox);
		}

		BuiltShape = Shape;
		Builds++;
		return true;
	}

	// A text block in a game font (written before the block is first shown); the engine font when the font did not load.
	private UTextBlock NewText(FString FontPath, FString Face, int FontSize, FLinearColor Color)
	{
		UTextBlock Block = Cast<UTextBlock>(Owner.ConstructWidget(UTextBlock));
		FSlateFontInfo Info = Block.Font;
		UFont Font = Cast<UFont>(LoadAsset(FontPath, "font", "the engine font"));
		if (Font != nullptr)
		{
			Info.FontObject = Font;
			Info.TypefaceFontName = FName(Face);
		}
		Info.Size = FontSize;
		Block.SetFont(Info);
		Block.SetColorAndOpacity(FSlateColor(Color));
		Block.SetShadowOffset(FVector2D(1.5, 1.5));
		Block.SetShadowColorAndOpacity(FLinearColor(0.0, 0.0, 0.0, 0.9));
		return Block;
	}

	// Draws a Border as a rounded box: Fill inside, an outline of Width px in Outline.
	private void Rounded(UBorder Border, FLinearColor Fill, FLinearColor Outline, float Width)
	{
		FSlateBrush Brush;
		Brush.DrawAs = ESlateBrushDrawType::RoundedBox;
		Brush.TintColor = FSlateColor(Fill);
		Brush.OutlineSettings.Width = Width;
		Brush.OutlineSettings.Color = FSlateColor(Outline);
		Brush.OutlineSettings.RoundingType = ESlateBrushRoundingType::FixedRadius;
		Brush.OutlineSettings.CornerRadii = FVector4(LPH::CornerRadius, LPH::CornerRadius, LPH::CornerRadius, LPH::CornerRadius);
		Border.SetBrush(Brush);
		Border.SetBrushColor(FLinearColor(1.0, 1.0, 1.0, 1.0));
	}

	// A key: the Overlay with the frame (collapsed until the key is the current one) under the letter.
	private ULPH_HintToken NewToken(int LetterSize, FMargin Pad, bool bKeepSpace)
	{
		ULPH_HintToken Token = Cast<ULPH_HintToken>(NewObject(this, ULPH_HintToken::StaticClass()));
		Token.bKeepSpace = bKeepSpace;
		Token.LetterSize = LetterSize;
		Token.Pad = Pad;
		Token.Box = Cast<UOverlay>(Owner.ConstructWidget(UOverlay));
		Token.Frame = Cast<UBorder>(Owner.ConstructWidget(UBorder));
		Rounded(Token.Frame, BuiltStyle.Fill, BuiltStyle.Frame, 2.0);
		Token.Frame.SetVisibility(ESlateVisibility::Collapsed);
		Token.FramedState = 0;
		UOverlaySlot FrameSlot = Token.Box.AddChildToOverlay(Token.Frame);
		FrameSlot.SetHorizontalAlignment(EHorizontalAlignment::HAlign_Fill);
		FrameSlot.SetVerticalAlignment(EVerticalAlignment::VAlign_Fill);
		Token.Letter = NewText(LettersFont(), LettersFace(), LetterSize, BuiltStyle.Next);
		Token.Letter.SetJustification(ETextJustify::Center);
		UOverlaySlot LetterSlot = Token.Box.AddChildToOverlay(Token.Letter);
		LetterSlot.SetHorizontalAlignment(EHorizontalAlignment::HAlign_Center);
		LetterSlot.SetVerticalAlignment(EVerticalAlignment::VAlign_Center);
		LetterSlot.SetPadding(Pad);
		TokensMade++;
		return Token;
	}

	// The icon row of a token, made when an icon is first drawn there: a square Image of the letter size times
	// LPH::IconScale and the "×N" of a run after it.
	private void EnsureIconRow(ULPH_HintToken Token)
	{
		if (Token.IconRow != nullptr)
			return;
		Token.IconRow = Cast<UHorizontalBox>(Owner.ConstructWidget(UHorizontalBox));
		USizeBox IconBox = Cast<USizeBox>(Owner.ConstructWidget(USizeBox));
		int IconPx = Px(float(Token.LetterSize) * LPH::IconScale);
		IconBox.SetWidthOverride(IconPx);
		IconBox.SetHeightOverride(IconPx);
		Token.Icon = Cast<UImage>(Owner.ConstructWidget(UImage));
		IconBox.SetContent(Token.Icon);
		UHorizontalBoxSlot IconSlot = Token.IconRow.AddChildToHorizontalBox(IconBox);
		IconSlot.SetVerticalAlignment(EVerticalAlignment::VAlign_Center);
		Token.Tail = NewText(LettersFont(), LettersFace(), Token.LetterSize, BuiltStyle.Next);
		Token.Tail.SetVisibility(ESlateVisibility::Collapsed);
		Token.TailText = "";
		Token.bTailSet = true;
		UHorizontalBoxSlot TailSlot = Token.IconRow.AddChildToHorizontalBox(Token.Tail);
		TailSlot.SetVerticalAlignment(EVerticalAlignment::VAlign_Center);
		Token.IconRow.SetVisibility(ESlateVisibility::Collapsed);
		UOverlaySlot RowSlot = Token.Box.AddChildToOverlay(Token.IconRow);
		RowSlot.SetHorizontalAlignment(EHorizontalAlignment::HAlign_Center);
		RowSlot.SetVerticalAlignment(EVerticalAlignment::VAlign_Center);
		RowSlot.SetPadding(Token.Pad);
	}

	private FString LettersFont() const
	{
		if (Opts.bGothic)
			return LPH::FontGothic;
		return LPH::FontSimple;
	}

	private FString LettersFace() const
	{
		if (Opts.bGothic)
			return LPH::FontGothicFace;
		return LPH::FontSimpleFace;
	}

	// The row R of the lines, made when first needed.
	private ULPH_HintRow RowOf(int R)
	{
		while (Rows.Num() <= R)
		{
			ULPH_HintRow Row = Cast<ULPH_HintRow>(NewObject(this, ULPH_HintRow::StaticClass()));
			Row.Box = Cast<UHorizontalBox>(Owner.ConstructWidget(UHorizontalBox));
			LineBox.AddChildToVerticalBox(Row.Box);
			Rows.Add(Row);
		}
		return Rows[R];
	}

	// The token C of a row of the lines, made when first needed.
	private ULPH_HintToken TokenOf(ULPH_HintRow Row, int C)
	{
		while (Row.Tokens.Num() <= C)
		{
			FMargin Pad = FMargin(Px(Size * 0.25), Px(Size * 0.1), Px(Size * 0.25), Px(Size * 0.1));
			ULPH_HintToken Token = NewToken(Size, Pad, false);
			UHorizontalBoxSlot TokenSlot = Row.Box.AddChildToHorizontalBox(Token.Box);
			TokenSlot.SetPadding(FMargin(0.0, 0.0, Px(Size * 0.15), 0.0));
			Row.Tokens.Add(Token);
		}
		return Row.Tokens[C];
	}

	private void DrawHint(const FLPH_HintModel& Model)
	{
		if (!bCounterSet || CounterText != Model.Counter)
		{
			SetBlockText(Counter, Model.Counter);
			CounterText = Model.Counter;
			bCounterSet = true;
		}
		if (Opts.bCounter || Model.bCounterAlways)
			Counter.SetVisibility(ESlateVisibility::HitTestInvisible);
		else
			Counter.SetVisibility(ESlateVisibility::Collapsed);
		Message.SetVisibility(ESlateVisibility::Collapsed);
		Body().SetVisibility(ESlateVisibility::HitTestInvisible);

		if (Tape != nullptr)
		{
			for (int At = 0; At < Cells.Num(); At++)
			{
				if (At < Model.Cells.Num())
				{
					FLPH_Cell Cell = Model.Cells[At];
					SetToken(Cells[At], Cell.Text, Cell.Role, Cell.Alpha, Cell.bHasKey, Cell.Key, 0);
				}
				else
				{
					SetToken(Cells[At], "", ELPH_Role::Empty, 0.0, false, ELPH_Key::W, 0);
				}
			}
			return;
		}

		int LineCount = Math::Min(Model.Lines.Num(), Opts.MaxLines);
		for (int R = 0; R < LineCount; R++)
		{
			ULPH_HintRow Row = RowOf(R);
			Row.Box.SetVisibility(ESlateVisibility::HitTestInvisible);
			int TokenCount = Math::Min(Model.Lines[R].Tokens.Num(), Opts.PerLine);
			for (int C = 0; C < TokenCount; C++)
			{
				FLPH_Token Item = Model.Lines[R].Tokens[C];
				SetToken(TokenOf(Row, C), Item.Text, Item.Role, 1.0, true, Item.Key, Item.Count);
			}
			for (int C = TokenCount; C < Row.Tokens.Num(); C++)
				SetToken(Row.Tokens[C], "", ELPH_Role::Empty, 0.0, false, ELPH_Key::W, 0);
		}
		for (int R = LineCount; R < Rows.Num(); R++)
			Rows[R].Box.SetVisibility(ESlateVisibility::Collapsed);
	}

	// One key of the model. Text empty: nothing here. With an icon set, the key's icon replaces the letter ("×Count"
	// after it for a run) and takes the letter's colour; a texture that did not load leaves the letter.
	private void SetToken(ULPH_HintToken Token, FString Text, ELPH_Role Role, float Alpha, bool bHasKey, ELPH_Key Key, int Count)
	{
		bool bShown = !Text.IsEmpty();
		int Shown = bShown ? 1 : 0;
		if (Token.ShownState != Shown)
		{
			if (bShown)
				Token.Box.SetVisibility(ESlateVisibility::HitTestInvisible);
			else if (Token.bKeepSpace)
				Token.Box.SetVisibility(ESlateVisibility::Hidden);
			else
				Token.Box.SetVisibility(ESlateVisibility::Collapsed);
			Token.ShownState = Shown;
		}
		if (!bShown)
			return;

		FString Path;
		if (bHasKey && IconSet != ELPH_IconSet::Letters)
			Path = LPH::KeyTexture(IconSet, Key);
		UTexture2D Texture = nullptr;
		if (!Path.IsEmpty())
			Texture = Cast<UTexture2D>(LoadAsset(Path, "icon", "the letter"));
		bool bIconic = Texture != nullptr;
		if (bIconic)
			EnsureIconRow(Token);
		int Iconic = bIconic ? 1 : 0;
		if (Token.IconicState != Iconic)
		{
			if (bIconic)
			{
				Token.Letter.SetVisibility(ESlateVisibility::Collapsed);
				Token.IconRow.SetVisibility(ESlateVisibility::HitTestInvisible);
			}
			else
			{
				Token.Letter.SetVisibility(ESlateVisibility::HitTestInvisible);
				if (Token.IconRow != nullptr)
					Token.IconRow.SetVisibility(ESlateVisibility::Collapsed);
			}
			Token.IconicState = Iconic;
		}

		if (bIconic)
		{
			if (Token.BrushPath != Path)
			{
				Token.Icon.SetBrushFromTexture(Texture, false);
				Token.BrushPath = Path;
			}
			FString Tail = "";
			if (Count > 0)
				Tail = f"{LPH::RunSign}{Count}";
			if (!Token.bTailSet || Token.TailText != Tail)
			{
				if (Tail.IsEmpty())
				{
					Token.Tail.SetVisibility(ESlateVisibility::Collapsed);
				}
				else
				{
					SetBlockText(Token.Tail, Tail);
					Token.Tail.SetVisibility(ESlateVisibility::HitTestInvisible);
				}
				Token.TailText = Tail;
				Token.bTailSet = true;
			}
		}
		else if (!Token.bLetterSet || Token.LetterText != Text)
		{
			SetBlockText(Token.Letter, Text);
			Token.LetterText = Text;
			Token.bLetterSet = true;
		}

		FLinearColor Color = ColorOf(Role, Alpha);
		if (!Token.bColorSet || Token.bColorIconic != bIconic || !SameColor(Token.Color, Color))
		{
			if (bIconic)
			{
				Token.Icon.SetColorAndOpacity(Color);
				Token.Tail.SetColorAndOpacity(FSlateColor(Color));
			}
			else
			{
				Token.Letter.SetColorAndOpacity(FSlateColor(Color));
			}
			Token.Color = Color;
			Token.bColorIconic = bIconic;
			Token.bColorSet = true;
		}

		int Framed = Role == ELPH_Role::Current ? 1 : 0;
		if (Token.FramedState != Framed)
		{
			if (Framed == 1)
				Token.Frame.SetVisibility(ESlateVisibility::HitTestInvisible);
			else
				Token.Frame.SetVisibility(ESlateVisibility::Collapsed);
			Token.FramedState = Framed;
		}
	}

	// Pressed keys are green, a miss red (both styles); the current key and the rest take the style's colours. Alpha
	// multiplies the colour's own.
	private FLinearColor ColorOf(ELPH_Role Role, float Alpha) const
	{
		FLinearColor Color = BuiltStyle.Next;
		if (Role == ELPH_Role::Done)
			Color = LPH::ColorDone;
		else if (Role == ELPH_Role::Miss)
			Color = LPH::ColorMiss;
		else if (Role == ELPH_Role::Current)
			Color = BuiltStyle.Current;
		Color.A = Color.A * Alpha;
		return Color;
	}

	private bool SameColor(FLinearColor A, FLinearColor B) const
	{
		return A.R == B.R && A.G == B.G && A.B == B.B && A.A == B.A;
	}

	private void SetBlockText(UTextBlock Block, FString Text)
	{
		Block.SetText(FText::FromString(Text));
		TextSets++;
	}

	// A game asset by its object path, loaded once; a path that did not load is not tried again (one log line).
	private UObject LoadAsset(FString Path, FString What, FString Instead)
	{
		UObject Found = nullptr;
		if (Assets.Find(Path, Found))
			return Found;
		if (Missing.Contains(Path))
			return nullptr;
		Found = LPH::LoadGameAsset(Path);
		if (Found != nullptr)
		{
			Assets.Add(Path, Found);
			return Found;
		}
		Missing.Add(Path);
		Warn(f"{What} not found, using {Instead}: {Path}");
		return nullptr;
	}

	private void Warn(FString Text)
	{
		if (ModLog != nullptr)
			ModLog.Line(Text);
	}
}
