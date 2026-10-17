@tool
class_name GdssValue
extends RefCounted

const REF_PREFIX: String = "__gdss_"
const GLOBAL_REF: String = "__gdss_global__"
const INSTANCE_REF: String = "__gdss_instance__"
const LOCAL_REF: String = "__gdss_local__"
const LOCAL_METHOD_REF: String = "__gdss_local_method__"
const METHOD_KEY: String = "__gdss_method__"
const CALC_KEY: String = "__gdss_calc__"
const COMPOSITE2_KEY: String = "__gdss_composite2__"
const COMPOSITE4_KEY: String = "__gdss_composite4__"
const COMPOSITE4_PATCH_KEY: String = "__gdss_composite4_patch__"
const COLOR4_KEY: String = "__gdss_color4__"
const SCOPED_TIME_KEY: String = "__gdss_scoped_time__"
const SCOPED_TIME_ANY: String = "*"
const SCHEME_PARENT_KEY: String = "__gdss_extends__"
const CLASSES_KEY: String = "_classes"
const VARIATIONS_KEY: String = "_variations"
const DESCENDANTS_KEY: String = "_descendants"
const VARS_KEY: String = "_vars"
const ANCESTOR_STATE_PREFIX: String = "@"
const LEGACY_EVENTS: Dictionary[String, String] = {
	"on_pressed": "pressed",
	"on_focus": "focus_entered",
	"on_blur": "focus_exited",
	"on_mouse_entered": "mouse_entered",
	"on_mouse_exited": "mouse_exited",
	"on_toggled": "toggled",
}


static func merge_scoped_time(existing: Variant, incoming: Variant) -> Variant:
	if incoming == null:
		return existing
	if existing == null:
		return incoming
	var existing_scoped: bool = existing is Dictionary and (existing as Dictionary).has(SCOPED_TIME_KEY)
	var incoming_scoped: bool = incoming is Dictionary and (incoming as Dictionary).has(SCOPED_TIME_KEY)
	if not existing_scoped and not incoming_scoped:
		return incoming
	var map: Dictionary = {}
	if existing_scoped:
		map = (existing.get(SCOPED_TIME_KEY) as Dictionary).duplicate()
	elif existing is int or existing is float:
		map.set(SCOPED_TIME_ANY, float(existing))
	if incoming_scoped:
		map.merge(incoming.get(SCOPED_TIME_KEY) as Dictionary, true)
	elif incoming is int or incoming is float:
		map.set(SCOPED_TIME_ANY, float(incoming))
	return {SCOPED_TIME_KEY: map}


static func fold_composite_component(container: Dictionary, parent_prop: String, index: int, value: Variant, as_patch: bool = false) -> void:
	var existing: Variant = container.get(parent_prop)
	var parent: GdssProp = GDSS.get_registry().property_list.get(parent_prop)
	var is_color: bool = existing is Color \
		or (existing is Dictionary and (existing as Dictionary).has(COLOR4_KEY)) \
		or (parent != null and parent.type == GDSS.Type.COLOR)
	if value is Dictionary and not is_color:
		return
	if as_patch and (existing == null or (existing is Dictionary and (existing as Dictionary).has(COMPOSITE4_PATCH_KEY))):
		var patch: Dictionary = (existing as Dictionary).get(COMPOSITE4_PATCH_KEY) if existing is Dictionary else {}
		patch.set(index, value)
		container.set(parent_prop, {COMPOSITE4_PATCH_KEY: patch})
		return
	if existing == null:
		existing = parent.get_default_value() if parent != null else Vector4i.ZERO
	if is_color:
		var sides: Array = []
		if existing is Dictionary and (existing as Dictionary).has(COLOR4_KEY):
			sides = (existing as Dictionary).get(COLOR4_KEY)
		else:
			sides = [existing, existing, existing, existing]
		sides.set(index, value)
		container.set(parent_prop, {COLOR4_KEY: sides})
		return
	var is_vec2: bool = existing is Vector2 \
		or (existing is Dictionary and (existing as Dictionary).has(COMPOSITE2_KEY)) \
		or (parent != null and parent.type == GDSS.Type.VECTOR2)
	var is_ref: bool = value is String and (value as String).begins_with(REF_PREFIX)
	var sentinel: String = COMPOSITE2_KEY if is_vec2 else COMPOSITE4_KEY
	if existing is Dictionary and (existing as Dictionary).has(sentinel):
		var parts: Array = (existing as Dictionary).get(sentinel)
		if index < parts.size():
			parts.set(index, String(value) if is_ref else (str(float(value)) if is_vec2 else str(int(value))))
		container.set(parent_prop, existing)
		return
	if is_vec2:
		var vec2: Vector2 = existing if existing is Vector2 else Vector2.ZERO
		if is_ref:
			var parts2: Array = [str(vec2.x), str(vec2.y)]
			parts2.set(index, value)
			container.set(parent_prop, {COMPOSITE2_KEY: parts2})
			return
		match index:
			0: vec2.x = float(value)
			1: vec2.y = float(value)
		container.set(parent_prop, vec2)
		return
	var vec: Vector4i = existing if existing is Vector4i else Vector4i.ZERO
	if is_ref:
		var parts: Array = [str(vec.x), str(vec.y), str(vec.z), str(vec.w)]
		parts.set(index, value)
		container.set(parent_prop, {COMPOSITE4_KEY: parts})
		return
	match index:
		0: vec.x = int(value)
		1: vec.y = int(value)
		2: vec.z = int(value)
		3: vec.w = int(value)
	container.set(parent_prop, vec)


static func resolve_base_composite_patches(selector_entry: Dictionary) -> void:
	var all_dict: Variant = selector_entry.get("all")
	if all_dict is Dictionary:
		_fold_state_patches(all_dict as Dictionary, {})
	for state_key: String in selector_entry:
		if state_key == "all" or state_key == CLASSES_KEY or state_key == VARIATIONS_KEY or state_key == DESCENDANTS_KEY or state_key == VARS_KEY:
			continue
		var sd: Variant = selector_entry.get(state_key)
		if sd is Dictionary:
			_fold_state_patches(sd as Dictionary, all_dict if all_dict is Dictionary else {})


static func _fold_state_patches(state_dict: Dictionary, base_all: Dictionary) -> void:
	for prop_name: String in state_dict.keys():
		var raw: Variant = state_dict.get(prop_name)
		if not (raw is Dictionary and (raw as Dictionary).has(COMPOSITE4_PATCH_KEY)):
			continue
		var patch: Dictionary = (raw as Dictionary).get(COMPOSITE4_PATCH_KEY)
		var base_val: Variant = base_all.get(prop_name)
		if base_val == null:
			var prop: GdssProp = GDSS.get_registry().property_list.get(prop_name)
			base_val = prop.get_default_value() if prop != null else Vector4i.ZERO
		var scratch: Dictionary = {prop_name: base_val if not base_val is Dictionary else (base_val as Dictionary).duplicate(true)}
		for index: Variant in patch:
			fold_composite_component(scratch, prop_name, int(index), patch.get(index))
		state_dict.set(prop_name, scratch.get(prop_name))


static func is_live(raw: Variant) -> bool:
	if raw is String:
		var s: String = raw as String
		return s.begins_with(GLOBAL_REF) or s.begins_with(INSTANCE_REF)
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		if d.has(COMPOSITE4_KEY) or d.has(COMPOSITE2_KEY):
			for part: Variant in d.get(COMPOSITE4_KEY, d.get(COMPOSITE2_KEY)):
				if part is String and ((part as String).begins_with(GLOBAL_REF) or (part as String).begins_with(INSTANCE_REF)):
					return true
			return false
		if d.has(COLOR4_KEY):
			for side: Variant in d.get(COLOR4_KEY):
				if is_live(side):
					return true
			return false
		if d.has(CALC_KEY):
			return GdssCalc.has_dynamic_ref(d.get(CALC_KEY))
		if not d.has(METHOD_KEY):
			return false
		for arg: Variant in d.get("args", []):
			if not arg is String:
				continue
			var a: String = (arg as String).strip_edges()
			if a.begins_with(GLOBAL_REF) or a.begins_with(INSTANCE_REF) or a.begins_with("$"):
				return true
	return false


static func is_shareable_live(raw: Variant) -> bool:
	return not is_node_specific(raw) and not may_read_instance(raw)


static func may_read_instance(raw: Variant) -> bool:
	if raw is String:
		var s: String = (raw as String).strip_edges()
		return s.begins_with(INSTANCE_REF) or s.begins_with(LOCAL_REF) or s.begins_with(LOCAL_METHOD_REF) or s.begins_with("$")
	if raw is Array:
		for item: Variant in raw as Array:
			if may_read_instance(item):
				return true
		return false
	if not raw is Dictionary:
		return false
	var d: Dictionary = raw as Dictionary
	if d.has(CALC_KEY):
		return true
	for key: Variant in d:
		if may_read_instance(d.get(key)):
			return true
	return false


static func is_node_specific(raw: Variant) -> bool:
	if raw is String:
		return (raw as String).begins_with(LOCAL_METHOD_REF)
	if not raw is Dictionary:
		return false
	var d: Dictionary = raw as Dictionary
	if d.has(COLOR4_KEY):
		for side: Variant in d.get(COLOR4_KEY):
			if is_node_specific(side):
				return true
		return false
	if not d.has(METHOD_KEY):
		return false
	var method: GdssMethod = GDSS._get_gdss_methods().get(d.get(METHOD_KEY))
	return method == null or method.returns_texture


static func splat_shorthand(key: String, value: Variant) -> Variant:
	if not (value is int or value is float):
		return value
	var prop: GdssProp = GDSS.get_registry().property_list.get(key)
	if prop == null:
		return value
	if prop.type == GDSS.Type.COMPOSITE4:
		return Vector4i(int(value), int(value), int(value), int(value))
	if prop.type == GDSS.Type.VECTOR2:
		return Vector2(float(value), float(value))
	return value
