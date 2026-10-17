# omarchy-ruler

An [Omarchy](https://omarchy.org/) shell plugin that puts a ruler on the screen. Move it, rotate it to any angle, and measure in centimetres or pixels.

Plugin id: `kristianholme.ruler`

## Install

```bash
omarchy plugin add https://github.com/KristianHolme/omarchy-ruler.git --enable
```

Add a keybinding to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + R", "Screen ruler", { panel = "kristianholme.ruler" })
```

Or open it from a terminal:

```bash
omarchy-shell shell toggle kristianholme.ruler
```

## Update

```bash
omarchy plugin update kristianholme.ruler
```

## Remove

```bash
omarchy plugin remove kristianholme.ruler
```

## Usage

The top edge is in centimetres with millimetre ticks. The bottom edge is in physical screen pixels, so on a scaled display it matches screenshot pixels. Hover over the ruler to read the distance from its zero end, in both units, and its angle.

| Action | Mouse | Keyboard |
|--------|-------|----------|
| Move | Drag the ruler | Arrows (Shift for 10 px) |
| Rotate 1° | Scroll | `[` / `]` |
| Rotate in 15° steps | Shift+scroll, or Shift while dragging the knob | Shift+`[` / Shift+`]` |
| Rotate freely | Drag the round knob | |
| Horizontal / vertical | Double-click | `H` or `0` / `V` |
| Change length | Ctrl+scroll | `+` / `-` |
| Measure from a point | Right-click to set a zero mark, right-click it again to clear | `M` clears the mark |
| Close | | Esc, or the keybinding |

Keyboard keys work after you click the ruler. Only the ruler takes mouse input; the rest of the screen stays usable while it is open. The ruler keeps its position, angle, and length between opens until the shell restarts.

Centimetres come from the physical monitor size that Hyprland reports (`hyprctl monitors`). Monitors often report a rounded size, so expect an error of up to a few percent.

## License

MIT
