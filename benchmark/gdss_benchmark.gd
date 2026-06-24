extends Control

const COUNTS: Array[int] = [200, 1000, 3000]
const TIMING_RUNS: int = 5
const FRAME_SAMPLES: int = 120
const RENDER_PANELS: int = 80
const ANIM_NODES: int = 600

@export var output: RichTextLabel

var _accent: Color = Color("#3b82f6")
var _vanilla_theme: Theme
var _buf: PackedStringArray = []


func _ready() -> void:
	get_window().warp_mouse(Vector2(-4000, -4000))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if output != null:
		var mono: SystemFont = SystemFont.new()
		mono.font_names = PackedStringArray(["Menlo", "Consolas", "Courier New", "monospace"])
		output.add_theme_font_override("normal_font", mono)
		output.add_theme_font_override("bold_font", mono)
		output.add_theme_font_override("italics_font", mono)
		output.add_theme_font_size_override("normal_font_size", 13)
		output.add_theme_color_override("default_color", Color("#d7dae3"))
	_vanilla_theme = _build_vanilla_theme()
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()


func _run() -> void:
	_header()
	for count: int in COUNTS:
		await _suite(count)
	await _render_section()
	_emit("\n[i]* GDSS-exclusive benchmark (no vanilla Theme runtime equivalent).")
	_emit("Lower ms / higher FPS is better; timings are best-of-%d.[/i]" % TIMING_RUNS)
	_flush()


func _suite(n: int) -> void:
	_emit("\n[b]====== %d nodes ======[/b]" % n)
	
	var inst: Dictionary = await _bench_instantiate(n)
	_row("Instantiate (create nodes)", "%.2f ms (%.4f/node)" % [inst.get("gdss_inst"), inst.get("gdss_inst") / n], "%.2f ms (%.4f/node)" % [inst.get("van_inst"), inst.get("van_inst") / n], "%.1fx (%s)" % [inst.get("gdss_inst") / maxf(inst.get("van_inst"), 0.0001), _pct(inst.get("gdss_inst"), inst.get("van_inst"))])
	_row("Bind (enter tree)", "%.2f ms (%.4f/node)" % [inst.get("gdss_bind"), inst.get("gdss_bind") / n], "%.2f ms (%.4f/node)" % [inst.get("van_bind"), inst.get("van_bind") / n], "%.1fx (%s)" % [inst.get("gdss_bind") / maxf(inst.get("van_bind"), 0.0001), _pct(inst.get("gdss_bind"), inst.get("van_bind"))])
	
	var mem: Dictionary = await _bench_memory(n)
	_row("Memory: objects added", "%d (%.2f/node)" % [mem.get("gdss_obj"), float(mem.get("gdss_obj")) / n], "%d (%.2f/node)" % [mem.get("van_obj"), float(mem.get("van_obj")) / n], "%+d (%s)" % [mem.get("gdss_obj") - mem.get("van_obj"), _pct(mem.get("gdss_obj"), mem.get("van_obj"))])
	_row("Memory: static KiB", "%.0f (%.3f/node)" % [mem.get("gdss_kb"), mem.get("gdss_kb") / n], "%.0f (%.3f/node)" % [mem.get("van_kb"), mem.get("van_kb") / n], "%+.0f KiB (%s)" % [mem.get("gdss_kb") - mem.get("van_kb"), _pct(mem.get("gdss_kb"), mem.get("van_kb"))])
	
	var draw: Dictionary = await _bench_draw(n)
	_row("Steady-state FPS (visible)", "%.0f fps (%.3f ms)" % [draw.get("gdss_fps"), draw.get("gdss_ms")], "%.0f fps (%.3f ms)" % [draw.get("van_fps"), draw.get("van_ms")], "%+.3f ms (%s)" % [draw.get("gdss_ms") - draw.get("van_ms"), _pct(draw.get("gdss_ms"), draw.get("van_ms"))])
	
	var st: Dictionary = await _bench_state_restyle(n)
	_row("State change (disable all)", "%.2f ms (%.4f/node)" % [st.get("gdss"), st.get("gdss") / n], "%.2f ms (%.4f/node)" % [st.get("vanilla"), st.get("vanilla") / n], "%.1fx (%s)" % [st.get("gdss") / maxf(st.get("vanilla"), 0.0001), _pct(st.get("gdss"), st.get("vanilla"))])
	
	var reparent: Dictionary = await _bench_reparent(n)
	_row("Reparent all", "%.2f ms (%.4f/node)" % [reparent.get("gdss"), reparent.get("gdss") / n], "%.2f ms (%.4f/node)" % [reparent.get("vanilla"), reparent.get("vanilla") / n], "%.1fx (%s)" % [reparent.get("gdss") / maxf(reparent.get("vanilla"), 0.0001), _pct(reparent.get("gdss"), reparent.get("vanilla"))])
	
	var teardown: Dictionary = await _bench_teardown(n)
	_row("Teardown (free all)", "%.2f ms" % teardown.get("gdss"), "%.2f ms" % teardown.get("vanilla"), "%s | orphans left: %d" % [_pct(teardown.get("gdss"), teardown.get("vanilla")), teardown.get("orphans")])
	
	var scheme: float = await _bench_scheme(n)
	_row("Scheme switch (light/dark) *", "%.2f ms (%.4f/node)" % [scheme, scheme / n], "n/a", "")
	var gvar: float = await _bench_global_var(n)
	_row("Global var refresh (accent) *", "%.2f ms (%.4f/node)" % [gvar, gvar / n], "n/a", "")
	var ivar: float = await _bench_instance_var(n)
	_row("Per-instance var set *", "%.2f ms (%.4f/node)" % [ivar, ivar / n], "n/a", "")
	var refr: float = await _bench_refresh(n)
	_row("Refresh / reapply all *", "%.2f ms (%.4f/node)" % [refr, refr / n], "n/a", "")
	var addcls: float = await _bench_add_class(n)
	_row("Add class (restyle all) *", "%.2f ms (%.4f/node)" % [addcls, addcls / n], "n/a", "")


func _bench_instantiate(n: int) -> Dictionary:
	var gi: float = INF
	var gb: float = INF
	for r: int in TIMING_RUNS:
		var t0: int = Time.get_ticks_usec()
		var root: Node = _build_gdss(n, false)
		gi = minf(gi, (Time.get_ticks_usec() - t0) / 1000.0)
		var t1: int = Time.get_ticks_usec()
		get_tree().root.add_child(root)
		gb = minf(gb, (Time.get_ticks_usec() - t1) / 1000.0)
		root.queue_free()
		await _wait(6)
	var vi: float = INF
	var vb: float = INF
	for r: int in TIMING_RUNS:
		var t0: int = Time.get_ticks_usec()
		var root: Node = _build_vanilla(n, false)
		vi = minf(vi, (Time.get_ticks_usec() - t0) / 1000.0)
		var t1: int = Time.get_ticks_usec()
		get_tree().root.add_child(root)
		vb = minf(vb, (Time.get_ticks_usec() - t1) / 1000.0)
		root.queue_free()
		await _wait(6)
	return {"gdss_inst": gi, "gdss_bind": gb, "van_inst": vi, "van_bind": vb}


func _bench_memory(n: int) -> Dictionary:
	await _wait(8)
	var o0: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var m0: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var groot: Node = _build_gdss(n, false)
	get_tree().root.add_child(groot)
	await _wait(8)
	var go: int = int(Performance.get_monitor(Performance.OBJECT_COUNT)) - o0 - 1
	var gkb: float = (Performance.get_monitor(Performance.MEMORY_STATIC) - m0) / 1024.0
	groot.queue_free()
	await _wait(10)
	var o1: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var m1: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var vroot: Node = _build_vanilla(n, false)
	get_tree().root.add_child(vroot)
	await _wait(8)
	var vo: int = int(Performance.get_monitor(Performance.OBJECT_COUNT)) - o1 - 1
	var vkb: float = (Performance.get_monitor(Performance.MEMORY_STATIC) - m1) / 1024.0
	vroot.queue_free()
	await _wait(10)
	return {"gdss_obj": go, "van_obj": vo, "gdss_kb": gkb, "van_kb": vkb}


func _bench_draw(n: int) -> Dictionary:
	var groot: Node = _build_gdss(n, true)
	add_child(groot)
	await _wait(20)
	var gms: float = await _avg_frame_ms()
	groot.queue_free()
	await _wait(10)
	var vroot: Node = _build_vanilla(n, true)
	add_child(vroot)
	await _wait(20)
	var vms: float = await _avg_frame_ms()
	vroot.queue_free()
	await _wait(10)
	return {"gdss_ms": gms, "gdss_fps": 1000.0 / maxf(gms, 0.0001), "van_ms": vms, "van_fps": 1000.0 / maxf(vms, 0.0001)}


func _bench_state_restyle(n: int) -> Dictionary:
	var gms: float = await _disable_all_ms(_build_gdss(n, false))
	var vms: float = await _disable_all_ms(_build_vanilla(n, false))
	return {"gdss": gms, "vanilla": vms}


func _disable_all_ms(root: Node) -> float:
	get_tree().root.add_child(root)
	await _wait(8)
	var t0: int = Time.get_ticks_usec()
	for b: Node in root.get_children():
		(b as Button).disabled = true
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	root.queue_free()
	await _wait(8)
	return ms


func _bench_scheme(n: int) -> float:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var best: float = INF
	for r: int in TIMING_RUNS:
		var target: String = "light" if r % 2 == 0 else "dark"
		var t0: int = Time.get_ticks_usec()
		GDSS.set_scheme(target)
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		await _wait(2)
	GDSS.set_scheme("dark")
	root.queue_free()
	await _wait(8)
	return best


func _bench_global_var(n: int) -> float:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var best: float = INF
	for r: int in TIMING_RUNS:
		var t0: int = Time.get_ticks_usec()
		GDSS.set_global_var("accent", Color(randf(), randf(), randf()))
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		await _wait(2)
	GDSS.set_global_var("accent", _accent)
	root.queue_free()
	await _wait(8)
	return best


func _bench_teardown(n: int) -> Dictionary:
	var groot: Node = _build_gdss(n, false)
	get_tree().root.add_child(groot)
	await _wait(8)
	var orphan0: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var t0: int = Time.get_ticks_usec()
	groot.free()
	var gms: float = (Time.get_ticks_usec() - t0) / 1000.0
	await _wait(8)
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphan0
	var vroot: Node = _build_vanilla(n, false)
	get_tree().root.add_child(vroot)
	await _wait(8)
	t0 = Time.get_ticks_usec()
	vroot.free()
	var vms: float = (Time.get_ticks_usec() - t0) / 1000.0
	await _wait(8)
	return {"gdss": gms, "vanilla": vms, "orphans": orphans}


func _render_section() -> void:
	_emit("\n[b]====== Rendering: %d panels over a textured backdrop (FPS, vsync off) ======[/b]" % RENDER_PANELS)
	var r: Dictionary = await _bench_rendering()
	_emit("  Solid fill (GPU)         %.0f fps (%.3f ms)" % [r.get("solid"), 1000.0 / maxf(r.get("solid"), 0.0001)])
	_emit("  linear_gradient() fill   %.0f fps (%.3f ms)   [%.0f%% of solid fps]" % [r.get("gradient"), 1000.0 / maxf(r.get("gradient"), 0.0001), r.get("gradient") / maxf(r.get("solid"), 0.0001) * 100.0])
	if r.get("blur") >= 0.0:
		_emit("  blur() glass             %.0f fps (%.3f ms)   [%.0f%% of solid fps]" % [r.get("blur"), 1000.0 / maxf(r.get("blur"), 0.0001), r.get("blur") / maxf(r.get("solid"), 0.0001) * 100.0])
	else:
		_emit("  blur() glass             skipped (theme has no FrostedButton class)")
	if r.get("liquid") >= 0.0:
		_emit("  liquid_blur() glass      %.0f fps (%.3f ms)   [%.0f%% of solid fps]" % [r.get("liquid"), 1000.0 / maxf(r.get("liquid"), 0.0001), r.get("liquid") / maxf(r.get("solid"), 0.0001) * 100.0])
	else:
		_emit("  liquid_blur() glass      skipped (theme has no LiquidButton class)")
	var gpu_ms: float = 1000.0 / maxf(r.get("gpu"), 0.0001)
	var cpu_ms: float = 1000.0 / maxf(r.get("cpu"), 0.0001)
	_emit("  Solid panel draw mode    GPU %.0f fps (%.3f ms)  |  CPU %.0f fps (%.3f ms)  |  GPU %s" % [r.get("gpu"), gpu_ms, r.get("cpu"), cpu_ms, _pct(gpu_ms, cpu_ms)])
	var anim: Dictionary = await _bench_animating(ANIM_NODES)
	_emit("  %d nodes idle vs animating: idle %.0f fps (%.3f ms)  |  scheme-tweening %.0f fps (%.3f ms)  |  %s *" % [ANIM_NODES, anim.get("idle"), 1000.0 / maxf(anim.get("idle"), 0.0001), anim.get("anim"), 1000.0 / maxf(anim.get("anim"), 0.0001), _pct(1000.0 / maxf(anim.get("anim"), 0.0001), 1000.0 / maxf(anim.get("idle"), 0.0001))])


func _bench_rendering() -> Dictionary:
	var icon: Texture2D = load("res://meta/icon.png") as Texture2D
	_inject_gradient_class()
	var have_blur: bool = _has_button_class("FrostedButton")
	var have_liquid: bool = _has_button_class("LiquidButton")
	var solid: float = await _render_fps("", icon)
	var gradient: float = await _render_fps("BenchGradient", icon)
	var blur_fps: float = await _render_fps("FrostedButton", icon) if have_blur else -1.0
	var liquid_fps: float = await _render_fps("LiquidButton", icon) if have_liquid else -1.0
	var orig: int = GDSS._gpu_panels
	GDSS._gpu_panels = 1
	var gpu: float = await _render_fps("", icon)
	GDSS._gpu_panels = 0
	var cpu: float = await _render_fps("", icon)
	GDSS._gpu_panels = orig
	return {"solid": solid, "gradient": gradient, "blur": blur_fps, "liquid": liquid_fps, "gpu": gpu, "cpu": cpu}


func _render_fps(button_class: String, backdrop: Texture2D) -> float:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)
	if backdrop != null:
		var tr: TextureRect = TextureRect.new()
		tr.texture = backdrop
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		root.add_child(tr)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 10
	grid.position = Vector2(40, 40)
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	for i: int in RENDER_PANELS:
		var b: Button = Button.new()
		b.text = "panel"
		b.custom_minimum_size = Vector2(96, 64)
		if not button_class.is_empty():
			b.set_meta(GDSS.CLASSES_META, PackedStringArray([button_class]))
		grid.add_child(b)
	root.add_child(grid)
	add_child(root)
	await _wait(24)
	var ms: float = await _avg_frame_ms()
	root.queue_free()
	await _wait(12)
	return 1000.0 / maxf(ms, 0.0001)


func _has_button_class(name: String) -> bool:
	var btn: Dictionary = GdssInterpreter.parsed.get("Button", {})
	var classes: Dictionary = btn.get("_classes", {})
	return classes.has(name)


func _bench_reparent(n: int) -> Dictionary:
	var g: float = await _reparent_ms(_build_gdss(n, false), true)
	var v: float = await _reparent_ms(_build_vanilla(n, false), false)
	return {"gdss": g, "vanilla": v}


func _reparent_ms(root: Node, gdss_dest: bool) -> float:
	get_tree().root.add_child(root)
	var dest: Control = Control.new()
	if gdss_dest:
		dest.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)
	else:
		dest.theme = _vanilla_theme
	get_tree().root.add_child(dest)
	await _wait(8)
	var kids: Array[Node] = root.get_children()
	var t0: int = Time.get_ticks_usec()
	for b: Node in kids:
		root.remove_child(b)
		dest.add_child(b)
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	root.queue_free()
	dest.queue_free()
	await _wait(10)
	return ms


func _bench_instance_var(n: int) -> float:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var kids: Array[Node] = root.get_children()
	var best: float = INF
	for r: int in TIMING_RUNS:
		var t0: int = Time.get_ticks_usec()
		for b: Node in kids:
			GDSS.set_instance_var(b, "glass_strength", float(r + 1))
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		await _wait(2)
	root.queue_free()
	await _wait(8)
	return best


func _bench_refresh(n: int) -> float:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var kids: Array[Node] = root.get_children()
	var best: float = INF
	for r: int in TIMING_RUNS:
		var t0: int = Time.get_ticks_usec()
		for b: Node in kids:
			GDSS.refresh(b)
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		await _wait(2)
	root.queue_free()
	await _wait(8)
	return best


func _bench_add_class(n: int) -> float:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var t0: int = Time.get_ticks_usec()
	for b: Node in root.get_children():
		GDSS.add_class(b, "GhostButton")
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	root.queue_free()
	await _wait(8)
	return ms


func _bench_animating(count: int) -> Dictionary:
	var root: Node = _build_gdss(count, true)
	add_child(root)
	await _wait(20)
	var idle_ms: float = await _avg_frame_ms()
	GDSS.set_scheme("light", 6.0)
	var anim_ms: float = await _avg_frame_ms()
	GDSS.set_scheme("dark")
	root.queue_free()
	await _wait(10)
	return {"idle": 1000.0 / maxf(idle_ms, 0.0001), "anim": 1000.0 / maxf(anim_ms, 0.0001)}


func _inject_gradient_class() -> void:
	var btn: Dictionary = GdssInterpreter.parsed.get("Button", {})
	if btn.is_empty():
		return
	var classes: Dictionary = btn.get("_classes", {})
	classes["BenchGradient"] = {"all": {"bg_color": {"__gdss_method__": "linear_gradient", "args": ["RED", "BLUE", "90"]}}, "_classes": {}}


func _build_gdss(n: int, visible_grid: bool) -> Node:
	var root: Control = _make_root(visible_grid)
	root.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)
	for i: int in n:
		var b: Button = Button.new()
		b.text = "Item %d" % i
		root.add_child(b)
	return root


func _build_vanilla(n: int, visible_grid: bool) -> Node:
	var root: Control = _make_root(visible_grid)
	root.theme = _vanilla_theme
	for i: int in n:
		var b: Button = Button.new()
		b.text = "Item %d" % i
		root.add_child(b)
	return root


func _make_root(visible_grid: bool) -> Control:
	if visible_grid:
		var grid: GridContainer = GridContainer.new()
		grid.columns = 32
		grid.position = Vector2(0, 120)
		return grid
	return Control.new()


func _build_vanilla_theme() -> Theme:
	var theme: Theme = Theme.new()
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = _accent
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 9
	normal.content_margin_bottom = 9
	theme.set_stylebox("normal", "Button", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = _accent.lightened(0.08)
	theme.set_stylebox("hover", "Button", hover)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = _accent.darkened(0.1)
	theme.set_stylebox("pressed", "Button", pressed)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = _accent.darkened(0.3)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_color", "Button", Color.WHITE)
	return theme


func _avg_frame_ms() -> float:
	var t0: int = Time.get_ticks_usec()
	for i: int in FRAME_SAMPLES:
		await get_tree().process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / FRAME_SAMPLES


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _header() -> void:
	var v: Dictionary = Engine.get_version_info()
	_emit("[b]=======================================================[/b]")
	_emit("[b]  GDSS Benchmark[/b]  |  Godot %s  |  %s  |  %s" % [v.get("string"), OS.get_name(), RenderingServer.get_video_adapter_name()])
	_emit("[b]=======================================================[/b]")
	_emit("[i]Same Button nodes styled by GDSS (theme.tgdss) vs a shared vanilla Theme")
	_emit("with matching styleboxes. Timings are best-of-%d; FPS is averaged over %d" % [TIMING_RUNS, FRAME_SAMPLES])
	_emit("frames with vsync off. Columns: GDSS | Vanilla | Delta.[/i]")
	_emit("")
	_emit("%-30s %-26s %-26s %s" % ["Metric", "GDSS", "Vanilla Theme", "Delta"])
	_emit("%s" % "-".repeat(95))


func _pct(gdss: float, vanilla: float) -> String:
	if absf(vanilla) < 0.00001:
		return "n/a"
	return "%+.0f%%" % ((gdss - vanilla) / vanilla * 100.0)


func _row(metric: String, gdss: String, vanilla: String, delta: String) -> void:
	_emit("%-30s %-26s %-26s %s" % [metric, gdss, vanilla, delta])


func _emit(line: String) -> void:
	_buf.append(line)
	print(_strip_bbcode(line))
	if output != null:
		output.append_text(line + "\n")


func _flush() -> void:
	pass


func _strip_bbcode(s: String) -> String:
	var rx: RegEx = RegEx.create_from_string("\\[/?[a-z][^\\]]*\\]")
	return rx.sub(s, "", true)
