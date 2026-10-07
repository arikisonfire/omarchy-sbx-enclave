import QtQuick
import qs.Commons

// Section header in the HUD style: spaced capitals, an accent tick, a hairline
// running across, and an optional reading on the far end ("2 RUNNING").
Item {
  id: root

  property string text: ""
  property string trailing: ""
  property bool trailingAlert: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  // breathing room above the header, so sections read as sections
  property real topGap: Style.space(6)

  implicitWidth: label.implicitWidth + tail.implicitWidth + Style.space(60)
  implicitHeight: Math.max(label.implicitHeight, tail.implicitHeight) + topGap

  Text {
    id: label
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.topGap / 2
    text: root.text.toUpperCase()
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.6
  }

  Rectangle {
    id: tick
    anchors.left: label.right
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.topGap / 2
    width: Style.space(6)
    height: Math.max(2, Style.space(2))
    color: root.accent
  }

  Rectangle {
    anchors.left: tick.right
    anchors.right: tail.visible ? tail.left : parent.right
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: tail.visible ? Style.space(8) : 0
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.topGap / 2
    height: 1
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
  }

  Text {
    id: tail
    visible: root.trailing !== ""
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.topGap / 2
    text: root.trailing.toUpperCase()
    color: root.trailingAlert ? root.urgent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.62)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }
}
