@tool
@abstract class_name GdssNode
extends Resource

@export var states: PackedStringArray
@export var enabled_components: Dictionary[String, bool]
@export var base_type: StringName
@export var style_name: StringName


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
		var list: Dictionary[String, GdssNodeComponent] = GDSS.get_db().component_list
		if list.has(component_name):
			var component: GdssNodeComponent = list.get(component_name)
			props.append_array(component.properties)
	
	return props


func _update_state(...a: Array) -> void:
	update_state(a.get(a.size()-1))


func update_state(canvas_item: CanvasItem) -> void:
	if not canvas_item:
		return
	var state: String = get_active_state(canvas_item)
	if not canvas_item.has_meta("gdss_handler"):
		return
	var box: GdssPropHandler = canvas_item.get_meta("gdss_handler") as GdssPropHandler
	box.current_state = state
