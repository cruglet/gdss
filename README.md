# GDSS: Godot stylesheets

An experimental CSS-like styling system for Godot 4. This was originally not intended for public use. However, upon further developing it into something more stable and sophisticated I've
decided to open source it in case anyone would like to use it or help support the development of it.

Do not expect this plugin to be 100% stable- it is a work in progress.

## Some showcase videos
[[dev#1]](https://youtu.be/0vPR0N9wa-M) [[dev#2]](https://youtu.be/HSPjfHhVoIQ) [[dev#3]](https://youtu.be/9HrSvX_Mqbo) [[dev#4]](https://youtu.be/JoT_QkDIMgE) [[dev#5]](https://www.youtube.com/watch?v=BR3UW3jRbD8)

## Example Syntax

```css
Button {
    bg_color: BLACK
    border_color: RED
    border: 5 5 5 5
    corner_radius: 20 0 20 0
    transition_time: 0.4
    transition_func: QUINT
    transition_type: EASE_OUT

    :hover {
        border_color: YELLOW
    }
    :pressed {
        expand: 20 20 20 20
    }
    :normal, :focus {
        skew_y: 0
    }
}

Panel, PanelContainer {
    bg_color: BLACK
}
```

### Features
- [x] Selectors, state blocks, composite shorthand, comma groups
- [x] State transitions
- [x] Easing config (`transition_func`, `transition_type`)
- [x] Skew (`skew_x`, `skew_y`), corner detail, shadow
- [x] Per-node opt-in
- [x] Classes
- [x] Runtime support + hot-reload
- [x] Hex color parsing
- [x] Variable support
- [x] Some way to preview the node as you're writing in gdss.
- [x] Export variable support (in order to access from GDScript)
- [x] Method support 
- [x] Syntax error highlighting 

### TODO
(not necessarily in order)
- [ ] UI polish

