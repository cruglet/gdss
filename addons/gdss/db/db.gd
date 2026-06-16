@tool
class_name GdssDB
extends Resource


@export_group("Lists")
@export var node_list: Dictionary[String, GdssNode]
@export var property_list: Dictionary[String, GdssProp]
@export var method_list: Dictionary[String, GdssMethod]
@export var component_list: Dictionary[String, GdssNodeComponent]
@export var boolean_overrides: Dictionary[String, bool]

@export_tool_button("Repopulate") var _repopulate: Callable:
	get: return repopulate
@export_tool_button("Repopulate (Hard)") var _repopulate_full: Callable:
	get: return repopulate.bind(true)
@export_tool_button("Populate Missing Nodes") var _populate_nodes: Callable:
	get: return _populate_missing_nodes
@export_tool_button("Remove Invalid Nodes") var _remove_invalid_nodes: Callable:
	get: return _remove_invalid_nodes_fn
@export_tool_button("Clear Lists") var _clear_lists: Callable:
	get: return clear_lists


@export_group("Resource Directories")
@export_dir var methods_dir: String
@export_dir var nodes_dir: String
@export_dir var props_dir: String


func clear_lists() -> void:
	node_list.clear()
	method_list.clear()
	component_list.clear()
	property_list.clear()
	ResourceSaver.save(self)


func repopulate(new: bool = false) -> void:
	_set_properties()
	_set_nodes(new)
	_set_methods()
	for node: GdssNode in node_list.values():
		node.invalidate_props_cache()
	ResourceSaver.save(self)


func _set_properties() -> void:
	var properties: Dictionary[String, GdssProp]
	var dir: DirAccess = DirAccess.open(props_dir)
	if dir == null:
		return
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
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.get_extension() == "tres":
			continue
		var resource: Resource = load(nodes_dir.path_join(file_name))
		if resource is GdssNode:
			nodes.set(resource.base_type, resource)
		elif resource is GdssNodeComponent:
			component_list.set(resource.component_name, resource)
			components.append(resource)
	
	var valid_component_names: PackedStringArray = []
	for component: GdssNodeComponent in components:
		valid_component_names.append(component.component_name)
	
	for node: GdssNode in nodes.values():
		node.invalidate_theme_cache()
		if new:
			node.enabled_components.clear()
		for component_name: String in node.enabled_components.keys():
			if not valid_component_names.has(component_name):
				node.enabled_components.erase(component_name)
		for component: GdssNodeComponent in components:
			if not node.enabled_components.has(component.component_name):
				node.enabled_components.set(component.component_name, component.default_state)
		if node.is_static and node.enabled_components.has("Transitionable"):
			node.enabled_components["Transitionable"] = false
		if node.enabled_components.has("Stylebox") and node.states.is_empty():
			node.enabled_components["Stylebox"] = false
	node_list = nodes


func _set_methods() -> void:
	var methods: Dictionary[String, GdssMethod]
	var dir: DirAccess = DirAccess.open(methods_dir)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.get_extension() == "tres":
			continue
		var resource: Resource = load(methods_dir.path_join(file_name))
		if resource is GdssMethod:
			methods.set(resource.method_name, resource)
	
	method_list = methods


func _populate_missing_nodes() -> void:
	var existing_types: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(nodes_dir)
	for file_name: String in dir.get_files():
		if not file_name.get_extension() == "tres":
			continue
		var resource: Resource = load(nodes_dir.path_join(file_name))
		if resource is GdssNode:
			existing_types.append(String(resource.base_type))
	
	var theme: Theme = ThemeDB.get_default_theme()
	var theme_types: PackedStringArray = theme.get_type_list()
	
	for type: String in theme_types:
		if not ClassDB.is_parent_class(StringName(type), &"Control") and type != "Control":
			continue
		if existing_types.has(type):
			continue
		var node: GdssNode_Base = GdssNode_Base.new()
		node.base_type = StringName(type)
		node.style_name = StringName(type)
		node.is_static = true
		ResourceSaver.save(node, nodes_dir.path_join(type + ".tres"))
	
	repopulate()


func _remove_invalid_nodes_fn() -> void:
	var theme: Theme = ThemeDB.get_default_theme()
	var theme_types: PackedStringArray = theme.get_type_list()
	
	var dir: DirAccess = DirAccess.open(nodes_dir)
	for file_name: String in dir.get_files():
		if not file_name.get_extension() == "tres":
			continue
		var resource: Resource = load(nodes_dir.path_join(file_name))
		if not resource is GdssNode:
			continue
		var type: String = String((resource as GdssNode).base_type)
		if not theme_types.has(type):
			DirAccess.remove_absolute(nodes_dir.path_join(file_name))
	
	repopulate()
