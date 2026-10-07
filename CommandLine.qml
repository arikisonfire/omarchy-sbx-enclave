import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The exact sbx command as a terminal line: accent prompt, the command, a
// block cursor that blinks while `live`, and a copy button.
Rectangle {
  id: root

  property string command: ""
  property bool live: true
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string copyIcon: String.fromCodePoint(0xF018F)
  property string checkIcon: String.fromCodePoint(0xF012C)
  property bool copied: false

  implicitHeight: Math.max(body.implicitHeight, copyButton.implicitHeight) + Style.space(14)
  radius: Style.cornerRadius
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  border.width: 1
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.16)

  function copy() {
    if (root.command === "") return
    Quickshell.execDetached(["wl-copy", "--", root.command])
    root.copied = true
    copiedTimer.restart()
  }

  Timer { id: copiedTimer; interval: 1600; onTriggered: root.copied = false }

  Text {
    id: prompt
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.top: body.top
    text: "❯"
    color: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  // TextEdit (read-only) rather than Text: it can report where the last
  // character sits, so the cursor follows the wrapped command.
  TextEdit {
    id: body
    textFormat: TextEdit.PlainText
    readOnly: true
    selectByMouse: false
    activeFocusOnPress: false
    anchors.left: prompt.right
    anchors.leftMargin: Style.space(8)
    anchors.right: copyButton.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.command
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: TextEdit.Wrap
  }

  Rectangle {
    id: cursor
    visible: root.live && root.command !== ""
    width: Math.max(2, Math.round(Style.font.bodySmall * 0.55))
    height: Math.round(Style.font.bodySmall * 1.15)
    color: root.accent
    readonly property rect end: { body.width; body.contentHeight; return body.positionToRectangle(body.length) }
    x: body.x + Math.min(body.width - width, end.x + Style.space(2))
    y: body.y + end.y + Math.round((end.height - height) / 2)

    SequentialAnimation on opacity {
      running: cursor.visible
      loops: Animation.Infinite
      onRunningChanged: if (!running) cursor.opacity = 1
      PauseAnimation { duration: 520 }
      NumberAnimation { to: 0; duration: 60 }
      PauseAnimation { duration: 420 }
      NumberAnimation { to: 1; duration: 60 }
    }
  }

  PanelActionButton {
    id: copyButton
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    iconText: root.copied ? root.checkIcon : root.copyIcon
    tooltipText: root.copied ? "Copied" : "Copy command"
    foreground: root.foreground
    hoverColor: root.accent
    fontFamily: root.fontFamily
    onClicked: root.copy()
  }
}
