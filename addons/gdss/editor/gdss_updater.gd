@tool
class_name GdssUpdater
extends Node

signal check_completed(result: Dictionary)
signal install_completed(success: bool, message: String)

const TAGS_URL: String = "https://api.github.com/repos/cruglet/gdss/tags"
const HEADERS: PackedStringArray = ["Accept: application/vnd.github+json", "User-Agent: gdss-updater"]
const ADDON_ROOT: String = "res://addons/gdss"
const ZIP_PATH: String = "user://gdss_update.zip"

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


func get_current_version() -> String:
	var config: ConfigFile = ConfigFile.new()
	if config.load(ADDON_ROOT.path_join("plugin.cfg")) != OK:
		return "0.0.0"
	return str(config.get_value("plugin", "version", "0.0.0"))


func check() -> void:
	if _http.request(TAGS_URL, HEADERS) != OK:
		check_completed.emit({"ok": false, "message": "Could not reach GitHub."})
		return
	var result: Array = await _http.request_completed
	if int(result.get(1)) != 200:
		check_completed.emit({"ok": false, "message": "GitHub returned status %d." % int(result.get(1))})
		return
	var body: PackedByteArray = result.get(3)
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Array) or (data as Array).is_empty():
		check_completed.emit({"ok": false, "message": "No tags have been published yet."})
		return
	var current: String = get_current_version()
	var best_name: String = ""
	var best_url: String = ""
	for tag: Dictionary in data:
		var tag_name: String = str(tag.get("name", ""))
		if tag_name.is_empty():
			continue
		if best_name.is_empty() or _compare_versions(tag_name, best_name) > 0:
			best_name = tag_name
			best_url = str(tag.get("zipball_url", ""))
	if best_name.is_empty() or _compare_versions(best_name, current) <= 0:
		check_completed.emit({"ok": true, "update": false, "current": current, "latest": best_name})
		return
	check_completed.emit({"ok": true, "update": true, "current": current, "latest": best_name, "url": best_url})


func install(version: String, url: String) -> void:
	if url.is_empty():
		install_completed.emit(false, "No download URL was provided for %s." % version)
		return
	_http.download_file = ZIP_PATH
	if _http.request(url, HEADERS) != OK:
		_http.download_file = ""
		install_completed.emit(false, "Could not start the download.")
		return
	var result: Array = await _http.request_completed
	_http.download_file = ""
	if int(result.get(1)) != 200:
		install_completed.emit(false, "Download failed (HTTP %d)." % int(result.get(1)))
		return
	_extract(version)


func _extract(version: String) -> void:
	var reader: ZIPReader = ZIPReader.new()
	if reader.open(ZIP_PATH) != OK:
		install_completed.emit(false, "Could not open the downloaded archive.")
		return
	var marker: String = "/addons/gdss/"
	var written: int = 0
	for entry: String in reader.get_files():
		if entry.ends_with("/"):
			continue
		var index: int = entry.find(marker)
		if index == -1:
			continue
		var relative: String = entry.substr(index + marker.length())
		if relative.is_empty():
			continue
		var destination: String = ADDON_ROOT.path_join(relative)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			continue
		file.store_buffer(reader.read_file(entry))
		file.close()
		written += 1
	reader.close()
	DirAccess.remove_absolute(ZIP_PATH)
	if written == 0:
		install_completed.emit(false, "The archive did not contain the addon files.")
		return
	install_completed.emit(true, "Updated to %s (%d files replaced). Reload the project to apply." % [version, written])


func _compare_versions(a: String, b: String) -> int:
	var parsed_a: Dictionary = _parse_version(a)
	var parsed_b: Dictionary = _parse_version(b)
	var core_a: Array = parsed_a.get("core")
	var core_b: Array = parsed_b.get("core")
	for i: int in 3:
		var diff: int = int(core_a.get(i)) - int(core_b.get(i))
		if diff != 0:
			return signi(diff)
	var pre_a: Array = parsed_a.get("pre")
	var pre_b: Array = parsed_b.get("pre")
	if pre_a.is_empty() and pre_b.is_empty():
		return 0
	if pre_a.is_empty():
		return 1
	if pre_b.is_empty():
		return -1
	return _compare_prerelease(pre_a, pre_b)


func _parse_version(version: String) -> Dictionary:
	var clean: String = version.strip_edges().trim_prefix("v")
	var dash: int = clean.find("-")
	var core_text: String = clean if dash == -1 else clean.substr(0, dash)
	var pre_text: String = "" if dash == -1 else clean.substr(dash + 1)
	var core: Array[int] = []
	for part: String in core_text.split("."):
		core.append(part.to_int())
	while core.size() < 3:
		core.append(0)
	var pre: Array[String] = []
	if not pre_text.is_empty():
		for part: String in pre_text.split(".", false):
			pre.append(part)
	return {"core": core, "pre": pre}


func _compare_prerelease(a: Array, b: Array) -> int:
	for i: int in mini(a.size(), b.size()):
		var left: String = str(a.get(i))
		var right: String = str(b.get(i))
		if left.is_valid_int() and right.is_valid_int():
			var diff: int = left.to_int() - right.to_int()
			if diff != 0:
				return signi(diff)
		elif left != right:
			return 1 if left > right else -1
	return signi(a.size() - b.size())
