// The mod's own layer in the game's viewport: a widget the size of the screen whose root is an empty canvas, drawn above
// the game's interface and never taking the mouse or the keys. The hint lives inside the minigame's window; this layer is
// for what the mod shows elsewhere (the notes of F3 and F4 outside a minigame, the preview): a ULPH_HintWidget attaches
// to it with Attach(Layer, Layer.LayerCanvas). One layer is made per world (ULPH_NoteLayer, Hotkeys.as) and the engine
// takes it out of the viewport together with the world, so the layer and the hint on it die together: nothing is
// released when a save loads. (Release(), not a plain Detach(), is for a canvas the mod owns that survives a load - R14;
// there is none today.)

class ULPH_ViewportLayer : UUserWidget
{
	UPROPERTY()
	UCanvasPanel LayerCanvas;

	// Adds the layer to the viewport if it is not there.
	void Show()
	{
		if (!IsInViewport())
			AddToViewport(LPH::LayerZOrder);
	}
}

namespace LPH
{
	const int LayerZOrder = 1000; // above the game's interface (the hint's own ZOrder is the one inside the layer)

	// A new layer of the player's, with its canvas, in the viewport; null when it could not be made.
	ULPH_ViewportLayer NewViewportLayer(APlayerController Player)
	{
		if (Player == nullptr)
			return nullptr;
		ULPH_ViewportLayer Layer = Cast<ULPH_ViewportLayer>(WidgetBlueprint::CreateWidget(ULPH_ViewportLayer::StaticClass(), Player));
		if (Layer == nullptr)
			return nullptr;
		UCanvasPanel Root = Cast<UCanvasPanel>(Layer.ConstructWidget(UCanvasPanel));
		if (Root == nullptr)
			return nullptr;
		Layer.SetRootWidget(Root);
		Layer.LayerCanvas = Root;
		Layer.SetVisibility(ESlateVisibility::HitTestInvisible);
		Layer.Show();
		return Layer;
	}
}
