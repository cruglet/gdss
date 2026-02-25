@tool
@abstract class_name GdssNode
extends Resource

@export var states: PackedStringArray
@export var theme_properties: Dictionary[String, bool]
@export var base_type: StringName
@export var style_name: StringName

@export_group("Debug")
#@export_tool_button("Print Property Info") var _print_properties: Callable:
	#get:
		#return func() -> void:
			#for prop: GdssProp in theme_properties:
				#print(prop.get_info(), "\n\n")


@abstract func get_events() -> PackedStringArray
@abstract func get_active_state(canvas_item: CanvasItem) -> String


func bind_canvas_item(canvas_item: CanvasItem) -> void:
	for event: String in get_events():
		canvas_item.connect(event, _update_state, CONNECT_APPEND_SOURCE_OBJECT)


func unbind_canvas_item(canvas_item: CanvasItem) -> void:
	for event: String in get_events():
		if canvas_item.is_connected(event, _update_state):
			canvas_item.disconnect(event, _update_state)


func get_enabled_props() -> Array[GdssProp]:
	var props: Array[GdssProp]
	
	for prop: String in theme_properties:
		var enabled: bool = theme_properties.get(prop)
		if enabled:
			props.append(GdssNodeList.PROPERTY_LIST.list.get(prop))
	
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
