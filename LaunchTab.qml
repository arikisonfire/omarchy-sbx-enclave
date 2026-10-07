pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Sbx.js" as Sbx

// New sandbox: folder → agent → name and Git mode → advanced options. The
// command at the bottom is always the exact `sbx run` that Launch starts.
Item {
  id: root

  required property var panel
  readonly property var svc: panel.svc
  readonly property var spec: panel.spec

  // The folder as typed may end in "/" (you are still typing); this is the
  // folder itself.
  readonly property string path: Sbx.cleanPath(spec.path)

  // What `checkedPath` is: "" (none or not checked yet) | "relative" (not a
  // full path) | "missing" | "git" | "plain" | "unknown" (the check gave no
  // answer in time). Launch waits until the folder in the form is the one
  // checked.
  property string folderKind: ""
  property string checkedPath: ""
  property string branch: ""
  readonly property bool folderOk: checkedPath === path && (folderKind === "git" || folderKind === "plain")

  readonly property string effectiveName: spec.name !== "" ? spec.name : Sbx.defaultName(spec.agent, path)
  readonly property string nameIssue: Sbx.nameProblem(spec.name)
  readonly property var agentInfo: Sbx.agent(spec.agent)
  readonly property var launchSpec: Object.assign({}, spec, { path: path, name: effectiveName, clone: spec.clone && folderKind === "git" })
  readonly property var runArgv: Sbx.launchArgs(launchSpec, "run")
  readonly property var createArgv: Sbx.launchArgs(launchSpec, "create")
  readonly property bool ready: path !== "" && folderOk && nameIssue === ""

  // A sandbox already answers to this name: Launch reattaches instead.
  readonly property var existing: {
    var list = svc.sandboxes || []
    for (var i = 0; i < list.length; i++) if (list[i].name === effectiveName) return list[i]
    return null
  }

  // Recent folders: the workspaces of the sandboxes you have.
  readonly property var recentFolders: {
    var seen = {}
    var out = []
    var list = svc.sandboxes || []
    for (var j = 0; j < list.length; j++) {
      var w = list[j].workspaces || []
      var p = w.length ? Sbx.splitMount(w[0]).path : ""
      if (p && !seen[p]) { seen[p] = true; out.push(p) }
    }
    return out.slice(0, 8)
  }

  readonly property bool editing: pathField.activeFocus || nameField.activeFocus || ports.editing || envs.editing || deny.editing || kits.editing

  // seconds since `sbx create` started, ticking while it runs
  ElapsedSeconds { id: createTimer; active: root.svc.creating; since: root.svc.createStartedAt }
  readonly property int createSeconds: createTimer.seconds

  // the running step's segment breathes
  BreathingPulse { id: createBreath; active: root.svc.creating && root.panel.opened }
  readonly property real createPulse: createBreath.value

  // "PREPARE IMAGE" → "Prepare image"
  function stepLabel(title) {
    var t = String(title || "")
    return t.charAt(0) + t.slice(1).toLowerCase()
  }


  // A finished path (picker, terminal, recent folders).
  function setPath(p) {
    panel.setSpec("path", Sbx.cleanPath(p))
  }

  onSpecChanged: folderTimer.restart()
  Component.onCompleted: folderTimer.restart()
  // the folder may have come or gone while the popup was closed
  Connections {
    target: root.panel
    function onOpenedChanged() { if (root.panel.opened) folderTimer.restart() }
  }

  // ---------------------------------------------------------------- folder facts
  // Whether the folder exists and which Git branch it is on. This does not
  // run git: in a direct-mode workspace the agent can write .git/config,
  // and git reads it. Only the HEAD file is read (bounded, with a timeout,
  // in case .git holds something odd such as a FIFO).
  readonly property string folderScript: "exec 2>/dev/null; p=$1; [ -d \"$p\" ] || { echo missing; exit 0; }; d=$p; "
    + "while [ ! -e \"$d/.git\" ]; do [ \"$d\" = / ] && { echo plain; exit 0; }; d=$(dirname -- \"$d\"); done; "
    + "g=$d/.git; if [ -f \"$g\" ]; then l=$(head -c 4096 -- \"$g\" | head -n 1); case $l in 'gitdir: '*) g=${l#gitdir: };; *) echo plain; exit 0;; esac; "
    + "case $g in /*) ;; *) g=$d/$g;; esac; fi; "
    + "h=$(head -c 512 -- \"$g/HEAD\" 2>/dev/null | head -n 1); "
    + "case $h in 'ref: refs/heads/'*) echo \"git ${h#ref: refs/heads/}\";; 'ref: '*) echo \"git ${h#ref: }\";; "
    + "'') echo plain;; *) echo \"git ${h:0:7}\";; esac"

  Timer {
    id: folderTimer
    interval: 250
    onTriggered: {
      var p = root.path
      if (p === "") { root.folderKind = ""; root.checkedPath = ""; root.branch = ""; return }
      if (p.charAt(0) !== "/") { root.folderKind = "relative"; root.checkedPath = p; root.branch = ""; return }
      if (root.panel.demoMode) { root.folderKind = "git"; root.checkedPath = p; root.branch = "main"; return }
      if (folderProc.running) { restart(); return }
      folderProc.target = p
      folderProc.command = ["timeout", "-k", "2", "5", "bash", "-c", root.folderScript, "sbx-enclave", p]
      folderProc.running = true
    }
  }

  Process {
    id: folderProc
    property string target: ""
    stdout: StdioCollector { id: folderOut; waitForEnd: true }
    onExited: {
      var t = String(folderOut.text || "").trim()
      root.checkedPath = folderProc.target
      root.folderKind = t.indexOf("git ") === 0 ? "git" : t === "missing" ? "missing" : t === "plain" ? "plain" : "unknown"
      root.branch = root.folderKind === "git" ? t.substr(4) : ""
      // the form moved on while this ran
      if (folderProc.target !== root.path) folderTimer.restart()
    }
  }

  // ---------------------------------------------------------------- pickers
  property string pickFor: ""        // "path" | "extra"

  function browse(target) {
    if (picker.running) return
    pickFor = target
    picker.command = ["python3", panel.pluginDir + "pick-path.py", "folder",
      target === "extra" ? "Add a folder to the sandbox" : "Choose the sandbox workspace",
      root.path.charAt(0) === "/" ? root.path : panel.home]
    picker.running = true
  }

  Process {
    id: picker
    stdout: StdioCollector { id: pickerOut; waitForEnd: true }
    onExited: function(exitCode) {
      var path = String(pickerOut.text || "").trim()
      if (exitCode !== 0 || path === "") return
      if (root.pickFor === "extra") {
        var extra = (root.spec.extra || []).slice()
        if (path !== root.path && !extra.some(function(x) { return x.path === path })) extra.push({ path: path, ro: true })
        root.panel.setSpec("extra", extra)
      } else {
        root.setPath(path)
      }
    }
  }

  // Folder of the focused terminal (Omarchy's own helper). The popup is a
  // layer surface, so the terminal is still the active window.
  Process {
    id: terminalCwd
    command: ["bash", "-lc", "omarchy-cmd-terminal-cwd"]
    stdout: StdioCollector { id: cwdOut; waitForEnd: true }
    onExited: {
      var p = String(cwdOut.text || "").trim()
      if (p !== "") root.setPath(p)
    }
  }

  // ---------------------------------------------------------------- form
  Flickable {
    id: flick
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: dock.top
    anchors.bottomMargin: Style.space(10)
    contentWidth: width
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

    Column {
      id: form
      width: flick.width - (flick.contentHeight > flick.height ? Style.space(10) : 0)
      spacing: Style.space(10)

      // ============================================================ workspace
      Item {
        width: parent.width
        implicitHeight: workspaceHeader.implicitHeight

        HudHeader {
          id: workspaceHeader
          anchors.left: parent.left
          anchors.right: resetButton.left
          anchors.rightMargin: Style.space(10)
          text: "Workspace"
          trailing: root.folderKind === "git" ? "git · " + root.branch : root.folderKind === "plain" ? "folder"
            : root.folderKind === "missing" ? "not found" : root.folderKind === "relative" ? "not a full path" : ""
          trailingAlert: root.folderKind === "missing" || root.folderKind === "relative"
          foreground: root.panel.fg
          accent: root.panel.accent
          urgent: root.panel.urgent
          fontFamily: root.panel.ff
        }
        PanelActionButton {
          id: resetButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: workspaceHeader.topGap / 2
          iconText: root.panel.icons.refresh
          tooltipText: "Reset this form to defaults"
          foreground: root.panel.fg
          hoverColor: root.panel.urgent
          fontFamily: root.panel.ff
          onClicked: { root.panel.spec = root.panel.defaultSpec(); root.panel.advancedOpen = false }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: pathField
          width: parent.width - (browseButton.width + termButton.width + recentButton.width + parent.spacing * 3)
          text: root.spec.path
          placeholderText: "Folder the agent may work in, e.g. ~/Work/my-project"
          placeholderTextColor: Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.4)
          foreground: root.panel.fg
          font.family: root.panel.ff
          // stored as typed (only "~" becomes your home): normalizing here
          // would take back the "/" you just typed
          onTextEdited: root.panel.setSpec("path", Sbx.expandHome(text, root.panel.home))
        }
        PanelActionButton {
          id: browseButton
          size: pathField.height
          bordered: true
          iconText: root.panel.icons.folderOpen
          tooltipText: "Choose a folder"
          foreground: root.panel.fg
          hoverColor: root.panel.accent
          fontFamily: root.panel.ff
          onClicked: root.browse("path")
        }
        PanelActionButton {
          id: termButton
          size: pathField.height
          bordered: true
          iconText: root.panel.icons.console
          tooltipText: "Use the folder of the focused terminal"
          foreground: root.panel.fg
          hoverColor: root.panel.accent
          fontFamily: root.panel.ff
          onClicked: if (!terminalCwd.running) terminalCwd.running = true
        }
        PanelActionButton {
          id: recentButton
          size: pathField.height
          bordered: true
          iconText: root.panel.icons.history
          tooltipText: root.recentFolders.length ? "Recent folders" : "No recent folders yet"
          enabled: root.recentFolders.length > 0
          foreground: root.panel.fg
          hoverColor: root.panel.accent
          fontFamily: root.panel.ff
          onClicked: recentMenu.opened ? recentMenu.close() : recentMenu.open()

          QQC.Popup {
            id: recentMenu
            x: recentButton.width - width
            y: recentButton.height + Style.space(4)
            width: Style.space(380)
            padding: Style.space(6)
            background: Rectangle {
              color: Color.popups.background
              border.width: 1
              border.color: Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.25)
              radius: Style.cornerRadius
            }
            contentItem: Column {
              spacing: Style.space(2)
              Repeater {
                model: root.recentFolders
                Button {
                  required property string modelData
                  width: parent.width
                  leftAlign: true
                  text: Sbx.prettyPath(modelData, root.panel.home)
                  iconText: root.panel.icons.folder
                  foreground: root.panel.fg
                  fontFamily: root.panel.ff
                  fontSize: Style.font.bodySmall
                  onClicked: { root.setPath(modelData); recentMenu.close() }
                }
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        visible: text !== ""
        text: root.folderKind === "missing" ? root.panel.icons.alert + "  This folder does not exist."
          : root.folderKind === "relative" ? root.panel.icons.alert + "  Use a full path, e.g. ~/Work/my-project."
          : root.folderKind === "unknown" ? root.panel.icons.alert + "  Could not check this folder: it did not answer in time."
          : root.existing ? root.panel.icons.swap + "  \"" + root.effectiveName + "\" exists (" + root.existing.status + "): Launch reattaches to it, the options below only apply to new sandboxes."
          : root.folderKind === "git" ? root.panel.icons.git + "  Git repository on " + root.branch + ". The agent sees this folder at the same path; nothing else of your home."
          : root.folderKind === "plain" ? root.panel.icons.folder + "  The agent sees this folder at the same path; nothing else of your home."
          : ""
        color: root.folderKind === "missing" || root.folderKind === "relative" || root.folderKind === "unknown" ? root.panel.urgent : root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      // extra folders
      Repeater {
        model: root.spec.extra || []

        Row {
          id: extraRow
          required property var modelData
          required property int index
          width: form.width
          spacing: Style.space(8)

          ButtonGroup {
            anchors.verticalCenter: parent.verticalCenter
            focusable: false
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            fontSize: Style.font.caption
            value: extraRow.modelData.ro ? "ro" : "rw"
            options: [{ value: "ro", label: "RO", tooltip: "Read-only: the agent can look, not change" }, { value: "rw", label: "RW", tooltip: "Read-write" }]
            onChanged: function(v) {
              var extra = root.spec.extra.slice()
              extra[extraRow.index] = { path: extraRow.modelData.path, ro: v === "ro" }
              root.panel.setSpec("extra", extra)
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(140)
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            text: Sbx.prettyPath(extraRow.modelData.path, root.panel.home)
            color: root.panel.fg
            font.family: root.panel.ff
            font.pixelSize: Style.font.bodySmall
          }
          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.panel.icons.close
            tooltipText: "Remove this folder"
            foreground: root.panel.fg
            hoverColor: root.panel.urgent
            fontFamily: root.panel.ff
            onClicked: {
              var extra = root.spec.extra.slice()
              extra.splice(extraRow.index, 1)
              root.panel.setSpec("extra", extra)
            }
          }
        }
      }

      Button {
        text: "Add another folder"
        iconText: root.panel.icons.folderPlus
        foreground: root.panel.fg
        fontFamily: root.panel.ff
        fontSize: Style.font.caption
        tooltipText: "Mounted read-only unless you switch it to RW"
        onClicked: root.browse("extra")
      }

      // ============================================================ agent
      HudHeader {
        width: parent.width
        text: "Agent"
        trailing: root.agentInfo.vendor
        foreground: root.panel.fg
        accent: root.panel.accent
        urgent: root.panel.urgent
        fontFamily: root.panel.ff
      }

      Flow {
        id: agents
        width: parent.width
        spacing: Style.space(6)
        readonly property int columns: 4
        readonly property real tileWidth: Math.floor((width - spacing * (columns - 1)) / columns)

        Repeater {
          model: Sbx.AGENTS

          Item {
            id: tile
            required property var modelData
            readonly property bool chosen: root.spec.agent === modelData.id
            readonly property bool hot: tileMouse.containsMouse
            width: agents.tileWidth
            implicitHeight: tileText.implicitHeight + Style.space(14)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: tile.chosen ? Qt.rgba(root.panel.accent.r, root.panel.accent.g, root.panel.accent.b, 0.13)
                : Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, tile.hot ? 0.06 : 0.02)
              border.width: 1
              border.color: tile.chosen ? Qt.rgba(root.panel.accent.r, root.panel.accent.g, root.panel.accent.b, 0.7)
                : Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, tile.hot ? 0.3 : 0.12)
              Behavior on color { ColorAnimation { duration: 120 } }
            }
            HudFrame {
              anchors.fill: parent
              visible: tile.chosen
              color: root.panel.accent
              arm: Style.space(6)
              stroke: Math.max(2, Style.space(2))
            }
            Column {
              id: tileText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: tile.modelData.label
                color: root.panel.fg
                font.family: root.panel.ff
                font.pixelSize: Style.font.bodySmall
                font.bold: tile.chosen
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: tile.modelData.vendor
                color: tile.chosen ? root.panel.accent : root.panel.dim
                font.family: root.panel.ff
                font.pixelSize: Style.font.caption
              }
            }
            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.panel.setSpec("agent", tile.modelData.id)
            }
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.agentInfo.secret && root.panel.hasSecret(root.agentInfo.secret)
          ? root.panel.icons.check + "  Your " + root.agentInfo.secret + " credentials are stored: the proxy signs the agent in, the key never enters the sandbox."
          : root.panel.icons.key + "  " + root.agentInfo.login
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      // ============================================================ name + mode
      Row {
        width: parent.width
        spacing: Style.space(14)

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.space(8)

          HudHeader {
            width: parent.width
            text: "Name"
            foreground: root.panel.fg
            accent: root.panel.accent
            urgent: root.panel.urgent
            fontFamily: root.panel.ff
          }
          TextField {
            id: nameField
            width: parent.width
            text: root.spec.name
            placeholderText: Sbx.defaultName(root.spec.agent, root.path)
            placeholderTextColor: Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.4)
            foreground: root.panel.fg
            font.family: root.panel.ff
            onTextEdited: root.panel.setSpec("name", text.trim())
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.nameIssue !== "" ? root.panel.icons.alert + "  " + root.nameIssue
              : root.spec.name === "" ? "Empty: sbx uses " + root.effectiveName
              : "Reattach later with: sbx run --name " + root.effectiveName
            color: root.nameIssue !== "" ? root.panel.urgent : root.panel.dim
            font.family: root.panel.ff
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.space(8)

          HudHeader {
            width: parent.width
            text: "Git mode"
            foreground: root.panel.fg
            accent: root.panel.accent
            urgent: root.panel.urgent
            fontFamily: root.panel.ff
          }
          ButtonGroup {
            focusable: false
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            fontSize: Style.font.bodySmall
            value: root.spec.clone && root.folderKind === "git" ? "clone" : "direct"
            options: [
              { value: "direct", label: "Direct", tooltip: "The agent edits your folder; changes show up immediately" },
              { value: "clone", label: "Clone", tooltip: root.folderKind === "git" ? "The agent works on a private clone; you fetch its commits" : "Needs a Git repository" }
            ]
            onChanged: function(v) { if (v === "direct" || root.folderKind === "git") root.panel.setSpec("clone", v === "clone") }
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.spec.clone && root.folderKind === "git"
              ? "Your files stay untouched. Get the agent's commits with: git fetch sandbox-" + root.effectiveName
              : "The agent writes straight into your folder. Review with git diff."
            color: root.panel.dim
            font.family: root.panel.ff
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ============================================================ advanced
      Item {
        width: parent.width
        implicitHeight: advHeader.implicitHeight + Style.space(4)

        HudHeader {
          id: advHeader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: (root.panel.advancedOpen ? "▾ " : "▸ ") + "Advanced"
          trailing: root.panel.advancedSummary()
          foreground: root.panel.fg
          accent: root.panel.accent
          urgent: root.panel.urgent
          fontFamily: root.panel.ff
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.panel.advancedOpen = !root.panel.advancedOpen
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.panel.advancedOpen

        DetailRow {
          label: "CPUs"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          ButtonGroup {
            focusable: false
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            fontSize: Style.font.caption
            value: String(root.spec.cpus || 0)
            options: [{ value: "0", label: "Auto", tooltip: "All host CPUs (at most 16 on arm64)" }, "2", "4", "8"]
            onChanged: function(v) { root.panel.setSpec("cpus", Number(v)) }
          }
        }
        DetailRow {
          label: "Memory"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          ButtonGroup {
            focusable: false
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            fontSize: Style.font.caption
            value: root.spec.memory || ""
            options: [{ value: "", label: "Auto", tooltip: "Half the host memory, 512 MiB to 32 GiB" }, { value: "4g", label: "4 GB" }, { value: "8g", label: "8 GB" }, { value: "16g", label: "16 GB" }]
            onChanged: function(v) { root.panel.setSpec("memory", v) }
          }
        }
        DetailRow {
          label: "Ports"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          TokenField {
            id: ports
            width: parent.width
            values: root.spec.ports || []
            placeholder: "8080:3000 publishes sandbox port 3000 on localhost:8080"
            validate: function(v) { return /^((\[?[0-9a-fA-F:.]+\]?:)?\d{1,5}:)?\d{1,5}(\/(tcp|tcp4|tcp6|udp|udp4|udp6))?$/.test(v) ? "" : "Use [[HOST_IP:]HOST_PORT:]SANDBOX_PORT[/PROTOCOL], e.g. 8080:3000" }
            foreground: root.panel.fg
            accent: root.panel.accent
            urgent: root.panel.urgent
            fontFamily: root.panel.ff
            onChanged: function(values) { root.panel.setSpec("ports", values) }
          }
        }
        DetailRow {
          label: "Variables"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          TokenField {
            id: envs
            width: parent.width
            values: root.spec.env || []
            placeholder: "KEY=value · not for secrets: store those under Setup"
            validate: function(v) { return /^[A-Za-z_][A-Za-z0-9_]*(=.*)?$/.test(v) ? "" : "Use KEY=value, or a bare KEY to copy it from your environment" }
            foreground: root.panel.fg
            accent: root.panel.accent
            urgent: root.panel.urgent
            fontFamily: root.panel.ff
            onChanged: function(values) { root.panel.setSpec("env", values) }
          }
        }
        DetailRow {
          label: "Template"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          Dropdown {
            id: templateBox
            width: parent.width
            showLabel: false
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            value: root.spec.template || ""
            options: [{ value: "", label: "Agent default image" }].concat((root.svc.templates || []).map(function(t) {
              var ref = String(t.repository || "") + ":" + String(t.tag || "")
              return { value: ref, label: ref.replace(/^docker\.io\//, "") + "  ·  " + Sbx.bytes(t.size) }
            }))
            onChanged: function(v) {
              root.panel.setSpec("template", v)
              templateBox.value = Qt.binding(function() { return root.spec.template || "" })
            }
          }
        }
        DetailRow {
          label: "Pull"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          ButtonGroup {
            focusable: false
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            fontSize: Style.font.caption
            value: root.spec.pull || "always"
            options: [{ value: "always", label: "Always", tooltip: "Check the registry for a newer image (default)" }, { value: "missing", label: "Missing", tooltip: "Only download when there is no local copy" }, { value: "never", label: "Never", tooltip: "Offline: only use local images" }]
            onChanged: function(v) { root.panel.setSpec("pull", v) }
          }
        }
        DetailRow {
          label: "Skills"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          ButtonGroup {
            focusable: false
            foreground: root.panel.fg
            fontFamily: root.panel.ff
            fontSize: Style.font.caption
            value: root.spec.skills || ""
            options: [{ value: "", label: "Default", tooltip: "sbx default: the shared skills store, read-only" }, { value: "off", label: "Off" }, { value: "readonly", label: "Read-only" }, { value: "readwrite", label: "Read-write", tooltip: "Skills the agent writes land in the shared store" }]
            onChanged: function(v) { root.panel.setSpec("skills", v) }
          }
        }
        DetailRow {
          label: "MCP"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.svc.mcpServers || []
              Button {
                required property var modelData
                readonly property bool on: (root.spec.mcp || []).indexOf(modelData.name) >= 0
                text: modelData.name
                iconText: on ? root.panel.icons.check : root.panel.icons.plus
                selected: on
                bordered: true
                foreground: root.panel.fg
                fontFamily: root.panel.ff
                fontSize: Style.font.caption
                tooltipText: String(modelData.transport || "") + " · " + String(modelData.status || "")
                onClicked: {
                  var list = (root.spec.mcp || []).slice()
                  var at = list.indexOf(modelData.name)
                  if (at >= 0) list.splice(at, 1)
                  else list.push(modelData.name)
                  root.panel.setSpec("mcp", list)
                }
              }
            }
            Text {
              visible: (root.svc.mcpServers || []).length === 0
              textFormat: Text.PlainText
              text: root.svc.catalogLoading ? "Loading …" : "No MCP servers registered (sbx mcp add)"
              color: root.panel.dim
              font.family: root.panel.ff
              font.pixelSize: Style.font.caption
            }
          }
        }
        DetailRow {
          label: "Block"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          TokenField {
            id: deny
            width: parent.width
            values: root.spec.deny || []
            placeholder: "Hosts this sandbox may never reach, e.g. *.example.com"
            validate: function(v) { return /^[A-Za-z0-9*?.\[\]!:\/_-]+$/.test(v) ? "" : "A host, *.domain, IP or CIDR" }
            foreground: root.panel.fg
            accent: root.panel.accent
            urgent: root.panel.urgent
            fontFamily: root.panel.ff
            onChanged: function(values) { root.panel.setSpec("deny", values) }
          }
        }
        DetailRow {
          label: "Kits"
          foreground: root.panel.fg
          fontFamily: root.panel.ff
          keyWidth: Style.space(90)
          TokenField {
            id: kits
            width: parent.width
            values: root.spec.kits || []
            placeholder: "Mixin kit: ./dir, file.zip, git URL or OCI ref (experimental)"
            foreground: root.panel.fg
            accent: root.panel.accent
            urgent: root.panel.urgent
            fontFamily: root.panel.ff
            onChanged: function(values) { root.panel.setSpec("kits", values) }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- command + buttons
  Column {
    id: dock
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: Style.space(10)

    // While `sbx create` runs: one segment per step (done, running, to come;
    // the last one is the plugin's own stop), the step and the seconds so
    // far, and the last line sbx printed.
    Column {
      width: parent.width
      visible: root.svc.creating
      spacing: Style.space(6)

      Row {
        id: createTrack
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.svc.createSteps

          Rectangle {
            required property int index
            width: (createTrack.width - createTrack.spacing * (root.svc.createSteps - 1)) / root.svc.createSteps
            height: Math.max(2, Style.space(3))
            color: index <= root.svc.createDone ? root.panel.accent : Qt.rgba(root.panel.fg.r, root.panel.fg.g, root.panel.fg.b, 0.14)
            opacity: index === root.svc.createDone ? root.createPulse : 1
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: "Creating " + root.svc.createName + "  ·  step " + Math.min(root.svc.createDone + 1, root.svc.createSteps) + " of " + root.svc.createSteps
          + (root.svc.createStep ? ": " + root.stepLabel(root.svc.createStep) : "") + "  ·  " + root.createSeconds + " s"
        color: root.panel.fg
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: root.svc.createLast
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }
    }

    CommandLine {
      width: parent.width
      command: root.path !== "" ? Sbx.commandLine(root.runArgv) : "sbx run " + root.spec.agent + " <folder>"
      live: root.panel.opened
      foreground: root.panel.fg
      accent: root.panel.accent
      fontFamily: root.panel.ff
    }

    Item {
      width: parent.width
      implicitHeight: launchButton.implicitHeight

      Text {
        anchors.left: parent.left
        anchors.right: createButton.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: root.ready ? (root.existing ? "Opens a terminal attached to " + root.effectiveName : "Opens a terminal: first start pulls the image")
          : root.path === "" ? "Choose a folder to start" : ""
        color: root.panel.dim
        font.family: root.panel.ff
        font.pixelSize: Style.font.caption
      }

      Button {
        id: createButton
        anchors.right: launchButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.existing
        enabled: root.ready && !root.svc.creating
        opacity: enabled ? 1 : 0.45
        text: root.svc.creating ? "Creating …" : "Create only"
        bordered: true
        foreground: root.panel.fg
        fontFamily: root.panel.ff
        fontSize: Style.font.bodySmall
        tooltipText: "Create it in the background, stopped; start the agent later from Sandboxes"
        onClicked: root.panel.launch(root.createArgv, false)
      }

      PrimaryButton {
        id: launchButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: root.ready
        text: root.existing ? "Reattach" : "Launch"
        iconText: root.panel.icons.rocket
        fontFamily: root.panel.ff
        accent: root.panel.accent
        foreground: root.panel.fg
        onClicked: root.panel.launch(root.runArgv, true, root.spec.agent)
      }
    }
  }
}
