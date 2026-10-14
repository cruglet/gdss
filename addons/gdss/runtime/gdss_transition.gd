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
