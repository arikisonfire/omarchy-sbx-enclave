import QtQuick
import qs.Commons

// Small label in a hairline box: agent names, ports, "RO", counts.
Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property color foreground: Color.foreground
  property color tone: foreground
  property string fontFamily: Style.font.family
  property bool strong: false
  property bool caps: true

  implicitWidth: row.implicitWidth + Style.space(12)
  implicitHeight: row.implicitHeight + Style.space(4)
  radius: Style.cornerRadius
  color: strong ? Qt.rgba(tone.r, tone.g, tone.b, 0.14) : "transparent"
  border.width: 1
  border.color: Qt.rgba(tone.r, tone.g, tone.b, strong ? 0.55 : 0.32)

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(4)

    Text {
      visible: root.iconText !== ""
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconText
      color: root.tone
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.caps ? root.text.toUpperCase() : root.text
      color: root.strong ? root.tone : Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.85)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: root.caps ? 0.8 : 0
    }
  }
}
