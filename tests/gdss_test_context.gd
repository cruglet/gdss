extends RefCounted


var tree: SceneTree
var holder: Control
var passed: int = 0
var failed: int = 0
var _current_file: String = ""


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	holder = Control.new()
	holder.name = "GdssTestHolder"
	holder.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)
	holder.position = Vector2(4000, 4000)
	tree.root.add_child(holder)
	tree.root.warp_mouse(Vector2(-4000, -4000))


func canary() -> bool:
	if GDSS._runtime == null:
		printerr("canary: GDSS._runtime is null")
		return false
	if GDSS._get_gdss_nodes().is_empty():
		printerr("canary: node registry is empty")
		return false
	var ci: RID = RenderingServer.canvas_item_create()
	var ci_ok: bool = ci.is_valid()
	RenderingServer.free_rid(ci)
	if not ci_ok:
		printerr("canary: canvas_item RIDs unavailable")
		return false
	return true


func begin_file(name: String) -> void:
	_current_file = name
	print("--- %s" % name)


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS %s" % label)
	else:
		failed += 1
		print("FAIL %s  [%s]" % [label, _current_file])


func check_eq(actual: Variant, expected: Variant, label: String) -> void:
	var equal: bool = typeof(actual) == typeof(expected) and actual == expected
	if not equal and actual is float and expected is float:
		equal = is_equal_approx(actual, expected)
	if equal:
		passed += 1
		print("PASS %s" % label)
	else:
		failed += 1
		print("FAIL %s  expected %s, got %s  [%s]" % [label, str(expected), str(actual), _current_file])


func await_frames(count: int) -> void:
	for i: int in count:
		await tree.process_frame


func await_seconds(seconds: float) -> void:
	await tree.create_timer(seconds).timeout


func make_styled_button(text: String = "btn") -> Button:
	var button: Button = Button.new()
	button.text = text
	holder.add_child(button)
	return button


func add_styled(node: Node) -> Node:
	holder.add_child(node)
	return node


func free_children() -> void:
	for child: Node in holder.get_children():
		child.free()


func parse_fixture(source: String) -> Dictionary:
	return GdssInterpreter.interpret_all(PackedStringArray([source]))


func validate_fixture(source: String) -> Array[Array]:
	var interp: GdssInterpreter = GdssInterpreter.new()
	var errors: Array[Array] = interp.check_errors(source)
	interp.free()
	return errors


func error_messages(errors: Array[Array]) -> PackedStringArray:
	var result: PackedStringArray = []
	for entry: Array in errors:
		result.append(str(entry.front()))
	return result


func has_error_containing(errors: Array[Array], needle: String) -> bool:
	for message: String in error_messages(errors):
		if message.contains(needle):
			return true
	return false


func apply_fixture(source: String) -> void:
	_interpret_into_parsed(PackedStringArray([source]))


func restore_theme() -> void:
	_interpret_into_parsed(GdssStorage.load_sources())


func entry_val(result: Dictionary, selector: String, state: String, prop: String) -> Variant:
	var entry: Variant = result.get(selector)
	if not entry is Dictionary:
		return null
	var state_dict: Variant = (entry as Dictionary).get(state)
	if not state_dict is Dictionary:
		return null
	return (state_dict as Dictionary).get(prop)


func class_entry(result: Dictionary, selector: String, gdss_class: String) -> Dictionary:
	var entry: Variant = result.get(selector)
	if not entry is Dictionary:
		return {}
	var classes: Variant = (entry as Dictionary).get("_classes")
	if not classes is Dictionary:
		return {}
	var found: Variant = (classes as Dictionary).get(gdss_class)
	return found if found is Dictionary else {}


func _interpret_into_parsed(sources: PackedStringArray) -> void:
	var result: Dictionary = GdssInterpreter.interpret_all(sources)
	GdssInterpreter.parsed.clear()
	for key: String in result:
		GdssInterpreter.parsed[key] = result[key]
	if GDSS._runtime != null:
		GDSS._runtime._refresh_all_handlers()
