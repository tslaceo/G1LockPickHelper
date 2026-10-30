// The mod's own layer in the game's viewport: a widget the size of the screen whose root is an empty canvas, drawn above
// the game's interface and never taking the mouse or the keys. The hint lives inside the minigame's window; this layer is
// for what the mod shows elsewhere (the notes of F3 and F4 outside a minigame, the preview): a ULPH_HintWidget attaches
// to it with Attach(Layer, Layer.LayerCanvas). The engine drops viewport widgets when a level loads; Show() adds the layer
// back, with what its canvas holds. So a hint on the layer outlives a load: Hide() takes it off the screen and Release()
// off the layer - never a plain Detach(), which would leave its plate in the canvas (shown as it was) and make the next
// show add a second one.

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
