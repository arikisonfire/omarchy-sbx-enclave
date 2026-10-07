pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui
import "Sbx.js" as Sbx

// The machinery: daemon and versions, health checks from `sbx diagnose`,
// stored secrets, MCP servers, templates and clean-up.
Item {
  id: root

  required property var panel
  readonly property var svc: panel.svc
  readonly property var prunePlan: panel.prunePlan()

  // While Prune removes: the job of the sandbox in work, its seconds so far,
  // and a breathing segment for it.
  readonly property var pruneJob: panel.pruning ? (svc.jobs["rm:" + panel.pruneCurrent] || null) : null

  ElapsedSeconds { id: pruneTimer; active: root.pruneJob !== null; since: root.pruneJob ? root.pruneJob.since : 0 }
  readonly property int pruneSeconds: pruneTimer.seconds

  BreathingPulse { id: pruneBreath; active: root.panel.pruning && root.panel.opened }
  readonly property real prunePulse: pruneBreath.value

  function healthColor(status) {
    return status === "fail" ? panel.urgent : status === "warn" ? panel.urgent : panel.accent
  }

  Flickable {
    id: flick
    anchors.fill: parent
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

      // ============================================================ system
      HudHeader {
        width: parent.width
        text: "System"
        trailing: root.svc.clientVersion ? "sbx " + root.svc.clientVersion : ""
        foreground: root.panel.fg
        accent: root.panel.accent
        urgent: root.panel.urgent
        fontFamily: root.panel.ff
      }

      // While the daemon starts, stops or restarts, the row says so (LED,
      // seconds, sbx's last line), only the clicked button stays, greyed
      // out, and a bar sweeps below it in the gap to the next row, so
      // nothing moves.
      Item {
        width: parent.width
        implicitHeight: Math.max(daemonText.implicitHeight, daemonButtons.implicitHeight)

        StatusLed {
          id: daemonLed
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          mode: root.panel.daemonJob ? "busy"
            : root.svc.daemon === "running" ? "running" : root.svc.daemon === "stopped" ? "stopped" : root.svc.daemon === "unresponsive" ? "alert" : "busy"
          animate: root.panel.opened
          foreground: root.panel.fg
          accent: root.panel.accent
          urgent: root.panel.urgent
        }
        Column {
          id: daemonText
          anchors.left: daemonLed.right
          anchors.leftMargin: Style.space(12)
          anchors.right: daemonButtons.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: root.panel.daemonJob ? root.panel.daemonBusy + " …"
              : root.svc.daemon === "running" ? "Daemon running" : root.svc.daemon === "stopped" ? "Daemon stopped"
              : root.svc.daemon === "unresponsive" ? "Daemon not responding: sbx commands hang" : "Checking the daemon …"
            color: root.panel.daemonJob ? root.panel.accent : root.panel.fg
            font.family: root.panel.ff
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: root.panel.daemonJob ? root.panel.daemonProgress
              : (root.svc.serverVersion ? "sandboxd " + root.svc.serverVersion + "  ·  " : "") + (root.svc.daemonLog ? Sbx.prettyPath(root.svc.daemonLog, root.panel.home) : "")
            color: root.panel.dim
            font.family: root.panel.ff
            font.pixelSize: Style.font.caption
          }
        }
        Row {
          id: daemonButtons
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Button {
            visible: root.panel.daemonJob ? root.panel.daemonVerb === "start" : root.svc.daemon === "stopped"
            enabled: !root.panel.daemonJob
            opacity: enabled ? 1 : 0.45
            text: enabled ? "Start" : "Starting …"
            iconText: root.panel.icons.power
            bordered: true
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            fontSize: Style.font.caption
            onClicked: root.panel.daemonAction("start")
          }
          Button {
            visible: root.panel.daemonJob ? root.panel.daemonVerb === "restart" : root.svc.daemon === "running" || root.svc.daemon === "unresponsive"
            enabled: !root.panel.daemonJob
            opacity: enabled ? 1 : 0.45
            text: enabled ? "Restart" : "Restarting …"
            iconText: root.panel.icons.restart
            bordered: true
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            fontSize: Style.font.caption
            tooltipText: "Stops every running sandbox first"
            onClicked: root.panel.daemonAction("restart")
          }
          Button {
            visible: root.panel.daemonJob ? root.panel.daemonVerb === "stop" : root.svc.daemon === "running"
            enabled: !root.panel.daemonJob
            opacity: enabled ? 1 : 0.45
            text: enabled ? "Stop" : "Stopping …"
            iconText: root.panel.icons.stop
            bordered: true
            foreground: root.panel.urgent
            fontFamily: root.panel.ff
            fontSize: Style.font.caption
            tooltipText: "Stops every running sandbox"
            onClicked: root.panel.daemonAction("stop")
          }
        }
        SweepBar {
          visible: root.panel.daemonJob !== null
          anchors.top: parent.bottom
          anchors.topMargin: Style.space(4)
          anchors.left: daemonText.left
          anchors.right: parent.right
          running: root.panel.daemonJob !== null && root.panel.opened
          color: root.panel.daemonVerb === "stop" ? root.panel.urgent : root.panel.accent
          foreground: root.panel.fg
        }
      }

      Row {
        spacing: Style.space(6)
        Button {
          text: "Dashboard"
          iconText: root.panel.icons.monitor
          bordered: true
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.caption
          tooltipText: "sbx's own TUI dashboard in a terminal"
          onClicked: root.panel.terminal(["tui"], "tile")
        }
        Button {
          text: "Sign in"
          iconText: root.panel.icons.login
          bordered: true
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.caption
          tooltipText: "sbx login in a terminal"
          onClicked: root.panel.terminal(["login"], "float")
        }
        Button {
          text: "Daemon log"
          iconText: root.panel.icons.text
          bordered: true
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.caption
          enabled: root.svc.daemonLog !== ""
          onClicked: root.panel.openLog()
        }
      }

      // ============================================================ health
      Item {
        width: parent.width
        implicitHeight: healthHeader.implicitHeight

        HudHeader {
          id: healthHeader
          anchors.left: parent.left
          anchors.right: checkButton.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: "Health"
          trailing: root.svc.healthSummary ? root.svc.healthSummary.pass + " ok · " + root.svc.healthSummary.warn + " warn · " + root.svc.healthSummary.fail + " fail" : ""
          trailingAlert: root.svc.healthSummary && (root.svc.healthSummary.fail > 0 || root.svc.healthSummary.warn > 0)
          foreground: root.panel.fg
          accent: root.panel.accent
          urgent: root.panel.urgent
          fontFamily: root.panel.ff
        }
        Button {
          id: checkButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: healthHeader.topGap / 2
          text: root.svc.diagnosing ? "Checking …" : root.svc.health.length ? "Check again" : "Run checks"
          iconText: root.panel.icons.stethoscope
          iconSpinning: false
          bordered: true
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.caption
          tooltipText: "sbx diagnose: CLI, daemon, virtualization, disk space, sign-in"
          onClicked: root.svc.diagnose()
        }
      }

      Text {
        visible: root.svc.health.length === 0
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.svc.diagnosing ? "Running sbx diagnose …" : "Checks the CLI, the daemon, virtualization, disk space and your sign-in."
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.svc.health

        Item {
          id: check
          required property var modelData
          readonly property bool ok: modelData.status === "pass" || modelData.status === "skip"
          width: column.width
          implicitHeight: checkText.implicitHeight + Style.space(6)

          Text {
            id: checkMark
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.top: parent.top
            anchors.topMargin: Style.space(3)
            textFormat: Text.PlainText
            text: check.ok ? root.panel.icons.check : check.modelData.status === "fail" ? root.panel.icons.close : root.panel.icons.alert
            color: check.ok ? root.panel.accent : root.panel.urgent
            font.family: root.panel.ff
            font.pixelSize: Style.font.bodySmall
          }
          Column {
            id: checkText
            anchors.left: checkMark.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Style.space(3)
            spacing: Style.space(1)
            Text {
              width: parent.width
              textFormat: Text.StyledText
              wrapMode: Text.WordWrap
              text: Sbx.escapeHtml(check.modelData.name + "   ") + Sbx.linkify(check.modelData.message)
              color: check.ok ? root.panel.fg : root.panel.urgent
              linkColor: root.panel.accent
              font.family: root.panel.ff
              font.pixelSize: Style.font.bodySmall
              onLinkActivated: function(link) { Quickshell.execDetached(["xdg-open", link]) }
            }
            Text {
              visible: !check.ok && String(check.modelData.hint || "") !== ""
              width: parent.width
              textFormat: Text.StyledText
              wrapMode: Text.WordWrap
              text: Sbx.linkify(check.modelData.hint)
              color: root.panel.dim
              linkColor: root.panel.accent
              font.family: root.panel.ff
              font.pixelSize: Style.font.caption
              onLinkActivated: function(link) { Quickshell.execDetached(["xdg-open", link]) }
            }
          }
        }
      }

      // ============================================================ secrets
      Item {
        width: parent.width
        implicitHeight: secretsHeader.implicitHeight

        HudHeader {
          id: secretsHeader
          anchors.left: parent.left
          anchors.right: addSecret.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: "Secrets"
          trailing: root.svc.catalogLoading ? "loading" : root.svc.secrets.length + " stored"
          foreground: root.panel.fg
          accent: root.panel.accent
          urgent: root.panel.urgent
          fontFamily: root.panel.ff
        }
        Dropdown {
          id: addSecret
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: secretsHeader.topGap / 2
          width: Style.space(170)
          showLabel: false
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          value: ""
          options: [{ value: "", label: "Add a key …" }].concat(["anthropic", "openai", "github", "google", "copilot", "cursor", "devin", "droid", "groq", "mistral", "nebius", "openrouter", "xai"].map(function(s) { return { value: s, label: s } }))
          // Dropdown keeps what was picked; it is a menu here, so it goes back
          // to "Add a key …" right away
          onChanged: function(v) {
            if (v !== "") root.panel.terminal(["secret", "set", v], "float")
            addSecret.value = ""
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "The proxy injects these into the agent's requests; they never enter a sandbox. You type a value in a terminal, never in this popup."
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.svc.secrets

        Item {
          id: secret
          required property var modelData
          readonly property string name: String(modelData.name || "")
          readonly property bool armed: name !== "" && root.panel.armedKey === "secret:" + name + ":" + String(modelData.scope || "")
          width: column.width
          implicitHeight: secretText.implicitHeight + Style.space(8)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: secretHover.hovered ? Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.05) : "transparent"
          }
          HoverHandler { id: secretHover }

          Text {
            id: secretText
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.right: secretRemove.left
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.panel.icons.key + "  " + String(secret.modelData.name || secret.modelData.placeholder || "") + "   "
              + String(secret.modelData.scope || "") + " · " + String(secret.modelData.type || "") + " · " + String(secret.modelData.secret || "")
            color: root.panel.fg
            font.family: root.panel.ff
            font.pixelSize: Style.font.bodySmall
          }
          // custom secrets have no service name to remove them by
          PanelActionButton {
            id: secretRemove
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: secret.name !== ""
            opacity: secretHover.hovered || secret.armed ? 1 : 0
            iconText: root.panel.icons.trash
            tooltipText: secret.armed ? "Click again to delete" : "Remove this secret"
            foreground: secret.armed ? root.panel.urgent : root.panel.fg
            hoverColor: root.panel.urgent
            fontFamily: root.panel.ff
            onClicked: root.panel.removeSecret(secret.modelData)
          }
        }
      }

      // ============================================================ mcp
      HudHeader {
        width: parent.width
        text: "MCP servers"
        trailing: root.svc.mcpGateway ? String(root.svc.mcpGateway.name || "") + (root.svc.mcpGateway.signed_in_as ? " · " + root.svc.mcpGateway.signed_in_as : "") : ""
        foreground: root.panel.fg
        accent: root.panel.accent
        urgent: root.panel.urgent
        fontFamily: root.panel.ff
      }
      Repeater {
        model: root.svc.mcpServers
        Text {
          required property var modelData
          width: column.width
          leftPadding: Style.space(4)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: root.panel.icons.puzzle + "  " + modelData.name + "   " + String(modelData.transport || "") + " · " + String(modelData.status || "")
          color: root.panel.fg
          font.family: root.panel.ff
          font.pixelSize: Style.font.bodySmall
        }
      }
      Text {
        visible: root.svc.mcpServers.length === 0
        textFormat: Text.PlainText
        text: root.svc.catalogLoading ? "Loading …" : "None registered. Add one with sbx mcp add (see Guide)."
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      // ============================================================ templates
      HudHeader {
        width: parent.width
        text: "Templates"
        trailing: root.svc.catalogLoading ? "loading" : root.svc.templates.length + " images"
        foreground: root.panel.fg
        accent: root.panel.accent
        urgent: root.panel.urgent
        fontFamily: root.panel.ff
      }
      Repeater {
        model: root.svc.templates
        Text {
          required property var modelData
          width: column.width
          leftPadding: Style.space(4)
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
          text: root.panel.icons.package + "  " + String(modelData.repository || "").replace(/^docker\.io\//, "") + ":" + String(modelData.tag || "") + "   " + Sbx.bytes(modelData.size) + " · " + Sbx.ago(modelData.created_at)
          color: root.panel.fg
          font.family: root.panel.ff
          font.pixelSize: Style.font.bodySmall
        }
      }

      // ============================================================ clean-up
      HudHeader {
        width: parent.width
        text: "Clean up"
        trailing: root.svc.pruneLoading ? "loading" : root.svc.pruneCandidates.length + " stopped"
        foreground: root.panel.fg
        accent: root.panel.accent
        urgent: root.panel.urgent
        fontFamily: root.panel.ff
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.prunePlan.remove.length
          ? "Prune removes these stopped sandboxes and everything installed inside them: " + root.prunePlan.remove.join(", ") + ". Your project folders stay."
            + (root.prunePlan.keep.length ? " Protected, so they stay too: " + root.prunePlan.keep.join(", ") + "." : "")
          : root.prunePlan.keep.length ? "Only protected sandboxes are stopped (" + root.prunePlan.keep.join(", ") + "); Prune leaves them alone."
          : root.svc.pruneLoading ? "Loading …" : "No stopped sandboxes to prune."
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }
      Button {
        visible: root.prunePlan.remove.length > 0 || root.panel.pruneCheckAt > 0 || root.panel.armedKey === "prune" || root.panel.pruning
        enabled: !root.panel.pruning && root.panel.pruneCheckAt === 0
        opacity: enabled ? 1 : 0.45
        text: root.panel.pruning ? "Removing …"
          : root.panel.pruneCheckAt > 0 ? "Checking …"
          : root.panel.armedKey === "prune" ? "Click again to remove " + root.panel.pruneNames.length
          : "Prune " + root.prunePlan.remove.length + " stopped"
        iconText: root.panel.icons.broom
        bordered: true
        foreground: root.panel.urgent
        fontFamily: root.panel.ff
        fontSize: Style.font.caption
        onClicked: root.panel.prune()
      }

      // Below the button, so nothing above it moves: one segment per sandbox
      // (removed, in work, to come) and the one in work.
      Column {
        width: parent.width
        visible: root.panel.pruning
        spacing: Style.space(6)

        Row {
          id: pruneTrack
          readonly property int count: Math.max(1, root.panel.pruneNames.length)
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: pruneTrack.count

            Rectangle {
              required property int index
              width: (pruneTrack.width - pruneTrack.spacing * (pruneTrack.count - 1)) / pruneTrack.count
              height: Math.max(2, Style.space(3))
              color: index <= root.panel.pruneFinished ? root.panel.urgent : Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.14)
              opacity: index === root.panel.pruneFinished ? root.prunePulse : 1
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: "Removing " + root.panel.pruneCurrent + "  (" + Math.min(root.panel.pruneFinished + 1, pruneTrack.count) + " of " + pruneTrack.count + ")  ·  "
            + root.pruneSeconds + " s" + (root.pruneJob && root.pruneJob.last ? "  ·  " + root.pruneJob.last : "")
          color: root.panel.fg
          font.family: root.panel.ff
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
