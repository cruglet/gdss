extends SceneTree


const TEST_DIR: String = "res://tests/"
const TestContext: GDScript = preload("res://tests/gdss_test_context.gd")


class ErrorCounter extends Logger:
	var count: int = 0
	var _mutex: Mutex = Mutex.new()
	
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		count += 1
		_mutex.unlock()


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
	var errors: ErrorCounter = ErrorCounter.new()
	OS.add_logger(errors)
	for path: String in _discover_tests():
		var script: GDScript = load(path) as GDScript
		if script == null:
			context.failed += 1
			print("FAIL could not load %s" % path)
			continue
		var test: RefCounted = script.new()
		context.begin_file(path.get_file())
		var errors_before: int = errors.count
		await test.run(context)
		if errors.count > errors_before:
			context.failed += 1
			print("FAIL %d error(s) while running %s" % [errors.count - errors_before, path.get_file()])
		context.free_children()
		context.restore_theme()
	await process_frame
	OS.remove_logger(errors)
	print("")
	if context.failed == 0:
		print("GDSS_TESTS_OK  %d passed" % context.passed)
	else:
		print("GDSS_TESTS_FAILED  %d passed, %d failed" % [context.passed, context.failed])
	quit(0 if context.failed == 0 else 1)


func _ensure_runtime() -> void:
	if GDSS._runtime != null:
		return
	var runtime: Node = (load("res://addons/gdss/runtime/gdss_runtime.gd") as GDScript).new() as Node
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
