extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")

const FIXTURE: String = """
@instance var tint: "#111111"

Button {
	bg_color: "#202020"
	border_color: $tint
	Ghost {
		bg_color: "#00ff00"
	}
	Fancy {
		bg_color: linear_gradient("#ff0000", "#0000ff")
	}
}
"""


func _vals(button: Button) -> Dictionary:
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	return stylebox._build_style_vals(stylebox._resolve_gdss_node(), stylebox._resolve_entry(), stylebox._get_state())


func _shared(button: Button) -> GdssSharedEntry:
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	stylebox._resolve_entry()
	return stylebox._shared


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	var plain_a: Button = t.make_styled_button()
	var plain_b: Button = t.make_styled_button()
	var ghost_a: Button = t.make_styled_button()
	var ghost_b: Button = t.make_styled_button()
	GDSS.add_class(ghost_a, "Ghost")
	GDSS.add_class(ghost_b, "Ghost")
	t.check(_shared(plain_a) != null and _shared(plain_a) == _shared(plain_b), "nodes with the same styling share one entry")
	t.check(_shared(ghost_a) != null and _shared(ghost_a) == _shared(ghost_b), "nodes with the same classes share one merged entry")
	t.check(_shared(ghost_a) != _shared(plain_a), "different classes do not share")
	t.check_eq(_vals(ghost_a).get("bg_color"), Color("#00ff00"), "a shared class entry resolves its own values")
	t.check_eq(_vals(plain_a).get("bg_color"), Color("#202020"), "the base entry is untouched by the class entry")
	GDSS.set_prop_override(plain_b, "bg_color", Color.RED)
	t.check(_shared(plain_b) == null, "a node with its own overrides opts out of sharing")
	t.check_eq(_vals(plain_b).get("bg_color"), Color.RED, "the override still applies")
	t.check_eq(_vals(plain_a).get("bg_color"), Color("#202020"), "another node's override does not leak into the shared entry")
	GDSS.set_instance_var(plain_a, "tint", Color("#abcdef"))
	t.check_eq(_vals(plain_a).get("border_color"), Color("#abcdef"), "instance vars stay per node")
	t.check_eq(_vals(ghost_a).get("border_color"), Color("#111111"), "other nodes keep the default instance var")
	var fancy_a: Button = t.make_styled_button()
	var fancy_b: Button = t.make_styled_button()
	GDSS.add_class(fancy_a, "Fancy")
	GDSS.add_class(fancy_b, "Fancy")
	var grad_a: Variant = _vals(fancy_a).get("bg_color")
	var grad_b: Variant = _vals(fancy_b).get("bg_color")
	t.check(grad_a is GdssGradient and grad_b is GdssGradient, "gradient fills resolve on shared entries")
	t.check(grad_a != grad_b, "node-specific values are not shared between nodes")
	t.apply_fixture(FIXTURE.replace("#202020", "#303030"))
	GDSS.refresh(plain_a)
	t.check_eq(_vals(plain_a).get("bg_color"), Color("#303030"), "a reparsed sheet does not reuse stale shared entries")
