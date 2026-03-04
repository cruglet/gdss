@tool
@abstract class_name GdssNode
extends Resource

@export var states: PackedStringArray
@export var enabled_components: Dictionary[String, bool]
@export var unique_properties: Array[GdssProp]
@export var unique_icons: PackedStringArray
@export var base_type: StringName
@export var style_name: StringName
@export var is_static: bool = false

@abstract func get_events() -> PackedStringArray
@abstract func get_active_state(canvas_item: CanvasItem) -> String


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
	var props: Array[GdssProp]
	for component_name: String in enabled_components:
		if enabled_components.get(component_name) == false:
			continue
		var list: Dictionary[String, GdssNodeComponent] = GDSS.get_db().component_list
		if list.has(component_name):
			props.append_array(list.get(component_name).properties)
	props.append_array(unique_properties)
	return props


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
