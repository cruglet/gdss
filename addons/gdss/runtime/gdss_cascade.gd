@tool
class_name GdssCascade
extends RefCounted


static func find_class(classes: Dictionary, name: String) -> Dictionary:
	if classes.has(name):
		return classes.get(name)
	for key: String in classes:
		var nested: Dictionary = classes.get(key).get(GdssValue.CLASSES_KEY, {})
		if nested.is_empty():
			continue
		var found: Dictionary = find_class(nested, name)
		if not found.is_empty():
			return found
	return {}


static func find_class_path(classes: Dictionary, name: String) -> Array[Dictionary]:
	if classes.has(name):
		return [classes.get(name)] as Array[Dictionary]
	for key: String in classes:
		var nested: Dictionary = classes.get(key).get(GdssValue.CLASSES_KEY, {})
		if nested.is_empty():
			continue
		var found: Array[Dictionary] = find_class_path(nested, name)
		if not found.is_empty():
			var path: Array[Dictionary] = [classes.get(key)] as Array[Dictionary]
			path.append_array(found)
			return path
	return [] as Array[Dictionary]


static func merge_descendants(base: Dictionary, override: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in base:
		out.set(key, base.get(key))
	for key: String in override:
		if out.has(key) and out.get(key) is Dictionary and override.get(key) is Dictionary:
			out.set(key, merge_entries(out.get(key), override.get(key), true))
		else:
			out.set(key, override.get(key))
	return out


static func merge_entries(base: Dictionary, override: Dictionary, keep_ancestor_states: bool = false) -> Dictionary:
	var merged: Dictionary = {}
	for state: String in base:
		if state == GdssValue.CLASSES_KEY or state == GdssValue.VARS_KEY:
			continue
		if not keep_ancestor_states and state.begins_with(GdssValue.ANCESTOR_STATE_PREFIX):
			continue
		merged.set(state, base.get(state).duplicate() if base.get(state) is Dictionary else base.get(state))
	for state: String in override:
		if state == GdssValue.CLASSES_KEY or state == GdssValue.VARS_KEY:
			continue
		if not keep_ancestor_states and state.begins_with(GdssValue.ANCESTOR_STATE_PREFIX):
			continue
		if state == GdssValue.DESCENDANTS_KEY:
			merged.set(state, merge_descendants(merged.get(state, {}), override.get(state)))
			continue
		if not merged.has(state):
			merged.set(state, override.get(state).duplicate() if override.get(state) is Dictionary else override.get(state))
			continue
		if override.get(state) is Dictionary:
			for key: String in override.get(state):
				if key == "transition_time":
					merged.get(state).set(key, GdssValue.merge_scoped_time(
						merged.get(state).get(key), override.get(state).get(key)))
					continue
				merged.get(state).set(key, override.get(state).get(key))
		else:
			merged.set(state, override.get(state))
	merged.set(GdssValue.CLASSES_KEY, override.get(GdssValue.CLASSES_KEY, {}))
	return merged


static func propagate_all(entry: Dictionary, overlay: Dictionary) -> void:
	var all_overrides: Variant = overlay.get("all")
	if not all_overrides is Dictionary:
		return
	for state_key: String in entry:
		if state_key == "all" or state_key == GdssValue.CLASSES_KEY or state_key == GdssValue.VARIATIONS_KEY or state_key == GdssValue.DESCENDANTS_KEY or state_key == GdssValue.VARS_KEY or state_key.ends_with("()"):
			continue
		if overlay.has(state_key):
			continue
		var state_dict: Variant = entry.get(state_key)
		if not state_dict is Dictionary:
			continue
		for prop_name: String in (all_overrides as Dictionary):
			(state_dict as Dictionary).set(prop_name, (all_overrides as Dictionary).get(prop_name))


static func build_override_entry(override_meta: Variant) -> Dictionary:
	if override_meta is String:
		return GdssParser.parse_override_entry(override_meta)
	if override_meta is Dictionary:
		return {"all": (override_meta as Dictionary).duplicate()}
	return {}


static func resolve_override_patches(base: Dictionary, override_entry: Dictionary) -> Dictionary:
	var has_patch: bool = false
	for state_key: String in override_entry:
		var state_dict: Variant = override_entry.get(state_key)
		if not state_dict is Dictionary:
			continue
		for prop_name: String in (state_dict as Dictionary):
			var raw: Variant = (state_dict as Dictionary).get(prop_name)
			if raw is Dictionary and (raw as Dictionary).has(GdssValue.COMPOSITE4_PATCH_KEY):
				has_patch = true
	if not has_patch:
		return override_entry
	var resolved: Dictionary = override_entry.duplicate(true)
	for state_key: String in resolved:
		var state_dict: Variant = resolved.get(state_key)
		if not state_dict is Dictionary:
			continue
		for prop_name: String in (state_dict as Dictionary):
			var raw: Variant = (state_dict as Dictionary).get(prop_name)
			if not (raw is Dictionary and (raw as Dictionary).has(GdssValue.COMPOSITE4_PATCH_KEY)):
				continue
			var patch: Dictionary = (raw as Dictionary).get(GdssValue.COMPOSITE4_PATCH_KEY)
			var scratch: Dictionary = {prop_name: _base_composite_value(base, state_key, prop_name)}
			for index: Variant in patch:
				GdssValue.fold_composite_component(scratch, prop_name, int(index), patch.get(index))
			(state_dict as Dictionary).set(prop_name, scratch.get(prop_name))
	return resolved


static func _base_composite_value(base: Dictionary, state_key: String, prop_name: String) -> Variant:
	var raw: Variant = raw_value(base, state_key, prop_name)
	if raw != null:
		return raw if not raw is Dictionary else (raw as Dictionary).duplicate(true)
	var prop: GdssProp = GDSS.get_registry().property_list.get(prop_name)
	return prop.get_default_value() if prop != null else Vector4i.ZERO


static func styled_props(entry: Dictionary) -> Dictionary:
	var props: Dictionary = {}
	for key: String in entry:
		if key == GdssValue.CLASSES_KEY or key == GdssValue.VARIATIONS_KEY or key == GdssValue.DESCENDANTS_KEY or key == GdssValue.VARS_KEY:
			continue
		var state_dict: Variant = entry.get(key)
		if state_dict is Dictionary:
			for prop_name: String in state_dict as Dictionary:
				props.set(prop_name, true)
	return props


static func raw_value(entry: Dictionary, state: String, key: String) -> Variant:
	var sd: Variant = entry.get(state)
	if sd is Dictionary:
		var v: Variant = (sd as Dictionary).get(key)
		if v != null:
			return v
	var ad: Variant = entry.get("all")
	if ad is Dictionary:
		var v2: Variant = (ad as Dictionary).get(key)
		if v2 != null:
			return v2
	return null
