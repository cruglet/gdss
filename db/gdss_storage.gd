@tool
class_name GdssStorage
extends RefCounted

const DEFAULT_PATH: String = "res://gdss_data.gdss"


static func get_save_path() -> String:
	if ProjectSettings.has_setting("gdss/storage/save_path"):
		return ProjectSettings.get_setting("gdss/storage/save_path")
	return DEFAULT_PATH


static func save(source: String, parsed: Dictionary) -> void:
	var data: Dictionary = {"source": source, "parsed": parsed}
	var bytes: PackedByteArray = var_to_bytes_with_objects(data)
	var file: FileAccess = FileAccess.open(get_save_path(), FileAccess.WRITE)
	if file == null:
		push_error("[GDSS] Could not write to: %s" % get_save_path())
		return
	file.store_var(bytes)
	file.close()
	#print("[GDSS] Saved to: %s (source len: %d, parsed keys: %s)" % [get_save_path(), source.length(), str(parsed.keys())])


static func load_data() -> Dictionary:
	var path: String = get_save_path()
	#print("[GDSS] Loading from: %s, exists: %s" % [path, str(FileAccess.file_exists(path))])
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[GDSS] Could not read from: %s" % path)
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
