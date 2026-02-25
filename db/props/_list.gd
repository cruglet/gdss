@tool
class_name GdssPropertyList
extends Resource

@export var list: Dictionary[String, GdssProp] = {}

@export_dir var dir_path: String

@export_tool_button("Populate")
var _populate_list: Callable:
	get():
		return func() -> void:
			if dir_path.is_empty():
				return
			
			var dir: DirAccess = DirAccess.open(dir_path)
			if dir == null:
				return
			
			var new_list: Dictionary[String, GdssProp] = {}
			
			for file_name: String in dir.get_files():
				if file_name.begins_with("_"):
					continue
				
				if not file_name.ends_with(".tres"):
					continue
				
				var full_path: String = dir_path.path_join(file_name)
				var res: Resource = load(full_path)
				if not (res is GdssProp):
					continue
				
				new_list[file_name.get_basename()] = res
			
			list = new_list
