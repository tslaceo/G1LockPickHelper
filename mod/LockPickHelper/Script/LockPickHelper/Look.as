// How the hint looks: the overlay block of config.lua of 1.2.0, carried over unchanged (placement, sizes, animation, the
// game's fonts and the colours of both styles). The player's choices (style, size, offset) are settings (Values.as).

// One style of the keys: the colours, and the shape of the current key's frame.
struct FLPH_Style
{
	FLinearColor Current; // the letter of the key to press now
	FLinearColor Next; // the letters of the keys after it
	FLinearColor Frame; // the outline of the current key's frame
	FLinearColor Fill; // the inside of that frame
	float FrameRadius = 3.0; // the corners of that frame, px
	float FrameWidth = 2.0; // its outline, px (not scaled with the hint)
	bool bCurrentShadow = true; // a drop shadow under the letter of that key
}

namespace LPH
{
	// Placement in fractions of the screen, so it works on any aspect ratio (16:9, 21:9 ultrawide): the hint's pivot point
	// (fractions of the hint box) sits at the anchor (fractions of the screen), shifted by the player's OffsetX/OffsetY (UI
	// units; default: 760 left of the right edge - the game draws the lock at a fixed UI distance from that edge on every
	// aspect ratio, checked on 21:9 and 16:9).
	const float AnchorX = 1.0;
	const float AnchorY = 0.45;
	const float PivotX = 1.0;
	const float PivotY = 0.5;
	const int ZOrder = 100;
	const int BaseFontSize = 26; // letter size at scale 100 %
	const float IconScale = 1.15; // a gamepad icon is a square of the letter size times this
	const float PlateAlpha = 0.45; // the dark plate under the hint
	const int SlideMs = 120; // tape slide after a press
	const int ShakeMs = 300; // shake after a miss
	const int ShakePx = 8; // shake amplitude at scale 100 %
	const float PlateRadius = 3.0; // the corners of the dark plate (the key frames have their own, per style)

	// The game's fonts (an object path and a typeface of it); a font that does not load falls back to the engine font.
	const FString FontSimple = "/Game/UI/Fonts/Boucherie-Block_Font.Boucherie-Block_Font"; // the letters, plain style
	const FString FontSimpleFace = "Default";
	const FString FontGothic = "/Game/UI/Fonts/NotoSerif-Regular_Font.NotoSerif-Regular_Font"; // the letters, gold letters
	const FString FontGothicFace = "Bold";
	const FString FontText = "/Game/UI/Fonts/NotoSerif-Regular_Font.NotoSerif-Regular_Font"; // the counter and messages
	const FString FontTextFace = "Default";

	const FLinearColor ColorDone = FLinearColor(0.43, 0.78, 0.37, 1.0);
	const FLinearColor ColorMiss = FLinearColor(0.92, 0.29, 0.24, 1.0);
	const FLinearColor ColorMessage = FLinearColor(1.0, 0.55, 0.35, 1.0);
	const FLinearColor ColorCounter = FLinearColor(0.84, 0.59, 0.43, 1.0);
	// outline of the dark plate: the gold of the gold letters' frame
	const FLinearColor ColorPlateFrame = FLinearColor(1.0, 0.78, 0.1, 1.0);

	// The drop shadow of the letters (the offset is set where a text is made); none is the same colour with no opacity.
	const FLinearColor ColorShadow = FLinearColor(0.0, 0.0, 0.0, 0.9);
	const FLinearColor ColorNoShadow = FLinearColor(0.0, 0.0, 0.0, 0.0);

	// plain (the setting "Gold letters" off): the key copies the minigame's own key prompts (the boxes "A D", "W S",
	// "ESC", "R" of its legend, measured on a 3440x1440 screenshot): a square box, a thin border (about 1 px at 1440p),
	// fill sRGB #131213, border and letter sRGB #FFD7BD (the border reads #DAB7A1 on the picture only because it is
	// anti-aliased), letters without a drop shadow. The colours here are linear (UMG): the sRGB values above converted.
	const FLinearColor SimpleCurrent = FLinearColor(1.0, 0.68, 0.51, 1.0);
	const FLinearColor SimpleNext = FLinearColor(1.0, 0.68, 0.51, 1.0);
	const FLinearColor SimpleFrame = FLinearColor(1.0, 0.68, 0.51, 1.0);
	const FLinearColor SimpleFill = FLinearColor(0.0065, 0.0061, 0.0065, 1.0);
	const float SimpleFrameRadius = 0.0;
	const float SimpleFrameWidth = 1.5;

	// gold letters: a golden letter in a golden frame
	const FLinearColor GothicCurrent = FLinearColor(1.0, 0.78, 0.1, 1.0);
	const FLinearColor GothicNext = FLinearColor(1.0, 1.0, 1.0, 1.0);
	const FLinearColor GothicFrame = FLinearColor(1.0, 0.78, 0.1, 1.0);
	const FLinearColor GothicFill = FLinearColor(0.0, 0.0, 0.0, 0.0);
	const float GothicFrameRadius = 3.0;
	const float GothicFrameWidth = 2.0;

	// The style of the setting "Gold letters" (bGothic: its property in the player's files keeps the old name).
	FLPH_Style StyleOf(bool bGothic)
	{
		FLPH_Style Style;
		if (bGothic)
		{
			Style.Current = GothicCurrent;
			Style.Next = GothicNext;
			Style.Frame = GothicFrame;
			Style.Fill = GothicFill;
			Style.FrameRadius = GothicFrameRadius;
			Style.FrameWidth = GothicFrameWidth;
			Style.bCurrentShadow = true;
		}
		else
		{
			Style.Current = SimpleCurrent;
			Style.Next = SimpleNext;
			Style.Frame = SimpleFrame;
			Style.Fill = SimpleFill;
			Style.FrameRadius = SimpleFrameRadius;
			Style.FrameWidth = SimpleFrameWidth;
			Style.bCurrentShadow = false;
		}
		return Style;
	}
}
