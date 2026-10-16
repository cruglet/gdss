@tool
class_name GdssTransition
extends RefCounted

const _TRANSITION_FUNCS: Dictionary = {
	"LINEAR": Tween.TRANS_LINEAR, "SINE": Tween.TRANS_SINE, "QUINT": Tween.TRANS_QUINT,
	"QUART": Tween.TRANS_QUART, "QUAD": Tween.TRANS_QUAD, "EXPO": Tween.TRANS_EXPO,
	"ELASTIC": Tween.TRANS_ELASTIC, "CUBIC": Tween.TRANS_CUBIC, "CIRC": Tween.TRANS_CIRC,
	"BOUNCE": Tween.TRANS_BOUNCE, "BACK": Tween.TRANS_BACK, "SPRING": Tween.TRANS_SPRING,
}
const _EASE_TYPES: Dictionary = {
	"EASE_IN": Tween.EASE_IN, "EASE_OUT": Tween.EASE_OUT,
	"EASE_IN_OUT": Tween.EASE_IN_OUT, "EASE_OUT_IN": Tween.EASE_OUT_IN,
}


static func tween_trans(func_enum: GDSS.TransitionFunc) -> Tween.TransitionType:
	return _TRANSITION_FUNCS.get(GDSS.TransitionFunc.find_key(func_enum), Tween.TRANS_LINEAR)


static func tween_ease(type_enum: GDSS.TransitionType) -> Tween.EaseType:
	return _EASE_TYPES.get(GDSS.TransitionType.find_key(type_enum), Tween.EASE_IN_OUT)


static func resolve_trans(raw: Variant) -> Tween.TransitionType:
	if raw is int or raw is float:
		var keys: Array = GDSS.TransitionFunc.keys()
		var index: int = int(raw)
		if index >= 0 and index < keys.size():
			return _TRANSITION_FUNCS.get(keys.get(index), Tween.TRANS_LINEAR)
		return Tween.TRANS_LINEAR
	return _TRANSITION_FUNCS.get(raw, Tween.TRANS_LINEAR)


static func resolve_ease(raw: Variant) -> Tween.EaseType:
	if raw is int or raw is float:
		var keys: Array = GDSS.TransitionType.keys()
		var index: int = int(raw)
		if index >= 0 and index < keys.size():
			return _EASE_TYPES.get(keys.get(index), Tween.EASE_OUT)
		return Tween.EASE_OUT
	return _EASE_TYPES.get(raw, Tween.EASE_OUT)


static func time_for(raw: Variant, prop_name: String) -> float:
	if raw is Dictionary and (raw as Dictionary).has(GdssValue.SCOPED_TIME_KEY):
		var map: Dictionary = raw.get(GdssValue.SCOPED_TIME_KEY)
		if map.has(prop_name):
			return float(map.get(prop_name))
		return float(map.get(GdssValue.SCOPED_TIME_ANY, -1.0))
	return float(raw) if raw is int or raw is float else 0.0


static func time_in(raw: Variant, base_raw: Variant, prop_name: String) -> float:
	var seconds: float = time_for(raw, prop_name)
	if seconds >= 0.0:
		return seconds
	return maxf(time_for(base_raw, prop_name), 0.0)


static func longest_time(raw: Variant) -> float:
	if not (raw is Dictionary and (raw as Dictionary).has(GdssValue.SCOPED_TIME_KEY)):
		return float(raw) if raw is int or raw is float else 0.0
	var longest: float = 0.0
	for key: String in (raw.get(GdssValue.SCOPED_TIME_KEY) as Dictionary):
		longest = maxf(longest, float(raw.get(GdssValue.SCOPED_TIME_KEY).get(key)))
	return longest


static func tween_fallback(prop: GdssProp) -> Variant:
	var value: Variant = prop.get_default_value()
	match prop.type:
		GDSS.Type.COLOR:
			return value if value is Color else Color.TRANSPARENT
		GDSS.Type.COMPOSITE4:
			return value if value is Vector4i else Vector4i.ZERO
		GDSS.Type.VECTOR2:
			return value if value is Vector2 else Vector2.ZERO
		GDSS.Type.FLOAT:
			return float(value)
		GDSS.Type.INT:
			return int(value)
	return value


static func tween_pair(type: GDSS.Type, from_value: Variant, to_value: Variant, fallback: Variant) -> Array:
	if type == GDSS.Type.COLOR and (from_value is Array or to_value is Array):
		var sides_from: Array = GdssRenderer.side_colors(from_value, fallback)
		var sides_to: Array = GdssRenderer.side_colors(to_value, fallback)
		return [] if sides_from == sides_to else [sides_from, sides_to]
	var from: Variant = _tween_endpoint(type, from_value)
	var to: Variant = _tween_endpoint(type, to_value)
	if from == null or to == null or from == to:
		return []
	return [from, to]


static func _tween_endpoint(type: GDSS.Type, value: Variant) -> Variant:
	match type:
		GDSS.Type.COLOR:
			return value if value is Color else null
		GDSS.Type.COMPOSITE4:
			if value is Vector4i:
				return Vector4(value as Vector4i)
			return value if value is Vector4 else null
		GDSS.Type.VECTOR2:
			if value is int or value is float:
				return Vector2(float(value), float(value))
			return value if value is Vector2 else null
		GDSS.Type.FLOAT:
			return float(value) if value is int or value is float else null
		GDSS.Type.INT:
			return int(value) if value is int or value is float else null
	return null


static func lerp_value(from: Variant, to: Variant, t: float) -> Variant:
	if from is Color and to is Color:
		return (from as Color).lerp(to as Color, t)
	if from is Vector4 and to is Vector4:
		return (from as Vector4).lerp(to as Vector4, t)
	if from is Vector4i and to is Vector4i:
		return Vector4i(Vector4(from as Vector4i).lerp(Vector4(to as Vector4i), t))
	if from is Vector2 and to is Vector2:
		return (from as Vector2).lerp(to as Vector2, t)
	if (from is float or from is int) and (to is float or to is int):
		var result: float = lerpf(float(from), float(to), t)
		return int(round(result)) if from is int and to is int else result
	if from is Array and to is Array:
		var sides: Array = []
		for side: int in (from as Array).size():
			sides.append(lerp_value((from as Array).get(side), (to as Array).get(side), t))
		return sides
	return to

