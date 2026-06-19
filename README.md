# GDSS (Godot Stylesheets)

> Experimental and under active development, expect rough edges. Please report any issues you come across!

A CSS-like styling system for Godot 4. You can write your UI theme as a stylesheet, target nodes by type and state, share values through variables, and animate between states*. This plugin is opt-in per node, therefore it won't interfere with any existing or present Godot theme. Because of this, I actually encourage using this plugin in *tandem* with Godot's vanilla styling system instead of outright replacing it, especially since this plugin is currently in beta - GDSS is powerful, but its not native, so a lot of imperfect workarounds & compromises* had to be made

> \* One unfortunate compromise when using this plugin is that using GDSS to animate between "states" on certain nodes has been disabled, due to issues arising from the way stylebox rendering works internally in Godot. This is most prominent for nodes that draw multiple instances of the same stylebox (e.g. Tree, ItemList, TabBar). There is no straightforward solution to this issue, aside from potentially making custom versions of those affected nodes. This pull request to the Godot engine might help a lot though: https://github.com/godotengine/godot/pull/114285.

## Why?

Godot themes are oftentimes tedious to edit and hard to keep consistent. GDSS lets you describe your styling in one place in a clean, familiar CSS-like language. Variables and style methods are a key component of GDSS, since they allow you to reuse and rapidly change theme values in a very seamless way:

```gdscript
@global var accent: "#8e00ff"

Button {
	bg_color: linear_gradient($accent, darken($accent, 0.3), -45)
	corner_radius: 10 10 10 10
	padding: 12 12 6 6
	font_color: "#fff"
	transition_time: 0.2
	transition_func: QUINT
	transition_type: EASE_OUT
	:hover {
		expand: 2 2 2 2
	}
	:pressed, :hover_pressed {
		bg_color: $accent
	}
	GhostButton {
		bg_color: rgba(0, 0, 0, 0)
		border_color: $accent
		border: 2 2 2 2
	}
}

Panel, PanelContainer {
	bg_color: "#101027"
	corner_radius: 10 10 10 10
}
```

## Getting started

1. Download the GDSS plugin from the asset library or copy `addons/gdss` into your project and enable GDSS in Project Settings > Plugins. Reload the project when prompted.
2. Open the GDSS editor. It starts as a bottom dock, but you can switch it to a full main-screen tab from the editor toolbar if you want.
3. Select a themable control node and set its **GDSS** mode in the Inspector (under the "Theme" group): **Enable** styles the node, **Inherit** follows its parent, and **Disable** opts out. Enable a container and leave its children on Inherit to style a whole subtree at once. The inspector shows the resolved "Effective" state beneath the dropdown.
4. Edit the stylesheet (changes apply live in the editor!)

The stylesheet is saved to `res://theme.tgdss` by default. You can change that in `Project Settings > GDSS > Storage`.

## Language

- Selectors target a node type, like `Button { ... }`. Group them with commas: `Panel, PanelContainer { ... }`.
- State blocks restyle interaction states like `:hover`, `:pressed`, `:focus`, and `:disabled`. You can group them too: `:hover, :pressed { ... }`.
- Classes are named variants nested inside a selector, like `GhostButton { ... }`. You assign them to individual nodes in the Inspector, and they cascade on top of the base selector.
- Composite shorthand expands to four sides: `border: 5 5 5 5`, `corner_radius: 20 0 20 0`. Per-side keys also work, like `border_left: 5`.
- Variables come in three kinds: `@global` is shared and settable from code, `@instance` can be overridden per node, and plain `var` is file-local. Reference any of them with `$name`.
- Methods compute values, such as `linear_gradient`, `radial_gradient`, `mix`, `lighten`, `darken`, `saturate`, `desaturate`, `grayscale`, `invert`, `complement`, `contrast`, `hsv`, `hsv_shift`, `alpha`, `rgba`, `clamp`, and `texture`. Use `pass` for an optional argument to fall back to its default, like `linear_gradient($a, $b, pass, 0.2, 0.8)`.
- Transitions animate between states with `transition_time`, `transition_func` (LINEAR, QUINT, ELASTIC, and so on), and `transition_type` (EASE_IN, EASE_OUT, EASE_IN_OUT, EASE_OUT_IN).
- Schemes are named sets of variable overrides, declared with `@scheme name { ... }`. A scheme only lists the variables that differ from the base, so everything it omits falls back to the base `@global` value. Switch or animate between them from code with `GDSS.set_scheme(...)`.
- Theme metadata lives in an `@meta { ... }` block (`name`, `description`, `default_scheme`, and so on) and is readable from code with `GDSS.get_theme_meta(...)`.
- Colors accept hex like `"#8e00ff"`, `"#fff"`, or `"#ffffff22"`, and named colors like `RED` and `BLACK`.
- Lines starting with `#` are comments and get ignored. When you toggle a line off in the editor, it is written without a space, like `#bg_color: RED`.

A documentation button is also provided in the editor panel as well for extra detail and clarification!

## Editor

The built-in stylesheet editor has syntax highlighting, error checking with click-to-jump, and autocompletion. It also includes:

- Outline panel: jump to any selector, class, or state, with a filter box.
- Chunks: split one stylesheet into named tabs to stay organized. They are still a single file under the hood though.
- Go-to-definition: Ctrl/Cmd-click a `$variable` to jump to where it is declared.
- Find with Ctrl/Cmd+F, and select-next-occurrence with multiple cursors using Ctrl/Cmd+D.
- Comment toggle with Ctrl/Cmd+/, convert spaces to tabs with Ctrl/Cmd+Shift+I, and font zoom.

## Runtime API

You can drive globals and per-instance variables from GDScript, and the nodes that use them update on their own.

Animate a global, and every node that references it restyles:

```gdscript
var tween: Tween = create_tween()
tween.tween_method(func(c: Color) -> void:
	GDSS.set_global_var("accent", c)
, Color.PURPLE, Color.CYAN, 0.35)
```

Override a variable on a single node, or read a global back with a fallback if the currently loaded GDSS theme does not have it:

```gdscript
GDSS.set_instance_var(my_button, "card_color", Color.RED)
var current: Color = GDSS.get_global_var("accent", Color.WHITE)
```

### Schemes

Declare named palettes in the stylesheet, then switch or tween between them with a single call. A scheme only restates the variables that differ from the base:

```gdscript
@global var bg: "#0d0d14"
@global var text: "#ffffff"

@meta {
	default_scheme: dark
}

@scheme dark {}            # dark matches the base, so it needs nothing

@scheme light {
	bg: "#eceef5"
	text: "#1b1e28"
}
```

```gdscript
GDSS.set_scheme("light")          # instant
GDSS.set_scheme("dark", 0.25)     # tween over 0.25s (colors/numbers interpolate)

var active: String = GDSS.get_scheme()
for name: String in GDSS.get_schemes():
	print(name)
```

The runtime applies the theme's `default_scheme` on start, and a `GdssRuntime.scheme_changed(name)` signal fires whenever the scheme changes. Theme metadata is available too, via `GDSS.get_theme_meta("name")` or `GDSS.get_theme_info()`.

## TODO

> UI polish, performance optimizations, and better stability are always a work in progress.

## Showcase

[dev #1](https://youtu.be/0vPR0N9wa-M) · [dev #2](https://youtu.be/HSPjfHhVoIQ) · [dev #3](https://youtu.be/9HrSvX_Mqbo) · [dev #4](https://youtu.be/JoT_QkDIMgE) · [dev #5](https://www.youtube.com/watch?v=BR3UW3jRbD8)

