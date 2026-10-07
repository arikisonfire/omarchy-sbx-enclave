import QtQuick
import qs.Commons

// Status light for a sandbox.
// mode:
//   running  solid accent with a slow glow (only while `animate`)
//   alert    solid urgent, glowing
//   busy     hollow accent, blinking
//   stopped  hollow, dim
Item {
  id: root

  property string mode: "stopped"
  property bool animate: true
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property real size: Style.space(8)

  readonly property bool lit: mode === "running" || mode === "alert"
  readonly property color tone: mode === "alert" ? urgent : (mode === "running" || mode === "busy") ? accent : foreground
  readonly property bool round: Style.cornerRadius > 0

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    id: glow
    anchors.centerIn: parent
    visible: root.lit
    width: root.size * 2.4
    height: width
    radius: root.round ? width / 2 : Style.space(2)
    color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.22)
    opacity: 0.0

    SequentialAnimation on opacity {
      running: root.animate && root.lit && root.visible
      loops: Animation.Infinite
      onRunningChanged: if (!running) glow.opacity = 0
      NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.15; duration: 1100; easing.type: Easing.InOutSine }
    }
  }

  Rectangle {
    id: core
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: root.round ? width / 2 : 0
    color: root.lit ? root.tone : "transparent"
    border.width: root.lit ? 0 : Math.max(1, Math.round(root.size / 6))
    border.color: root.mode === "busy" ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)

    SequentialAnimation on opacity {
      running: root.animate && root.mode === "busy" && root.visible
      loops: Animation.Infinite
      onRunningChanged: if (!running) core.opacity = 1
      NumberAnimation { to: 0.2; duration: 420 }
      NumberAnimation { to: 1.0; duration: 420 }
    }
  }
}
