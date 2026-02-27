@tool
class_name GdssStorage
extends RefCounted


static func get_save_path() -> String:
	return ProjectSettings.get_setting("gdss/storage/save_path", "res://theme.gdss")


static func save(source: String, parsed: Dictionary, path: String = "") -> void:
	var target: String = path if not path.is_empty() else get_save_path()
	var data: Dictionary = {"source": source, "parsed": parsed}
	var bytes: PackedByteArray = var_to_bytes_with_objects(data)
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("[GDSS] Could not write to: %s" % target)
		return
	file.store_var(bytes)
	file.close()
	#print("[GDSS] Saved to: %s (source len: %d, parsed keys: %s)" % [get_save_path(), source.length(), str(parsed.keys())])


static func load_data(path: String = "") -> Dictionary:
	var target: String = path if not path.is_empty() else get_save_path()
	#print("[GDSS] Loading from: %s, exists: %s" % [path, str(FileAccess.file_exists(path))])
	if not FileAccess.file_exists(target):
		return {}
	var file: FileAccess = FileAccess.open(target, FileAccess.READ)
	if file == null:
		push_error("[GDSS] Could not read from: %s" % target)
		return {}
	var raw: Variant = file.get_var()
	file.close()
	if not raw is PackedByteArray:
		return {}
	var data: Variant = bytes_to_var_with_objects(raw as PackedByteArray)
	#print("[GDSS] Loaded data keys: %s" % str(data.keys()))
	#print("[GDSS] parsed keys from file: %s" % str((data.get("parsed", {}) as Dictionary).keys()))
	if data is Dictionary:
		return data
	return {}
