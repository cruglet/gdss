@tool
class_name GdssExportPlugin
extends EditorExportPlugin


func _get_name() -> String:
	return "GDSS"


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	var compiled_path: String = GdssStorage.get_compiled_path()
	if not FileAccess.file_exists(compiled_path):
		GdssInterpreter.compile_for_export()
	if not FileAccess.file_exists(compiled_path):
		push_error("[GDSS] No theme to export and none could be compiled from the source. Check the GDSS save path.")
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(compiled_path)
	if not bytes.is_empty():
		add_file(compiled_path, bytes, false)
