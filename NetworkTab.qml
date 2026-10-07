pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "Sbx.js" as Sbx

// What the sandboxes reach: pending approvals first (answer them here), then
// recent blocked and allowed hosts, then the rules, with a line to add one.
Item {
  id: root

  required property var panel
  readonly property var svc: panel.svc

  property string activity: "blocked"     // blocked | allowed
  property string ruleScope: ""           // "" = all sandboxes, else a sandbox name
  // the chosen sandbox, as long as it still exists
  readonly property string effectiveScope: (svc.sandboxes || []).some(function(s) { return s.name === root.ruleScope }) ? ruleScope : ""
  readonly property bool editing: ruleInput.activeFocus

  readonly property var activityRows: (activity === "blocked" ? svc.blockedHosts : svc.allowedHosts) || []
  readonly property var editableRules: (svc.rules || []).filter(function(r) { return r.resource_type === "network" })

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

      // ============================================================ approvals
      HudHeader {
        width: parent.width
        text: "Waiting for you"
        trailing: root.svc.approvals.length ? root.svc.approvals.length + " pending" : "none"
        trailingAlert: root.svc.approvals.length > 0
        foreground: root.panel.fg
        accent: root.panel.accent
        urgent: root.panel.urgent
        fontFamily: root.panel.ff
      }

      Text {
        visible: root.svc.approvals.length === 0
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "When an agent asks for a host your policy does not allow, the request shows up here."
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.svc.approvals

        Item {
          id: approval
          required property var modelData
          // The host comes from what the agent tried to reach. Allow and
          // Block are offered only for one plain host (see Sbx.isPlainHost).
          readonly property bool plain: Sbx.isPlainHost(modelData.title)
          width: column.width
          implicitHeight: approvalRow.implicitHeight + Style.space(16)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(root.panel.urgent.r, root.panel.urgent.g, root.panel.urgent.b, 0.07)
          }
          HudFrame {
            anchors.fill: parent
            color: Qt.rgba(root.panel.urgent.r, root.panel.urgent.g, root.panel.urgent.b, 0.7)
            arm: Style.space(7)
          }

          Item {
            id: approvalRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(8)
            implicitHeight: Math.max(approvalText.implicitHeight, approvalButtons.implicitHeight)

            StatusLed {
              id: approvalLed
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              mode: "alert"
              animate: root.panel.opened
              foreground: root.panel.fg
              accent: root.panel.accent
              urgent: root.panel.urgent
            }
            Column {
              id: approvalText
              anchors.left: approvalLed.right
              anchors.leftMargin: Style.space(10)
              anchors.right: approvalButtons.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                width: parent.width
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: Sbx.host(approval.modelData.title)
                color: root.panel.fg
                font.family: root.panel.ff
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: approval.modelData.sandbox.toUpperCase() + "  ·  " + approval.modelData.detail.replace(/Protocol: (\S+) Resource type: (\S+) /, "$1 $2 · ")
                color: root.panel.dim
                font.family: root.panel.ff
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: !approval.plain
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.panel.icons.alert + "  Not a plain host name, so Allow could open more than one host. Answer it with sbx policy approval if you trust it."
                color: root.panel.urgent
                font.family: root.panel.ff
                font.pixelSize: Style.font.caption
              }
            }
            Row {
              id: approvalButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Repeater {
                model: (approval.modelData.options || []).filter(function(o) { return approval.plain || !/^allow/i.test(o.id) })
                Button {
                  required property var modelData
                  text: modelData.label
                  bordered: true
                  selected: modelData.id === "allow"
                  foreground: modelData.id === "allow" ? root.panel.fg : root.panel.dim
                  fontFamily: root.panel.ff
                  fontSize: Style.font.caption
                  tooltipText: modelData.id === "allow" ? "Allow this host from now on" : modelData.id === "dismiss" ? "Keep it blocked and drop the request" : ""
                  onClicked: root.panel.answerApproval(approval.modelData, modelData.id)
                }
              }
              Button {
                visible: approval.plain
                text: "Block"
                bordered: true
                foreground: root.panel.urgent
                fontFamily: root.panel.ff
                fontSize: Style.font.caption
                tooltipText: "Add a deny rule for " + Sbx.host(approval.modelData.title) + " on " + (approval.modelData.sandbox || "this sandbox") + ", then drop this request"
                onClicked: root.panel.blockApproval(approval.modelData)
              }
            }
          }
        }
      }

      // ============================================================ activity
      Item {
        width: parent.width
        implicitHeight: activityHeader.implicitHeight

        HudHeader {
          id: activityHeader
          anchors.left: parent.left
          anchors.right: activitySwitch.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: "Activity"
          trailing: root.svc.policyAt ? "updated " + Sbx.clock(new Date(root.svc.policyAt).toISOString()) : "loading"
          foreground: root.panel.fg
          accent: root.panel.accent
          urgent: root.panel.urgent
          fontFamily: root.panel.ff
        }
        ButtonGroup {
          id: activitySwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: activityHeader.topGap / 2
          focusable: false
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.caption
          value: root.activity
          options: [
            { value: "blocked", label: "Blocked " + (root.svc.blockedHosts || []).length },
            { value: "allowed", label: "Allowed " + (root.svc.allowedHosts || []).length }
          ]
          onChanged: function(v) { root.activity = v }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: root.activityRows.slice(0, 12)

          Item {
            id: hostRow
            required property var modelData
            readonly property bool blocked: root.activity === "blocked"
            width: column.width
            implicitHeight: Math.max(hostText.implicitHeight, rowButton.implicitHeight) + Style.space(6)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: hostHover.hovered ? Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.05) : "transparent"
            }
            HoverHandler { id: hostHover }

            Text {
              id: mark
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: hostRow.blocked ? root.panel.icons.cancel : root.panel.icons.check
              color: hostRow.blocked ? root.panel.urgent : root.panel.accent
              font.family: root.panel.ff
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              id: hostText
              anchors.left: mark.right
              anchors.leftMargin: Style.space(8)
              anchors.right: count.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideMiddle
              textFormat: Text.PlainText
              text: Sbx.host(hostRow.modelData.host) + "   " + String(hostRow.modelData.vm_name || "")
              color: root.panel.fg
              font.family: root.panel.ff
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              id: count
              anchors.right: rowButton.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: hostRow.modelData.count_since + "×  " + Sbx.clock(hostRow.modelData.last_seen)
              color: root.panel.dim
              font.family: root.panel.ff
              font.pixelSize: Style.font.caption
            }
            Button {
              id: rowButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              // hosts in the log come from what an agent tried to reach
              visible: Sbx.isPlainHost(hostRow.modelData.host)
              opacity: hostHover.hovered ? 1 : 0
              text: hostRow.blocked ? "Allow" : "Block"
              foreground: hostRow.blocked ? root.panel.fg : root.panel.urgent
              fontFamily: root.panel.ff
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              tooltipText: (hostRow.blocked ? "Allow " : "Block ") + Sbx.ruleHost(hostRow.modelData.host) + (root.effectiveScope ? " for " + root.effectiveScope : " for every sandbox")
              onClicked: root.panel.addRule(hostRow.blocked ? "allow" : "deny", Sbx.ruleHost(hostRow.modelData.host), root.effectiveScope)
            }
          }
        }

        Text {
          visible: root.activityRows.length === 0
          textFormat: Text.PlainText
          text: root.svc.policyAt ? "Nothing " + root.activity + " recently." : "Loading the policy log …"
          color: root.panel.dim
          font.family: root.panel.ff
          font.pixelSize: Style.font.caption
        }
      }

      // ============================================================ rules
      HudHeader {
        width: parent.width
        text: "Rules"
        trailing: root.svc.policyAt ? root.editableRules.length + " network rules" : "loading"
        foreground: root.panel.fg
        accent: root.panel.accent
        urgent: root.panel.urgent
        fontFamily: root.panel.ff
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: ruleInput
          width: parent.width - allowButton.width - blockButton.width - scopeBox.width - parent.spacing * 3
          placeholderText: "Host, *.domain, IP or CIDR"
          placeholderTextColor: Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.4)
          foreground: root.panel.fg
          font.family: root.panel.ff
          font.pixelSize: Style.font.bodySmall
          verticalPadding: Style.space(5)
        }
        Dropdown {
          id: scopeBox
          width: Style.space(150)
          showLabel: false
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          value: root.effectiveScope
          options: [{ value: "", label: "All sandboxes" }].concat((root.svc.sandboxes || []).map(function(s) { return { value: s.name, label: s.name } }))
          onChanged: function(v) {
            root.ruleScope = v
            scopeBox.value = Qt.binding(function() { return root.effectiveScope })
          }
        }
        Button {
          id: allowButton
          text: "Allow"
          bordered: true
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          fontSize: Style.font.caption
          enabled: ruleInput.text.trim() !== ""
          onClicked: { root.panel.addRule("allow", ruleInput.text.trim(), root.effectiveScope); ruleInput.text = "" }
        }
        Button {
          id: blockButton
          text: "Block"
          bordered: true
          foreground: root.panel.urgent
          fontFamily: root.panel.ff
          fontSize: Style.font.caption
          enabled: ruleInput.text.trim() !== ""
          onClicked: { root.panel.addRule("deny", ruleInput.text.trim(), root.effectiveScope); ruleInput.text = "" }
        }
      }

      Repeater {
        model: root.editableRules

        Item {
          id: ruleRow
          required property var modelData
          readonly property bool allow: modelData.decision === "allow"
          readonly property bool armed: root.panel.armedKey === "rule-rm:" + modelData.id
          readonly property var hosts: (modelData.resources || []).map(Sbx.host)
          // a rule with a generated name is titled by its hosts (Sbx.ruleTitle)
          readonly property bool byHosts: Sbx.ruleShowsHosts(modelData)
          width: column.width
          implicitHeight: ruleText.implicitHeight + Style.space(8)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: ruleHover.hovered ? Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.05) : "transparent"
          }
          HoverHandler { id: ruleHover }

          Chip {
            id: decision
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(56)
            text: ruleRow.allow ? "allow" : "deny"
            tone: ruleRow.allow ? root.panel.accent : root.panel.urgent
            strong: true
            foreground: root.panel.fg
            fontFamily: root.panel.ff
          }
          Column {
            id: ruleText
            anchors.left: decision.right
            anchors.leftMargin: Style.space(10)
            anchors.right: ruleRemove.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)
            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: Sbx.ruleTitle(ruleRow.modelData)
                + (ruleRow.byHosts && ruleRow.hosts.length === 1 ? "" : "   " + ruleRow.hosts.length + (ruleRow.hosts.length === 1 ? " host" : " hosts"))
              color: root.panel.fg
              font.family: root.panel.ff
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: (ruleRow.modelData.applies_to === "all" ? "all sandboxes" : String(ruleRow.modelData.applies_to).replace(/^sandbox:/, ""))
                + "  ·  " + String(ruleRow.modelData.provenance ? ruleRow.modelData.provenance.created_via : "")
                + (ruleRow.byHosts ? "" : "  ·  " + ruleRow.hosts.slice(0, 3).join(", ") + (ruleRow.hosts.length > 3 ? " …" : ""))
              color: root.panel.dim
              font.family: root.panel.ff
              font.pixelSize: Style.font.caption
            }
          }
          PanelActionButton {
            id: ruleRemove
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: ruleRow.modelData.editable === true
            opacity: ruleHover.hovered || ruleRow.armed ? 1 : 0
            iconText: root.panel.icons.trash
            tooltipText: ruleRow.armed ? "Click again to remove" : "Remove this rule"
            foreground: ruleRow.armed ? root.panel.urgent : root.panel.fg
            hoverColor: root.panel.urgent
            fontFamily: root.panel.ff
            onClicked: root.panel.removeRule(ruleRow.modelData)
          }
        }
      }
    }
  }
}
