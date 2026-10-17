import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A movable, rotatable ruler. The top edge is graduated in millimetres and the
// bottom edge in physical pixels. Only the ruler itself takes input; the rest
// of the screen stays clickable.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool placed: false

  // Ruler geometry in window (logical pixel) coordinates. `angle` follows
  // QML rotation: degrees, clockwise.
  property real cx: 0
  property real cy: 0
  property real angle: 0
  property real lengthPx: 900
  readonly property real thickness: 104
  readonly property real minLength: 160

  // Local x positions along the ruler; -1 when unset.
  property real markX: -1
  property real hoverX: -1
  property point hoverScene: Qt.point(0, 0)
  property bool rotating: false
  property bool showHint: false

  readonly property real pxScale: panel.targetMonitor ? panel.targetMonitor.scale : 1
  // Millimetres per logical pixel, from the physical size Hyprland reports.
  readonly property real mmPerPx: {
    var monitor = panel.targetMonitor
    var screen = panel.targetScreen
    var ipc = monitor ? monitor.lastIpcObject : null
    if (ipc && screen && screen.width > 0) {
      var rotated = (Number(ipc.transform) % 2) === 1
      var physical = Number(rotated ? ipc.physicalHeight : ipc.physicalWidth)
      if (physical > 0) return physical / screen.width
    }
    return 25.4 / 96
  }

  readonly property color surface: withAlpha(Commons.Color.background, 0.94)
  readonly property color ink: Commons.Color.menu.text
  readonly property color edge: Commons.Color.menu.border
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Style.font.menuFamily

  readonly property int segmentCount: 24
  property var maskRegions: []

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function open(payloadJson) {
    root.opened = true
    root.showHint = true
    hintTimer.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.hoverX = -1
    root.rotating = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "kristianholme.ruler")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Center the ruler the first time, and pull it back on screen when it is
  // opened on a smaller monitor.
  function place() {
    if (panel.width <= 0 || panel.height <= 0) return
    if (!root.placed) {
      root.lengthPx = Math.round(panel.width * 0.6)
      root.cx = panel.width / 2
      root.cy = panel.height / 2
      root.placed = true
    }
    root.lengthPx = root.clamp(root.lengthPx, root.minLength, Math.hypot(panel.width, panel.height))
    root.cx = root.clamp(root.cx, 0, panel.width)
    root.cy = root.clamp(root.cy, 0, panel.height)
  }

  function rotateBy(delta) {
    root.angle = ((root.angle + delta) % 360 + 360) % 360
  }

  function rotateSnapped(direction) {
    var step = 15
    var next = direction > 0
      ? Math.floor(root.angle / step + 1e-6) * step + step
      : Math.ceil(root.angle / step - 1e-6) * step - step
    root.angle = (next % 360 + 360) % 360
  }

  function resizeBy(delta) {
    root.lengthPx = root.clamp(root.lengthPx + delta, root.minLength, Math.hypot(panel.width, panel.height))
    if (root.markX > root.lengthPx) root.markX = -1
  }

  // Angle of the ruler as a line, counter-clockwise from horizontal, 0–180°.
  function displayAngle() {
    var a = ((-root.angle) % 180 + 180) % 180
    return Math.round(a * 10) / 10
  }

  function formatCm(px) {
    return Commons.I18n.formatNumber(px * root.mmPerPx / 10, 2) + " cm"
  }

  function formatPx(px) {
    return Commons.I18n.formatNumber(Math.round(px * root.pxScale), 0) + " px"
  }

  // Axis-aligned box around one slice of the rotated ruler, for the input mask.
  function segmentRect(i) {
    var rad = root.angle * Math.PI / 180
    var c = Math.cos(rad)
    var s = Math.sin(rad)
    var seg = root.lengthPx / root.segmentCount
    var t = (i + 0.5) * seg - root.lengthPx / 2
    var px = root.cx + t * c
    var py = root.cy + t * s
    var hx = Math.abs(c) * seg / 2 + Math.abs(s) * root.thickness / 2
    var hy = Math.abs(s) * seg / 2 + Math.abs(c) * root.thickness / 2
    return { x: Math.floor(px - hx) - 1, y: Math.floor(py - hy) - 1, w: Math.ceil(hx * 2) + 2, h: Math.ceil(hy * 2) + 2 }
  }

  Timer {
    id: hintTimer
    interval: 5000
    onTriggered: root.showHint = false
  }

  Instantiator {
    model: root.segmentCount
    delegate: Region {
      required property int index
      readonly property var rect: root.segmentRect(index)
      x: rect.x
      y: rect.y
      width: rect.w
      height: rect.h
    }
    onObjectAdded: function(index, object) { root.maskRegions = root.maskRegions.concat([object]) }
    onObjectRemoved: function(index, object) {
      root.maskRegions = root.maskRegions.filter(function(region) { return region !== object })
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    shownKeyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "kristianholme-ruler"
    mask: Region { regions: root.maskRegions }

    onContentReadyChanged: if (contentReady) root.place()

    Item {
      id: ruler
      x: root.cx - width / 2
      y: root.cy - height / 2
      width: root.lengthPx
      height: root.thickness
      rotation: root.angle
      transformOrigin: Item.Center
      antialiasing: true

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          var fine = (event.modifiers & Qt.ShiftModifier) ? 10 : 1
          switch (event.key) {
          case Qt.Key_Escape: root.dismiss(); break
          case Qt.Key_Left: root.cx -= fine; break
          case Qt.Key_Right: root.cx += fine; break
          case Qt.Key_Up: root.cy -= fine; break
          case Qt.Key_Down: root.cy += fine; break
          case Qt.Key_BracketLeft:
            if (event.modifiers & Qt.ShiftModifier) root.rotateSnapped(-1)
            else root.rotateBy(-1)
            break
          case Qt.Key_BracketRight:
            if (event.modifiers & Qt.ShiftModifier) root.rotateSnapped(1)
            else root.rotateBy(1)
            break
          case Qt.Key_0:
          case Qt.Key_H: root.angle = 0; break
          case Qt.Key_V: root.angle = 270; break
          case Qt.Key_Plus:
          case Qt.Key_Equal: root.resizeBy(40 * fine); break
          case Qt.Key_Minus: root.resizeBy(-40 * fine); break
          case Qt.Key_M: root.markX = -1; break
          default: return
          }
          event.accepted = true
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: 4
        color: root.surface
        border.width: 1
        border.color: root.edge
        antialiasing: true
      }

      Canvas {
        id: scaleCanvas
        anchors.fill: parent
        antialiasing: true

        property real mmPerPx: root.mmPerPx
        property real pxScale: root.pxScale
        property color ink: root.ink
        onMmPerPxChanged: requestPaint()
        onPxScaleChanged: requestPaint()
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          var w = width
          var h = height
          ctx.reset()
          ctx.strokeStyle = ink
          ctx.fillStyle = ink
          ctx.lineWidth = 1
          ctx.font = "11px \"" + root.fontFamily + "\""

          // Top edge: millimetres, labelled every centimetre.
          ctx.textAlign = "center"
          ctx.textBaseline = "top"
          var pxPerMm = 1 / mmPerPx
          for (var mm = 0; mm * pxPerMm <= w; mm++) {
            var x = Math.round(mm * pxPerMm) + 0.5
            var len = mm % 10 === 0 ? h * 0.3 : (mm % 5 === 0 ? h * 0.2 : h * 0.12)
            ctx.beginPath()
            ctx.moveTo(x, 0)
            ctx.lineTo(x, len)
            ctx.stroke()
            if (mm % 10 === 0 && mm > 0 && x < w - 36)
              ctx.fillText(String(mm / 10), x, len + 2)
          }

          // Bottom edge: physical pixels, labelled every 100.
          ctx.textBaseline = "bottom"
          for (var p = 0; p / pxScale <= w; p += 10) {
            var bx = Math.round(p / pxScale) + 0.5
            var blen = p % 100 === 0 ? h * 0.3 : (p % 50 === 0 ? h * 0.2 : h * 0.12)
            ctx.beginPath()
            ctx.moveTo(bx, h)
            ctx.lineTo(bx, h - blen)
            ctx.stroke()
            if (p % 100 === 0 && p > 0 && bx < w - 36)
              ctx.fillText(String(p), bx, h - blen - 2)
          }

          ctx.textAlign = "left"
          ctx.textBaseline = "middle"
          ctx.globalAlpha = 0.6
          ctx.fillText("cm", 6, h * 0.42)
          ctx.fillText("px", 6, h * 0.58)
        }
      }

      // Zero mark set with right-click.
      Rectangle {
        visible: root.markX >= 0
        x: root.markX - width / 2
        width: 2
        height: parent.height
        color: root.accent
      }

      // Hairline under the cursor.
      Rectangle {
        visible: root.hoverX >= 0 && !root.rotating
        x: Math.round(root.hoverX)
        width: 1
        height: parent.height
        color: root.accent
        opacity: 0.8
      }

      MouseArea {
        id: body
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property point pressScene: Qt.point(0, 0)
        property real pressCx: 0
        property real pressCy: 0

        function track(mouse) {
          root.hoverX = root.clamp(mouse.x, 0, width)
          root.hoverScene = mapToItem(null, mouse.x, mouse.y)
        }

        onPressed: function(mouse) {
          keyCatcher.forceActiveFocus()
          if (mouse.button === Qt.RightButton) {
            root.markX = (root.markX >= 0 && Math.abs(mouse.x - root.markX) < 6) ? -1 : mouse.x
            return
          }
          pressScene = mapToItem(null, mouse.x, mouse.y)
          pressCx = root.cx
          pressCy = root.cy
        }
        onPositionChanged: function(mouse) {
          if (pressed && (mouse.buttons & Qt.LeftButton)) {
            var p = mapToItem(null, mouse.x, mouse.y)
            root.cx = pressCx + p.x - pressScene.x
            root.cy = pressCy + p.y - pressScene.y
          }
          track(mouse)
        }
        onExited: root.hoverX = -1
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.LeftButton) root.angle = 0
        }
        // High-resolution wheels split one notch (120 units) into several
        // events. Accumulate them so one notch is always one step.
        property real wheelRemainder: 0

        onWheel: function(wheel) {
          wheel.accepted = true
          var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
          if (delta === 0) return
          if ((delta > 0) !== (wheelRemainder > 0)) wheelRemainder = 0
          wheelRemainder += delta
          var notches = wheelRemainder > 0 ? Math.floor(wheelRemainder / 120) : Math.ceil(wheelRemainder / 120)
          if (notches === 0) return
          wheelRemainder -= notches * 120
          var direction = notches > 0 ? -1 : 1
          for (var i = 0; i < Math.abs(notches); i++) {
            if (wheel.modifiers & Qt.ControlModifier) root.resizeBy(-direction * 40)
            else if (wheel.modifiers & Qt.ShiftModifier) root.rotateSnapped(direction)
            else root.rotateBy(direction)
          }
        }
      }

      // Rotation knob at the right end, on the ruler's center line.
      Rectangle {
        id: knob
        width: 22
        height: 22
        radius: 11
        x: parent.width - width - 8
        anchors.verticalCenter: parent.verticalCenter
        color: knobArea.containsMouse || knobArea.pressed ? root.accent : "transparent"
        border.width: 2
        border.color: root.accent
        antialiasing: true

        MouseArea {
          id: knobArea
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          preventStealing: true
          cursorShape: Qt.SizeAllCursor

          onPressed: { keyCatcher.forceActiveFocus(); root.rotating = true }
          onReleased: root.rotating = false
          onCanceled: root.rotating = false
          onPositionChanged: function(mouse) {
            root.hoverScene = mapToItem(null, mouse.x, mouse.y)
            if (!pressed) return
            var p = root.hoverScene
            var a = Math.atan2(p.y - root.cy, p.x - root.cx) * 180 / Math.PI
            if (mouse.modifiers & Qt.ShiftModifier) a = Math.round(a / 15) * 15
            root.angle = (a % 360 + 360) % 360
          }
        }
      }
    }

    // Readout next to the cursor: distance from the zero end (or the mark),
    // in both units, plus the ruler angle.
    Rectangle {
      id: readout
      visible: root.hoverX >= 0 || root.rotating
      width: readoutText.implicitWidth + 16
      height: readoutText.implicitHeight + 10
      radius: 4
      color: root.surface
      border.width: 1
      border.color: root.edge
      x: root.clamp(root.hoverScene.x + 18, 0, panel.width - width)
      y: root.clamp(root.hoverScene.y + 18, 0, panel.height - height)

      Text {
        id: readoutText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        text: {
          var angle = Commons.I18n.formatNumber(root.displayAngle(), 1) + "°"
          if (root.rotating || root.hoverX < 0) return angle
          var d = root.markX >= 0 ? Math.abs(root.hoverX - root.markX) : root.hoverX
          var dist = root.formatCm(d) + " · " + root.formatPx(d)
          if (root.markX >= 0) dist = strings.t("fromMark").arg(dist)
          return dist + " · " + angle
        }
      }
    }

    Rectangle {
      id: hint
      visible: root.showHint
      readonly property real reach: Math.abs(Math.sin(root.angle * Math.PI / 180)) * root.lengthPx / 2
        + Math.abs(Math.cos(root.angle * Math.PI / 180)) * root.thickness / 2
      width: Math.min(hintText.implicitWidth + 24, panel.width - 32)
      height: hintText.implicitHeight + 12
      radius: 4
      color: root.surface
      border.width: 1
      border.color: root.edge
      x: root.clamp(root.cx - width / 2, 16, panel.width - width - 16)
      y: root.clamp(root.cy - reach - height - 12, 16, panel.height - height - 16)

      Text {
        id: hintText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        text: strings.t("hint")
      }
    }
  }
}
