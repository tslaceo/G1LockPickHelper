// How the hint looks: the overlay block of config.lua of 1.2.0, carried over unchanged (placement, sizes, animation, the
// game's fonts and the colours of both styles). The player's choices (style, size, offset) are settings (Values.as).

// The colours of one style of the keys.
struct FLPH_Style
{
	FLinearColor Current; // the letter of the key to press now
	FLinearColor Next; // the letters of the keys after it
	FLinearColor Frame; // the outline of the current key's frame
	FLinearColor Fill; // the inside of that frame
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
	const float CornerRadius = 3.0; // of the key frame and of the plate

	// The game's fonts (an object path and a typeface of it); a font that does not load falls back to the engine font.
	const FString FontSimple = "/Game/UI/Fonts/Boucherie-Block_Font.Boucherie-Block_Font"; // the letters, simple style
	const FString FontSimpleFace = "Default";
	const FString FontGothic = "/Game/UI/Fonts/NotoSerif-Regular_Font.NotoSerif-Regular_Font"; // the letters, gothic style
	const FString FontGothicFace = "Bold";
	const FString FontText = "/Game/UI/Fonts/NotoSerif-Regular_Font.NotoSerif-Regular_Font"; // the counter and messages
	const FString FontTextFace = "Default";

	const FLinearColor ColorDone = FLinearColor(0.43, 0.78, 0.37, 1.0);
	const FLinearColor ColorMiss = FLinearColor(0.92, 0.29, 0.24, 1.0);
	const FLinearColor ColorMessage = FLinearColor(1.0, 0.55, 0.35, 1.0);
	const FLinearColor ColorCounter = FLinearColor(0.84, 0.59, 0.43, 1.0);
	// outline of the dark plate: the gold of the gothic frame
	const FLinearColor ColorPlateFrame = FLinearColor(1.0, 0.78, 0.1, 1.0);

	// simple: the key looks like a key in the game's key binding menu (dark box, beige frame)
	const FLinearColor SimpleCurrent = FLinearColor(0.95, 0.86, 0.78, 1.0);
	const FLinearColor SimpleNext = FLinearColor(0.95, 0.86, 0.78, 1.0);
	const FLinearColor SimpleFrame = FLinearColor(0.91, 0.76, 0.65, 1.0);
	const FLinearColor SimpleFill = FLinearColor(0.07, 0.07, 0.07, 1.0);

	// gothic: a golden letter in a golden frame
	const FLinearColor GothicCurrent = FLinearColor(1.0, 0.78, 0.1, 1.0);
	const FLinearColor GothicNext = FLinearColor(1.0, 1.0, 1.0, 1.0);
	const FLinearColor GothicFrame = FLinearColor(1.0, 0.78, 0.1, 1.0);
	const FLinearColor GothicFill = FLinearColor(0.0, 0.0, 0.0, 0.0);

	FLPH_Style StyleOf(bool bGothic)
	{
		FLPH_Style Style;
		if (bGothic)
		{
			Style.Current = GothicCurrent;
			Style.Next = GothicNext;
			Style.Frame = GothicFrame;
			Style.Fill = GothicFill;
		}
		else
		{
			Style.Current = SimpleCurrent;
			Style.Next = SimpleNext;
			Style.Frame = SimpleFrame;
			Style.Fill = SimpleFill;
		}
		return Style;
	}
}
