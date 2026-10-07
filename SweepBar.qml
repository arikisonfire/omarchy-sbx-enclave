import QtQuick
import qs.Commons

// A thin track with a segment sweeping along it while `running`: "busy, but
// sbx gives no percentage". Sandbox cards show it during Start, Stop and
// Remove; Setup and the Sandboxes tab while the daemon starts, stops or
// restarts.
Item {
  id: root

  property bool running: false
  property color color: Color.accent
  property color foreground: Color.foreground

  implicitHeight: Math.max(2, Style.space(2))
  clip: true

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
  }
  Rectangle {
    id: sweep
    width: root.width * 0.3
    height: root.height
    color: root.color

    NumberAnimation on x {
      from: -sweep.width
      to: root.width
      duration: 1400
      loops: Animation.Infinite
      running: root.running
    }
  }
}
