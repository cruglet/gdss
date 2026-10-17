@tool
class_name GdssTransitionState
extends RefCounted

var tween: Tween = null
var values: Dictionary = {}
var args: Dictionary = {}
var style_values: Dictionary = {}
var style_live: Array[GdssProp] = []
var style_state: String = "￿"
