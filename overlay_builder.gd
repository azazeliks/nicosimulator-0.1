# OverlayBuilder.gd
# The part every full-screen overlay (shop, character select, pause menu) builds the same way:
# a dark backdrop that soaks up clicks, with a centred column on top. Call build() with the
# overlay's own Control and fill the column it returns.
class_name OverlayBuilder
extends RefCounted


# Adds the backdrop and the centred column to `parent` and returns the column (a VBoxContainer)
# for you to add your content to.
#   dim_alpha   how dark the backdrop is (0 = clear, 1 = black)
#   separation  pixels between the things in the column
#   with_panel  true = the column sits on a bordered panel with a 20 px margin (shop, select);
#               false = the column floats directly on the backdrop (pause menu)
static func build(parent: Control, dim_alpha: float, separation: int, with_panel: bool = true) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, dim_alpha)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # Nothing underneath can be clicked
	parent.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	parent.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	if with_panel:
		var panel := PanelContainer.new()
		center.add_child(panel)
		var margin := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 20)
		panel.add_child(margin)
		margin.add_child(box)
	else:
		center.add_child(box)
	return box
