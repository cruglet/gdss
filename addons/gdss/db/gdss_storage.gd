@tool
class_name GdssStorage
extends RefCounted


static func get_save_path() -> String:
	return ProjectSettings.get_setting("gdss/storage/save_path", "res://theme.tgdss")


static func get_cache_path() -> String:
	return ProjectSettings.get_setting("gdss/storage/gdss_cache_path", "user://gdss_cache.gdssc")


static func get_save_paths() -> PackedStringArray:
	if ProjectSettings.has_setting("gdss/storage/save_paths"):
		var paths: PackedStringArray = ProjectSettings.get_setting("gdss/storage/save_paths")
		if not paths.is_empty():
			return paths
	return PackedStringArray([get_save_path()])


static func set_save_paths(paths: PackedStringArray) -> void:
	ProjectSettings.set_setting("gdss/storage/save_paths", paths)
	ProjectSettings.save()


static func get_latest_modified() -> int:
	var latest: int = 0
	for path: String in get_save_paths():
		if FileAccess.file_exists(path):
			latest = maxi(latest, FileAccess.get_modified_time(path))
	return latest


static func load_sources() -> PackedStringArray:
	var sources: PackedStringArray = []
	for path: String in get_save_paths():
		sources.append(read_source(path))
	return sources


static func read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


static func write_source(path: String, source: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("[GDSS] Failed to open file for writing: ", path)
		return
	file.store_string(source)
	file.close()


static func write_cache(parsed: Dictionary, global_defaults: Dictionary, instance_defaults: Dictionary, local_vars: Dictionary) -> void:
	var cache_file: FileAccess = FileAccess.open(get_cache_path(), FileAccess.WRITE)
	if cache_file == null:
		printerr("[GDSS] Failed to open cache file for writing: ", get_cache_path())
		return
	cache_file.store_var({"parsed": parsed, "global_defaults": global_defaults, "instance_defaults": instance_defaults, "local_vars": local_vars})
	cache_file.close()


static func save(source: String, parsed: Dictionary, global_defaults: Dictionary = {}, instance_defaults: Dictionary = {}, local_vars: Dictionary = {}, path: String = "") -> void:
	var target: String = path if not path.is_empty() else get_save_path()
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		printerr("[GDSS] Failed to open file for writing: ", target)
		return
	file.store_string(source)
	file.close()
	var cache_file: FileAccess = FileAccess.open(get_cache_path(), FileAccess.WRITE)
	if cache_file == null:
		printerr("[GDSS] Failed to open cache file for writing: ", get_cache_path())
		return
	cache_file.store_var({"parsed": parsed, "global_defaults": global_defaults, "instance_defaults": instance_defaults, "local_vars": local_vars})
	cache_file.close()


static func load_data(path: String = "") -> Dictionary:
	var target: String = path if not path.is_empty() else get_save_path()
	if not FileAccess.file_exists(target):
		return {}
	var file: FileAccess = FileAccess.open(target, FileAccess.READ)
	if file == null:
		return {}
	var result: Dictionary = {"source": file.get_as_text()}
	file.close()
	var cache_path: String = get_cache_path()
	if not FileAccess.file_exists(cache_path):
		return result
	var cache_file: FileAccess = FileAccess.open(cache_path, FileAccess.READ)
	if cache_file == null:
		return result
	var cache: Variant = cache_file.get_var()
	cache_file.close()
	if cache is Dictionary:
		for key: String in (cache as Dictionary):
			result[key] = (cache as Dictionary)[key]
	return result
