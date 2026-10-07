pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// Tab strip: spaced capitals, the active tab underlined in the accent color,
// with an optional badge (pending approvals). Keys 1–5 switch tabs.
Row {
  id: root

  property var tabs: []              // [{ value, label, badge, alert }]
  property string value: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  signal changed(string value)

  spacing: Style.space(14)

  Repeater {
    model: root.tabs

    Item {
      id: tab
      required property var modelData
      required property int index
      readonly property bool current: modelData.value === root.value
      readonly property bool hot: mouse.containsMouse

      implicitWidth: label.implicitWidth + (badge.visible ? badge.width + Style.space(4) : 0)
      implicitHeight: label.implicitHeight + Style.space(8)

      Text {
        id: label
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.top: parent.top
        text: String(tab.modelData.label).toUpperCase()
        color: tab.current ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, tab.hot ? 0.85 : 0.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.4

        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Text {
        id: badge
        textFormat: Text.PlainText
        visible: tab.modelData.badge !== undefined && String(tab.modelData.badge) !== "" && String(tab.modelData.badge) !== "0"
        anchors.left: label.right
        anchors.leftMargin: Style.space(4)
        anchors.top: label.top
        anchors.topMargin: -Style.space(3)
        text: String(tab.modelData.badge || "")
        color: tab.modelData.alert ? root.urgent : root.accent
        font.family: root.fontFamily
        font.pixelSize: Math.max(7, Style.font.caption - 1)
        font.bold: true
      }

      Rectangle {
        anchors.left: label.left
        anchors.right: label.right
        anchors.bottom: parent.bottom
        height: Math.max(2, Style.space(2))
        color: root.accent
        opacity: tab.current ? 1 : (tab.hot ? 0.35 : 0)
        transformOrigin: Item.Left
        scale: tab.current ? 1 : 0.4

        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.changed(tab.modelData.value)
      }
    }
  }
}
