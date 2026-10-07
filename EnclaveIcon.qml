pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// The sbx mark: "sbx" held by four corner brackets. A light sits on the
// top-right corner while something needs a glance:
//   status  "missing"  sbx is not installed       → mark dimmed
//           "offline"  the daemon is not running   → mark dimmed
//           "idle"     nothing runs                → no light
//           "running"  sandboxes run               → accent light, with the
//                                                    count from two on
//           "alert"    approval pending / VM hung  → urgent light
// The light only pulses while `pulse` is set: a bar icon that animates for
// hours keeps the compositor redrawing, so callers pulse alerts only.
Item {
  id: root

  property color color: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color ink: Color.background
  property string fontFamily: Style.font.family
  property real fontSize: Math.max(7, Math.round(height * 0.56))
  property string status: "idle"
  property int count: 0
  property bool pulse: false

  readonly property real stroke: Math.max(1, Math.round(height / 15))
  readonly property real arm: Math.max(3, Math.round(height * 0.3))
  readonly property bool dimmed: status === "missing" || status === "offline"
  readonly property bool lit: status === "running" || status === "alert"
  readonly property bool numbered: lit && count > 1

  implicitHeight: 16
  implicitWidth: Math.round(label.implicitWidth + arm * 1.7)

  Item {
    id: mark
    anchors.fill: parent
    opacity: root.dimmed ? 0.45 : 1

    Behavior on opacity { NumberAnimation { duration: 160 } }

    Repeater {
      model: 4

      Item {
        id: corner
        required property int index
        readonly property bool atRight: index === 1 || index === 3
        readonly property bool atBottom: index >= 2
        x: atRight ? mark.width - root.arm : 0
        y: atBottom ? mark.height - root.arm : 0
        width: root.arm
        height: root.arm

        Rectangle {
          y: corner.atBottom ? corner.height - root.stroke : 0
          width: corner.width
          height: root.stroke
          color: root.color
        }
        Rectangle {
          x: corner.atRight ? corner.width - root.stroke : 0
          width: root.stroke
          height: corner.height
          color: root.color
        }
      }
    }

    Text {
      id: label
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: "sbx"
      color: root.color
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: true
      renderType: Text.NativeRendering
    }
  }

  Rectangle {
    id: light
    visible: root.lit && !root.dimmed
    height: root.numbered ? Math.max(7, Math.round(root.height * 0.5)) : Math.max(4, Math.round(root.height * 0.3))
    width: root.numbered ? Math.max(height, countText.implicitWidth + Math.round(height * 0.5)) : height
    radius: Style.cornerRadius > 0 ? height / 2 : Math.max(0, Math.round(height / 5))
    // centered on the corner point where the top-right bracket bends
    x: root.width - root.stroke / 2 - width / 2
    y: root.stroke / 2 - height / 2
    color: root.status === "alert" ? root.urgent : root.accent

    Text {
      id: countText
      visible: root.numbered
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: String(root.count)
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: Math.max(6, Math.round(light.height * 0.86))
      font.bold: true
    }

    SequentialAnimation on opacity {
      running: root.pulse && light.visible
      loops: Animation.Infinite
      onRunningChanged: if (!running) light.opacity = 1
      NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
    }
  }
}
