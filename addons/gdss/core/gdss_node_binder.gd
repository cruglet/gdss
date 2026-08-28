@tool
class_name GdssNodeBinder
extends Object

const GROUP: StringName = &"gdss"

static var _registry: Dictionary[int, Dictionary] = {}
static var _all_cache: Array[GdssStylebox] = []
static var _all_dirty: bool = true


static func get_stylebox(canvas_item: Node, state: String = "") -> GdssStylebox:
	var id: int = canvas_item.get_instance_id()
	if not _registry.has(id):
		return null
	return _registry[id].get(state)


static func get_all_styleboxes() -> Array[GdssStylebox]:
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
			var stylebox: GdssStylebox = slots[state]
			if stylebox != null:
				_all_cache.append(stylebox)
	for id: int in dead:
		purge(id)
	_all_dirty = false
	return _all_cache


## Marks the cached stylebox array as stale so the next call to [method
## get_all_styleboxes] rebuilds it (and prunes any dead entries).
static func mark_dirty() -> void:
	_all_dirty = true


## Releases everything GDSS holds for the node whose instance id is [param id].
## Erases its registry slot (freeing the styleboxes, and with them their GPU
## resources), purges per-node method caches, and drops any instance variables.
## Idempotent: safe to call for an id that was already purged.
static func purge(id: int) -> void:
	if _registry.has(id):
		for stylebox: GdssStylebox in (_registry[id] as Dictionary).values():
			if stylebox != null:
				stylebox._kill_tween()
				stylebox._free_gpu_ci()
		_registry.erase(id)
		_all_dirty = true
	for method: GdssMethod in GDSS._get_gdss_methods().values():
		if method.returns_texture:
			method.purge_node(id)
	GdssStylesheet._instance_vars.erase(id)


## Deferred teardown guard: purges the node's GDSS state only if the instance is
## genuinely gone. Routed through [code]call_deferred[/code] from tree-exit hooks
## so a reparent (remove-then-readd in the same frame) does not tear anything down.
static func _check_purge(id: int) -> void:
	if is_instance_valid(instance_from_id(id)):
		return
	purge(id)


static func get_styleboxes(canvas_item: Node) -> Array[GdssStylebox]:
	var result: Array[GdssStylebox] = []
	if canvas_item == null:
		return result
	var slots: Dictionary = _registry.get(canvas_item.get_instance_id(), {})
	for stylebox: GdssStylebox in slots.values():
		if stylebox != null:
			result.append(stylebox)
	return result


## Returns the live {state -> stylebox} slots dict for a node WITHOUT copying it
## (unlike get_styleboxes, which allocates an Array). Hot-path callers iterate this
## directly; they must not mutate the returned dict.
static func get_slots(canvas_item: Node) -> Dictionary:
	if canvas_item == null:
		return {}
	return _registry.get(canvas_item.get_instance_id(), {})


## Returns the one stylebox that owns node-level concerns (e.g. on_show/on_hide
## visibility events): the unslotted stylebox for stateful nodes, else the first
## slot for static nodes. Null if the node has no styleboxes.
static func get_primary_stylebox(canvas_item: Node) -> GdssStylebox:
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
		var stylebox: GdssStylebox = slots[state]
		if stylebox != null:
			stylebox.reapply()
	# Window-derived nodes have no queue_redraw; reapply() already fired emit_changed()
	# on each stylebox, which notifies the window to re-render.
	if canvas_item is CanvasItem:
		(canvas_item as CanvasItem).queue_redraw()


## Lightweight refresh for an instance-variable change: re-applies only the node's
## dynamic non-style overrides (same work the coalesced global-var flush does) and
## queues a redraw so style props re-resolve, instead of a full invalidate + reapply.
static func refresh_vars(canvas_item: Node) -> void:
	if canvas_item == null:
		return
	var slots: Dictionary = get_slots(canvas_item)
	for state: String in slots:
		var stylebox: GdssStylebox = slots[state]
		if stylebox != null:
			stylebox.refresh_globals()
	if canvas_item is CanvasItem:
		(canvas_item as CanvasItem).queue_redraw()
	else:
		for state: String in slots:
			var stylebox: GdssStylebox = slots[state]
			if stylebox != null:
				stylebox.emit_changed()


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
	if not GDSS._get_node_types().has(canvas_item.get_class()):
		return
	if GDSS.resolve_mode(canvas_item):
		bind(canvas_item)
	elif _registry.has(canvas_item.get_instance_id()):
		unbind(canvas_item)


static func detach_foreign_styleboxes(node: Node, node_type: GdssNodeType = null) -> void:
	if not (node is Control or node is Window):
		return
	if node_type == null:
		node_type = GDSS._get_node_types().get(node.get_class())
	if node_type == null or node_type.states.is_empty():
		return
	var control: Variant = node
	var removed: bool = false
	for state: String in node_type.states:
		if not control.has_theme_stylebox_override(state):
			continue
		var sb: StyleBox = control.get_theme_stylebox(state)
		if not sb is GdssStylebox:
			continue
		var owner_node: Node = (sb as GdssStylebox).ref
		if owner_node != null and owner_node != node:
			if not removed:
				control.begin_bulk_theme_override()
				removed = true
			control.remove_theme_stylebox_override(state)
	if removed:
		control.end_bulk_theme_override()


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
	var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
	if node_type != null:
		for state: String in node_type.states:
			var meta_key: StringName = "gdss_handler_" + state
			if canvas_item.has_meta(meta_key):
				canvas_item.remove_meta(meta_key)
	if was_enabled:
		canvas_item.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)


static func bind(canvas_item: Node, apply: bool = true, node_type: GdssNodeType = null) -> void:
	# node_type may be passed by the caller (e.g. runtime._try_bind already looked it
	# up) to avoid a redundant class->node dictionary fetch per bound node.
	if node_type == null:
		node_type = GDSS._get_node_types().get(canvas_item.get_class())
	if node_type == null:
		return
	# Control and Window both expose the theme-override API; everything else is unstylable.
	if not (canvas_item is Control or canvas_item is Window):
		return
	var control: Variant = canvas_item
	# One bulk-override region wraps the stylebox adds (a Button binds the same stylebox to
	# ~9 state slots) and, for stateful nodes, the value overrides too - so a fresh bind
	# costs a single theme-changed notification instead of one per override group.
	control.begin_bulk_theme_override()
	var styleboxes: Array[GdssStylebox] = []
	if node_type.is_static:
		if node_type.states.is_empty():
			styleboxes.append(_obtain(canvas_item, control, "", ""))
		else:
			for state: String in node_type.states:
				var stylebox: GdssStylebox = _obtain(canvas_item, control, state, state)
				stylebox._slot_state = state
				styleboxes.append(stylebox)
	else:
		var states: PackedStringArray = node_type.states
		var first_slot: String = states[0] if not states.is_empty() else ""
		var stylebox: GdssStylebox = _obtain(canvas_item, control, "", first_slot)
		for state: String in states:
			if not control.has_theme_stylebox_override(state) or control.get_theme_stylebox(state) != stylebox:
				control.add_theme_stylebox_override(state, stylebox)
		styleboxes.append(stylebox)
		# Seed the resting interaction state (without firing the setter) and apply in this
		# same bulk. The caller's follow-up update_state then no-ops; a reparent, where the
		# state is unchanged and the overrides are intact, skips the re-apply entirely.
		if apply and canvas_item is CanvasItem:
			var active: String = node_type.get_active_state(canvas_item as CanvasItem)
			if stylebox.current_state != active:
				var clear: bool = not stylebox.current_state.is_empty()
				stylebox._seeding = true
				stylebox.current_state = active
				stylebox._seeding = false
				stylebox._apply_overrides_unwrapped(node_type, control, clear)
				(canvas_item as CanvasItem).queue_redraw()
	control.end_bulk_theme_override()
	if apply and node_type.is_static:
		for stylebox: GdssStylebox in styleboxes:
			stylebox._apply_overrides(false)
	node_type.bind_canvas_item(canvas_item)


static func _obtain(canvas_item: Node, control: Variant, state: String, slot: String) -> GdssStylebox:
	var slots: Dictionary = _registry.get_or_add(canvas_item.get_instance_id(), {})
	var stylebox: GdssStylebox = slots.get(state)
	if stylebox == null and not slot.is_empty():
		var existing: StyleBox = control.get_theme_stylebox(slot) if control.has_theme_stylebox_override(slot) else null
		if existing is GdssStylebox:
			var candidate: GdssStylebox = existing as GdssStylebox
			var bound: Node = candidate.ref
			if bound == null or bound == canvas_item:
				stylebox = candidate
	if stylebox == null:
		stylebox = GdssStylebox.new()
	if slots.get(state) != stylebox:
		_all_dirty = true
	slots[state] = stylebox
	stylebox.ref = canvas_item
	if not slot.is_empty() and (not control.has_theme_stylebox_override(slot) or control.get_theme_stylebox(slot) != stylebox):
		control.add_theme_stylebox_override(slot, stylebox)
	_connect_editor(stylebox)
	return stylebox


static func _connect_editor(stylebox: GdssStylebox) -> void:
	if not Engine.is_editor_hint():
		return
	var interp: GdssStylesheet = GdssStylesheet.get_instance()
	if is_instance_valid(interp) and not interp.parsed_changed.is_connected(stylebox._on_parsed_changed):
		interp.parsed_changed.connect(stylebox._on_parsed_changed)


static func unbind(canvas_item: Node) -> void:
	var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
	if node_type == null:
		printerr("Could not unbind %s of type \"%s\"" % [canvas_item, canvas_item.get_class()])
		return
	if not (canvas_item is Control or canvas_item is Window):
		return
	var control: Variant = canvas_item
	node_type.unbind_canvas_item(canvas_item)
	var interp: GdssStylesheet = GdssStylesheet.get_instance() if Engine.is_editor_hint() else null
	var slots: Dictionary = _registry.get(canvas_item.get_instance_id(), {})
	for stylebox: GdssStylebox in slots.values():
		if stylebox == null:
			continue
		stylebox._kill_tween()
		stylebox._reset_node_props(node_type, control, false)
		stylebox._free_gpu_ci()
		if is_instance_valid(interp) and interp.parsed_changed.is_connected(stylebox._on_parsed_changed):
			interp.parsed_changed.disconnect(stylebox._on_parsed_changed)
	control.begin_bulk_theme_override()
	_clear_overrides_for(control, node_type)
	for state: String in node_type.states:
		control.remove_theme_stylebox_override(state)
	control.end_bulk_theme_override()
	_registry.erase(canvas_item.get_instance_id())
	_all_dirty = true
	GDSS.clear_instance_vars(canvas_item)
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var ei: Object = Engine.get_singleton(&"EditorInterface")
		if ei.call(&"get_edited_scene_root") != null:
			ei.call(&"mark_scene_as_unsaved")


static func _clear_overrides_for(control: Variant, node_type: GdssNodeType) -> void:
	for prop: GdssProp in node_type.get_enabled_props():
		match prop.category:
			GdssProp.Category.COLOR:
				if prop.category_subproperties.is_empty():
					control.remove_theme_color_override(prop.name)
				else:
					if node_type.colors.has(prop.name):
						control.remove_theme_color_override(prop.name)
					for subprop: String in prop.category_subproperties:
						if node_type.colors.has(subprop):
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
		var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
		if node_type == null:
			continue
		if not (canvas_item is Control or canvas_item is Window):
			continue
		var control: Variant = canvas_item
		_clear_overrides_for(control, node_type)
		for stylebox: GdssStylebox in _registry.get(id, {}).values():
			if stylebox != null:
				stylebox._reset_node_props(node_type, control, false)
		for state: String in node_type.states:
			control.remove_theme_stylebox_override(state)


# Re-applies the GDSS style overrides to every bound node, reusing the styleboxes
# that are already in the registry.
static func reapply_overrides() -> void:
	for id: int in _registry.keys():
		var canvas_item: Node = instance_from_id(id) as Node
		if not is_instance_valid(canvas_item):
			continue
		var node_type: GdssNodeType = GDSS._get_node_types().get(canvas_item.get_class())
		if node_type == null:
			continue
		if not (canvas_item is Control or canvas_item is Window):
			continue
		var control: Variant = canvas_item
		for stylebox: GdssStylebox in _registry.get(id, {}).values():
			if stylebox == null:
				continue
			if node_type.is_static:
				if not stylebox._slot_state.is_empty():
					control.add_theme_stylebox_override(stylebox._slot_state, stylebox)
			else:
				for state: String in node_type.states:
					control.add_theme_stylebox_override(state, stylebox)
			stylebox._apply_overrides(false)
