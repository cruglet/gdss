extends Control

const DARK: Dictionary = {
	"bg": Color("0d0d14"),
	"surface": Color("16161f"),
	"surface_2": Color("1f1f3a"),
	"text": Color("ffffff"),
	"text_dim": Color("9097ad"),
	"border": Color("ffffff22"),
}
const LIGHT: Dictionary = {
	"bg": Color("eceef5"),
	"surface": Color("ffffff"),
	"surface_2": Color("dfe3ee"),
	"text": Color("161622"),
	"text_dim": Color("6a7088"),
	"border": Color("00000018"),
}

var _dark: bool = true
var _toggle: Button


func _ready() -> void:
	_apply_palette(DARK, false)
	_build()


func _build() -> void:
	var background: PanelContainer = _styled(PanelContainer.new())
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin: MarginContainer = _with_margin(MarginContainer.new(), 24)
	background.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = _styled(Label.new(), PackedStringArray(["TitleLabel"]))
	title.text = "GDSS Stress Test"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_toggle = _styled(Button.new())
	_toggle.text = "Switch to light"
	_toggle.pressed.connect(_toggle_mode)
	header.add_child(_toggle)

	var subtitle: Label = _styled(Label.new(), PackedStringArray(["SubtitleLabel"]))
	subtitle.text = "Toggling the theme tweens a shared palette across every styled node."
	column.add_child(subtitle)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	for index: int in 20:
		grid.add_child(_make_card(index))


func _make_card(index: int) -> Control:
	var card: PanelContainer = _styled(PanelContainer.new(), PackedStringArray(["CardPanel"]))
	card.custom_minimum_size = Vector2(230, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner_margin: MarginContainer = _with_margin(MarginContainer.new(), 14)
	card.add_child(inner_margin)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	inner_margin.add_child(body)

	var heading: Label = _styled(Label.new(), PackedStringArray(["TitleLabel"]))
	heading.text = "Card %d" % (index + 1)
	heading.add_theme_font_size_override("font_size", 18)
	body.add_child(heading)
	var caption: Label = _styled(Label.new(), PackedStringArray(["SubtitleLabel"]))
	caption.text = "Buttons, inputs and a card surface, all GDSS-styled."
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(caption)
	var field: LineEdit = _styled(LineEdit.new())
	field.placeholder_text = "Type something…"
	body.add_child(field)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	var primary: Button = _styled(Button.new())
	primary.text = "Action"
	primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(primary)
	var ghost: Button = _styled(Button.new(), PackedStringArray(["GhostButton"]))
	ghost.text = "Ghost"
	actions.add_child(ghost)
	if index % 4 == 0:
		var pill: Button = _styled(Button.new(), PackedStringArray(["PillButton"]))
		pill.text = "Pill action"
		body.add_child(pill)
	if index % 5 == 0:
		var disabled: Button = _styled(Button.new())
		disabled.text = "Disabled"
		disabled.disabled = true
		body.add_child(disabled)
	return card


func _styled(node: Control, classes: PackedStringArray = []) -> Control:
	node.add_to_group("gdss")
	if not classes.is_empty():
		node.set_meta("gdss_classes", classes)
	return node


func _with_margin(container: MarginContainer, amount: int) -> MarginContainer:
	for side: String in ["left", "top", "right", "bottom"]:
		container.add_theme_constant_override("margin_" + side, amount)
	return container


func _toggle_mode() -> void:
	_dark = not _dark
	_toggle.text = "Switch to light" if _dark else "Switch to dark"
	_apply_palette(DARK if _dark else LIGHT, true)


func _apply_palette(palette: Dictionary, animate: bool) -> void:
	if not animate:
		for key: String in palette:
			GDSS.set_global_var(key, palette[key])
		return
	var tween: Tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	for key: String in palette:
		var from: Color = GDSS.get_global_var(key, palette[key])
		var to: Color = palette[key]
		tween.tween_method(func(c: Color) -> void:
			GDSS.set_global_var(key, c)
		, from, to, 0.25)
