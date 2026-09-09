@tool
class_name GdssRegistry
extends Resource

const _WINDOW_PANEL_NODE: GDScript = preload("res://addons/gdss/registry/node_types/window_panel.gd")

@export_group("Lists")
@export var node_list: Dictionary[String, GdssNodeType]
@export var property_list: Dictionary[String, GdssProp]
@export var method_list: Dictionary[String, GdssMethod]
@export var component_list: Dictionary[String, GdssComponent]
@export var boolean_overrides: Dictionary[String, bool]


func repopulate() -> void:
	build_code()
	for node: GdssNodeType in node_list.values():
		node.invalidate_props_cache()


func build_code() -> void:
	node_list.clear()
	property_list.clear()
	method_list.clear()
	component_list.clear()
	_build_properties_code()
	_build_components_code()
	_build_methods_code()
	_build_nodes_code()
	boolean_overrides = {"align_to_largest_stylebox": true}


func _make_prop(n: String, t: GDSS.Type, d: Variant, c: GdssProp.Category, comp: PackedStringArray = PackedStringArray(), sub: PackedStringArray = PackedStringArray()) -> void:
	var p: GdssProp = GdssProp.new()
	p.name = n
	p.type = t
	p.default_value = d
	p.category = c
	if not comp.is_empty():
		p.composite_of = comp # set after type so it overrides the auto _left/_right pattern
	p.category_subproperties = sub
	property_list.set(n, p)


func _build_properties_code() -> void:
	_make_prop("anti_aliasing", GDSS.Type.BOOLEAN, true, GdssProp.Category.STYLE)
	_make_prop("bg_color", GDSS.Type.COLOR, Color(0, 0, 0, 0), GdssProp.Category.STYLE)
	_make_prop("border", GDSS.Type.COMPOSITE4, Vector4i.ZERO, GdssProp.Category.STYLE, PackedStringArray(["border_left", "border_right", "border_top", "border_bottom"]))
	_make_prop("border_color", GDSS.Type.COLOR, Color(0, 0, 0, 0), GdssProp.Category.STYLE, PackedStringArray(["border_color_left", "border_color_right", "border_color_top", "border_color_bottom"]))
	_make_prop("corner_detail", GDSS.Type.INT, 8, GdssProp.Category.STYLE)
	_make_prop("corner_radius", GDSS.Type.COMPOSITE4, Vector4i.ZERO, GdssProp.Category.STYLE, PackedStringArray(["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]))
	_make_prop("cursor", GDSS.Type.CURSOR, 0, GdssProp.Category.NODE_PROPERTY)
	_make_prop("expand", GDSS.Type.COMPOSITE4, Vector4i.ZERO, GdssProp.Category.STYLE, PackedStringArray(["expand_left", "expand_right", "expand_top", "expand_bottom"]))
	_make_prop("font_color", GDSS.Type.COLOR, Color(1, 1, 1, 1), GdssProp.Category.COLOR, PackedStringArray(), PackedStringArray(["font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_uneditable_color", "font_selected_color", "font_readonly_color", "font_unselected_color", "font_hovered_color", "font_hover_pressed_color", "font_hovered_selected_color"]))
	_make_prop("icon_color", GDSS.Type.COLOR, Color(1, 1, 1, 1), GdssProp.Category.COLOR, PackedStringArray(), PackedStringArray(["icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_disabled_color", "icon_uneditable_color", "icon_selected_color", "icon_readonly_color", "icon_unselected_color", "icon_hovered_color", "icon_hover_pressed_color", "icon_hovered_selected_color", "icon_normal_color"]))
	_make_prop("padding", GDSS.Type.COMPOSITE4, Vector4i.ZERO, GdssProp.Category.STYLE, PackedStringArray(["padding_left", "padding_right", "padding_top", "padding_bottom"]))
	_make_prop("shadow", GDSS.Type.COMPOSITE4, Vector4i.ZERO, GdssProp.Category.STYLE, PackedStringArray(["shadow_left", "shadow_right", "shadow_top", "shadow_bottom"]))
	_make_prop("sfx", GDSS.Type.AUDIO, null, GdssProp.Category.STYLE)
	_make_prop("shadow_color", GDSS.Type.COLOR, Color(0, 0, 0, 1), GdssProp.Category.STYLE)
	_make_prop("skew_x", GDSS.Type.FLOAT, 0.0, GdssProp.Category.STYLE)
	_make_prop("skew_y", GDSS.Type.FLOAT, 0.0, GdssProp.Category.STYLE)
	_make_prop("transform_enabled", GDSS.Type.BOOLEAN, false, GdssProp.Category.NODE_PROPERTY)
	_make_prop("transform_pivot", GDSS.Type.VECTOR2, Vector2.ZERO, GdssProp.Category.NODE_PROPERTY)
	_make_prop("transform_pivot_ratio", GDSS.Type.VECTOR2, Vector2(0.5, 0.5), GdssProp.Category.NODE_PROPERTY)
	_make_prop("transform_position", GDSS.Type.VECTOR2, Vector2.ZERO, GdssProp.Category.NODE_PROPERTY)
	_make_prop("transform_position_ratio", GDSS.Type.VECTOR2, Vector2.ZERO, GdssProp.Category.NODE_PROPERTY)
	_make_prop("transform_rotation", GDSS.Type.FLOAT, 0.0, GdssProp.Category.NODE_PROPERTY)
	_make_prop("transform_scale", GDSS.Type.VECTOR2, Vector2.ONE, GdssProp.Category.NODE_PROPERTY)
	_make_prop("transform_visual_only", GDSS.Type.BOOLEAN, true, GdssProp.Category.NODE_PROPERTY)
	_make_prop("transition_func", GDSS.Type.TRANSITION_FUNC, 0, GdssProp.Category.STYLE)
	_make_prop("transition_time", GDSS.Type.FLOAT, 0.0, GdssProp.Category.STYLE)
	_make_prop("transition_type", GDSS.Type.TRANSITION_TYPE, 1, GdssProp.Category.STYLE)


func _component_props(names: PackedStringArray) -> Array[GdssProp]:
	var arr: Array[GdssProp] = []
	for n: String in names:
		arr.append(property_list.get(n))
	return arr


func _build_components_code() -> void:
	var stylebox: GdssComponent = GdssComponent.new()
	stylebox.component_name = "Stylebox"
	stylebox.default_state = true
	stylebox.properties = _component_props(PackedStringArray(["anti_aliasing", "bg_color", "border", "border_color", "corner_detail", "corner_radius", "cursor", "expand", "font_color", "padding", "shadow", "shadow_color", "skew_x", "skew_y"]))
	component_list.set("Stylebox", stylebox)
	var trans: GdssComponent = GdssComponent.new()
	trans.component_name = "Transitionable"
	trans.default_state = true
	trans.properties = _component_props(PackedStringArray(["transition_time", "transition_func", "transition_type"]))
	component_list.set("Transitionable", trans)
	var audible: GdssComponent = GdssComponent.new()
	audible.component_name = "Audible"
	audible.default_state = true
	audible.properties = _component_props(PackedStringArray(["sfx"]))
	component_list.set("Audible", audible)


func _build_methods_code() -> void:
	var methods: Array[GdssMethod] = [
		GdssMethod_Alpha.new(), GdssMethod_Blur.new(), GdssMethod_Clamp.new(),
		GdssMethod_Complement.new(), GdssMethod_Contrast.new(), GdssMethod_Darken.new(),
		GdssMethod_Desaturate.new(), GdssMethod_Font.new(),
		GdssMethod_Grayscale.new(), GdssMethod_Hsv.new(),
		GdssMethod_HsvShift.new(), GdssMethod_Invert.new(), GdssMethod_Lighten.new(),
		GdssMethod_LinearBlurGradient.new(), GdssMethod_LinearGradient.new(),
		GdssMethod_LiquidBlur.new(), GdssMethod_Mix.new(),
		GdssMethod_RadialGradient.new(), GdssMethod_Rgba.new(), GdssMethod_Saturate.new(), GdssMethod_Sound.new(),
		GdssMethod_Texture.new(),
	]
	for m: GdssMethod in methods:
		method_list.set(m.method_name, m)


func _instantiate_node_class(type: String) -> GdssNodeType:
	match type:
		"Button", "CheckBox", "CheckButton", "ColorPickerButton", "LinkButton", "MenuButton", "OptionButton":
			return GdssNodeType_Button.new()
		"TextEdit", "CodeEdit":
			return GdssNodeType_TextEdit.new()
		"Label":
			return GdssNodeType_Label.new()
		"LineEdit":
			return GdssNodeType_LineEdit.new()
		"ItemList":
			return GdssNodeType_ItemList.new()
		"Panel", "PanelContainer":
			return GdssNodeType_Panel.new()
		"PopupMenu":
			return GdssNodeType_PopupMenu.new()
		"PopupPanel", "AcceptDialog", "ConfirmationDialog", "FileDialog":
			return _WINDOW_PANEL_NODE.new()
		"Window":
			return GdssNodeType_Window.new()
	return GdssNodeType_Fallback.new()


func _node_config(type: String) -> Array:
	match type:
		"Button", "CheckBox", "CheckButton", "ColorPickerButton", "MenuButton", "OptionButton":
			return [false, true, true]
		"LinkButton":
			return [true, true, true]
		"TextEdit":
			return [false, true, true]
		"CodeEdit":
			return [true, true, true]
		"Label":
			return [true, true, true]
		"LineEdit":
			return [false, true, true]
		"ItemList":
			return [true, true, false]
		"TextureRect", "ColorRect":
			return [true, false, true]
		"Panel", "PanelContainer":
			return [false, true, false]
		"PopupMenu", "PopupPanel", "AcceptDialog", "ConfirmationDialog", "FileDialog", "Window":
			return [true, true, false]
	return []


func _build_nodes_code() -> void:
	var theme: Theme = ThemeDB.get_default_theme()
	var types: Dictionary = {}
	for t: String in theme.get_type_list():
		if ClassDB.class_exists(t) and (t == "Control" or ClassDB.is_parent_class(StringName(t), &"Control")):
			types.set(t, true)
	for window_type: String in ["PopupMenu", "Window", "PopupPanel", "AcceptDialog", "ConfirmationDialog", "FileDialog"]:
		types.set(window_type, true)
	types.set("TextureRect", true)
	types.set("ColorRect", true)
	for type: String in types:
		var node: GdssNodeType = _instantiate_node_class(type)
		node.base_type = StringName(type)
		node.style_name = StringName(type)
		match type:
			"ColorRect":
				node.unique_properties.append(GdssProp.create("color", GDSS.Type.COLOR, Color.WHITE, GdssProp.Category.NODE_PROPERTY))
			"TextureRect":
				node.unique_properties.append(GdssProp.create("texture", GDSS.Type.ICON, null, GdssProp.Category.NODE_PROPERTY))
		var ec: Dictionary[String, bool] = {"Audible": true}
		var cfg: Array = _node_config(type)
		if cfg.is_empty():
			node.is_static = true
			ec.set("Stylebox", not theme.get_stylebox_list(type).is_empty())
			ec.set("Transitionable", false)
		else:
			node.is_static = cfg.get(0)
			ec.set("Stylebox", cfg.get(1))
			ec.set("Transitionable", cfg.get(2))
		node.enabled_components = ec
		node.invalidate_theme_cache()
		node.invalidate_props_cache()
		node_list.set(type, node)
