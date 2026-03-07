@tool
@abstract class_name GdssNode
extends Resource

@export var enabled_components: Dictionary[String, bool]
@export var unique_properties: Array[GdssProp]
@export var base_type: StringName
@export var style_name: StringName
@export var is_static: bool = false

@export_storage var states: PackedStringArray
@export_storage var icons: PackedStringArray
@export_storage var font_sizes: PackedStringArray
@export_storage var fonts: PackedStringArray
@export_storage var constants: PackedStringArray
@export_storage var colors: PackedStringArray
@export_storage var theme_defaults: Dictionary[String, Variant]

var _props_cache: Array[GdssProp] = []
var _props_dirty: bool = true


@abstract func get_events() -> PackedStringArray
@abstract func get_active_state(canvas_item: CanvasItem) -> String


func invalidate_props_cache() -> void:
	_props_dirty = true
	_props_cache.clear()


func get_default_events() -> PackedStringArray:
	return ["item_rect_changed", "visibility_changed"]


func bind_canvas_item(canvas_item: CanvasItem) -> void:
	var events: PackedStringArray = get_events()
	events.append_array(get_default_events())
	for event: String in events:
		if not canvas_item.is_connected(event, _update_state):
			canvas_item.connect(event, _update_state, CONNECT_APPEND_SOURCE_OBJECT)


func unbind_canvas_item(canvas_item: CanvasItem) -> void:
	var events: PackedStringArray = get_events()
	events.append_array(get_default_events())
	for event: String in events:
		if canvas_item.is_connected(event, _update_state):
			canvas_item.disconnect(event, _update_state)


func get_enabled_props() -> Array[GdssProp]:
	if not _props_dirty:
		return _props_cache
	
	var props: Array[GdssProp]
	var db: GdssDB = GDSS.get_db()
	var overrides: Dictionary[String, GdssProp] = db.property_list
	
	for component_name: String in enabled_components:
		if enabled_components.get(component_name) == false:
			continue
		if db.component_list.has(component_name):
			props.append_array(db.component_list.get(component_name).properties)
	
	props.append_array(unique_properties)
	
	for item_name: String in constants:
		if overrides.has(item_name):
			props.append(overrides[item_name])
		elif db.boolean_overrides.has(item_name):
			props.append(GdssProp.create(item_name, GDSS.Type.BOOLEAN, db.boolean_overrides[item_name], GdssProp.Category.CONST))
		else:
			props.append(GdssProp.create(item_name, GDSS.Type.INT, theme_defaults.get(item_name, 0), GdssProp.Category.CONST))
	
	for item_name: String in font_sizes:
		props.append(overrides.get(item_name, GdssProp.create(item_name, GDSS.Type.INT, theme_defaults.get(item_name, 0), GdssProp.Category.FONT_SIZE)))
	
	for item_name: String in fonts:
		props.append(overrides.get(item_name, GdssProp.create(item_name, GDSS.Type.FONT, theme_defaults.get(item_name, null), GdssProp.Category.FONT)))
	
	for item_name: String in icons:
		props.append(overrides.get(item_name, GdssProp.create(item_name, GDSS.Type.ICON, theme_defaults.get(item_name, null), GdssProp.Category.ICON)))
	
	var grouped_colors: Dictionary = {}
	for override_prop: GdssProp in overrides.values():
		for subprop: String in override_prop.category_subproperties:
			grouped_colors[subprop] = true
	
	for override_prop: GdssProp in overrides.values():
		if override_prop.category_subproperties.is_empty():
			continue
		var any_match: bool = false
		for subprop_name: String in override_prop.category_subproperties:
			if colors.has(subprop_name):
				any_match = true
				break
		if any_match:
			props.append(override_prop)
	
	for item_name: String in colors:
		if overrides.has(item_name):
			props.append(overrides[item_name])
		elif not grouped_colors.has(item_name):
			props.append(GdssProp.create(item_name, GDSS.Type.COLOR, theme_defaults.get(item_name, Color.TRANSPARENT), GdssProp.Category.COLOR))
	
	_props_cache = props
	_props_dirty = false
	return _props_cache


func _update_state(...a: Array) -> void:
	update_state(a.get(a.size() - 1))


func update_state(canvas_item: CanvasItem) -> void:
	if not canvas_item:
		return
	if is_static:
		for state: String in states:
			var meta_key: StringName = "gdss_handler_" + state
			if not canvas_item.has_meta(meta_key):
				continue
			var box: GdssPropHandler = canvas_item.get_meta(meta_key) as GdssPropHandler
			box._apply_overrides()
			box.emit_changed()
			if canvas_item is CanvasItem:
				canvas_item.queue_redraw()
		return
	var state: String = get_active_state(canvas_item)
	if not canvas_item.has_meta("gdss_handler"):
		return
	var box: GdssPropHandler = canvas_item.get_meta("gdss_handler") as GdssPropHandler
	box.current_state = state
