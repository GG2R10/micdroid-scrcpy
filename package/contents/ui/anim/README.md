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
