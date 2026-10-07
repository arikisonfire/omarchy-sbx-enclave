pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons

// Every sandbox as a card, running ones first. Empty states explain what is
// missing: the sbx CLI, the daemon, or simply a first sandbox.
Item {
  id: root

  required property var panel
  readonly property var svc: panel.svc

  // The keyboard cursor follows a sandbox by name, not a row: the order
  // changes when one starts or stops, and o, s and p must still act on the
  // card that is lit.
  property string cursorName: ""
  readonly property int cursor: sortedNames.indexOf(cursorName)
  property string expandedName: ""
  // A card's port field has the keyboard (asked from the window, so a card
  // that goes away while you type cannot leave this stuck).
  readonly property bool editing: {
    var item = root.Window.activeFocusItem
    return item !== null && item.objectName === "sbxe.portInput"
  }

  readonly property var sorted: {
    var list = (svc.sandboxes || []).slice()
    list.sort(function(a, b) {
      var ra = a.status === "running" ? 0 : 1
      var rb = b.status === "running" ? 0 : 1
      if (ra !== rb) return ra - rb
      return String(b.last_used_at || "").localeCompare(String(a.last_used_at || ""))
    })
    return list
  }
  // The cards are built from the names alone and look their sandbox up, so a
  // status or port change updates a card in place instead of rebuilding them
  // all (which dropped what you were typing into a card).
  readonly property var sortedNames: sorted.map(function(s) { return s.name })
  readonly property var byName: {
    var out = {}
    for (var i = 0; i < sorted.length; i++) out[sorted[i].name] = sorted[i]
    return out
  }

  function move(dy) {
    if (sorted.length === 0) return
    var i = cursor < 0 ? 0 : Math.max(0, Math.min(sorted.length - 1, cursor + dy))
    cursorName = sorted[i].name
    Qt.callLater(scrollToCursor)
  }

  function activate() {
    if (cursor >= 0) toggle(cursorName)
  }

  function selected() {
    return cursor >= 0 ? sorted[cursor] : null
  }

  function expandName(name) {
    expandedName = name
    focusName = name
    focusCard()
    root.svc.inspect(name)
  }

  // A card asked for before the list shows it (a sandbox just created) gets
  // the cursor once it appears.
  property string focusName: ""
  onSortedChanged: focusCard()

  function focusCard() {
    if (focusName === "" || sortedNames.indexOf(focusName) < 0) return
    cursorName = focusName
    focusName = ""
    Qt.callLater(scrollToCursor)
  }

  function toggle(name) {
    expandedName = expandedName === name ? "" : name
    if (expandedName !== "") root.svc.inspect(name)
  }

  function scrollToCursor() {
    var item = cards.itemAt(cursor)
    if (!item) return
    var top = item.y
    var bottom = item.y + item.height
    if (top < flick.contentY) flick.contentY = top
    else if (bottom > flick.contentY + flick.height) flick.contentY = bottom - flick.height
  }

  HudHeader {
    id: header
    width: parent.width
    topGap: 0
    text: "Sandboxes"
    trailing: root.svc.daemon !== "running" ? "" : root.svc.runningCount + " running · " + root.sorted.length + " total"
    foreground: root.panel.fg
    accent: root.panel.accent
    urgent: root.panel.urgent
    fontFamily: root.panel.ff
  }

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.topMargin: Style.space(12)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: list.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: list
      width: flick.width - (flick.contentHeight > flick.height ? Style.space(10) : 0)
      spacing: Style.space(8)

      Repeater {
        id: cards
        model: root.sortedNames

        SandboxCard {
          id: card
          required property string modelData
          width: list.width
          panel: root.panel
          sandbox: root.byName[modelData] || ({ name: modelData })
          detail: root.svc.details[modelData] || null
          expanded: root.expandedName === modelData
          current: root.cursorName === modelData
          onToggled: { root.cursorName = modelData; root.toggle(modelData) }
          onAction: function(kind) { root.panel.sandboxAction(kind, card.sandbox) }
        }
      }
    }
  }

  // ---------------------------------------------------------------- empty states
  Column {
    anchors.centerIn: flick
    width: Math.min(parent.width, Style.space(420))
    spacing: Style.space(12)
    visible: root.sorted.length === 0 && root.svc.resolved

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: !root.svc.installed || root.svc.daemon === "unresponsive" ? root.panel.icons.alert
        : root.svc.daemon === "stopped" ? root.panel.icons.power : root.svc.signedOut ? root.panel.icons.login : root.panel.icons.cube
      color: root.panel.daemonJob ? root.panel.accent
        : !root.svc.installed || root.svc.daemon === "unresponsive" || root.svc.signedOut ? root.panel.urgent : root.panel.dim
      font.family: root.panel.ff
      font.pixelSize: Style.font.display
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: !root.svc.installed ? "The sbx CLI is not installed"
        : root.panel.daemonJob ? root.panel.daemonBusy + " …"
        : root.svc.daemon === "stopped" ? "The sandbox daemon is not running"
        : root.svc.daemon === "unresponsive" ? "The sandbox daemon is not responding"
        : root.svc.daemon === "unknown" ? "Checking Docker Sandboxes …"
        : root.svc.signedOut ? "Sign in to Docker"
        : "No sandboxes yet"
      color: root.panel.fg
      font.family: root.panel.ff
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: !root.svc.installed ? "On Omarchy: yay -S docker-sbx-bin, add yourself to the kvm group (sudo usermod -aG kvm $USER), log in again and run sbx login. Elsewhere: docs.docker.com/ai/sandboxes/install. Then reopen this popup."
        : root.svc.daemon === "stopped" ? "sbxEnclave never starts it on its own. Start it here, or run any sbx command."
        : root.svc.daemon === "unresponsive" ? "Every sbx command hangs until the daemon restarts. Restarting stops all running sandboxes, so pick a good moment."
        : root.svc.daemon === "unknown" ? ""
        : root.svc.signedOut ? "Docker Sandboxes needs a Docker account. Sign in once in a terminal; this popup updates afterwards."
        : "Pick a folder and an agent: the agent gets its own microVM and sees only that folder."
      color: root.panel.dim
      font.family: root.panel.ff
      font.pixelSize: Style.font.bodySmall
    }
    // While the daemon job runs, the button stays where it is, greyed out
    // with the seconds, and a bar sweeps below it without moving anything.
    PrimaryButton {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.svc.installed && (root.svc.daemon !== "unknown" || root.panel.daemonJob !== null)
      enabled: !root.panel.daemonJob
      text: root.panel.daemonJob ? root.panel.daemonBusy + " · " + root.panel.daemonSeconds + " s"
        : root.svc.daemon === "stopped" ? "Start daemon" : root.svc.daemon === "unresponsive" ? "Restart daemon"
        : root.svc.signedOut ? "Sign in" : "Launch a sandbox"
      iconText: root.svc.daemon === "stopped" ? root.panel.icons.power : root.svc.daemon === "unresponsive" ? root.panel.icons.restart
        : root.svc.signedOut ? root.panel.icons.login : root.panel.icons.rocket
      fontFamily: root.panel.ff
      accent: root.panel.accent
      foreground: root.panel.fg
      onClicked: root.svc.daemon === "stopped" ? root.panel.daemonAction("start")
        : root.svc.daemon === "unresponsive" ? root.panel.daemonAction("restart")
        : root.svc.signedOut ? root.panel.terminal(["login"], "float")
        : root.panel.setTab("launch")

      SweepBar {
        visible: root.panel.daemonJob !== null
        anchors.top: parent.bottom
        anchors.topMargin: Style.space(8)
        width: parent.width
        running: root.panel.daemonJob !== null && root.panel.opened
        color: root.panel.accent
        foreground: root.panel.fg
      }
    }
  }

  Text {
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    visible: root.svc.error !== ""
    width: parent.width
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: root.panel.icons.alert + "  " + root.svc.error
    color: root.panel.urgent
    font.family: root.panel.ff
    font.pixelSize: Style.font.caption
  }
}
