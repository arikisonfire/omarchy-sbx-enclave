import QtQuick
import qs.Commons

// The one filled button per view (Launch): accent fill, text in the panel
// background color, spaced capitals. Disabled shows as a hairline outline.
Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property string fontFamily: Style.font.family
  property color accent: Color.accent
  property color ink: Color.background
  property color foreground: Color.foreground
  property bool hasCursor: false

  signal clicked()

  readonly property bool hot: (mouse.containsMouse || hasCursor) && enabled

  implicitWidth: row.implicitWidth + Style.space(28)
  implicitHeight: row.implicitHeight + Style.space(14)
  radius: Style.cornerRadius
  color: !enabled ? "transparent" : hot ? Qt.lighter(accent, 1.12) : accent
  border.width: enabled ? 0 : 1
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.3)

  Behavior on color { ColorAnimation { duration: 120 } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(8)

    Text {
      visible: root.iconText !== ""
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconText
      color: root.enabled ? root.ink : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.text.toUpperCase()
      color: root.enabled ? root.ink : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.6
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.enabled) root.clicked()
  }
}
