# anim/ - low-cost animation kit for Plasma widgets

Drop this folder into any widget's `contents/ui/` and `import "anim"`.

Rules it encodes:
1. **Static by default.** One short transition when the state turns on, then
   nothing runs (no Timer, no repaint).
2. **Continuous is opt-in** (`mode: 1`) and **fps-capped** (12/24/30/60/native).
3. **Animate transforms** (`rotation`, `opacity`, `scale`, `x/y`) of a
   *statically drawn* item - never `sweepAngle`/path geometry, which forces
   CPU re-tessellation each frame.
4. **Time-based**: use `anim.turns(ms)` / `anim.wave(ms)`; speed does not
   depend on fps.
5. Respects Plasma's animation speed (`Kirigami.Units.longDuration == 0`) and
   an external `paused` flag (hook Gamemode / fullscreen detection here).

Config wiring: add `animationMode` (Int, 0) and `animationFps` (Int, 2) to
`main.xml`, a ComboBox each using `AnimationOptions.modeLabels/fpsLabels`
(see ConfigAdvanced.qml), and bind them to the controller.
Remember Plasma requires every `cfg_*` property on every config page.

## HoverFeedback

Hover/press feedback for panel icons (highlight pill + scale, optional tilt),
with swappable styles. See the header of `HoverFeedback.qml` for the 5-line
wiring. Styles are rows of `AnimationOptions.hoverPresets`; add a style by
appending a row and a label (never reorder - indices live in kcfg).
Config: add `hoverStyle` (Int, 0) to `main.xml` and a ComboBox with
`AnimationOptions.hoverStyleLabels` on every config page (Plasma requires
each `cfg_*` everywhere).

## Using this kit in a widget

Vendored with `git subtree` so each widget stays self-contained:

    git subtree add  --prefix=package/contents/ui/anim <kit-url> main --squash
    git subtree pull --prefix=package/contents/ui/anim <kit-url> main --squash
