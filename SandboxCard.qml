pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Sbx.js" as Sbx

// One sandbox: a bracketed card with its light, name, agent and state, the
// workspace underneath, and quick actions. Expanded, it lists what
// `sbx inspect` knows and every action.
Item {
  id: root

  required property var panel
  property var sandbox: ({})
  property var detail: null
  property bool expanded: false
  property bool current: false

  signal toggled()
  signal action(string kind)

  readonly property color fg: panel.fg
  // running | stopped | busy (starting, stopping, …) | alert (Sbx.statusKind)
  readonly property string kind: Sbx.statusKind(sandbox.status)
  readonly property bool running: kind === "running"
  readonly property bool busy: kind === "busy"
  readonly property bool hung: kind === "alert"
  readonly property bool hot: hover.hovered || current
  readonly property var mounts: (sandbox.workspaces || []).map(function(w) { return Sbx.splitMount(w) })
  readonly property var agentInfo: Sbx.agent(sandbox.agent)
  readonly property int sessions: detail && detail.sessions !== undefined ? Number(detail.sessions) : -1
  readonly property var ports: sandbox.ports instanceof Array ? sandbox.ports : []
  readonly property string name: String(sandbox.name || "")
  readonly property bool locked: panel.isProtected(name)
  readonly property bool removeArmed: panel.armedKey === "rm:" + name
  readonly property bool unlockArmed: panel.armedKey === "unprotect:" + name
  readonly property bool editing: portInput.activeFocus
  property bool portEdit: false
  readonly property bool portBusy: panel.svc.isBusy("ports:" + name)

  // A Start, Stop or Remove in progress takes the folder line: verb, seconds
  // so far and sbx's last line; a light runs along the bottom edge.
  readonly property var job: panel.svc.jobs["rm:" + name] || panel.svc.jobs["stop:" + name] || panel.svc.jobs["attach:" + name] || null
  readonly property bool removing: panel.svc.jobs["rm:" + name] !== undefined
  readonly property bool starting: panel.svc.jobs["attach:" + name] !== undefined

  ElapsedSeconds { id: cardTimer; active: root.job !== null; since: root.job ? root.job.since : 0 }
  readonly property int jobSeconds: cardTimer.seconds

  readonly property string stateLine: {
    if (running) return "RUNNING" + (detail && detail.uptime ? " · " + String(detail.uptime).toUpperCase() : "")
    if (hung || busy) return String(sandbox.status).toUpperCase()
    var used = Sbx.ago(sandbox.last_used_at)
    return "STOPPED" + (used ? " · USED " + used.toUpperCase() : "")
  }

  implicitHeight: content.implicitHeight + pad * 2

  // A card that goes away while its port field has the keyboard hands the
  // keyboard back to the popup.
  Component.onDestruction: if (portInput.activeFocus) Qt.callLater(root.panel.focusKeys)
  readonly property real pad: Style.space(12)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.expanded ? 0.05 : (root.hot ? 0.045 : 0.018))
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  HudFrame {
    anchors.fill: parent
    color: root.current ? root.panel.accent
      : root.hung ? Qt.rgba(root.panel.urgent.r, root.panel.urgent.g, root.panel.urgent.b, 0.8)
      : root.running ? Qt.rgba(root.panel.accent.r, root.panel.accent.g, root.panel.accent.b, root.hot ? 0.9 : 0.6)
      : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.hot ? 0.5 : 0.25)
    arm: Style.space(root.expanded ? 12 : 9)
    Behavior on arm { NumberAnimation { duration: 160 } }
  }

  SweepBar {
    visible: root.job !== null
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    anchors.bottomMargin: Style.space(5)
    running: root.job !== null && root.panel.opened
    color: root.removing ? root.panel.urgent : root.panel.accent
    foreground: root.fg
  }

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }

  Column {
    id: content
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: Style.space(6)

    // ---- line 1: light · name · agent ............ state
    Item {
      width: parent.width
      implicitHeight: Math.max(nameText.implicitHeight, stateText.implicitHeight, agentChip.implicitHeight)

      StatusLed {
        id: led
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        mode: root.hung ? "alert" : root.busy ? "busy" : root.running ? "running" : "stopped"
        animate: root.panel.opened
        foreground: root.fg
        accent: root.panel.accent
        urgent: root.panel.urgent
      }

      Text {
        id: nameText
        textFormat: Text.PlainText
        anchors.left: led.right
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - led.width - agentChip.width - (lockChip.visible ? lockChip.width + Style.space(6) : 0) - stateText.implicitWidth - Style.space(40))
        elide: Text.ElideRight
        text: String(root.sandbox.name || "")
        color: root.fg
        font.family: root.panel.ff
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Chip {
        id: agentChip
        anchors.left: nameText.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.sandbox.agent || "")
        foreground: root.fg
        fontFamily: root.panel.ff
      }

      Chip {
        id: lockChip
        visible: root.locked
        anchors.left: agentChip.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: "protected"
        iconText: root.panel.icons.shield
        foreground: root.fg
        fontFamily: root.panel.ff
      }

      Text {
        id: stateText
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.stateLine
        color: root.hung ? root.panel.urgent : root.running || root.busy ? root.panel.accent : root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }
    }

    // ---- line 2: workspace ............ sessions · ports · quick actions
    Item {
      width: parent.width
      implicitHeight: Math.max(pathText.implicitHeight, quick.implicitHeight)

      Text {
        id: pathText
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: led.width + Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - anchors.leftMargin - meta.width - quick.width - Style.space(24))
        elide: Text.ElideMiddle
        text: root.job ? (root.removing ? "Removing" : root.starting ? "Starting" : "Stopping") + "  ·  " + root.jobSeconds + " s" + (root.job.last ? "  ·  " + root.job.last : "")
          : root.mounts.length
          ? root.panel.icons.folder + "  " + Sbx.prettyPath(root.mounts[0].path, root.panel.home) + (root.mounts.length > 1 ? "  +" + (root.mounts.length - 1) : "")
          : root.panel.icons.cube + "  no host folder"
        color: root.job ? (root.removing ? root.panel.urgent : root.panel.accent) : root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        id: meta
        anchors.right: quick.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Repeater {
          model: root.ports.slice(0, 2)
          Chip {
            required property var modelData
            text: typeof modelData === "string" ? modelData : JSON.stringify(modelData)
            caps: false
            foreground: root.fg
            fontFamily: root.panel.ff
          }
        }

        Text {
          visible: root.sessions > 0
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: root.sessions + (root.sessions === 1 ? " SESSION" : " SESSIONS")
          color: root.panel.dim
          font.family: root.panel.ff
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.0
        }
      }

      Row {
        id: quick
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        opacity: root.hot || root.expanded ? 1 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        PanelActionButton {
          iconText: root.panel.icons.play
          tooltipText: root.running ? "Open the agent session" : "Start and open the agent"
          foreground: root.fg
          hoverColor: root.panel.accent
          fontFamily: root.panel.ff
          onClicked: root.action("attach")
        }
        PanelActionButton {
          iconText: root.panel.icons.console
          tooltipText: root.running ? "Open a shell inside" : "Start it and open a shell inside"
          foreground: root.fg
          hoverColor: root.panel.accent
          fontFamily: root.panel.ff
          onClicked: root.action("shell")
        }
        // The lock protects with one click; unprotecting takes two.
        PanelActionButton {
          iconText: root.locked ? root.panel.icons.lock : root.panel.icons.lockOpen
          tooltipText: !root.locked ? "Protect: no Stop, Remove or Prune from here"
            : root.unlockArmed ? "Click again to unprotect" : "Protected: click twice to unprotect"
          enabled: !root.panel.protecting
          foreground: root.locked ? root.panel.accent : root.fg
          hoverColor: root.panel.accent
          fontFamily: root.panel.ff
          onClicked: root.action(root.locked ? "unprotect" : "protect")
        }
        // On a protected sandbox Stop and Remove stay clickable but dim, so the
        // tooltip and a click can say why nothing happens.
        PanelActionButton {
          iconText: root.panel.icons.stop
          tooltipText: root.locked ? "Protected: " + root.name + " is not stopped from here"
            : root.running ? "Stop (files and installed tools stay)" : "Already stopped"
          enabled: root.running && !root.panel.svc.isBusy("stop:" + root.name)
          foreground: root.locked ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4) : root.fg
          hoverColor: root.locked ? root.fg : root.panel.urgent
          fontFamily: root.panel.ff
          onClicked: root.action("stop")
        }
        PanelActionButton {
          iconText: root.expanded ? root.panel.icons.chevronUp : root.panel.icons.chevronDown
          tooltipText: root.expanded ? "Less" : "Details and more actions"
          foreground: root.fg
          fontFamily: root.panel.ff
          onClicked: root.toggled()
        }
      }
    }

    // ---- details
    Column {
      width: parent.width
      visible: root.expanded
      spacing: Style.space(8)
      topPadding: Style.space(8)

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
      }

      DetailRow {
        foreground: root.fg
        fontFamily: root.panel.ff
        label: "Workspaces"
        Column {
          spacing: Style.space(3)
          Repeater {
            model: root.mounts
            Row {
              id: mountRow
              required property var modelData
              required property int index
              spacing: Style.space(8)
              Chip {
                text: mountRow.modelData.ro ? "ro" : "rw"
                tone: mountRow.modelData.ro ? root.fg : root.panel.accent
                strong: !mountRow.modelData.ro
                foreground: root.fg
                fontFamily: root.panel.ff
              }
              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Sbx.prettyPath(mountRow.modelData.path, root.panel.home) + (mountRow.index === 0 ? "   ·  primary" : "")
                color: mountRow.index === 0 ? root.fg : root.panel.dim
                font.family: root.panel.ff
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
          Text {
            visible: root.mounts.length === 0
            textFormat: Text.PlainText
            text: "None: the agent works in the sandbox's own filesystem"
            color: root.panel.dim
            font.family: root.panel.ff
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      DetailRow {
        foreground: root.fg
        fontFamily: root.panel.ff
        label: "Agent"
        value: root.agentInfo.label + (root.detail && root.detail.auth_mode ? "  ·  " + root.detail.auth_mode : "")
      }
      DetailRow {
        foreground: root.fg
        fontFamily: root.panel.ff
        label: "Image"
        value: root.detail && root.detail.image ? root.detail.image : "…"
      }
      DetailRow {
        foreground: root.fg
        fontFamily: root.panel.ff
        label: "Network"
        value: root.detail && root.detail.network_policy
          ? (root.detail.network_policy.scope === "global" ? "Global policy" : String(root.detail.network_policy.scope)) + (root.detail.proxy ? "  ·  proxy " + root.detail.proxy : "")
          : "…"
      }
      DetailRow {
        foreground: root.fg
        fontFamily: root.panel.ff
        label: "Secrets"
        value: root.detail && root.detail.secrets instanceof Array
          ? (root.detail.secrets.length ? root.detail.secrets.map(function(s) { return s.name }).join("  ·  ") : "none")
          : "…"
      }
      DetailRow {
        foreground: root.fg
        fontFamily: root.panel.ff
        label: "Ports"
        value: root.ports.length ? root.ports.join("  ·  ") : "None published"
      }
      DetailRow {
        foreground: root.fg
        fontFamily: root.panel.ff
        label: "Created"
        value: Sbx.ago(root.sandbox.created_at) + (root.sandbox.last_used_at ? "  ·  last used " + Sbx.ago(root.sandbox.last_used_at) : "")
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        topPadding: Style.space(4)

        Button {
          text: root.running ? "Open agent" : "Start agent"
          iconText: root.panel.icons.play
          bordered: true
          foreground: root.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.bodySmall
          onClicked: root.action("attach")
        }
        Button {
          text: "Shell"
          iconText: root.panel.icons.console
          bordered: true
          foreground: root.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.bodySmall
          onClicked: root.action("shell")
        }
        Button {
          visible: root.running
          enabled: !root.panel.svc.isBusy("stop:" + root.name)
          opacity: enabled && !root.locked ? 1 : 0.45
          text: enabled ? "Stop" : "Stopping …"
          tooltipText: root.locked ? "Protected (setting protectedSandboxes)" : ""
          iconText: root.panel.icons.stop
          bordered: true
          foreground: root.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.bodySmall
          onClicked: root.action("stop")
        }
        Button {
          text: "Publish port"
          iconText: root.panel.icons.lan
          bordered: true
          foreground: root.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.bodySmall
          onClicked: { root.portEdit = !root.portEdit; if (root.portEdit) portInput.forceActiveFocus() }
        }
        Button {
          visible: root.mounts.length > 0
          text: "Folder"
          iconText: root.panel.icons.folderOpen
          bordered: true
          foreground: root.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.bodySmall
          onClicked: root.action("folder")
        }
        Button {
          text: "Copy name"
          iconText: root.panel.icons.copy
          bordered: true
          foreground: root.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.bodySmall
          onClicked: root.action("copy")
        }
        Button {
          text: !enabled ? "Removing …" : root.removeArmed ? "Click again to remove" : "Remove"
          iconText: root.panel.icons.trash
          enabled: !root.panel.svc.isBusy("rm:" + root.name)
          opacity: enabled && !root.locked ? 1 : 0.45
          tooltipText: root.locked ? "Protected (setting protectedSandboxes)" : ""
          bordered: true
          foreground: root.panel.urgent
          fontFamily: root.panel.ff
          fontSize: Style.font.bodySmall
          onClicked: root.action("remove")
        }
      }

      Row {
        visible: root.portEdit
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: portInput
          objectName: "sbxe.portInput"     // SandboxesTab.editing looks for it
          width: parent.width - publishButton.width - parent.spacing
          placeholderText: "Port to publish, e.g. 3000 or 8080:3000"
          placeholderTextColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4)
          foreground: root.fg
          accent: root.panel.accent
          font.family: root.panel.ff
          font.pixelSize: Style.font.bodySmall
          verticalPadding: Style.space(5)
          onAccepted: publishButton.clicked()
        }
        Button {
          id: publishButton
          text: "Publish"
          bordered: true
          foreground: root.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.bodySmall
          enabled: portInput.text.trim() !== "" && !root.portBusy
          // the text stays when the port is refused, so it can be corrected
          onClicked: if (root.panel.publishPort(root.sandbox, portInput.text)) { portInput.text = ""; root.portEdit = false }
        }
      }
    }
  }
}
