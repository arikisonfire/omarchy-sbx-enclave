import QtQuick
import qs.Commons

// "KEY        value" row for detail grids: a fixed key column in spaced
// capitals, then either `value` as text or whatever is placed inside.
Item {
  id: root

  property string label: ""
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real keyWidth: Style.space(96)
  default property alias extra: slot.data

  width: parent ? parent.width : 0
  implicitHeight: Math.max(key.implicitHeight, slot.childrenRect.height, valueText.visible ? valueText.implicitHeight : 0)

  Text {
    id: key
    textFormat: Text.PlainText
    width: root.keyWidth
    text: root.label.toUpperCase()
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
    topPadding: Style.space(2)
  }

  Text {
    id: valueText
    visible: root.value !== ""
    textFormat: Text.PlainText
    anchors.left: key.right
    anchors.right: parent.right
    text: root.value
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WrapAnywhere
  }

  Item {
    id: slot
    anchors.left: key.right
    anchors.right: parent.right
    height: childrenRect.height
  }
}
