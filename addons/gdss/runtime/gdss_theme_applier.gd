@tool
class_name GdssThemeApplier
extends RefCounted


static func apply(prop: GdssProp, control: Variant, node_type: GdssNodeType, val: Variant, applied: Dictionary, applied_node_props: Dictionary) -> bool:
	match prop.category:
		GdssProp.Category.COLOR:
			if val is Color:
				if prop.category_subproperties.is_empty():
					override_color(control, node_type, prop.name, val, applied)
				else:
					if node_type.colors.has(prop.name):
						override_color(control, node_type, prop.name, val, applied)
					for subprop: String in prop.category_subproperties:
						if node_type.colors.has(subprop):
							override_color(control, node_type, subprop, val, applied)
		GdssProp.Category.CONST:
			if val is int or val is float:
				var theme_def: Variant = node_type.theme_defaults.get(prop.name, null)
				if theme_def is int and int(val) == int(theme_def):
					if applied.has(prop.name):
						control.remove_theme_constant_override(prop.name)
						applied.erase(prop.name)
					return false
				applied.set(prop.name, GdssProp.Category.CONST)
				if control.has_theme_constant_override(prop.name) and control.get_theme_constant(prop.name) == int(val):
					return false
				control.add_theme_constant_override(prop.name, int(val))
		GdssProp.Category.FONT_SIZE:
			if val is int or val is float:
				var theme_def: Variant = node_type.theme_defaults.get(prop.name, null)
				if theme_def is int and int(val) == int(theme_def):
					if applied.has(prop.name):
						control.remove_theme_font_size_override(prop.name)
						applied.erase(prop.name)
					return false
				applied.set(prop.name, GdssProp.Category.FONT_SIZE)
				if control.has_theme_font_size_override(prop.name) and control.get_theme_font_size(prop.name) == int(val):
					return false
				control.add_theme_font_size_override(prop.name, int(val))
		GdssProp.Category.FONT:
			if val is Font:
				var theme_def: Variant = node_type.theme_defaults.get(prop.name, null)
				if theme_def is Font and val == theme_def:
					return false
				applied.set(prop.name, GdssProp.Category.FONT)
				if control.has_theme_font_override(prop.name) and control.get_theme_font(prop.name) == val:
					return false
				control.add_theme_font_override(prop.name, val as Font)
		GdssProp.Category.ICON:
			if val is Texture2D:
				applied.set(prop.name, GdssProp.Category.ICON)
				if control.has_theme_icon_override(prop.name) and control.get_theme_icon(prop.name) == val:
					return false
				control.add_theme_icon_override(prop.name, val)
		GdssProp.Category.NODE_PROPERTY:
			if not GDSS.transforms_enabled and prop.name.begins_with("transform_"):
				val = prop.get_default_value()
			if prop.type == GDSS.Type.VECTOR2 and (val is int or val is float):
				val = Vector2(float(val), float(val))
			var def: Variant = prop.get_default_value()
			if not (typeof(val) == typeof(def) and val == def):
				applied_node_props.set(prop.name, true)
			if prop.type == GDSS.Type.CURSOR:
				control.set("mouse_default_cursor_shape", cursor_shape(str(val)))
				return false
			if prop.name == "char_skew" or prop.name == "char_embolden":
				return true
			if prop.name == "opacity":
				var mod: Color = control.modulate
				var alpha: float = float(val)
				if not is_equal_approx(mod.a, alpha):
					mod.a = alpha
					control.modulate = mod
				return false
			var node_prop: String = "offset_" + prop.name if prop.name.begins_with("transform_") else prop.name
			var current: Variant = control.get(node_prop)
			if typeof(current) != typeof(val) or current != val:
				control.set(node_prop, val)
	return false


static func override_color(control: Variant, node_type: GdssNodeType, key: String, val: Color, applied: Dictionary) -> void:
	var theme_def: Variant = node_type.theme_defaults.get(key, null)
	if theme_def is Color and val.is_equal_approx(theme_def as Color):
		if applied.has(key):
			control.remove_theme_color_override(key)
			applied.erase(key)
		return
	applied.set(key, GdssProp.Category.COLOR)
	if control.has_theme_color_override(key) and control.get_theme_color(key).is_equal_approx(val):
		return
	control.add_theme_color_override(key, val)


static func remove_overrides(control: Variant, applied: Dictionary) -> void:
	for key: String in applied.keys():
		match int(applied.get(key)):
			GdssProp.Category.COLOR:
				control.remove_theme_color_override(key)
			GdssProp.Category.CONST:
				control.remove_theme_constant_override(key)
			GdssProp.Category.FONT_SIZE:
				control.remove_theme_font_size_override(key)
			GdssProp.Category.FONT:
				control.remove_theme_font_override(key)
			GdssProp.Category.ICON:
				control.remove_theme_icon_override(key)
	applied.clear()


static func apply_font_transform(control: Variant, node_type: GdssNodeType, skew: Vector2, embolden: float) -> void:
	if control == null or node_type == null:
		return
	var neutral: bool = is_zero_approx(skew.x) and is_zero_approx(skew.y) and is_zero_approx(embolden)
	for item: String in node_type.fonts:
		var current: Font = control.get_theme_font(item)
		var marked: bool = current is FontVariation and (current as FontVariation).has_meta(&"gdss_font_transform")
		if neutral:
			if marked and control.has_theme_font_override(item):
				control.remove_theme_font_override(item)
			continue
		var xform: Transform2D = Transform2D(Vector2(1.0, skew.y), Vector2(skew.x, 1.0), Vector2.ZERO)
		if marked and (current as FontVariation).variation_transform == xform \
			and is_equal_approx((current as FontVariation).variation_embolden, embolden):
			continue
		var variation: FontVariation = FontVariation.new()
		variation.base_font = (current as FontVariation).base_font if marked else current
		variation.variation_transform = xform
		variation.variation_embolden = embolden
		variation.set_meta(&"gdss_font_transform", true)
		control.add_theme_font_override(item, variation)


static func cursor_shape(type: String) -> Control.CursorShape:
	match type:
		"ARROW": return Control.CursorShape.CURSOR_ARROW
		"IBEAM": return Control.CursorShape.CURSOR_IBEAM
		"POINTING": return Control.CursorShape.CURSOR_POINTING_HAND
		"CROSS": return Control.CursorShape.CURSOR_CROSS
		"WAIT": return Control.CursorShape.CURSOR_WAIT
		"BUSY": return Control.CursorShape.CURSOR_BUSY
		"DRAG": return Control.CursorShape.CURSOR_DRAG
		"CAN_DROP": return Control.CursorShape.CURSOR_CAN_DROP
		"FORBIDDEN", "DISABLED": return Control.CursorShape.CURSOR_FORBIDDEN
		"VSIZE": return Control.CursorShape.CURSOR_VSIZE
		"HSIZE": return Control.CursorShape.CURSOR_HSIZE
		"BDIAGSIZE": return Control.CursorShape.CURSOR_BDIAGSIZE
		"FDIAGSIZE": return Control.CursorShape.CURSOR_FDIAGSIZE
		"MOVE": return Control.CursorShape.CURSOR_MOVE
		"VSPLIT": return Control.CursorShape.CURSOR_VSPLIT
		"HSPLIT": return Control.CursorShape.CURSOR_HSPLIT
		"HELP": return Control.CursorShape.CURSOR_HELP
	return Control.CursorShape.CURSOR_ARROW
