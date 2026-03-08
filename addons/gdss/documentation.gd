class_name GDSSDocumentation
extends Object
## Here is a handy reference sheet for GDSS.

## To enable GDSS, click on a node that is themable, and under the "Theme" property group,
## you should see a toggle that says "Use GDSS." When this is on, the node will start using your GDSS
## declarations for styling.
var HowToEnable: GDSSDocumentation

## GDSS is meant to be used as one singular file that holds all theming information across your project.[br][br]
## There are two format options: [b].tgdss[/b] (Default) and [b].gdss[/b]:[br]
## • [b]*.tgdss[/b] is stored in plain text. It's the default and is ideal for version control systems and readability.[br]
## • [b]*.gdss[/b] is stored in binary. It's best for smaller filesize.
## [br][br]
## You [i]can[/i] change the type and how this file is stored in [code]Project > Project Settings > Gdss > Storage > Save Path[/code],
## but you can only have one file loaded at a time.
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
## To set the class of a "node", make sure that "Use GDSS" is on. Then, under [code]Theme > Classes[/code]
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
