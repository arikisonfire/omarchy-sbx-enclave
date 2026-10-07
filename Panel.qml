import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Sbx.js" as Sbx

// sbxEnclave: Docker Sandboxes (sbx) from the bar. The bar mark shows whether
// sandboxes run and whether one waits for a network approval; the popup has
// Sandboxes · Launch · Network · Setup · Guide.
Panel {
  id: root
  moduleName: "io.github.arikisonfire.sbx-enclave"
  ipcTarget: "io.github.arikisonfire.sbx-enclave"
  manageIpc: false

  readonly property string appName: "sbxEnclave"

  // ------------------------------------------------------------------ look
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string ff: bar ? bar.fontFamily : Style.font.family
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.62)
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, ""))

  function glyph(cp) { return String.fromCodePoint(cp) }
  readonly property var icons: ({
    play: glyph(0xF040A), console: glyph(0xF018D), stop: glyph(0xF04DB), folder: glyph(0xF024B),
    folderOpen: glyph(0xF0770), folderPlus: glyph(0xF0257), history: glyph(0xF02DA), copy: glyph(0xF018F),
    trash: glyph(0xF01B4), refresh: glyph(0xF0450), plus: glyph(0xF0415), check: glyph(0xF012C),
    close: glyph(0xF0156), alert: glyph(0xF0026), shield: glyph(0xF0498), lan: glyph(0xF0317),
    key: glyph(0xF0306), rocket: glyph(0xF14DE), cube: glyph(0xF01A7), git: glyph(0xF02A2),
    chevronDown: glyph(0xF0140), chevronUp: glyph(0xF0143), power: glyph(0xF0425), restart: glyph(0xF0709),
    broom: glyph(0xF00E2), stethoscope: glyph(0xF04D9), cancel: glyph(0xF073A), swap: glyph(0xF04E1),
    monitor: glyph(0xF0379), login: glyph(0xF0342), text: glyph(0xF0EAF), puzzle: glyph(0xF0A66),
    package: glyph(0xF03D6), magnify: glyph(0xF0349), openIn: glyph(0xF03CC),
    lock: glyph(0xF033E), lockOpen: glyph(0xF0FC6)
  })

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight


  // ------------------------------------------------------------------ data
  // Demo mode (IPC `demo on`): made-up sandboxes, nothing is asked of sbx.
  // A placeholder home, not the real one — this fills the Launch form, and a
  // demo screenshot must never reveal whose machine it was taken on.
  readonly property string demoHome: "/home/demo"
  property bool demoMode: false
  onDemoModeChanged: if (demoMode) {
    spec = Object.assign(defaultSpec(), { path: demoHome + "/Work/webshop-v2", ports: ["8080:3000"], extra: [{ path: demoHome + "/Work/design-system", ro: true }], mcp: ["notion"] })
  } else spec = defaultSpec()

  SbxService {
    id: sbxService
    panelOpen: root.opened
    refreshSeconds: Number(root.setting("refreshSeconds", 15)) || 15
    demo: root.demoMode
  }
  readonly property var svc: sbxService

  // ------------------------------------------------------------------ view state
  property string tab: "sandboxes"
  readonly property var tabOrder: ["sandboxes", "launch", "network", "setup", "guide"]

  function setTab(t) {
    if (tabOrder.indexOf(t) < 0) return
    tab = t
    loadForTab()
  }

  function loadForTab() {
    if (!opened) return
    if (tab === "network") svc.loadPolicy()
    if (tab === "launch" || tab === "setup") svc.loadCatalog()
    if (tab === "setup") svc.loadPrune()
  }

  onOpenedChanged: if (opened) { loadForTab(); scan.restart() }

  // ------------------------------------------------------------------ launch spec
  property var spec: defaultSpec()
  property bool advancedOpen: false

  function defaultSpec() {
    return { path: "", agent: "claude", name: "", clone: false, extra: [], cpus: 0, memory: "",
             ports: [], env: [], envFiles: [], template: "", pull: "always", skills: "", mcp: [], kits: [], deny: [] }
  }

  function setSpec(key, value) {
    var next = Object.assign({}, spec)
    next[key] = value
    spec = next
  }

  function advancedSummary() {
    var parts = []
    parts.push(spec.cpus ? spec.cpus + " cpu" : "auto cpu")
    parts.push(spec.memory ? spec.memory : "auto ram")
    if (spec.ports.length) parts.push(spec.ports.length + " port" + (spec.ports.length > 1 ? "s" : ""))
    if (spec.env.length) parts.push(spec.env.length + " var" + (spec.env.length > 1 ? "s" : ""))
    if (spec.template) parts.push("template")
    if (spec.mcp.length) parts.push(spec.mcp.length + " mcp")
    if (spec.deny.length) parts.push(spec.deny.length + " blocked")
    if (spec.kits.length) parts.push(spec.kits.length + " kit" + (spec.kits.length > 1 ? "s" : ""))
    if (spec.pull !== "always") parts.push("pull " + spec.pull)
    if (spec.skills) parts.push("skills " + spec.skills)
    return parts.join(" · ")
  }

  function hasSecret(service) {
    var list = svc.secrets || []
    for (var i = 0; i < list.length; i++) if (list[i].name === service) return true
    return false
  }

  // ------------------------------------------------------------------ flash line
  property string flashText: ""
  property bool flashAlert: false
  function flash(text, alert) {
    flashText = String(text || "")
    flashAlert = !!alert
    flashTimer.restart()
  }
  Timer { id: flashTimer; interval: 7000; onTriggered: root.flashText = "" }

  // ------------------------------------------------------------------ actions
  function cmdLine(argv) { return Sbx.commandLine(argv, svc.sbxName) }

  // Sandboxes named in the `protectedSandboxes` setting (comma separated) get
  // no Stop or Remove, are never pruned, and block stopping or restarting the
  // daemon.
  //
  // The value comes from shell.json itself, not only from the `settings` the
  // bar hands in: when the plugin reloads, the bar hands it the entry as it
  // was when the bar was built, without the changes protect.sh made since
  // (those reach a running widget only as patches). The card then shows a
  // stale lock, and unlocking writes nothing new, so it stays. Protection
  // decides what Stop, Remove and Prune may touch, so it follows the file.
  // `setting()` is the fallback while the file has no entry for the widget.
  readonly property string pluginId: "io.github.arikisonfire.sbx-enclave"
  property var fileProtected: null      // string from shell.json, null when unknown

  FileView {
    id: protectedFile
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.fileProtected = Sbx.protectedSetting(text(), root.pluginId, "io.github.arikisonfire.bar-folder")
    onLoadFailed: root.fileProtected = null
    onFileChanged: reload()
  }

  // Demo mode protects two made-up sandboxes, so the lock and Prune's
  // "Protected, so they stay" can be seen without touching shell.json.
  readonly property var demoProtected: ["codex-api", "gemini-docs"]

  function protectedNames() {
    if (demoMode) return demoProtected
    var value = fileProtected !== null ? fileProtected : setting("protectedSandboxes", "")
    return String(value).split(",").map(function(n) { return n.trim() }).filter(function(n) { return n !== "" })
  }

  function isProtected(name) {
    return name !== "" && protectedNames().indexOf(String(name)) >= 0
  }

  function protectedRunning() {
    for (var i = 0; i < svc.sandboxes.length; i++)
      if (svc.sandboxes[i].status === "running" && isProtected(svc.sandboxes[i].name)) return svc.sandboxes[i].name
    return ""
  }

  // The lock on a card: protect.sh changes the setting in shell.json with
  // Omarchy's own helper, and protectedFile reads the new value back.
  readonly property bool protecting: protectProc.running

  function setProtected(name, on) {
    if (demoMode) { flash("Demo · would " + (on ? "protect " : "unprotect ") + name, false); return }
    if (protectProc.running) { flash("Still saving the last change …", false); return }
    protectProc.target = name
    protectProc.on = on
    protectProc.command = ["bash", pluginDir + "protect.sh", on ? "on" : "off", name]
    protectProc.running = true
  }

  Process {
    id: protectProc
    property string target: ""
    property bool on: true
    stderr: StdioCollector { id: protectErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        protectedFile.reload()
        root.flash(protectProc.target + (protectProc.on ? " is protected: no Stop, Remove or Prune from here." : " is no longer protected."), false)
      } else root.flash("Could not change the protection: " + (Sbx.errorLine(protectErr.text) || "exit code " + exitCode), true)
    }
  }

  // Two clicks for anything destructive: the first arms the key for a few
  // seconds and says what would happen, the second one runs.
  property string armedKey: ""
  Timer { id: armTimer; interval: 5000; onTriggered: root.armedKey = "" }
  function confirmed(key, question) {
    if (armedKey === key) { armedKey = ""; armTimer.stop(); return true }
    armedKey = key
    armTimer.restart()
    flash(question + "  Click again to confirm.", true)
    return false
  }

  // Runs one sbx command in the background and reports the result.
  // opts: seconds, ok (text on success), fail (text on failure), after(success)
  function run(key, argv, opts) {
    var o = opts || {}
    if (demoMode) { flash("Demo · would run:  " + cmdLine(argv), false); return }
    var started = svc.act(key, argv, o.seconds || 30, function(success, message) {
      if (success) flash((o.ok || "Done") + (message && message.length <= 90 && !o.quiet ? "  ·  " + message : ""), false)
      else flash((o.fail || "Failed") + ": " + message, true)
      if (o.after) o.after(success)
    })
    if (!started && !svc.demo) flash("Still working on the last request…", false)
  }

  // Terminal windows: "tile" opens a tiled TUI window, "float" a floating one
  // that waits for a key when the command ends. A tiled agent terminal gets a
  // per-agent window class (see Sbx.terminalAppId).
  function terminal(args, mode, agentId) {
    if (demoMode) { flash("Demo · would open a terminal:  " + cmdLine(args), false); return }
    if (mode === "float") shellFloat(cmdLine(args))
    else {
      var appId = Sbx.terminalAppId(agentId)
      var argv = ["omarchy-launch-tui"]
      if (appId !== "") argv.push("--app-id=" + appId)
      Quickshell.execDetached(argv.concat([svc.sbxName], args))
    }
    // signing in, storing a key or the dashboard change what the tabs show
    if (["login", "secret", "tui"].indexOf(String(args[0])) >= 0) svc.invalidate()
  }

  // Gives the keyboard back to the popup, e.g. after the field that had it
  // went away with its card.
  function focusKeys() { if (opened) keys.forceActiveFocus() }

  function shellFloat(script) {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", script])
  }

  function sandboxAction(kind, sandbox) {
    var name = String(sandbox.name || "")
    var path = (sandbox.workspaces || []).length ? Sbx.splitMount(sandbox.workspaces[0]).path : ""
    if (kind === "attach" || kind === "shell") {
      // `sbx exec` starts a stopped sandbox first, just like `sbx run`
      terminal(kind === "attach" ? ["run", "--name", name] : ["exec", "-it", name, "bash"], "tile",
               kind === "attach" ? sandbox.agent : "shell")
      if (demoMode) return
      // "Starting" until the list says it runs; the service reads the list
      // on every poll meanwhile (SbxService.starting)
      if (sandbox.status !== "running") svc.setJob("attach:" + name, { since: Date.now(), last: "" })
      svc.refresh()
    } else if (kind === "stop") {
      if (isProtected(name)) flash(name + " is protected, so it is not stopped from here (setting protectedSandboxes).", true)
      else run("stop:" + name, ["stop", "--", name], { seconds: 60, ok: "Stopped " + name, fail: "Could not stop " + name, quiet: true })
    } else if (kind === "remove") {
      if (isProtected(name)) flash(name + " is protected, so it is not removed from here (setting protectedSandboxes).", true)
      else if (confirmed("rm:" + name, "Remove " + name + " and everything inside it?"))
        run("rm:" + name, ["rm", "--force", "--", name], { seconds: 60, ok: "Removed " + name, fail: "Could not remove " + name, quiet: true })
    } else if (kind === "protect") setProtected(name, true)
    else if (kind === "unprotect") {
      if (confirmed("unprotect:" + name, "Unprotect " + name + "? Stop, Remove and Prune work on it again.")) setProtected(name, false)
    } else if (kind === "folder") {
      if (path.charAt(0) === "/") Quickshell.execDetached(["xdg-open", path])
    } else if (kind === "copy") copyText(name)
  }

  function publishPort(sandbox, spec) {
    var name = String(sandbox.name || "")
    var s = String(spec || "").trim()
    if (!/^([0-9.:\[\]]+:)?[0-9]+(:[0-9]+)?(\/(tcp|tcp4|tcp6|udp|udp4|udp6))?$/.test(s)) { flash("Use a port like 3000 or 8080:3000", true); return false }
    run("ports:" + name, ["ports", "--publish", s, "--", name], { ok: "Published " + s + " on " + name, fail: "Could not publish " + s, quiet: true })
    return true
  }

  // Starting, stopping or restarting the daemon takes a few seconds and
  // otherwise looks like the click did nothing, so while the job runs Setup,
  // the Sandboxes tab and the header say what is going on, with the seconds
  // and sbx's last line.
  property string daemonVerb: ""        // start | stop | restart, of the running daemon job
  readonly property var daemonJob: svc.jobs["daemon"] || null
  readonly property string daemonBusy: !daemonJob ? ""
    : (daemonVerb === "stop" ? "Stopping" : daemonVerb === "restart" ? "Restarting" : "Starting") + " the daemon"
  readonly property int daemonSeconds: daemonTimer.seconds
  readonly property string daemonProgress: !daemonJob ? ""
    : daemonSeconds + " s" + (daemonJob.last ? "  ·  " + daemonJob.last : "")
  ElapsedSeconds { id: daemonTimer; active: root.daemonJob !== null; since: root.daemonJob ? root.daemonJob.since : 0 }

  function daemonAction(action) {
    if (daemonJob) { flash(daemonBusy + " …", false); return }
    if (action === "start") {
      daemonVerb = action
      run("daemon", ["daemon", "start", "-d"], { seconds: 90, ok: "Daemon started", fail: "Could not start the daemon", quiet: true })
      return
    }
    var guarded = protectedRunning()
    if (guarded !== "" && !demoMode) { flash("Not now: " + guarded + " is protected and running, and this would stop it.", true); return }
    var running = svc.runningCount
    var question = (action === "stop" ? "Stop the daemon" : "Restart the daemon") + (running ? " and " + running + " running sandbox" + (running > 1 ? "es" : "") + "?" : "?")
    if (!confirmed("daemon:" + action, question)) return
    daemonVerb = action
    run("daemon", ["daemon", action], { seconds: action === "stop" ? 60 : 90, ok: action === "stop" ? "Daemon stopped" : "Daemon restarted", fail: "Daemon " + action + " failed", quiet: true })
  }

  // Launch attaches in a terminal. Create only runs `sbx create` in the
  // background and then stops the new sandbox (sbx would leave it running
  // for a while), the Launch tab shows the steps, and afterwards the popup
  // turns to the new sandbox's card.
  function launch(argv, attach, agentId) {
    if (attach) { terminal(argv, "tile", agentId); return }
    if (demoMode) { flash("Demo · would run:  " + cmdLine(argv), false); return }
    var i = argv.indexOf("--name")
    var name = i >= 0 ? String(argv[i + 1]) : "the sandbox"
    // Only a sandbox we can name gets stopped, and never a protected one.
    var stopAfter = i >= 0 && !isProtected(name)
    var started = svc.create(name, argv, function(ok, message) {
      if (!ok) { flash("Could not create " + name + ": " + message, true); return }
      flash("Created " + name + (message ? ".  " + message : stopAfter ? ". It stays stopped until you start it." : "."), false)
      setTab("sandboxes")
      sandboxesTab.expandName(name)
    }, stopAfter)
    if (!started) flash("Still creating " + svc.createName + " …", false)
  }


  function answerApproval(approval, option) {
    run("approval:" + approval.id, ["policy", "approval", "respond", "--option", option, "--", approval.id],
        { ok: "Answered request for " + (approval.detail || approval.title || approval.id), fail: "Could not answer", quiet: true, after: function() { svc.loadPolicy(true) } })
  }

  // host: what you typed (sbx takes a comma separated list of hosts and
  // patterns), or one plain host from the Activity list.
  function addRule(decision, host, scope) {
    var h = String(host || "").trim()
    if (h === "") return
    var argv = ["policy", decision === "deny" ? "deny" : "allow", "network"]
    if (scope) argv.push("--sandbox", scope)
    argv.push("--", h)
    run("rule:" + decision + ":" + h, argv, { ok: (decision === "deny" ? "Blocked " : "Allowed ") + h, fail: "Could not change the rule", quiet: true, after: function() { svc.loadPolicy(true) } })
  }

  // Adds a permanent deny rule for the sandbox that raised the approval (not
  // whatever scope the separate Rules section happens to have selected),
  // then drops the request (only once the rule is in place, so a failed
  // rule leaves the request waiting instead of silently vanishing; only if
  // the daemon actually offered a "dismiss" option for it).
  function blockApproval(approval) {
    if (!Sbx.isPlainHost(approval.title)) { flash("Not a plain host name: answer this request with sbx policy approval.", true); return }
    var h = Sbx.ruleHost(approval.title)
    var scope = String(approval.sandbox || "")
    var argv = ["policy", "deny", "network"]
    if (scope) argv.push("--sandbox", scope)
    argv.push("--", h)
    var canDismiss = (approval.options || []).some(function(o) { return o.id === "dismiss" })
    run("rule:deny:" + h, argv, { ok: "Blocked " + h + (scope ? " for " + scope : ""), fail: "Could not add the rule", quiet: true, after: function(success) {
      svc.loadPolicy(true)
      if (success && canDismiss) answerApproval(approval, "dismiss")
    } })
  }

  // Removing a deny rule lets traffic through again, so it takes two clicks
  // like everything else that cannot be undone from here.
  function removeRule(rule) {
    var label = Sbx.ruleTitle(rule)
    var argv = Sbx.ruleRemoveArgs(rule)
    if (!argv) { flash("Remove this rule in a terminal: sbx policy rm network", true); return }
    if (!confirmed("rule-rm:" + rule.id, "Remove the " + (rule.decision === "deny" ? "deny" : "allow") + " rule " + label + "?")) return
    run("rule-rm:" + rule.id, argv,
        { ok: "Rule removed", fail: "Could not remove the rule", quiet: true, after: function() { svc.loadPolicy(true) } })
  }

  function removeSecret(secret) {
    var name = String(secret.name || "")
    if (name === "") { flash("Remove this one in a terminal: sbx secret rm", false); return }
    if (!confirmed("secret:" + name + ":" + (secret.scope || ""), "Delete the stored " + name + " secret?")) return
    var argv = ["secret", "rm", "--force"]
    if (String(secret.scope || "").indexOf("sandbox") === 0) argv.push("--sandbox", String(secret.scope).replace(/^sandbox:?/, ""))
    argv.push("--", name)
    var scope = String(secret.scope || "")
    run("secret:" + name, argv, { ok: "Deleted the " + name + " secret", fail: "Could not delete the secret", quiet: true, after: function(success) {
      // Don't make the row wait for the separate, slower catalog reload: a
      // successful delete can't be undone, so drop it from the list now.
      if (success) svc.secrets = svc.secrets.filter(function(s) { return !(String(s.name || "") === name && String(s.scope || "") === scope) })
      svc.loadCatalog(true)
    } })
  }

  // The last dry run of `sbx prune`, split into what Prune removes and the
  // protected sandboxes it leaves alone.
  function prunePlan() {
    var plan = { remove: [], keep: [] }
    var list = svc.pruneCandidates || []
    for (var i = 0; i < list.length; i++) {
      var name = String(list[i].name || "")
      if (name !== "") (isProtected(name) ? plan.keep : plan.remove).push(name)
    }
    return plan
  }

  function stoppedNow(name) {
    for (var i = 0; i < svc.sandboxes.length; i++)
      if (svc.sandboxes[i].name === name) return svc.sandboxes[i].status === "stopped"
    return false
  }

  // Prune takes two clicks. The first reads the list and the dry run afresh and
  // then asks with exactly the names that would go; clicks while it checks do
  // nothing. The second removes those names one at a time with `sbx rm --force`
  // if they are still stopped and not protected. `sbx prune --force` is not
  // used: it cannot spare a protected sandbox, and it removes whatever is
  // stopped when it runs, named in the question or not.
  property double pruneCheckAt: 0
  property var pruneNames: []
  property bool pruning: false
  property int pruneFinished: 0         // removed or failed so far
  property string pruneCurrent: ""      // the one being removed

  function prune() {
    if (pruning) { flash("Still removing …", false); return }
    if (pruneCheckAt > 0) return
    if (svc.daemon !== "running" && !demoMode) { flash("The daemon is not running.", true); return }
    if (armedKey === "prune") {
      armedKey = ""
      armTimer.stop()
      var names = pruneNames.filter(function(name) { return !isProtected(name) && (demoMode || stoppedNow(name)) })
      if (demoMode) { flash("Demo · would run:  " + names.map(function(name) { return cmdLine(["rm", "--force", "--", name]) }).join(" ; "), false); return }
      if (names.length === 0) { flash("Nothing to remove: no stopped sandbox that is not protected.", false); return }
      pruneNames = names
      pruning = true
      removeInTurn(names, [], [])
      return
    }
    pruneCheckAt = Date.now()
    svc.refresh()
    svc.loadPrune(true)
    flash("Checking which sandboxes are stopped …", false)
    pruneCheck.restart()
  }

  // Asks once the list and the dry run are newer than the first click.
  Timer {
    id: pruneCheck
    interval: 200
    repeat: true
    onTriggered: {
      var fresh = root.demoMode || (root.svc.listAt >= root.pruneCheckAt && root.svc.pruneAt >= root.pruneCheckAt)
      if (!fresh && Date.now() - root.pruneCheckAt < 30000) return
      stop()
      root.pruneCheckAt = 0
      if (!fresh) { root.flash("Could not read which sandboxes are stopped. Try again.", true); return }
      var plan = root.prunePlan()
      var names = plan.remove.filter(function(name) { return root.demoMode || root.stoppedNow(name) })
      var stays = plan.keep.length ? "  Protected, stays: " + plan.keep.join(", ") + "." : ""
      if (names.length === 0) { root.flash("Nothing to remove: no stopped sandbox that is not protected." + stays, false); return }
      root.pruneNames = names
      root.confirmed("prune", "Remove " + names.join(", ") + "?" + stays)
    }
  }

  // One sbx call at a time: parallel CLI calls are what strained gnome-keyring.
  function removeInTurn(names, removed, failed) {
    pruneFinished = removed.length + failed.length
    pruneCurrent = names.length ? names[0] : ""
    if (names.length === 0) {
      pruning = false
      svc.loadPrune(true)
      svc.loadCatalog(true)
      if (failed.length) flash("Removed " + (removed.length ? removed.join(", ") : "nothing") + "  ·  failed: " + failed.join(", "), true)
      else flash("Removed " + removed.join(", "), false)
      return
    }
    var name = names[0]
    var started = svc.act("rm:" + name, ["rm", "--force", "--", name], 60, function(ok) {
      removeInTurn(names.slice(1), ok ? removed.concat([name]) : removed, ok ? failed : failed.concat([name]))
    })
    if (!started) removeInTurn(names.slice(1), removed, failed.concat([name]))
  }

  function openLog() {
    if (svc.daemonLog === "") { flash("The daemon reports no log file.", true); return }
    shellFloat("less +G " + Sbx.shellWord(svc.daemonLog))
  }

  function copyText(text) {
    Quickshell.execDetached(["wl-copy", "--", String(text)])
    flash("Copied  " + text, false)
  }

  // ------------------------------------------------------------------ bar mark
  readonly property string tooltip: {
    if (!svc.installed) return appName + " · sbx is not installed"
    if (daemonJob) return appName + " · " + daemonBusy.toLowerCase() + " …"
    if (svc.daemon === "stopped") return appName + " · daemon stopped"
    if (svc.daemon === "unresponsive") return appName + " · the sandbox daemon is not responding"
    if (svc.signedOut && !demoMode) return appName + " · not signed in to Docker"
    var parts = [appName + (demoMode ? " (demo)" : "")]
    parts.push(svc.runningCount + " of " + svc.sandboxes.length + " sandboxes running")
    if (svc.approvals.length) parts.push(svc.approvals.length + " network request" + (svc.approvals.length > 1 ? "s" : "") + " waiting")
    if (svc.hungNames.length) parts.push("not responding: " + svc.hungNames.join(", "))
    return parts.join(" · ")
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : mark.implicitWidth + Style.space(12)
    fixedHeight: vertical ? mark.implicitHeight + Style.space(12) : -1
    tooltipText: root.tooltip
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { root.svc.refresh(); return }
      if (b === Qt.RightButton) { root.setTab(root.svc.approvals.length ? "network" : "launch"); root.open(); return }
      root.toggle()
    }

    EnclaveIcon {
      id: mark
      anchors.centerIn: parent
      height: Style.bar.iconCanvas
      width: implicitWidth
      color: button.foreground
      accent: root.accent
      urgent: button.activeColor
      fontFamily: button.fontFamily
      status: root.svc.status
      count: root.svc.runningCount
      pulse: root.svc.status === "alert"
    }
  }

  // ------------------------------------------------------------------ popup
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Style.space(720), Style.space(740))

    Item {
      id: keys
      anchors.fill: parent
      focus: true

      readonly property bool editing: (sandboxesTab.visible && sandboxesTab.editing) || (launchTab.visible && launchTab.editing) || (networkTab.visible && networkTab.editing) || (guideTab.visible && guideTab.editing)

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (keys.editing) keys.forceActiveFocus()
          else root.close()
          event.accepted = true
          return
        }
        if (keys.editing) return
        var n = "12345".indexOf(event.text)
        if (n >= 0 && event.text !== "") { root.setTab(root.tabOrder[n]); event.accepted = true; return }
        if (root.tab === "sandboxes") {
          if (event.key === Qt.Key_Down || event.text === "j") { sandboxesTab.move(1); event.accepted = true }
          else if (event.key === Qt.Key_Up || event.text === "k") { sandboxesTab.move(-1); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { sandboxesTab.activate(); event.accepted = true }
          else if (event.text === "o" && sandboxesTab.selected()) { root.sandboxAction("attach", sandboxesTab.selected()); event.accepted = true }
          else if (event.text === "s" && sandboxesTab.selected()) { root.sandboxAction("shell", sandboxesTab.selected()); event.accepted = true }
          else if (event.text === "p" && sandboxesTab.selected()) {
            root.sandboxAction(root.isProtected(sandboxesTab.selected().name) ? "unprotect" : "protect", sandboxesTab.selected())
            event.accepted = true
          }
          else if (event.text === "r") { root.svc.refresh(); event.accepted = true }
          else if (event.text === "n") { root.setTab("launch"); event.accepted = true }
        } else if (root.tab === "guide" && event.text === "/") {
          guideTab.focusSearch()
          event.accepted = true
        }
      }

      // clicking empty panel space hands the keys back from a text field
      MouseArea {
        anchors.fill: parent
        onPressed: function(mouse) { keys.forceActiveFocus(); mouse.accepted = false }
      }

      // ---- hero
      Item {
        id: hero
        width: parent.width
        implicitHeight: Math.max(heroMark.height, heroText.implicitHeight)

        EnclaveIcon {
          id: heroMark
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: Math.round(Style.font.display * 1.25)
          width: implicitWidth
          color: root.fg
          accent: root.accent
          urgent: root.urgent
          fontFamily: root.ff
          status: root.svc.status
          count: 0
          pulse: root.opened && (root.svc.status === "alert" || root.svc.status === "running")
        }

        Column {
          id: heroText
          anchors.left: heroMark.right
          anchors.leftMargin: Style.space(14)
          anchors.right: tabs.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: root.appName + (root.demoMode ? "  ·  demo" : "")
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: !root.svc.installed ? "SBX NOT INSTALLED"
              : root.daemonJob ? root.daemonBusy.toUpperCase() + " · " + root.daemonSeconds + " S"
              : root.svc.daemon === "stopped" ? "DAEMON OFFLINE"
              : root.svc.daemon === "unresponsive" ? "DAEMON NOT RESPONDING"
              : root.svc.daemon === "unknown" ? "CONNECTING"
              : root.svc.signedOut ? "NOT SIGNED IN TO DOCKER"
              : root.svc.runningCount + " RUNNING · " + root.svc.sandboxes.length + " TOTAL" + (root.svc.approvals.length ? " · " + root.svc.approvals.length + " WAITING" : "")
            color: root.daemonJob && root.svc.installed ? root.accent
              : root.svc.status === "alert" || root.svc.status === "missing" || root.svc.signedOut ? root.urgent : root.dim
            font.family: root.ff
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }
        }

        HudTabs {
          id: tabs
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.fg
          accent: root.accent
          urgent: root.urgent
          fontFamily: root.ff
          value: root.tab
          tabs: [
            { value: "sandboxes", label: "Sandboxes" },
            { value: "launch", label: "Launch" },
            { value: "network", label: "Network", badge: root.svc.approvals.length || "", alert: true },
            { value: "setup", label: "Setup" },
            { value: "guide", label: "Guide" }
          ]
          onChanged: function(v) { root.setTab(v) }
        }
      }

      // ---- rule under the hero; a light sweeps across when the popup opens
      Item {
        id: rule
        anchors.top: hero.bottom
        anchors.topMargin: Style.space(12)
        width: parent.width
        height: Math.max(1, Style.space(1))
        clip: true

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
        }
        Rectangle {
          id: sweep
          width: parent.width * 0.35
          height: parent.height + 1
          x: -width
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: root.accent }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
        NumberAnimation {
          id: scan
          target: sweep
          property: "x"
          from: -sweep.width
          to: rule.width
          duration: 900
          easing.type: Easing.InOutQuad
        }
      }

      // Messages get a fixed two-line slot: one that comes or goes never moves
      // the tab below, so a button stays under the pointer.
      Text {
        id: flashLine
        anchors.top: rule.bottom
        anchors.topMargin: Style.space(8)
        width: parent.width
        height: Math.ceil(flashMetrics.lineSpacing * 2)
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
        text: root.flashText
        color: root.flashAlert ? root.urgent : root.accent
        font.family: root.ff
        font.pixelSize: Style.font.caption

        FontMetrics { id: flashMetrics; font: flashLine.font }
      }

      // ---- tab bodies
      Item {
        id: body
        anchors.top: flashLine.bottom
        anchors.topMargin: Style.space(4)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        SandboxesTab {
          id: sandboxesTab
          anchors.fill: parent
          visible: root.tab === "sandboxes"
          panel: root
        }
        LaunchTab {
          id: launchTab
          anchors.fill: parent
          visible: root.tab === "launch"
          panel: root
        }
        NetworkTab {
          id: networkTab
          anchors.fill: parent
          visible: root.tab === "network"
          panel: root
        }
        SetupTab {
          id: setupTab
          anchors.fill: parent
          visible: root.tab === "setup"
          panel: root
        }
        GuideTab {
          id: guideTab
          anchors.fill: parent
          visible: root.tab === "guide"
          panel: root
        }
      }
    }
  }

  // ------------------------------------------------------------------ IPC
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(tab: string): void { if (tab) root.setTab(tab); root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.svc.refresh(); return "ok" }
    function status(): string { return root.tooltip }

    // open the popup on Sandboxes with one card unfolded
    function expand(name: string): void {
      root.setTab("sandboxes")
      if (Sbx.nameProblem(name) === "") sandboxesTab.expandName(name)
      root.open()
    }

    function demo(on: string): string {
      root.demoMode = on === "on" || on === "true" || on === "1"
      return root.demoMode ? "demo on" : "demo off"
    }
  }
}
