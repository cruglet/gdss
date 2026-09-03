extends RefCounted


const TC: GDScript = preload("res://tests/gdss_test_context.gd")
const InspectorPlugin: GDScript = preload("res://addons/gdss/editor/plugins/gdss_inspector_plugin.gd")

const FIXTURE: String = """
Button {
	bg_color: "#223344"
}
"""


func run(t: TC) -> void:
	t.apply_fixture(FIXTURE)
	_check_container_host(t)
	_check_nested_hosts(t)
	_check_self_modes(t)
	_check_inspector_reach(t)


func _check_container_host(t: TC) -> void:
	var outer: Control = Control.new()
	outer.set_meta(GDSS.MODE_META, GDSS.GdssMode.DISABLE)
	t.add_styled(outer)
	var container: CenterContainer = CenterContainer.new()
	outer.add_child(container)
	var button: Button = Button.new()
	container.add_child(button)
	t.check(not GDSS._get_node_types().has("CenterContainer"), "CenterContainer has nothing of its own to style")
	t.check(not GdssNodeBinder.is_bound(button), "a child of a disabled subtree stays unbound")
	GDSS.enable_gdss(container)
	t.check(GdssNodeBinder.is_bound(button), "enabling an unstyleable container binds its children")
	t.check(not GdssNodeBinder.is_bound(container), "the container itself binds nothing")
	t.check(GDSS.resolve_mode(container), "the container resolves as enabled")
	var late: Button = Button.new()
	container.add_child(late)
	t.check(GdssNodeBinder.is_bound(late), "a child added later inherits the enabled subtree")
	GDSS.disable_gdss(container)
	t.check(not GdssNodeBinder.is_bound(button), "disabling the container unbinds its children again")
	GDSS.set_gdss_mode(container, GDSS.GdssMode.INHERIT)
	t.check(not GdssNodeBinder.is_bound(button), "back on inherit the disabled ancestor wins")
	outer.free()


func _check_nested_hosts(t: TC) -> void:
	var outer: Control = Control.new()
	outer.set_meta(GDSS.MODE_META, GDSS.GdssMode.DISABLE)
	t.add_styled(outer)
	var host: Control = Control.new()
	outer.add_child(host)
	var middle: CenterContainer = CenterContainer.new()
	host.add_child(middle)
	var button: Button = Button.new()
	middle.add_child(button)
	GDSS.enable_gdss(host)
	t.check(GdssNodeBinder.is_bound(button), "styling reaches through two unstyleable levels")
	var stylebox: GdssStylebox = GdssNodeBinder.get_primary_stylebox(button)
	t.check(stylebox != null and stylebox._get_val("bg_color") == Color("#223344"), "the inherited node is styled")
	GDSS.set_gdss_mode(middle, GDSS.GdssMode.DISABLE)
	t.check(not GdssNodeBinder.is_bound(button), "a nearer unstyleable node can veto the host")
	GDSS.set_gdss_mode(middle, GDSS.GdssMode.INHERIT)
	t.check(GdssNodeBinder.is_bound(button), "clearing the veto restores the host's mode")
	outer.free()


func _check_self_modes(t: TC) -> void:
	var outer: Control = Control.new()
	outer.set_meta(GDSS.MODE_META, GDSS.GdssMode.DISABLE)
	t.add_styled(outer)
	var container: CenterContainer = CenterContainer.new()
	outer.add_child(container)
	var button: Button = Button.new()
	container.add_child(button)
	GDSS.enable_gdss_self(container)
	t.check(not GdssNodeBinder.is_bound(button), "enable (self) on an unstyleable node leaves children resolving upwards")
	t.check(GDSS.resolve_mode(container), "enable (self) still resolves for the node itself")
	outer.free()


func _check_inspector_reach(t: TC) -> void:
	var control: Control = Control.new()
	var container: CenterContainer = CenterContainer.new()
	var button: Button = Button.new()
	var window: Window = Window.new()
	var plain: Node = Node.new()
	t.check(InspectorPlugin.handles(control), "a plain Control gets the GDSS mode row")
	t.check(InspectorPlugin.handles(container), "an unstyleable container gets the GDSS mode row")
	t.check(InspectorPlugin.handles(button), "styleable nodes still get it")
	t.check(InspectorPlugin.handles(window), "Window-derived nodes get it too")
	t.check(not InspectorPlugin.handles(plain), "nodes without a theme are left alone")
	control.free()
	container.free()
	button.free()
	window.free()
	plain.free()
