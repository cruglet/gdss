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


static func _connect_states(canvas_item: CanvasItem, gdss_node: GdssNode) -> void:
	_disconnect_states(canvas_item)
	canvas_item.property_list_changed.connect(func() -> void:
		_apply_state.call_deferred(canvas_item)
	)
	#print("CONNECTING: %s" % canvas_item)
	match canvas_item.get_class():
		"Button", "CheckBox", "CheckButton", "MenuButton", "OptionButton":
			var button: Button = canvas_item as Button
			button.mouse_entered.connect(_on_state_changed.bind(canvas_item))
			button.mouse_exited.connect(_on_state_changed.bind(canvas_item))
			button.button_down.connect(_on_state_changed.bind(canvas_item))
			button.button_up.connect(_on_state_changed.bind(canvas_item))
			button.toggled.connect(_on_toggled.bind(canvas_item))
			button.focus_entered.connect(_on_state_changed.bind(canvas_item))
			button.focus_exited.connect(_on_state_changed.bind(canvas_item))
		"LineEdit":
			var line_edit: LineEdit = canvas_item as LineEdit
			line_edit.mouse_entered.connect(_on_state_changed.bind(canvas_item))
			line_edit.mouse_exited.connect(_on_state_changed.bind(canvas_item))
			line_edit.focus_entered.connect(_on_state_changed.bind(canvas_item))
			line_edit.focus_exited.connect(_on_state_changed.bind(canvas_item))
		"PanelContainer", "Panel":
			var control: Control = canvas_item as Control
			control.mouse_entered.connect(_on_state_changed.bind(canvas_item))
			control.mouse_exited.connect(_on_state_changed.bind(canvas_item))


static func _disconnect_states(canvas_item: CanvasItem) -> void:
	if canvas_item.property_list_changed.is_connected(_on_state_changed):
		canvas_item.property_list_changed.disconnect(_on_state_changed)
	match canvas_item.get_class():
		"Button", "CheckBox", "CheckButton", "MenuButton", "OptionButton":
			var button: Button = canvas_item as Button
			if button.mouse_entered.is_connected(_on_state_changed):
				button.mouse_entered.disconnect(_on_state_changed)
			if button.mouse_exited.is_connected(_on_state_changed):
				button.mouse_exited.disconnect(_on_state_changed)
			if button.button_down.is_connected(_on_state_changed):
				button.button_down.disconnect(_on_state_changed)
			if button.button_up.is_connected(_on_state_changed):
				button.button_up.disconnect(_on_state_changed)
			if button.toggled.is_connected(_on_toggled):
				button.toggled.disconnect(_on_toggled)
			if button.focus_entered.is_connected(_on_state_changed):
				button.focus_entered.disconnect(_on_state_changed)
			if button.focus_exited.is_connected(_on_state_changed):
				button.focus_exited.disconnect(_on_state_changed)
		"LineEdit":
			var line_edit: LineEdit = canvas_item as LineEdit
			if line_edit.mouse_entered.is_connected(_on_state_changed):
				line_edit.mouse_entered.disconnect(_on_state_changed)
			if line_edit.mouse_exited.is_connected(_on_state_changed):
				line_edit.mouse_exited.disconnect(_on_state_changed)
			if line_edit.focus_entered.is_connected(_on_state_changed):
				line_edit.focus_entered.disconnect(_on_state_changed)
			if line_edit.focus_exited.is_connected(_on_state_changed):
				line_edit.focus_exited.disconnect(_on_state_changed)
		"PanelContainer", "Panel":
			var control: Control = canvas_item as Control
			if control.mouse_entered.is_connected(_on_state_changed):
				control.mouse_entered.disconnect(_on_state_changed)
			if control.mouse_exited.is_connected(_on_state_changed):
				control.mouse_exited.disconnect(_on_state_changed)


static func _resolve_state(canvas_item: CanvasItem) -> String:
	var gdss_node: GdssNode = GDSS.get_gdss_nodes().get(canvas_item.get_class())
	var default_variant: String = gdss_node.states[0] if gdss_node and not gdss_node.states.is_empty() else "normal"
	var resolved: String = default_variant

	match canvas_item.get_class():
		"Button", "CheckBox", "CheckButton", "MenuButton", "OptionButton":
			var button: Button = canvas_item as Button
			for i: int in gdss_node.states.size():
				var variant: String = gdss_node.states[i]
				match variant:
					"disabled":
						if not button.is_visible_in_tree() or button.disabled:
							resolved = variant
					"normal":
						pass
					"hover":
						if button.is_hovered():
							resolved = variant
					"pressed":
						if button.button_pressed or button.is_pressed():
							resolved = variant
					"focus":
						if button.has_focus():
							resolved = variant

	return resolved


static func _on_state_changed(canvas_item: CanvasItem) -> void:
	_apply_state.call_deferred(canvas_item)


static func _on_toggled(_pressed: bool, canvas_item: CanvasItem) -> void:
	_apply_state.call_deferred(canvas_item)


static func _apply_state(canvas_item: CanvasItem) -> void:
	var state: String = _resolve_state(canvas_item)
	if not canvas_item.has_meta("gdss_handler"):
		return
	var box: GdssPropHandler = canvas_item.get_meta("gdss_handler") as GdssPropHandler
	box.current_state = state
	
