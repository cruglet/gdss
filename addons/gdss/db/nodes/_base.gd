@tool
@abstract class_name GdssNode
extends Resource

@export var enabled_components: Dictionary[String, bool]
@export var unique_properties: Array[GdssProp]
@export var base_type: StringName
@export var style_name: StringName
@export var is_static: bool = false

var states: PackedStringArray:
	get:
		_ensure_theme()
		return _states
	set(_v):
		pass
var icons: PackedStringArray:
	get:
		_ensure_theme()
		return _icons
	set(_v):
		pass
var font_sizes: PackedStringArray:
	get:
		_ensure_theme()
		return _font_sizes
	set(_v):
		pass
var fonts: PackedStringArray:
	get:
		_ensure_theme()
		return _fonts
	set(_v):
		pass
var constants: PackedStringArray:
	get:
		_ensure_theme()
		return _constants
	set(_v):
		pass
var colors: PackedStringArray:
	get:
		_ensure_theme()
		return _colors
	set(_v):
		pass
var theme_defaults: Dictionary[String, Variant]:
	get:
		_ensure_theme()
		return _theme_defaults
	set(_v):
		pass

var _states: PackedStringArray
var _icons: PackedStringArray
var _font_sizes: PackedStringArray
var _fonts: PackedStringArray
var _constants: PackedStringArray
var _colors: PackedStringArray
var _theme_defaults: Dictionary[String, Variant]
var _theme_dirty: bool = true

var _props_cache: Array[GdssProp] = []
var _props_dirty: bool = true

var _style_props_cache: Array[GdssProp] = []
var _style_props_dirty: bool = true

var _props_by_name_cache: Dictionary[String, GdssProp] = {}
var _props_by_name_dirty: bool = true

const _NON_STORED: PackedStringArray = [
	"states", "icons", "font_sizes", "fonts", "constants", "colors", "theme_defaults",
	"_states", "_icons", "_font_sizes", "_fonts", "_constants", "_colors", "_theme_defaults",
	"_theme_dirty", "_props_cache", "_props_dirty", "_style_props_cache", "_style_props_dirty",
	"_props_by_name_cache", "_props_by_name_dirty",
]


func _validate_property(property: Dictionary) -> void:
	if _NON_STORED.has(property.get("name")):
		property["usage"] = property.get("usage", 0) & ~PROPERTY_USAGE_STORAGE


@abstract func get_events() -> PackedStringArray
@abstract func get_active_state(canvas_item: CanvasItem) -> String


func get_extra_states() -> PackedStringArray:
	return []


# If non-empty, GDSS binds ONLY these stylebox slots (replacing the theme's full
# stylebox list). Used by Window-derived nodes to target just their background.
func get_only_states() -> PackedStringArray:
	return []


func _ensure_theme() -> void:
	if not _theme_dirty:
		return
	var theme: Theme = ThemeDB.get_default_theme()
	var type: StringName = base_type
	# get_only_states() lets Window-derived nodes (PopupMenu, Window) restrict GDSS to
	# their background slot instead of binding every theme stylebox (separator, hover, …).
	var only: PackedStringArray = get_only_states()
	if not only.is_empty():
		_states = only.duplicate()
	else:
		_states = theme.get_stylebox_list(type)
		for extra: String in get_extra_states():
			if not _states.has(extra):
				_states.append(extra)
	_icons = theme.get_icon_list(type)
	_font_sizes = theme.get_font_size_list(type)
	_fonts = theme.get_font_list(type)
	_constants = theme.get_constant_list(type)
	_colors = theme.get_color_list(type)
	_theme_defaults.clear()
	for item_name: String in _constants:
		_theme_defaults[item_name] = theme.get_constant(item_name, type)
	for item_name: String in _colors:
		_theme_defaults[item_name] = theme.get_color(item_name, type)
	for item_name: String in _font_sizes:
		_theme_defaults[item_name] = theme.get_font_size(item_name, type)
	for item_name: String in _icons:
		_theme_defaults[item_name] = theme.get_icon(item_name, type)
	for item_name: String in _fonts:
		_theme_defaults[item_name] = theme.get_font(item_name, type)
	_theme_dirty = false


func invalidate_theme_cache() -> void:
	_theme_dirty = true


func invalidate_props_cache() -> void:
	_props_dirty = true
	_props_cache.clear()
	_style_props_dirty = true
	_style_props_cache.clear()
	_props_by_name_dirty = true
	_props_by_name_cache.clear()


func get_props_by_name() -> Dictionary[String, GdssProp]:
	if not _props_by_name_dirty:
		return _props_by_name_cache
	_props_by_name_cache.clear()
	for prop: GdssProp in get_enabled_props():
		_props_by_name_cache[prop.name] = prop
	_props_by_name_dirty = false
	return _props_by_name_cache


func get_default_events() -> PackedStringArray:
	return ["item_rect_changed", "visibility_changed"]


func bind_canvas_item(canvas_item: Node) -> void:
	var events: PackedStringArray = get_events()
	events.append_array(get_default_events())
	for event: String in events:
		# has_signal guard: Window-derived nodes lack some Control signals (item_rect_changed).
		if not canvas_item.is_connected(event, _update_state):
			canvas_item.connect(event, _update_state, CONNECT_APPEND_SOURCE_OBJECT)


func unbind_canvas_item(canvas_item: Node) -> void:
	var events: PackedStringArray = get_events()
	events.append_array(get_default_events())
	for event: String in events:
		if canvas_item.has_signal(event) and canvas_item.is_connected(event, _update_state):
			canvas_item.disconnect(event, _update_state)


# Godot 4.7 Control offset-transform properties, exposed to GDSS as animatable node
# properties under the shorter "transform_" prefix. _apply_theme_prop maps them back to
# Godot's "offset_transform_*" Control properties. Defaults match Godot's, so a node that
# styles none of them keeps an identity transform. Set transform_enabled: true to activate.
static var _transform_props: Array[GdssProp] = []
static func _get_transform_props() -> Array[GdssProp]:
	if not _transform_props.is_empty():
		return _transform_props
	_transform_props = [
		GdssProp.create("transform_enabled", GDSS.Type.BOOLEAN, false, GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("transform_position", GDSS.Type.VECTOR2, Vector2.ZERO, GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("transform_position_ratio", GDSS.Type.VECTOR2, Vector2.ZERO, GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("transform_scale", GDSS.Type.VECTOR2, Vector2.ONE, GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("transform_rotation", GDSS.Type.FLOAT, 0.0, GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("transform_pivot", GDSS.Type.VECTOR2, Vector2.ZERO, GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("transform_pivot_ratio", GDSS.Type.VECTOR2, Vector2(0.5, 0.5), GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("transform_visual_only", GDSS.Type.BOOLEAN, true, GdssProp.Category.NODE_PROPERTY),
	]
	return _transform_props


static var _visual_props: Array[GdssProp] = []
static func _get_visual_props() -> Array[GdssProp]:
	if not _visual_props.is_empty():
		return _visual_props
	_visual_props = [
		GdssProp.create("modulate", GDSS.Type.COLOR, Color.WHITE, GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("self_modulate", GDSS.Type.COLOR, Color.WHITE, GdssProp.Category.NODE_PROPERTY),
		GdssProp.create("opacity", GDSS.Type.FLOAT, 1.0, GdssProp.Category.NODE_PROPERTY),
	]
	return _visual_props


func get_enabled_props() -> Array[GdssProp]:
	if not _props_dirty:
		return _props_cache
	_ensure_theme()
	var td: Dictionary[String, Variant] = _theme_defaults
	var props: Array[GdssProp] = []
	var db: GdssDB = GDSS.get_db()
	var overrides: Dictionary[String, GdssProp] = db.property_list
	for component_name: String in enabled_components:
		if not enabled_components[component_name]:
			continue
		var component: GdssNodeComponent = db.component_list.get(component_name)
		if component != null:
			props.append_array(component.properties)
	props.append_array(unique_properties)
	if base_type == &"Control" or ClassDB.is_parent_class(base_type, &"Control"):
		props.append_array(_get_transform_props())
		props.append_array(_get_visual_props())
	for item_name: String in _constants:
		if overrides.has(item_name):
			props.append(overrides[item_name])
		elif db.boolean_overrides.has(item_name):
			props.append(GdssProp.create(item_name, GDSS.Type.BOOLEAN, db.boolean_overrides[item_name], GdssProp.Category.CONST))
		else:
			props.append(GdssProp.create(item_name, GDSS.Type.INT, td.get(item_name, 0), GdssProp.Category.CONST))
	for item_name: String in _font_sizes:
		if overrides.has(item_name):
			props.append(overrides[item_name])
		else:
			props.append(GdssProp.create(item_name, GDSS.Type.INT, td.get(item_name, 0), GdssProp.Category.FONT_SIZE))
	for item_name: String in _fonts:
		if overrides.has(item_name):
			props.append(overrides[item_name])
		else:
			props.append(GdssProp.create(item_name, GDSS.Type.FONT, td.get(item_name, null), GdssProp.Category.FONT))
	for item_name: String in _icons:
		if overrides.has(item_name):
			props.append(overrides[item_name])
		else:
			props.append(GdssProp.create(item_name, GDSS.Type.ICON, td.get(item_name, null), GdssProp.Category.ICON))
	var grouped_colors: Dictionary = {}
	var subprop_overrides: Array[GdssProp] = []
	for override_prop: GdssProp in overrides.values():
		if override_prop.category_subproperties.is_empty():
			continue
		var any_match: bool = false
		for subprop_name: String in override_prop.category_subproperties:
			grouped_colors[subprop_name] = true
			if _colors.has(subprop_name):
				any_match = true
		if any_match:
			subprop_overrides.append(override_prop)
	props.append_array(subprop_overrides)
	for item_name: String in _colors:
		if overrides.has(item_name):
			props.append(overrides[item_name])
		elif not grouped_colors.has(item_name):
			props.append(GdssProp.create(item_name, GDSS.Type.COLOR, td.get(item_name, Color.TRANSPARENT), GdssProp.Category.COLOR))
	_props_cache = props
	_props_dirty = false
	return _props_cache


func get_style_props() -> Array[GdssProp]:
	if not _style_props_dirty:
		return _style_props_cache
	_style_props_cache.clear()
	for prop: GdssProp in get_enabled_props():
		if prop.category == GdssProp.Category.STYLE:
			_style_props_cache.append(prop)
	_style_props_dirty = false
	return _style_props_cache


func _update_state(...a: Array) -> void:
	update_state(a.get(a.size() - 1))


func update_state(canvas_item: Node) -> void:
	if not canvas_item:
		return
	if is_static:
		var slots: Dictionary = GdssNodeHandler.get_slots(canvas_item)
		var applied: bool = false
		for state: String in slots:
			var handler: GdssPropHandler = slots[state]
			if handler != null:
				handler._apply_overrides(false)
				handler.emit_changed()
				applied = true
		if applied and canvas_item is CanvasItem:
			(canvas_item as CanvasItem).queue_redraw()
		return
	if not canvas_item is CanvasItem:
		return
	var handler: GdssPropHandler = GdssNodeHandler.get_handler(canvas_item)
	if handler != null:
		handler.current_state = get_active_state(canvas_item as CanvasItem)
