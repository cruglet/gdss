# GDSS: Godot stylesheets

An experimental CSS-like styling system for Godot 4. This was originally not intended for public use. However, upon further developing it into something more stable and sophisticated I've
decided to open source it in case anyone would like to use it or help support the development of it.

Do not expect this plugin to be 100% stable- it is a work in progress.

## Some showcase videos

https://youtu.be/0vPR0N9wa-M

https://youtu.be/HSPjfHhVoIQ

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
- [x] Live editor preview
- [x] State transitions
- [x] Easing config (`transition_func`, `transition_type`)
- [x] Skew (`skew_x`, `skew_y`), corner detail, shadow
- [x] Per-node opt-in
- [x] Classes
- [x] Runtime support + hot-reload
- [x] Hex color parsing

### TODO
(not necessarily in order)
- [ ] Custom method support `min()/max()/clamp(), linear_gradient(), etc.`
- [ ] Variable support
- [ ] Export variable support (in order to access from GDScript)
- [ ] Syntax error highlighting 
- [ ] UI polish
- [ ] Some way to preview tS2heetshe node as you're writing in gdss.
- [ ] Masking support (for animated/custom color properties like a gradient bg_color or border_color)
