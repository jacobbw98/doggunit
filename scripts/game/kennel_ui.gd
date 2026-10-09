class_name KennelUI
extends RefCounted

const INK := Color("0c1823")
const PANEL := Color("142837")
const CREAM := Color("f5efda")
const MINT := Color("73e7b5")
const GOLD := Color("ffce69")

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 21
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", GOLD)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = MINT if state in ["hover", "pressed"] else PANEL
		box.border_color = GOLD if state == "focus" else MINT.darkened(0.5)
		box.set_border_width_all(2)
		box.set_corner_radius_all(12)
		box.content_margin_left = 26
		box.content_margin_right = 26
		box.content_margin_top = 17
		box.content_margin_bottom = 17
		theme.set_stylebox(state, "Button", box)
	theme.set_constant("separation", "VBoxContainer", 18)
	return theme

static func label(text: String, size: int = 22, color: Color = CREAM) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node

static func button(text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(action)
	return node
