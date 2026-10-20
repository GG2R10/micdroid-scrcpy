import QtQuick
import org.kde.kirigami as Kirigami

// Reusable animation policy + throttled clock for panel/compact widgets.
// Self-contained: copy this folder into another widget as-is.
//
// WHY: every frame a widget requests repaints the whole panel window and
// makes KWin recompose (and re-blur) behind it, so a tiny always-spinning
// indicator can cost several % CPU/GPU at idle. Defaults here are therefore
// "static, animate only on state changes"; continuous animation is opt-in
// and frame-rate capped.
//
// USAGE (see README.md in this folder):
//   AnimationController {
//       id: anim
//       active: isForwarding            // the state that deserves an indicator
//       mode: Plasmoid.configuration.animationMode
//       fpsIndex: Plasmoid.configuration.animationFps
//   }
//   // then bind visuals to anim.elapsed / anim.transitionProgress, and
//   // animate TRANSFORMS (rotation/opacity/scale), never geometry:
//   Item { rotation: anim.continuous ? anim.turns(6000) * 360 : ... }
//
// While nothing is animating, no Timer/FrameAnimation is running at all:
// zero wakeups, zero repaints.
Item {
    id: ctl

    // The widget state that wants an animated indicator (e.g. "connected").
    property bool active: false
    // 0 = static: one short transition when `active` turns on, then still.
    // 1 = continuous: keep animating while `active` (fps-capped).
    property int mode: 0
    // Index into AnimationOptions.fpsValues. Default 30.
    property int fpsIndex: 2
    // External pause (e.g. a fullscreen window or Gamemode is active).
    property bool paused: false
    // Length of the on-activation transition, ms.
    property int transitionDuration: 1200

    // Plasma's "animation speed = instant" (or off) means: never animate.
    readonly property bool systemAnimationsOn: Kirigami.Units.longDuration > 0
    readonly property bool animationsEnabled: systemAnimationsOn && !paused
    readonly property int fps: AnimationOptions.fpsValues[Math.max(0, Math.min(fpsIndex, AnimationOptions.fpsValues.length - 1))]

    readonly property bool continuous: animationsEnabled && active && mode === 1
    readonly property bool transitioning: animationsEnabled && active && !_transitionDone
    readonly property bool running: continuous || transitioning

    // ms since the animation (re)started; advances at `fps` while running.
    property real elapsed: 0
    // 0..1 over transitionDuration after `active` turns on; parks at 1.
    readonly property real transitionProgress: animationsEnabled ? Math.min(1, elapsed / transitionDuration) : 1

    // Fraction (0..1, wrapping) of a loop of `periodMs`. Time-based, so the
    // visual speed is identical at 12 fps or 60 fps.
    function turns(periodMs) { return (elapsed % periodMs) / periodMs }
    // Smooth 0..1..0 wave over `periodMs`, for breathing/pulsing opacity.
    function wave(periodMs) { return 0.5 - 0.5 * Math.cos(2 * Math.PI * turns(periodMs)) }
    function easeOut(t) { return 1 - Math.pow(1 - t, 3) }

    property bool _transitionDone: true
    property double _start: 0

    onActiveChanged: {
        if (active) {
            _start = Date.now()
            elapsed = 0
            _transitionDone = false
        } else {
            _transitionDone = true
            elapsed = 0
        }
    }

    function _tick() {
        elapsed = Date.now() - _start
        if (!_transitionDone && elapsed >= transitionDuration && !continuous)
            _transitionDone = true
    }

    Timer {
        interval: ctl.fps > 0 ? Math.round(1000 / ctl.fps) : 16
        repeat: true
        running: ctl.running && ctl.fps > 0
        onTriggered: ctl._tick()
    }
    // "Native" (fps 0): follow the display's refresh rate.
    FrameAnimation {
        running: ctl.running && ctl.fps === 0
        onTriggered: ctl._tick()
    }
}
