@tool
class_name GdssNodeHandler
extends Object


static func bind(canvas_item: CanvasItem) -> void:
	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		printerr("Could not bind %s of type \"%s\"", canvas_item, canvas_item.get_class())
		return
	var box: GdssPropHandler = GdssPropHandler.new()
	box.ref = canvas_item
	for variant: String in gdss_node.states:
		canvas_item.add_theme_stylebox_override(variant, box)
	canvas_item.set_meta("gdss_handler", box)
	gdss_node.bind_canvas_item(canvas_item)


static func unbind(canvas_item: CanvasItem) -> void:
	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		printerr("Could not unbind %s of type \"%s\"", canvas_item, canvas_item.get_class())
		return
	for variant: String in gdss_node.states:
		canvas_item.remove_theme_stylebox_override(variant)
	if canvas_item.has_meta("gdss_handler"):
		canvas_item.remove_meta("gdss_handler")
	gdss_node.unbind_canvas_item(canvas_item)
