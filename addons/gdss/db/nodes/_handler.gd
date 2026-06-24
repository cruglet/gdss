@tool
class_name GdssNodeHandler
extends Object

const GROUP: StringName = &"gdss"

static var _registry: Dictionary[int, Dictionary] = {}
static var _all_cache: Array[GdssPropHandler] = []
static var _all_dirty: bool = true


static func get_handler(canvas_item: Node, state: String = "") -> GdssPropHandler:
	var id: int = canvas_item.get_instance_id()
	if not _registry.has(id):
		return null
	return _registry[id].get(state)


static func get_all_handlers() -> Array[GdssPropHandler]:
	if not _all_dirty:
		return _all_cache
	_all_cache.clear()
	var dead: Array[int] = []
	for id: int in _registry:
		if not is_instance_valid(instance_from_id(id)):
			dead.append(id)
			continue
		var slots: Dictionary = _registry[id]
		for state: String in slots:
			var handler: GdssPropHandler = slots[state]
			if handler != null:
				_all_cache.append(handler)
	for id: int in dead:
		purge(id)
	_all_dirty = false
	return _all_cache


## Marks the cached handler array as stale so the next call to [method
## get_all_handlers] rebuilds it (and prunes any dead entries).
static func mark_dirty() -> void:
	_all_dirty = true


## Releases everything GDSS holds for the node whose instance id is [param id].
## Erases its registry slot (freeing the handlers, and with them their GPU
## resources), purges per-node method caches, and drops any instance variables.
## Idempotent: safe to call for an id that was already purged.
static func purge(id: int) -> void:
	if _registry.has(id):
		for handler: GdssPropHandler in (_registry[id] as Dictionary).values():
			if handler != null:
				handler._free_gpu_ci()
		_registry.erase(id)
		_all_dirty = true
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.purge_node(id)
	GdssInterpreter._instance_vars.erase(id)


## Deferred teardown guard: purges the node's GDSS state only if the instance is
## genuinely gone. Routed through [code]call_deferred[/code] from tree-exit hooks
## so a reparent (remove-then-readd in the same frame) does not tear anything down.
static func _check_purge(id: int) -> void:
	if is_instance_valid(instance_from_id(id)):
		return
	purge(id)


static func get_handlers(canvas_item: Node) -> Array[GdssPropHandler]:
	var result: Array[GdssPropHandler] = []
	if canvas_item == null:
		return result
	var slots: Dictionary = _registry.get(canvas_item.get_instance_id(), {})
	for handler: GdssPropHandler in slots.values():
		if handler != null:
			result.append(handler)
	return result


## Returns the live {state -> handler} slots dict for a node WITHOUT copying it
## (unlike get_handlers, which allocates an Array). Hot-path callers iterate this
## directly; they must not mutate the returned dict.
static func get_slots(canvas_item: Node) -> Dictionary:
	if canvas_item == null:
		return {}
	return _registry.get(canvas_item.get_instance_id(), {})


## Returns the one handler that owns node-level concerns (e.g. on_show/on_hide
## visibility events): the unslotted handler for stateful nodes, else the first
## slot for static nodes. Null if the node has no handlers.
static func get_primary_handler(canvas_item: Node) -> GdssPropHandler:
	if canvas_item == null:
		return null
	var slots: Dictionary = _registry.get(canvas_item.get_instance_id(), {})
	if slots.has(""):
		return slots[""]
	for state: String in slots:
		return slots[state]
	return null


static func is_enabled(canvas_item: Node) -> bool:
	return GDSS.resolve_mode(canvas_item)


static func is_bound(canvas_item: Node) -> bool:
	return _registry.has(canvas_item.get_instance_id())


static func refresh(canvas_item: Node) -> void:
	if canvas_item == null:
		return
	var slots: Dictionary = get_slots(canvas_item)
	for state: String in slots:
		var handler: GdssPropHandler = slots[state]
		if handler != null:
			handler.reapply()
	# Window-derived nodes have no queue_redraw; reapply() already fired emit_changed()
	# on each handler, which notifies the window to re-render.
	if canvas_item is CanvasItem:
		(canvas_item as CanvasItem).queue_redraw()


static func rebind_tree(node: Node) -> void:
	if node == null:
		return
	if node is CanvasItem:
		_migrate_legacy(node as CanvasItem)
		apply_mode(node)
	elif node is Window:
		apply_mode(node)
	for child: Node in node.get_children():
		rebind_tree(child)


static func apply_mode_tree(node: Node) -> void:
	if node == null:
		return
	if node is CanvasItem or node is Window:
		apply_mode(node)
	for child: Node in node.get_children():
		apply_mode_tree(child)


static func apply_mode(canvas_item: Node) -> void:
	if not GDSS._get_gdss_nodes().has(canvas_item.get_class()):
		return
	if GDSS.resolve_mode(canvas_item):
		bind(canvas_item)
	elif _registry.has(canvas_item.get_instance_id()):
		unbind(canvas_item)


static func set_mode_state(node: Node, mode: GDSS.GdssMode, in_legacy_group: bool) -> void:
	if mode == GDSS.GdssMode.INHERIT:
		if node.has_meta(GDSS.MODE_META):
			node.remove_meta(GDSS.MODE_META)
	else:
		node.set_meta(GDSS.MODE_META, mode)
	if in_legacy_group and not node.is_in_group(GROUP):
		node.add_to_group(GROUP, true)
	elif not in_legacy_group and node.is_in_group(GROUP):
		node.remove_from_group(GROUP)
	apply_mode_tree(node)
	if Engine.is_editor_hint():
		node.notify_property_list_changed()


static func _migrate_legacy(canvas_item: CanvasItem) -> void:
	if canvas_item.is_in_group(GROUP):
		return
	if not canvas_item.has_meta(&"gdss_enabled"):
		return
	var was_enabled: bool = canvas_item.get_meta(&"gdss_enabled", false)
	for meta_key: StringName in [&"gdss_enabled", &"gdss_handler"]:
		if canvas_item.has_meta(meta_key):
			canvas_item.remove_meta(meta_key)
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node != null:
		for state: String in gdss_node.states:
			var meta_key: StringName = "gdss_handler_" + state
			if canvas_item.has_meta(meta_key):
				canvas_item.remove_meta(meta_key)
	if was_enabled:
		canvas_item.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)


static func bind(canvas_item: Node, apply: bool = true, gdss_node: GdssNode = null) -> void:
	# gdss_node may be passed by the caller (e.g. runtime._try_bind already looked it
	# up) to avoid a redundant class->node dictionary fetch per bound node.
	if gdss_node == null:
		gdss_node = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		return
	# Control and Window both expose the theme-override API; everything else is unstylable.
	if not (canvas_item is Control or canvas_item is Window):
		return
	var control: Variant = canvas_item
	# Batch every stylebox-override add into one theme-changed notification (a Button
	# binds the same handler to ~9 state slots - 9 propagations become 1). The
	# value overrides are applied after, each in its own bulk inside _apply_overrides.
	control.begin_bulk_theme_override()
	var handlers: Array[GdssPropHandler] = []
	if gdss_node.is_static:
		for state: String in gdss_node.states:
			var handler: GdssPropHandler = _obtain(canvas_item, control, state, state)
			handler._slot_state = state
			handlers.append(handler)
	else:
		var states: PackedStringArray = gdss_node.states
		var first_slot: String = states[0] if not states.is_empty() else ""
		var handler: GdssPropHandler = _obtain(canvas_item, control, "", first_slot)
		for state: String in states:
			if control.get_theme_stylebox(state) != handler:
				control.add_theme_stylebox_override(state, handler)
		handlers.append(handler)
	control.end_bulk_theme_override()
	if apply:
		for handler: GdssPropHandler in handlers:
			handler._apply_overrides(false)
	gdss_node.bind_canvas_item(canvas_item)


static func _obtain(canvas_item: Node, control: Variant, state: String, slot: String) -> GdssPropHandler:
	var slots: Dictionary = _registry.get_or_add(canvas_item.get_instance_id(), {})
	var handler: GdssPropHandler = slots.get(state)
	if handler == null and not slot.is_empty():
		var existing: StyleBox = control.get_theme_stylebox(slot) if control.has_theme_stylebox_override(slot) else null
		if existing is GdssPropHandler:
			handler = existing as GdssPropHandler
	if handler == null:
		handler = GdssPropHandler.new()
	if slots.get(state) != handler:
		_all_dirty = true
	slots[state] = handler
	handler.ref = canvas_item
	if not slot.is_empty() and control.get_theme_stylebox(slot) != handler:
		control.add_theme_stylebox_override(slot, handler)
	_connect_editor(handler)
	return handler


static func _connect_editor(handler: GdssPropHandler) -> void:
	if not Engine.is_editor_hint():
		return
	var interp: GdssInterpreter = GdssInterpreter.get_instance()
	if is_instance_valid(interp) and not interp.parsed_changed.is_connected(handler._on_parsed_changed):
		interp.parsed_changed.connect(handler._on_parsed_changed)


static func unbind(canvas_item: Node) -> void:
	var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
	if gdss_node == null:
		printerr("Could not unbind %s of type \"%s\"" % [canvas_item, canvas_item.get_class()])
		return
	if not (canvas_item is Control or canvas_item is Window):
		return
	var control: Variant = canvas_item
	_clear_overrides_for(control, gdss_node)
	var interp: GdssInterpreter = GdssInterpreter.get_instance() if Engine.is_editor_hint() else null
	var slots: Dictionary = _registry.get(canvas_item.get_instance_id(), {})
	for handler: GdssPropHandler in slots.values():
		if handler == null:
			continue
		handler._free_gpu_ci()
		if is_instance_valid(interp) and interp.parsed_changed.is_connected(handler._on_parsed_changed):
			interp.parsed_changed.disconnect(handler._on_parsed_changed)
	for state: String in gdss_node.states:
		control.remove_theme_stylebox_override(state)
	_registry.erase(canvas_item.get_instance_id())
	_all_dirty = true
	gdss_node.unbind_canvas_item(canvas_item)
	GDSS.clear_instance_vars(canvas_item)
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var ei: Object = Engine.get_singleton(&"EditorInterface")
		if ei.call(&"get_edited_scene_root") != null:
			ei.call(&"mark_scene_as_unsaved")


static func _clear_overrides_for(control: Variant, gdss_node: GdssNode) -> void:
	for prop: GdssProp in gdss_node.get_enabled_props():
		match prop.category:
			GdssProp.Category.COLOR:
				if prop.category_subproperties.is_empty():
					control.remove_theme_color_override(prop.name)
				else:
					if gdss_node.colors.has(prop.name):
						control.remove_theme_color_override(prop.name)
					for subprop: String in prop.category_subproperties:
						if gdss_node.colors.has(subprop):
							control.remove_theme_color_override(subprop)
			GdssProp.Category.CONST:
				control.remove_theme_constant_override(prop.name)
			GdssProp.Category.FONT_SIZE:
				control.remove_theme_font_size_override(prop.name)
			GdssProp.Category.FONT:
				control.remove_theme_font_override(prop.name)
			GdssProp.Category.ICON:
				control.remove_theme_icon_override(prop.name)


# Removes every GDSS-applied theme override from all bound nodes without tearing
# down the binding, so a scene can be packed without baking runtime styling into
# it. Pair with reapply_overrides() to restore the live preview afterwards.
static func strip_overrides() -> void:
	for id: int in _registry.keys():
		var canvas_item: Node = instance_from_id(id) as Node
		if not is_instance_valid(canvas_item):
			continue
		var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
		if gdss_node == null:
			continue
		if not (canvas_item is Control or canvas_item is Window):
			continue
		var control: Variant = canvas_item
		_clear_overrides_for(control, gdss_node)
		for state: String in gdss_node.states:
			control.remove_theme_stylebox_override(state)


# Re-applies the GDSS style overrides to every bound node, reusing the handlers
# that are already in the registry.
static func reapply_overrides() -> void:
	for id: int in _registry.keys():
		var canvas_item: Node = instance_from_id(id) as Node
		if not is_instance_valid(canvas_item):
			continue
		var gdss_node: GdssNode = GDSS._get_gdss_nodes().get(canvas_item.get_class())
		if gdss_node == null:
			continue
		if not (canvas_item is Control or canvas_item is Window):
			continue
		var control: Variant = canvas_item
		for handler: GdssPropHandler in _registry.get(id, {}).values():
			if handler == null:
				continue
			if gdss_node.is_static:
				if not handler._slot_state.is_empty():
					control.add_theme_stylebox_override(handler._slot_state, handler)
			else:
				for state: String in gdss_node.states:
					control.add_theme_stylebox_override(state, handler)
			handler._apply_overrides(false)
