extends Button

# Makes a free-floating button draggable with the mouse, clamped so its rect
# stays inside the viewport. Hooked up via the gui_input signal so the button's
# own hover/pressed handling (and GDSS state styling) keeps working.

var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_grab_offset = get_global_mouse_position() - global_position
	elif event is InputEventMouseMotion and _dragging:
		var bounds: Vector2 = get_viewport_rect().size
		var target: Vector2 = get_global_mouse_position() - _grab_offset
		target.x = clampf(target.x, 0.0, maxf(bounds.x - size.x, 0.0))
		target.y = clampf(target.y, 0.0, maxf(bounds.y - size.y, 0.0))
		global_position = target
