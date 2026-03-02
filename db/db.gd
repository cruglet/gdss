@tool
class_name GdssDB
extends Resource


@export_group("Lists")
@export var node_list: Dictionary[String, GdssNode]
@export var property_list: Dictionary[String, GdssProp]
@export var method_list: Dictionary[String, GdssMethod]
@export var component_list: Dictionary[String, GdssNodeComponent]


@export_tool_button("Repopulate") var _repopulate: Callable:
	get: return repopulate
@export_tool_button("Repopulate (Hard)") var _repopulate_full: Callable:
	get: return repopulate.bind(true)

@export_group("Resource Directories")
@export_dir var methods_dir: String
@export_dir var nodes_dir: String
@export_dir var props_dir: String


func repopulate(new: bool = false) -> void:
	_set_properties(new)
	_set_nodes(new)
	_set_methods(new)



func _set_properties(new: bool = false) -> void:
	var properties: Dictionary[String, GdssProp]
	var dir: DirAccess = DirAccess.open(props_dir)
	
	for file_name: String in dir.get_files():
		if not file_name.get_extension() == "tres":
			continue
		var resource: Resource = load(props_dir.path_join(file_name))
		if resource is GdssProp:
			properties.set(resource.name, resource)
	
	property_list = properties


func _set_nodes(new: bool = false) -> void:
	var nodes: Dictionary[String, GdssNode]
	var components: Array[GdssNodeComponent]
	
	var dir: DirAccess = DirAccess.open(nodes_dir)
	
	for file_name: String in dir.get_files():
		if not file_name.get_extension() == "tres":
			continue
		var resource: Resource = load(nodes_dir.path_join(file_name))
		
		if resource is GdssNode:
			nodes.set(resource.base_type, resource)
		elif resource is GdssNodeComponent:
			component_list.set(resource.component_name, resource)
			components.append(resource)
	
	for node: GdssNode in nodes.values():
		if new:
			node.enabled_components.clear()
		for component: GdssNodeComponent in components:
			if not node.enabled_components.has(component.component_name):
				node.enabled_components.set(component.component_name, component.default_state)
	
	node_list = nodes


func _set_methods(new: bool = false) -> void:
	var methods: Dictionary[String, GdssMethod]
	var dir: DirAccess = DirAccess.open(methods_dir)
	
	for file_name: String in dir.get_files():
		if not file_name.get_extension() == "tres":
			continue
		var resource: Resource = load(methods_dir.path_join(file_name))
		if resource is GdssMethod:
			methods.set(resource.method_name, resource)
	
	method_list = methods
