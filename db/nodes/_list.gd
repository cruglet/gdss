@tool
class_name GdssNodeList
extends Resource

const PROPERTY_LIST: GdssPropertyList = preload("uid://bkefep4pffcq")

@export var list: Dictionary[String, GdssNode] = {}

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
			
			var new_list: Dictionary[String, GdssNode] = {}
			
			for file_name: String in dir.get_files():
				if file_name.begins_with("_"):
					continue
				
				if not file_name.ends_with(".tres"):
					continue
				
				var full_path: String = dir_path.path_join(file_name)
				var res: Resource = load(full_path)
				if not (res is GdssNode):
					continue
				
				for prop: String in PROPERTY_LIST.list:
					var node: GdssNode = res as GdssNode
					if not node.theme_properties.has(prop):
						node.theme_properties.set(prop, true)
				new_list[file_name.get_basename()] = res
			
			list = new_list
