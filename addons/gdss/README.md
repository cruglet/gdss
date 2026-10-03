# GDSS (Godot Stylesheets)

> Experimental and under active development, expect rough edges. Please report any issues you come across!

A CSS-like styling system for Godot 4. You can write your UI theme as a stylesheet, target nodes by type and state, share values through variables, and animate between states*. This plugin is opt-in per node by default, therefore it won't interfere with any existing or present Godot theme. Because of this, I actually encourage using this plugin in *tandem* with Godot's vanilla styling system instead of outright replacing it, especially since this plugin is currently in beta - GDSS is powerful, but its not native, so a lot of imperfect workarounds & compromises* had to be made.

> \* One unfortunate compromise when using this plugin is that using GDSS to animate between "states" on certain nodes has been disabled, due to issues arising from the way stylebox rendering works internally in Godot. This is most prominent for nodes that draw multiple instances of the same stylebox (e.g. Tree, ItemList, TabBar). There is no straightforward solution to this issue, aside from potentially making custom versions of those affected nodes. This pull request to the Godot engine might help a lot though: https://github.com/godotengine/godot/pull/114285.

## Why?

Godot themes are oftentimes tedious to edit and hard to keep consistent, especially at large-scale. GDSS lets you describe your styling in one place in a clean, familiar CSS-like language and have your changes automatically propogate everywhere. Variables and style methods are a key component of GDSS, since they allow you to reuse and rapidly change theme values in a very seamless way:

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

This plugin leverages the theme variables built into the engine, so that its more familiar to work with whilst leaving room to expand on it. However, sub-properties like those from styleboxes have been consolidated into the node theme-definition itself, instead of having to call `stylebox.property`.

Unlike GDScript, you assign properties with `:` instead of `=`. This was chosen in order to keep a clear semantic difference from GDScript, and giving it more of a CSS-like structure.
## How does it work?
Godot's theming system, in its current form, is not very extensible nor easy to hook into. The way this plugin achieves what it does is by using theme overrides to force the values defined by the GDSS sheet. For styleboxes, this means that every feature currently supported by `StyleboxFlat` and `StyleboxTexture` had to be remade in GDScript for this plugin. However, this *does* give the benefit of being able to have practically *full* control over how the stylebox is drawn, which means that transitions and post effects can also be supported now; i.e. `bg_color: blur()`.

Unfortunately, this is still quite the compromise, since this approach demands much more attention and polish. So, bug reports, contributions, or donations are always welcome and appreciated! 
## Getting started

1. Download the GDSS plugin from the asset library or copy `addons/gdss` into your project and enable GDSS in Project Settings > Plugins. Reload the project when prompted.
2. Open the GDSS editor. It starts as a bottom dock, but you can switch it to a full main-screen tab from the editor toolbar if you want.
3. Select a themable control node and set its **GDSS** mode in the Inspector (under the "Theme" group): **Enable** styles the node, **Inherit** follows its parent, and **Disable** opts out. Enable a container and leave its children on Inherit to style a whole subtree at once. The inspector shows the resolved "Effective" state beneath the dropdown.
4. Edit the stylesheet (changes apply live in the editor!)

The stylesheet is saved to `res://theme.tgdss` by default. You can change that in `Project Settings > GDSS > Storage`.

## Language

- Selectors target a node type, like `Button { ... }`

- You are also able to target different node types at once: `Panel, PanelContainer { ... }`.

- State blocks restyle interaction states like `:hover`, `:pressed`, `:focus`, and `:disabled`. You can group them too: `:hover, :pressed { ... }`.

- Classes are named variants nested inside a selector, like `GhostButton { ... }`. You assign them to individual nodes in the Inspector, and they cascade on top of the base selector.

- "Composite" types are those which have multiple components; i.e. `border`, which can be set via something like `boder: 2 2 2 2` or `border_left: 2`, `border_right: 2`, etc. Shorthand for composite types are also now supported, so `border: 2` expands into `border: 2 2 2 2` 

- `border_color` and `shadow` are now per-side too. Name a side to override just that one, like `border_color_top: RED` or `shadow_bottom: 8`; sides you leave out keep the shorthand's value, and a shorthand written afterwards resets all four. Per-side border colors meet on the corner diagonal, and a shadow tapers out around corners where the neighboring side is 0.

- Variables come in three kinds: `@global` is shared and settable from code, `@instance` can be overridden per node, and `var` is simply local. Reference any of them with `$name`.

- Methods are supported too! There are plenty of handy ones that handle computation and styling: `linear_gradient`, `radial_gradient`, `mix`, `lighten`, `darken`, `saturate`, `desaturate`, `grayscale`, `invert`, `complement`, `contrast`, `hsv`, `hsv_shift`, `alpha`, `rgba`, `clamp`, `blur`, and `texture`. 

- You can use `pass` as an explicit way to use the default  to fall back to its default, like `linear_gradient($a, $b, pass, 0.2, 0.8)`. Methods can be nested, like `linear_gradient(alpha(BLACK, 0.2), TRANSPARENT_BLACK)`.

- Liquid Glass-style blur and refraction is supported as well via `liquid_blur()`! It is a port from [OverShifted/LiquidGlass](https://github.com/OverShifted/LiquidGlass) (MIT).

- Transitions animate between states with `transition_time`, `transition_func` (LINEAR, QUINT, ELASTIC, and so on), and `transition_type` (EASE_IN, EASE_OUT, EASE_IN_OUT, EASE_OUT_IN).

- Schemes are named sets of variable overrides, declared with `@scheme name { ... }`. A scheme only lists the variables that differ from the base, so everything it omits falls back to the base `@global` value. Switch or animate between them from code with `GDSS.set_scheme(...)`.

- Theme metadata lives in a `@meta { ... }` block (`name`, `description`, `default_scheme`, and so on) and is readable from code with `GDSS.get_theme_meta(...)`.

- Colors accept hex like `"#8e00ff"`, `"#fff"`, or `"#ffffff22"`, and named colors like `RED` and `BLACK`, plus the GDSS aliases `TRANSPARENT_BLACK` and `TRANSPARENT_WHITE`.

- Lines starting with `#` are comments and get ignored. When you toggle a line off in the editor, it is written without a space, like `#bg_color: RED`.

A documentation button is also provided in the editor panel as well for extra detail and clarification!

## Editor

The built-in stylesheet editor has syntax highlighting, error checking with click-to-jump, and autocompletion. It also includes:

- Chunks: split one stylesheet into named tabs to stay organized. They are still a single file under the hood though.
- Improved symbol handling; rename symbol & proper go-to-definition fully supported
- Type hints (now improved further with the Resource panel)
- Parity with Godot's GDScript editor's shortcuts & theming

## Runtime API

You can handle `@global` and `@instance` variables from GDScript, and the nodes that use them update on their own.

For global variables, they are able to be set from anywhere, and every node that references it automatically restyles:

```gdscript
GDSS.set_global_var("accent", c)
```

For instance variables, you need a reference to the node which uses that instance variable, this way you can have multiple nodes use the same instance variable with different values.

```gdscript
GDSS.set_instance_var(my_button, "card_color", Color.RED)
```

### Schemes

Schemes allow you to define a "color scheme" or "palette" for your theme, although it's not limited to color, as you can define any supported GDSS variable:

```gdscript
@global var bg: "#0d0d14"
@global var text: "#ffffff"
@global var font_size: 16

@meta {
	default_scheme: dark
}

# Dark is the base theme in this case, so it doesn't need to be redefined.
@scheme dark {} 

@scheme light {
	bg: "#eceef5"
	text: "#1b1e28"
	font_size: 20
}
```

Scheme information is accessible from GDScript, of course:

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
