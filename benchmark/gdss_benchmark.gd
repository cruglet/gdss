extends Control

const COUNTS: Array[int] = [200, 1000, 3000]
const TIMING_RUNS: int = 5
const FRAME_SAMPLES: int = 120
const RENDER_PANELS: int = 80
const ANIM_NODES: int = 600
const LEAK_CYCLES: int = 5
const LEAK_NODES: int = 200
const OVERRIDE_TEXT: String = "bg_color: \"#8844ff\"\ncorner_radius: 16 16 16 16"
const PER_SIDE_TEXT: String = "corner_radius_top_left: 24"

@export var output: RichTextLabel

var _accent: Color = Color("#3b82f6")
var _vanilla_theme: Theme
var _buf: PackedStringArray = []
var _auto_quit: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg == "--auto-quit":
			_auto_quit = true
	_warp_mouse_away()
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
	_inject_bench_classes()
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()


func _run() -> void:
	_header()
	for count: int in COUNTS:
		await _suite(count)
	await _stability_section()
	await _render_section()
	_emit("\n[i]* GDSS-exclusive benchmark (no vanilla Theme runtime equivalent).")
	_emit("Lower ms / higher FPS is better. Timings show best-of-%d after a discarded" % TIMING_RUNS)
	_emit("warmup run, with the mean and standard deviation across runs.[/i]")
	if _auto_quit:
		await _wait(4)
		get_tree().quit()


func _suite(n: int) -> void:
	_emit("\n[b]====== %d nodes ======[/b]" % n)
	var inst: Dictionary = await _bench_instantiate(n)
	_row("Instantiate (create nodes)", _cell(inst.get("gdss_inst"), n), _cell(inst.get("van_inst"), n), _ratio(inst.get("gdss_inst"), inst.get("van_inst")))
	_row("Bind (enter tree)", _cell(inst.get("gdss_bind"), n), _cell(inst.get("van_bind"), n), _ratio(inst.get("gdss_bind"), inst.get("van_bind")))
	_row("First frame after bind", _cell(inst.get("gdss_frame"), n), _cell(inst.get("van_frame"), n), _ratio(inst.get("gdss_frame"), inst.get("van_frame")))
	var dup: Dictionary = await _bench_duplicate(n)
	_row("Duplicate + bind", _cell(dup.get("gdss"), n), _cell(dup.get("vanilla"), n), _ratio(dup.get("gdss"), dup.get("vanilla")))
	var mem: Dictionary = await _bench_memory(n)
	_row("Memory: objects added", "%d (%.2f/node)" % [mem.get("gdss_obj"), float(mem.get("gdss_obj")) / n], "%d (%.2f/node)" % [mem.get("van_obj"), float(mem.get("van_obj")) / n], "%+d (%s)" % [mem.get("gdss_obj") - mem.get("van_obj"), _pct(mem.get("gdss_obj"), mem.get("van_obj"))])
	_row("Memory: static KiB", "%.0f (%.3f/node)" % [mem.get("gdss_kb"), mem.get("gdss_kb") / n], "%.0f (%.3f/node)" % [mem.get("van_kb"), mem.get("van_kb") / n], "%+.0f KiB (%s)" % [mem.get("gdss_kb") - mem.get("van_kb"), _pct(mem.get("gdss_kb"), mem.get("van_kb"))])
	var draw: Dictionary = await _bench_draw(n)
	_row("Steady-state FPS (visible)", "%.0f fps (%.3f ms)" % [draw.get("gdss_fps"), draw.get("gdss_ms")], "%.0f fps (%.3f ms)" % [draw.get("van_fps"), draw.get("van_ms")], "%+.3f ms (%s)" % [draw.get("gdss_ms") - draw.get("van_ms"), _pct(draw.get("gdss_ms"), draw.get("van_ms"))])
	var st: Dictionary = await _bench_state_restyle(n)
	_row("State change (disable all)", _cell(st.get("gdss"), n), _cell(st.get("vanilla"), n), _ratio(st.get("gdss"), st.get("vanilla")))
	var reparent: Dictionary = await _bench_reparent(n)
	_row("Reparent all", _cell(reparent.get("gdss"), n), _cell(reparent.get("vanilla"), n), _ratio(reparent.get("gdss"), reparent.get("vanilla")))
	var teardown: Dictionary = await _bench_teardown(n)
	_row("Teardown (free all)", _plain_cell(teardown.get("gdss")), _plain_cell(teardown.get("vanilla")), "%s | orphans left: %d" % [_pct((teardown.get("gdss") as Dictionary).get("best"), (teardown.get("vanilla") as Dictionary).get("best")), teardown.get("orphans")])
	var scheme: Dictionary = await _bench_scheme(n)
	_row("Scheme switch (light/dark) *", _cell(scheme, n), "n/a", "")
	var gvar: Dictionary = await _bench_global_var(n)
	_row("Global var refresh (accent) *", _cell(gvar, n), "n/a", "")
	var ivar: Dictionary = await _bench_instance_var(n)
	_row("Per-instance var set *", _cell(ivar, n), "n/a", "")
	var refr: Dictionary = await _bench_refresh(n)
	_row("Refresh / reapply all *", _cell(refr, n), "n/a", "")
	var addcls: Dictionary = await _bench_add_class(n)
	_row("Add class (restyle all) *", _cell(addcls, n), "n/a", "")
	var modflip: Dictionary = await _bench_modulate_flip(n)
	_row("Modulate state flip *", _cell(modflip, n), "n/a", "")
	var override_stats: Dictionary = await _bench_override(n, OVERRIDE_TEXT)
	_row("Per-node override apply *", _cell(override_stats, n), "n/a", "")
	var per_side: Dictionary = await _bench_override(n, PER_SIDE_TEXT)
	_row("Per-side composite patch *", _cell(per_side, n), "n/a", "")


func _stability_section() -> void:
	_emit("\n[b]====== Stability: %d bind/free cycles of %d styled nodes ======[/b]" % [LEAK_CYCLES, LEAK_NODES])
	await _wait(10)
	var objects_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for cycle: int in LEAK_CYCLES:
		var root: Node = _build_gdss(LEAK_NODES, false)
		get_tree().root.add_child(root)
		await _wait(4)
		root.free()
		await _wait(4)
	await _wait(10)
	var object_delta: int = int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objects_before
	var orphan_delta: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphans_before
	_emit("  Object count delta       %+d    (0 = nothing leaked)" % object_delta)
	_emit("  Orphan node delta        %+d    (0 = clean teardown)" % orphan_delta)


func _stats(samples: PackedFloat64Array) -> Dictionary:
	var best: float = INF
	var total: float = 0.0
	for value: float in samples:
		best = minf(best, value)
		total += value
	var mean: float = total / maxf(samples.size(), 1.0)
	var variance: float = 0.0
	for value: float in samples:
		variance += (value - mean) * (value - mean)
	variance /= maxf(samples.size(), 1.0)
	return {"best": best, "mean": mean, "std": sqrt(variance)}


func _cell(s: Dictionary, n: int) -> String:
	return "%.2f ms (%.4f/node) σ%.2f" % [s.get("best"), s.get("best") / n, s.get("std")]


func _plain_cell(s: Dictionary) -> String:
	return "%.2f ms σ%.2f" % [s.get("best"), s.get("std")]


func _ratio(gdss: Dictionary, vanilla: Dictionary) -> String:
	var g: float = gdss.get("best")
	var v: float = vanilla.get("best")
	return "%.1fx (%s)" % [g / maxf(v, 0.0001), _pct(g, v)]


func _bench_instantiate(n: int) -> Dictionary:
	var gi: PackedFloat64Array = []
	var gb: PackedFloat64Array = []
	var gf: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var t0: int = Time.get_ticks_usec()
		var root: Node = _build_gdss(n, false)
		var inst_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		var t1: int = Time.get_ticks_usec()
		get_tree().root.add_child(root)
		var bind_ms: float = (Time.get_ticks_usec() - t1) / 1000.0
		var t2: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_ms: float = (Time.get_ticks_usec() - t2) / 1000.0
		if r > 0:
			gi.append(inst_ms)
			gb.append(bind_ms)
			gf.append(frame_ms)
		root.queue_free()
		await _wait(6)
	var vi: PackedFloat64Array = []
	var vb: PackedFloat64Array = []
	var vf: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var t0: int = Time.get_ticks_usec()
		var root: Node = _build_vanilla(n, false)
		var inst_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		var t1: int = Time.get_ticks_usec()
		get_tree().root.add_child(root)
		var bind_ms: float = (Time.get_ticks_usec() - t1) / 1000.0
		var t2: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_ms: float = (Time.get_ticks_usec() - t2) / 1000.0
		if r > 0:
			vi.append(inst_ms)
			vb.append(bind_ms)
			vf.append(frame_ms)
		root.queue_free()
		await _wait(6)
	return {"gdss_inst": _stats(gi), "gdss_bind": _stats(gb), "gdss_frame": _stats(gf), "van_inst": _stats(vi), "van_bind": _stats(vb), "van_frame": _stats(vf)}


func _bench_duplicate(n: int) -> Dictionary:
	var g: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var root: Control = Control.new()
		root.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)
		get_tree().root.add_child(root)
		var source: Button = Button.new()
		source.text = "source"
		root.add_child(source)
		await _wait(2)
		var t0: int = Time.get_ticks_usec()
		for i: int in n:
			root.add_child(source.duplicate())
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			g.append(ms)
		root.queue_free()
		await _wait(6)
	var v: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var root: Control = Control.new()
		root.theme = _vanilla_theme
		get_tree().root.add_child(root)
		var source: Button = Button.new()
		source.text = "source"
		root.add_child(source)
		await _wait(2)
		var t0: int = Time.get_ticks_usec()
		for i: int in n:
			root.add_child(source.duplicate())
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			v.append(ms)
		root.queue_free()
		await _wait(6)
	return {"gdss": _stats(g), "vanilla": _stats(v)}


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
	_warp_mouse_away()
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
	var g: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var root: Node = _build_gdss(n, false)
		var ms: float = await _disable_all_ms(root)
		if r > 0:
			g.append(ms)
	var v: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var root: Node = _build_vanilla(n, false)
		var ms: float = await _disable_all_ms(root)
		if r > 0:
			v.append(ms)
	return {"gdss": _stats(g), "vanilla": _stats(v)}


func _disable_all_ms(root: Node) -> float:
	get_tree().root.add_child(root)
	await _wait(6)
	var t0: int = Time.get_ticks_usec()
	for b: Node in root.get_children():
		(b as Button).disabled = true
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	root.queue_free()
	await _wait(6)
	return ms


func _bench_scheme(n: int) -> Dictionary:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var samples: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var target: String = "light" if r % 2 == 0 else "dark"
		var t0: int = Time.get_ticks_usec()
		GDSS.set_scheme(target)
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			samples.append(ms)
		await _wait(2)
	GDSS.set_scheme("dark")
	root.queue_free()
	await _wait(8)
	return _stats(samples)


func _bench_global_var(n: int) -> Dictionary:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var samples: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var t0: int = Time.get_ticks_usec()
		GDSS.set_global_var("accent", Color(randf(), randf(), randf()))
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			samples.append(ms)
		await _wait(2)
	GDSS.set_global_var("accent", _accent)
	root.queue_free()
	await _wait(8)
	return _stats(samples)


func _bench_teardown(n: int) -> Dictionary:
	var g: PackedFloat64Array = []
	var orphans: int = 0
	for r: int in TIMING_RUNS + 1:
		var groot: Node = _build_gdss(n, false)
		get_tree().root.add_child(groot)
		await _wait(6)
		var orphan0: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var t0: int = Time.get_ticks_usec()
		groot.free()
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		await _wait(6)
		if r > 0:
			g.append(ms)
			orphans = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphan0
	var v: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var vroot: Node = _build_vanilla(n, false)
		get_tree().root.add_child(vroot)
		await _wait(6)
		var t0: int = Time.get_ticks_usec()
		vroot.free()
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		await _wait(6)
		if r > 0:
			v.append(ms)
	return {"gdss": _stats(g), "vanilla": _stats(v), "orphans": orphans}


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
	_warp_mouse_away()
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
	var g: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var ms: float = await _reparent_ms(_build_gdss(n, false), true)
		if r > 0:
			g.append(ms)
	var v: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var ms: float = await _reparent_ms(_build_vanilla(n, false), false)
		if r > 0:
			v.append(ms)
	return {"gdss": _stats(g), "vanilla": _stats(v)}


func _reparent_ms(root: Node, gdss_dest: bool) -> float:
	get_tree().root.add_child(root)
	var dest: Control = Control.new()
	if gdss_dest:
		dest.set_meta(GDSS.MODE_META, GDSS.GdssMode.ENABLE)
	else:
		dest.theme = _vanilla_theme
	get_tree().root.add_child(dest)
	await _wait(6)
	var kids: Array[Node] = root.get_children()
	var t0: int = Time.get_ticks_usec()
	for b: Node in kids:
		root.remove_child(b)
		dest.add_child(b)
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	root.queue_free()
	dest.queue_free()
	await _wait(8)
	return ms


func _bench_instance_var(n: int) -> Dictionary:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var kids: Array[Node] = root.get_children()
	var samples: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var t0: int = Time.get_ticks_usec()
		for b: Node in kids:
			GDSS.set_instance_var(b, "glass_strength", float(r + 1))
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			samples.append(ms)
		await _wait(2)
	root.queue_free()
	await _wait(8)
	return _stats(samples)


func _bench_refresh(n: int) -> Dictionary:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var kids: Array[Node] = root.get_children()
	var samples: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var t0: int = Time.get_ticks_usec()
		for b: Node in kids:
			GDSS.refresh(b)
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			samples.append(ms)
		await _wait(2)
	root.queue_free()
	await _wait(8)
	return _stats(samples)


func _bench_add_class(n: int) -> Dictionary:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var kids: Array[Node] = root.get_children()
	var samples: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var t0: int = Time.get_ticks_usec()
		for b: Node in kids:
			GDSS.add_class(b, "GhostButton")
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			samples.append(ms)
		await _wait(2)
		for b: Node in kids:
			GDSS.remove_class(b, "GhostButton")
		await _wait(2)
	root.queue_free()
	await _wait(8)
	return _stats(samples)


func _bench_modulate_flip(n: int) -> Dictionary:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	var kids: Array[Node] = root.get_children()
	for b: Node in kids:
		GDSS.add_class(b, "BenchModulate")
	await _wait(8)
	var samples: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var target: bool = r % 2 == 0
		var t0: int = Time.get_ticks_usec()
		for b: Node in kids:
			(b as Button).disabled = target
			GDSS.refresh(b)
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			samples.append(ms)
		await _wait(2)
	root.queue_free()
	await _wait(8)
	return _stats(samples)


func _bench_override(n: int, text: String) -> Dictionary:
	var root: Node = _build_gdss(n, false)
	get_tree().root.add_child(root)
	await _wait(8)
	var kids: Array[Node] = root.get_children()
	var samples: PackedFloat64Array = []
	for r: int in TIMING_RUNS + 1:
		var t0: int = Time.get_ticks_usec()
		for b: Node in kids:
			GDSS.set_override_text(b, text)
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if r > 0:
			samples.append(ms)
		await _wait(2)
		for b: Node in kids:
			GDSS.set_override_text(b, "")
		await _wait(2)
	root.queue_free()
	await _wait(8)
	return _stats(samples)


func _bench_animating(count: int) -> Dictionary:
	_warp_mouse_away()
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


func _inject_bench_classes() -> void:
	var btn: Dictionary = GdssInterpreter.parsed.get("Button", {})
	if btn.is_empty():
		return
	var classes: Dictionary = btn.get("_classes", {})
	classes["BenchGradient"] = {"all": {"bg_color": {"__gdss_method__": "linear_gradient", "args": ["RED", "BLUE", "90"]}}, "_classes": {}}
	classes["BenchModulate"] = {"all": {}, "disabled": {"modulate": Color(1, 0.4, 0.4, 1), "opacity": 0.6}, "_classes": {}}
	btn["_classes"] = classes


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


func _warp_mouse_away() -> void:
	get_window().warp_mouse(Vector2(-4000, -4000))


func _header() -> void:
	var v: Dictionary = Engine.get_version_info()
	_emit("[b]=======================================================[/b]")
	_emit("[b]  GDSS Benchmark[/b]  |  Godot %s  |  %s  |  %s" % [v.get("string"), OS.get_name(), RenderingServer.get_video_adapter_name()])
	_emit("[b]=======================================================[/b]")
	_emit("[i]Same Button nodes styled by GDSS (theme.tgdss) vs a shared vanilla Theme")
	_emit("with matching styleboxes. Timings: best-of-%d after a discarded warmup," % TIMING_RUNS)
	_emit("with per-run standard deviation. FPS: averaged over %d frames, vsync off," % FRAME_SAMPLES)
	_emit("mouse warped away before every visible section. Columns: GDSS | Vanilla | Delta.[/i]")
	_emit("")
	_emit("%-30s %-30s %-30s %s" % ["Metric", "GDSS", "Vanilla Theme", "Delta"])
	_emit("%s" % "-".repeat(104))


func _pct(gdss: float, vanilla: float) -> String:
	if absf(vanilla) < 0.00001:
		return "n/a"
	return "%+.0f%%" % ((gdss - vanilla) / vanilla * 100.0)


func _row(metric: String, gdss: String, vanilla: String, delta: String) -> void:
	_emit("%-30s %-30s %-30s %s" % [metric, gdss, vanilla, delta])


func _emit(line: String) -> void:
	_buf.append(line)
	print(_strip_bbcode(line))
	if output != null:
		output.append_text(line + "\n")


func _strip_bbcode(s: String) -> String:
	var rx: RegEx = RegEx.create_from_string("\\[/?[a-z][^\\]]*\\]")
	return rx.sub(s, "", true)
