@tool
class_name GdssStorage
extends RefCounted


static func get_save_path() -> String:
	return ProjectSettings.get_setting("gdss/storage/save_path", "res://theme.tgdss")


static func get_cache_path() -> String:
	return ProjectSettings.get_setting("gdss/storage/parsed_cache_path", "user://gdss_cache.gdssc")


static func _is_text_format(path: String) -> bool:
	return path.get_extension() == "tgdss"


static func save(source: String, parsed: Dictionary, global_defaults: Dictionary = {}, instance_defaults: Dictionary = {}, local_vars: Dictionary = {}, path: String = "") -> void:
	var target: String = path if not path.is_empty() else get_save_path()

	if _is_text_format(target):
		var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			printerr("[GDSS] Failed to open file for writing: ", target)
			return
		file.store_string(source)
		file.close()
	else:
		var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			printerr("[GDSS] Failed to open file for writing: ", target)
			return
		file.store_string(source)
		file.close()

	var cache: Dictionary = {
		"parsed": parsed,
		"global_defaults": global_defaults,
		"instance_defaults": instance_defaults,
		"local_vars": local_vars,
	}
	var cache_file: FileAccess = FileAccess.open(get_cache_path(), FileAccess.WRITE)
	if cache_file == null:
		printerr("[GDSS] Failed to open cache file for writing: ", get_cache_path())
		return
	cache_file.store_var(cache)
	cache_file.close()


static func load_data(path: String = "") -> Dictionary:
	var target: String = path if not path.is_empty() else get_save_path()
	if not FileAccess.file_exists(target):
		return {}
	
	var source: String = ""
	var file: FileAccess = FileAccess.open(target, FileAccess.READ)
	if file == null:
		return {}
	source = file.get_as_text()
	file.close()
	
	var result: Dictionary = {"source": source}
	
	if FileAccess.file_exists(get_cache_path()):
		var cache_file: FileAccess = FileAccess.open(get_cache_path(), FileAccess.READ)
		if cache_file != null:
			var cache: Variant = cache_file.get_var()
			cache_file.close()
			if cache is Dictionary:
				for key: String in (cache as Dictionary):
					result[key] = (cache as Dictionary)[key]
	
	return result
