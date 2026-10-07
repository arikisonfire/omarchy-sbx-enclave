pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// A list of short values (ports, KEY=VALUE, hosts) as removable chips, with an
// input that adds one on Enter or with the + button. `validate` returns an
// error text for a value, or "".
Column {
  id: root

  property var values: []
  property string placeholder: ""
  property var validate: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  property string plusIcon: String.fromCodePoint(0xF0415)
  property string closeIcon: String.fromCodePoint(0xF0156)
  property string problem: ""
  readonly property bool editing: input.activeFocus

  signal changed(var values)

  spacing: Style.space(6)

  function addValue() {
    var v = String(input.text || "").trim()
    if (v === "") return
    var issue = typeof root.validate === "function" ? root.validate(v) : ""
    if (issue) { root.problem = issue; return }
    root.problem = ""
    if (root.values.indexOf(v) < 0) root.changed(root.values.concat([v]))
    input.text = ""
  }

  Row {
    width: parent.width
    spacing: Style.space(6)

    TextField {
      id: input
      width: parent.width - addButton.width - parent.spacing
      placeholderText: root.placeholder
      placeholderTextColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
      foreground: root.foreground
      accent: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      verticalPadding: Style.space(5)
      onAccepted: root.addValue()
      onTextEdited: root.problem = ""
    }
    PanelActionButton {
      id: addButton
      size: input.height
      bordered: true
      iconText: root.plusIcon
      tooltipText: "Add"
      foreground: root.foreground
      hoverColor: root.accent
      fontFamily: root.fontFamily
      enabled: input.text.trim() !== ""
      onClicked: root.addValue()
    }
  }

  Text {
    visible: root.problem !== ""
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: root.problem
    color: root.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Flow {
    width: parent.width
    spacing: Style.space(6)
    visible: root.values.length > 0

    Repeater {
      model: root.values

      Rectangle {
        id: token
        required property string modelData
        required property int index
        implicitWidth: tokenRow.implicitWidth + Style.space(10)
        implicitHeight: tokenRow.implicitHeight + Style.space(4)
        radius: Style.cornerRadius
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
        border.width: 1
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)

        Row {
          id: tokenRow
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: token.modelData
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.closeIcon
            color: removeMouse.containsMouse ? root.urgent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              id: removeMouse
              anchors.fill: parent
              anchors.margins: -Style.space(3)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var next = root.values.slice()
                next.splice(token.index, 1)
                root.changed(next)
              }
            }
          }
        }
      }
    }
  }
}
