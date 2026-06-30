@tool
class_name GdssExportPlugin
extends EditorExportPlugin


func _get_name() -> String:
	return "GDSS"


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	var bytes: PackedByteArray = GdssInterpreter.compile_for_export()
	if bytes.is_empty():
		push_error("[GDSS] No theme to export and none could be compiled from the source. Check the GDSS save path.")
		return
	add_file(GdssStorage.get_compiled_path(), bytes, false)
