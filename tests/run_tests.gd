extends SceneTree


const TEST_DIR: String = "res://tests/"
const TestContext: GDScript = preload("res://tests/gdss_test_context.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_ensure_runtime()
	await process_frame
	var context: TestContext = TestContext.new(self)
	if not context.canary():
		print("GDSS_TESTS_FAILED  harness canary failed")
		quit(1)
		return
	for path: String in _discover_tests():
		var script: GDScript = load(path) as GDScript
		if script == null:
			context.failed += 1
			print("FAIL could not load %s" % path)
			continue
		var test: RefCounted = script.new()
		context.begin_file(path.get_file())
		await test.run(context)
		context.free_children()
		context.restore_theme()
	await process_frame
	print("")
	if context.failed == 0:
		print("GDSS_TESTS_OK  %d passed" % context.passed)
	else:
		print("GDSS_TESTS_FAILED  %d passed, %d failed" % [context.passed, context.failed])
	quit(0 if context.failed == 0 else 1)


func _ensure_runtime() -> void:
	if GDSS._runtime != null:
		return
	var runtime: Node = (load("res://addons/gdss/runtime.gd") as GDScript).new() as Node
	runtime.name = "GdssRuntime"
	root.add_child(runtime)


func _discover_tests() -> PackedStringArray:
	var result: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(TEST_DIR)
	if dir == null:
		return result
	for file: String in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			result.append(TEST_DIR + file)
	result.sort()
	return result
