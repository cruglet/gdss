class_name GDSSDocumentation
extends Object
## Here is a handy reference sheet for GDSS.

## To enable GDSS, select a themable node and find the [b]GDSS[/b] mode dropdown under the "Theme"
## property group. It works like [enum Node.ProcessMode]:[br]
## • [b]Enable[/b] - always style this node.[br]
## • [b]Disable[/b] - never style this node.[br]
## • [b]Inherit[/b] (default) - follow the nearest ancestor that is explicitly Enabled or Disabled.[br][br]
## Because of Inherit, you can set one container to [b]Enable[/b] and leave its children on Inherit to
## style an entire subtree at once, and newly instantiated or reparented nodes adopt the GDSS state of
## wherever they land. A dimmed line under the dropdown shows the resolved "Effective" state and where it
## comes from. With nothing set anywhere, GDSS stays off (configurable via
## [code]Project Settings > Gdss > Binding > Root Default[/code]).[br][br]
## From code you can drive this with [method GDSS.set_gdss_mode], [method GDSS.enable_gdss],
## [method GDSS.disable_gdss], and query it with [method GDSS.is_gdss_enabled].
var HowToEnable: GDSSDocumentation

## GDSS stylesheets are saved as plain-text [b].tgdss[/b] files, which are ideal for version control and
## work directly with the built-in editor.[br][br]
## When you export your project, GDSS automatically compiles the active stylesheet into a compact binary
## [b].gdssc[/b] artifact that ships in the build and is read at runtime - you don't manage that file
## yourself (it is regenerated on save and injected into exports).[br][br]
## Switch the active stylesheet from the editor's [b]File[/b] menu (New, Open, Open Recent, Save As,
## Rename) or via [code]Project > Project Settings > Gdss > Storage > Save Path[/code]. Only one
## stylesheet is loaded at a time.
var FileFormat: GDSSDocumentation

## The syntax for GDSS is similar to CSS, with some Godot elements mixed in.[br][br]
## You start by declaring any themable node (See [member SupportedNodes]):
## [codeblock]
## 
## Button {
##     
## }
## [/codeblock][br]
## Then, you can enter any of that node's theme properties. To see a list, you can hit [kbd]Ctrl+Space[/kbd] on an empty line or begin typing.[br]
## This can look something like:
## [codeblock]
## Button {
##     bg_color: BLACK
##     border_color: "#f0f0f0"
##     corner_radius: 8 8 8 8
##     font_size: 16
## }
## [/codeblock]
## As you can see, the property name is defined first, followed by a colon, then the value.[br][br]
## Some nodes have "states" or alternate styleboxes, these can be seen by inserting a [code]:[/code] 
## in a block (recommended) or after a node declaration:
## [codeblock]
## Button {
##     bg_color: RED
##     :hover {
##         border_color: ORANGE
##     }
## }
## [/codeblock]
## or
## [codeblock]
## Button {
##     bg_color: RED
## }
## Button:hover {
##     border_color: ORANGE
## }
## [/codeblock]
## Any block that is inside/below another will inherit its ancestor's properties.
## So in the code snippets above, the hover state will have a bg_color of [b]RED[/b] [u]and[/u] a 
## border_color of [b]ORANGE[/b]. [br][br]
## You can also define variables, too. There are three main types of variables: [code]local[/code],
## [code]instance[/code], and [code]global[/code]. You can define them in the top scope like you would a property:
## [codeblock]
## var border_col: "#444"
## @instance var corner_rad: 8
## @global var accent_col: CYAN
## [/codeblock]
## You can use these variables on any property with the same type. These must be prefixed with a [code]$[/code]:
## [codeblock]
## Button {
##     bg_color: $accent_col
##     border_color: $border_col
##     corner_radius: $corner_rad $corner_rad $corner_rad $corner_rad
##     font_size: 16
## }
## [/codeblock]
## The difference in these variables is how they are modified from GDScript:[br][br]
## • [b]Local[/b] variables only exist in GDSS. These should be used when you want to be
## able to easily tweak and modify values without having to worry about updating them from GDScript.[br][br]
## • [b]Instance[/b] variables can be set individually per-node instance, so you can have two [Button]s
## sharing the same "style" definition with different appearances (See [method GDSS.get_instance_var] and [method GDSS.set_instance_var]).[br][br]
## • [b]Global[/b] variables affect every node instance (See [method GDSS.get_global_var] and [method GDSS.set_global_var]).[br][br]
##
## GDSS also supports [b]classes[/b]. You can use them by nesting a custom name within a base type:
## [codeblock]
## Button {
##     bg_color: "#444"
##     
##     RoundedButton {
##         corner_radius: 8 8 8 8
##     }
## }
## [/codeblock]
## You can still use states and nest other classes as well:
## [codeblock]
## Button {
##     bg_color: rgba(0.2, 0.2, 0.2)
##     
##     :hover {
##         expand: 3 3 3 3
##     }
## 
##     RoundedButton {
##         corner_radius: 8 8 8 8
##         
##         RoundedSkewButton {
##             skew_y: 0.2
##
##             :pressed {
##                 skew_y: -0.2
##             }
##         }
##     }
## }
## [/codeblock]
## To set the class of a "node", make sure its GDSS mode resolves to Enabled. Then, under [code]Theme > Classes[/code]
## in the inspector, give it the name of a class.[br][br]
## You can assign multiple classes as well. Each assigned class is space-separated in the input box, and the
## properties from each respective class are applied from left to right.
## [br][br]
## Lastly, comments are denoted with [code]#[/code].
## [codeblock]
## Button {
##     bg_color: "#8e00ff" # This is my favorite color!
## }
## [/codeblock]
var WritingGDSS: GDSSDocumentation

## A [b]scheme[/b] is a named set of variable overrides, letting one stylesheet carry
## several interchangeable palettes (light/dark, brand variants, and so on). Declare a
## scheme with the [code]@scheme[/code] annotation, listing only the variables that
## should differ from their base values:
## [codeblock]
## @global var bg: "#0d0d14"
## @global var text: "#ffffff"
##
## @scheme dark {}
##
## @scheme light {
##     bg: "#eceef5"
##     text: "#1b1e28"
## }
## [/codeblock]
## Anything a scheme omits falls back to the base [code]@global[/code] value, so the
## [code]dark[/code] scheme above (which matches the base) needs no entries.[br][br]
## Switch schemes from GDScript with [method GDSS.set_scheme]. Passing a time animates
## the change; colors, numbers, and composite values interpolate while everything else
## snaps:
## [codeblock]
## GDSS.set_scheme("light")          # instant
## GDSS.set_scheme("dark", 0.25)     # tween over 0.25s
## [/codeblock]
## Read the active scheme with [method GDSS.get_scheme], list them all with
## [method GDSS.get_schemes], and react to changes by passing a callable to
## [method GDSS.on_scheme_changed].[br][br]
## A theme can also carry [b]metadata[/b] in an [code]@meta[/code] block. Use it for a
## name, description, author, version, or the [code]default_scheme[/code] applied when
## the game starts:
## [codeblock]
## @meta {
##     name: "Aurora"
##     description: "Dark and light schemes."
##     default_scheme: dark
## }
## [/codeblock]
## Read metadata from code with [method GDSS.get_theme_meta] or [method GDSS.get_theme_info].
var SchemesAndMetadata: GDSSDocumentation

## These are the nodes that this plugin currently supports in alphabetical order:
## [br](nodes in a [code]code[/code] block are "internal" to another node)
## [br](nodes marked with [b]>[/b] are transitionable)
## [br]
## [BoxContainer][br]
## > [Button][br]
## > [CheckBox][br]
## > [CheckButton][br]
## [CodeEdit][br]
## [ColorPicker][br]
## > [ColorPickerButton][br]
## [FlowContainer][br]
## [FoldableContainer][br]
## [GraphEdit][br]
## [code]GraphEditMinimap[/code][br]
## [GraphFrame][br]
## [GraphNode][br]
## [GridContainer][br]
## [HBoxContainer][br]
## [HFlowContainer][br]
## [HScrollBar][br]
## [HSeparator][br]
## [HSlider][br]
## [HSplitContainer][br]
## [ItemList][br]
## [Label][br]
## > [LineEdit][br]
## [LinkButton][br]
## [MarginContainer][br]
## [MenuBar][br]
## > [MenuButton][br]
## > [OptionButton][br]
## [Panel][br]
## [PanelContainer][br]
## [ProgressBar][br]
## [RichTextLabel][br]
## [ScrollContainer][br]
## [SpinBox][br]
## [SplitContainer][br]
## [TabBar][br]
## [TabContainer][br]
## > [TextEdit][br]
## [Tree][br]
## [VBoxContainer][br]
## [VFlowContainer][br]
## [VScrollBar][br]
## [VSeparator][br]
## [VSlider][br]
## [VSplitContainer][br]
var SupportedNodes: GDSSDocumentation
