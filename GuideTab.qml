pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui
import "Guide.js" as Guide

// The sbx guide: search on top, the words you meet, then commands grouped by
// task. Each command can be copied.
Item {
  id: root

  required property var panel

  property string query: ""
  property bool conceptsOpen: true
  readonly property var sections: Guide.filtered(query)
  readonly property bool editing: search.activeFocus

  function focusSearch() { search.forceActiveFocus() }

  TextField {
    id: search
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    placeholderText: root.panel.icons.magnify + "  Search " + Guide.count() + " commands: port, secret, clone, block …"
    placeholderTextColor: Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.4)
    foreground: root.panel.fg
    font.family: root.panel.ff
    onTextEdited: root.query = text
  }

  Flickable {
    id: flick
    anchors.top: search.bottom
    anchors.topMargin: Style.space(12)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

    Column {
      id: column
      width: flick.width - (flick.contentHeight > flick.height ? Style.space(10) : 0)
      spacing: Style.space(10)

      // ============================================================ concepts
      Item {
        visible: root.query === ""
        width: parent.width
        implicitHeight: conceptsHeader.implicitHeight + Style.space(2)

        HudHeader {
          id: conceptsHeader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: (root.conceptsOpen ? "▾ " : "▸ ") + "The words"
          trailing: Guide.CONCEPTS.length + " concepts"
          foreground: root.panel.fg
          accent: root.panel.accent
          urgent: root.panel.urgent
          fontFamily: root.panel.ff
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.conceptsOpen = !root.conceptsOpen
        }
      }

      Grid {
        visible: root.query === "" && root.conceptsOpen
        width: parent.width
        columns: 2
        columnSpacing: Style.space(14)
        rowSpacing: Style.space(8)

        Repeater {
          model: Guide.CONCEPTS

          Column {
            id: concept
            required property var modelData
            width: (column.width - Style.space(14)) / 2
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: concept.modelData.term
              color: root.panel.accent
              font.family: root.panel.ff
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: concept.modelData.text
              color: root.panel.dim
              font.family: root.panel.ff
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // ============================================================ commands
      Repeater {
        model: root.sections

        Column {
          id: section
          required property var modelData
          width: column.width
          spacing: Style.space(6)

          HudHeader {
            width: parent.width
            text: section.modelData.title
            trailing: section.modelData.items.length + (section.modelData.items.length === 1 ? " command" : " commands")
            foreground: root.panel.fg
            accent: root.panel.accent
            urgent: root.panel.urgent
            fontFamily: root.panel.ff
          }

          Repeater {
            model: section.modelData.items

            Item {
              id: entry
              required property var modelData
              readonly property bool hot: entryHover.hovered
              width: section.width
              implicitHeight: entryColumn.implicitHeight + Style.space(10)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: entry.hot ? Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.045) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
              }
              HudFrame {
                anchors.fill: parent
                visible: entry.hot
                color: Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.4)
                arm: Style.space(6)
              }
              HoverHandler { id: entryHover }

              Column {
                id: entryColumn
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: entryButtons.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: entry.modelData.title
                  color: root.panel.fg
                  font.family: root.panel.ff
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.WrapAnywhere
                  text: "❯ " + entry.modelData.cmd
                  color: root.panel.accent
                  font.family: root.panel.ff
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  visible: entry.modelData.text !== ""
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  text: entry.modelData.text
                  color: root.panel.dim
                  font.family: root.panel.ff
                  font.pixelSize: Style.font.caption
                }
              }

              Row {
                id: entryButtons
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                opacity: entry.hot ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 100 } }

                PanelActionButton {
                  iconText: root.panel.icons.copy
                  tooltipText: "Copy the command"
                  foreground: root.panel.fg
                  hoverColor: root.panel.accent
                  fontFamily: root.panel.ff
                  onClicked: root.panel.copyText(entry.modelData.cmd)
                }
              }
            }
          }
        }
      }

      Text {
        visible: root.sections.length === 0
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Nothing matches \"" + root.query + "\". Every command: docs.docker.com/reference/cli/sbx"
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      Button {
        text: "Full CLI reference on docs.docker.com"
        iconText: root.panel.icons.openIn
        foreground: root.panel.fg
        fontFamily: root.panel.ff
        fontSize: Style.font.caption
        onClicked: Quickshell.execDetached(["xdg-open", "https://docs.docker.com/reference/cli/sbx/"])
      }
    }
  }
}
