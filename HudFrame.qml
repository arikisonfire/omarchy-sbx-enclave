pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// Four corner brackets around the parent's area: the sbxEnclave signature in
// place of a full border. Decoration only; fills the item it is placed in.
Item {
  id: root

  property color color: Color.foreground
  property real arm: Style.space(9)
  property real stroke: Math.max(1, Style.space(1))

  Repeater {
    model: 4

    Item {
      id: corner
      required property int index
      readonly property bool atRight: index === 1 || index === 3
      readonly property bool atBottom: index >= 2
      x: atRight ? root.width - root.arm : 0
      y: atBottom ? root.height - root.arm : 0
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
}
