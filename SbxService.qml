pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Sbx.js" as Sbx
import "DemoData.js" as DemoData

// Reads Docker Sandboxes state: the poll from the daemon's API socket, the
// rest through the sbx CLI.
//
// The poll does not run the CLI: every sbx 0.45.1 call opens about 25 Secret
// Service sessions with gnome-keyring, and polling the CLI every few seconds
// crashed gnome-keyring-daemon 50.0 (the restarted daemon then asks for the
// login password). curl on sandboxd.sock (GET /daemon/health, /sandbox,
// /user-prompts) reads the same data without the keyring. CLI calls are left
// for actions and for data a tab asks for, and those loads are cached. Start
// needs no CLI call either: saving a plugin file reloads the widget, and a
// burst of reloads that each asked the CLI crashed gnome-keyring again.
//
// sbx calls can hang: in 0.45.1 listing the ports of a running sandbox never
// returned and left the daemon's API stuck for every later command. So every
// call runs under `timeout -k` and `setpriv --pdeathsig KILL` (the process
// dies with its parent, nothing lingers after a shell restart), a daemon that
// does not answer the health check in time is reported as "unresponsive", and
// polling then slows to a minute.
//
// A missing or refusing socket means the daemon is down; the poll never
// starts it: a bar widget must not keep a VM daemon alive on its own.
Item {
  id: svc

  property bool panelOpen: false
  property int refreshSeconds: 15
  property bool autoPoll: true
  property bool demo: false
  readonly property string home: Quickshell.env("HOME") || ""

  // ---------------------------------------------------------------- discovery
  property string sbx: "sbx"
  property bool resolved: false
  property bool installed: true
  // The default place; `sbx daemon status` corrects it when nothing answers there.
  property string socket: home + "/.local/state/sandboxes/sandboxes/sandboxd/sandboxd.sock"

  // ---------------------------------------------------------------- state
  property string daemon: "unknown"        // running | stopped | unresponsive | unknown
  property string daemonLog: defaultLog
  property string clientVersion: ""
  property string serverVersion: ""
  property var sandboxes: []
  property var approvals: []
  property var details: ({})               // name → `sbx inspect --json`
  property string error: ""
  // The daemon answers but refuses until you sign in to Docker (`sbx login`).
  property bool signedOut: false

  readonly property int runningCount: {
    var n = 0
    for (var i = 0; i < sandboxes.length; i++) if (sandboxes[i].status === "running") n++
    return n
  }
  // Sandboxes in a state that is neither running, stopped nor on its way
  // (Sbx.statusKind "alert").
  readonly property var hungNames: {
    var out = []
    for (var i = 0; i < sandboxes.length; i++)
      if (Sbx.statusKind(sandboxes[i].status) === "alert") out.push(sandboxes[i].name)
    return out
  }
  // missing | offline | idle | running | alert (see EnclaveIcon)
  readonly property string status: !installed ? "missing"
    : daemon === "stopped" || (daemon === "running" && signedOut) ? "offline"
    : daemon === "unresponsive" || approvals.length > 0 || hungNames.length > 0 ? "alert"
    : runningCount > 0 ? "running" : "idle"

  // Every poll asks for health and approvals. GET /sandbox makes the daemon
  // upload a telemetry event, and that upload reads a Docker token from the
  // keyring (8 Secret Service sessions), so the list is read only when it is
  // older than listMaxAge or when refresh() asks for it (popup opened, after
  // an action, middle click, `r`).
  property double listAt: 0
  property bool listDue: true
  // While a sandbox started from here comes up ("Starting" on its card), the
  // list is read on every poll, so the card turns to running as soon as the
  // sandbox does, not at the next regular read up to 10 s later.
  readonly property bool starting: {
    for (var key in jobs) if (key.indexOf("attach:") === 0) return true
    return false
  }
  readonly property int listMaxAge: starting ? 1500 : panelOpen ? 10000 : 60000

  function poll(withList) {
    if (demo) return
    if (!resolved || !installed) return
    if (withList) listDue = true
    if (!daemonProc.running && !listProc.running) daemonProc.running = true
  }

  function refresh() { poll(true) }

  // Something may have changed outside the plugin (a terminal it opened:
  // sign-in, a stored key, the dashboard): every tab reads afresh next time.
  function invalidate() {
    listDue = true
    policyAt = 0; catalogAt = 0; pruneAt = 0
    inspectedAt = ({})
  }

  // Looks for the sbx CLI again, e.g. after installing it while the shell runs.
  function resolve() {
    if (!resolveProc.running) resolveProc.running = true
  }

  // ------------------------------------------------------------------ demo
  readonly property string defaultLog: home + "/.local/state/sandboxes/sandboxes/sandboxd/daemon.log"

  onDemoChanged: {
    if (demo) loadDemo()
    else {
      sandboxes = []; approvals = []; details = ({}); blockedHosts = []; allowedHosts = []; rules = []
      templates = []; mcpServers = []; mcpGateway = null; secrets = []; health = []; healthSummary = null
      pruneCandidates = []; daemon = "unknown"; clientVersion = ""; serverVersion = ""; signedOut = false
      daemonLog = defaultLog; infoAskedAt = 0; inspectedAt = ({})
      versionAsked = false; listAt = 0; policyAt = 0; catalogAt = 0; pruneAt = 0
      refresh()
    }
  }

  // No real home path here: demo data (and any screenshot taken from it)
  // must never reveal whose machine this is. DemoData.build() already
  // defaults to a placeholder "/home/demo" on its own.
  function loadDemo() {
    var d = DemoData.build()
    installed = true
    signedOut = false
    daemon = "running"
    daemonLog = d.daemonLog
    clientVersion = d.version.client
    serverVersion = d.version.server
    sandboxes = d.sandboxes
    details = d.details
    approvals = d.approvals
    blockedHosts = d.blocked
    allowedHosts = d.allowed
    rules = d.rules
    secrets = d.secrets
    mcpServers = d.mcp.servers
    mcpGateway = d.mcp.gateway
    templates = d.templates
    pruneCandidates = d.prune
    health = []
    healthSummary = null
    error = ""
    policyAt = Date.now()
    catalogAt = Date.now()
    pruneAt = Date.now()
  }

  // ------------------------------------------------------------------ helpers
  readonly property var guard: ["setpriv", "--pdeathsig", "KILL", "--"]

  // The plugin's own sbx calls send no CLI usage telemetry (the documented
  // opt-out, docs.docker.com/ai/sandboxes/faq).
  function timed(seconds, argv) {
    return ["timeout", "-k", "3", String(seconds)].concat(guard, ["env", "SBX_NO_TELEMETRY=1", svc.sbx], argv)
  }

  // Several sbx calls in one process, outputs split by a record separator
  // line. calls: argv arrays; every word is shell-quoted, the sbx path is $1.
  function batch(seconds, calls) {
    var script = "export SBX_NO_TELEMETRY=1; " + calls.map(function(argv) {
      return 'setpriv --pdeathsig KILL -- "$1" ' + argv.map(Sbx.shellWord).join(" ")
    }).join("; printf '\\n\\x1e\\n'; ")
    return ["timeout", "-k", "3", String(seconds)].concat(guard, ["bash", "-c", script, "sbx-enclave", svc.sbx])
  }

  // Several GETs on the daemon socket in one process, outputs split like
  // batch(). calls: [{ path, seconds, stream }]; a stream (NDJSON) is read for
  // `seconds` and then cut, so its timeout is expected and stays quiet. The
  // socket path is $1.
  function api(seconds, calls) {
    var script = calls.map(function(c) {
      return "setpriv --pdeathsig KILL -- curl " + (c.stream ? "-sN" : "-sS") + " --max-time " + Math.max(1, Math.round(Number(c.seconds) || 1))
        + ' --unix-socket "$1" ' + Sbx.shellWord("http://localhost" + c.path)
    }).join("; printf '\\n\\x1e\\n'; ") + "; true"
    return ["timeout", "-k", "3", String(seconds)].concat(guard, ["bash", "-c", script, "sbx-enclave", svc.socket])
  }

  function parseJson(text) {
    try { return JSON.parse(String(text || "")) } catch (e) { return null }
  }

  // ------------------------------------------------------------------ inspect queue
  // `sbx inspect` is a CLI call, so it runs only when a card is unfolded, and
  // not again for the same sandbox within inspectMaxAge (folding a card open
  // and shut must not turn into a stream of CLI calls). An action on a
  // sandbox drops its entry, so the next unfold reads it afresh.
  property var inspectQueue: []
  property var inspectedAt: ({})          // name → Date.now() of the last inspect
  readonly property int inspectMaxAge: 15000

  function inspect(name) {
    if (demo || !name || Sbx.nameProblem(name) !== "" || inspectQueue.indexOf(name) >= 0) return
    if (fresh(inspectedAt[name] || 0, inspectMaxAge)) return
    inspectQueue = inspectQueue.concat([name])
    if (!inspectProc.running) nextInspect()
  }

  function forgetInspect(name) {
    if (inspectedAt[name] === undefined) return
    var next = Object.assign({}, inspectedAt)
    delete next[name]
    inspectedAt = next
  }

  function nextInspect() {
    if (inspectQueue.length === 0 || daemon !== "running") { inspectQueue = []; return }
    inspectProc.target = inspectQueue[0]
    inspectQueue = inspectQueue.slice(1)
    inspectProc.running = true
  }

  // ------------------------------------------------------------------ poll
  Process {
    id: resolveProc
    // A login shell sees PATH additions from ~/.bash_profile (tarball installs
    // put sbx in ~/.docker/sbx/bin).
    command: ["bash", "-lc", "command -v sbx || for p in \"$HOME/.docker/sbx/bin/sbx\" /usr/local/bin/sbx /usr/bin/sbx; do [ -x \"$p\" ] && { echo \"$p\"; break; }; done; true"]
    stdout: StdioCollector { id: resolveOut; waitForEnd: true }
    onExited: {
      var lines = String(resolveOut.text || "").trim().split("\n")
      var path = lines[lines.length - 1].trim()
      svc.installed = path.charAt(0) === "/"
      if (svc.installed) svc.sbx = path
      svc.resolved = true
      if (svc.installed && !svc.demo && svc.autoPoll) svc.refresh()
    }
  }

  // Only when nothing answers at the default socket, and not more than once
  // per cooldown: where the daemon keeps its socket and its log. A cooldown
  // instead of a one-time latch so a daemon that moves its socket later
  // (reinstall, upgrade) is picked up again instead of showing "stopped"
  // until the plugin reloads.
  property double infoAskedAt: 0
  readonly property int infoCooldown: 300000

  Process {
    id: infoProc
    command: svc.timed(8, ["daemon", "status", "--json"])
    stdout: StdioCollector { id: infoOut; waitForEnd: true }
    onExited: {
      var d = svc.parseJson(infoOut.text)
      var moved = d && d.socket && String(d.socket) !== svc.socket
      if (d && d.socket) svc.socket = String(d.socket)
      // demo mode keeps its made-up log path (screenshots)
      if (d && d.logs && !svc.demo) svc.daemonLog = String(d.logs)
      if (moved && svc.autoPoll && !svc.demo) svc.refresh()
    }
  }

  // The client version, once, when Launch or Setup first loads the catalog.
  property bool versionAsked: false

  function loadVersion() {
    if (demo || versionAsked || !resolved || !installed) return
    versionAsked = true
    versionProc.running = true
  }

  Process {
    id: versionProc
    command: svc.timed(15, ["version", "--json"])
    stdout: StdioCollector { id: versionOut; waitForEnd: true }
    onExited: {
      var v = svc.parseJson(versionOut.text)
      if (!v || svc.demo) return
      svc.clientVersion = v.client && v.client.version ? String(v.client.version) : ""
      if (v.server && v.server.version) svc.serverVersion = String(v.server.version)
    }
  }

  // curl exits 7 when nothing listens on the socket (or it is gone) and 28
  // when the daemon does not answer in time.
  Process {
    id: daemonProc
    command: svc.api(10, [{ path: "/daemon/health", seconds: 6 }])
    stdout: StdioCollector { id: daemonOut; waitForEnd: true }
    stderr: StdioCollector { id: daemonErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (svc.demo) return
      var h = svc.parseJson(daemonOut.text)
      var err = String(daemonErr.text || "")
      if (h && h.status) {
        svc.daemon = "running"
        if (h.version) svc.serverVersion = String(h.version)
      } else if (/curl: \(28\)/.test(err) || exitCode === 124 || exitCode === 137) {
        svc.daemon = "unresponsive"
      } else {
        svc.daemon = "stopped"
      }
      if (svc.daemon === "running") {
        var withList = svc.listDue || !svc.fresh(svc.listAt, svc.listMaxAge)
        var calls = [{ path: "/user-prompts", seconds: 2, stream: true }]
        if (withList) calls.unshift({ path: "/sandbox", seconds: 10 })
        listProc.withList = withList
        listProc.command = svc.api(20, calls)
        listProc.running = true
      } else {
        svc.sandboxes = []
        svc.approvals = []
        svc.signedOut = false
        svc.listAt = 0
        if (svc.daemon === "stopped" && !svc.fresh(svc.infoAskedAt, svc.infoCooldown) && !infoProc.running) {
          svc.infoAskedAt = Date.now(); infoProc.running = true
        }
      }
    }
  }

  // The sandboxes (when due) and the pending approvals. /user-prompts is a
  // stream: it sends every waiting request, then {"action":"synced"}, then
  // stays open. A daemon that refuses (not signed in to Docker) answers both
  // with one {"message": …} object instead.
  Process {
    id: listProc
    property bool withList: false
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    stderr: StdioCollector { id: listErr; waitForEnd: true }
    onExited: {
      if (svc.demo) return
      var parts = String(listOut.text || "").split("\n\x1e\n")
      var refused = ""
      if (listProc.withList) {
        var body = svc.parseJson(parts.shift())
        var list = body instanceof Array ? body : body && body.sandboxes instanceof Array ? body.sandboxes : null
        if (list) {
          svc.sandboxes = list.map(Sbx.sandboxFromApi)
          svc.signedOut = false
          svc.clearFinishedAttachJobs()
          svc.error = ""
          svc.listAt = Date.now()
          svc.listDue = false
        } else {
          refused = body && body.message ? String(body.message) : ""
          svc.error = Sbx.errorLine(refused) || Sbx.errorLine(listErr.text) || "The daemon did not list its sandboxes"
        }
      }
      var stream = parts.length ? parts[0] : ""
      var prompts = Sbx.parsePromptStream(stream)
      if (prompts !== null) {
        svc.approvals = prompts
        if (svc.signedOut) { svc.signedOut = false; svc.listDue = true }
      } else if (refused === "") {
        var answer = svc.parseJson(stream)
        if (answer && answer.message) refused = String(answer.message)
      }
      // Signed out: nothing is listed until `sbx login`; the tabs say so
      // instead of showing what was there before.
      if (Sbx.signedOut(refused)) {
        svc.signedOut = true
        svc.sandboxes = []
        svc.approvals = []
        svc.error = ""
        svc.listAt = Date.now()
        svc.listDue = false
      }
    }
  }

  Process {
    id: inspectProc
    property string target: ""
    command: svc.timed(15, ["inspect", "--json", "--", inspectProc.target])
    stdout: StdioCollector { id: inspectOut; waitForEnd: true }
    onExited: {
      var d = svc.parseJson(inspectOut.text)
      if (!svc.demo) {
        // also after a failure, so a broken sandbox is not asked again at once
        var at = Object.assign({}, svc.inspectedAt)
        at[inspectProc.target] = Date.now()
        svc.inspectedAt = at
        if (d && d.name) {
          var next = Object.assign({}, svc.details)
          next[d.name] = d
          svc.details = next
        }
      }
      svc.nextInspect()
    }
  }

  // ------------------------------------------------------------------ on demand
  // Network: the policy log (blocked and allowed hosts) and the rules.
  property var blockedHosts: []
  property var allowedHosts: []
  property var rules: []
  property double policyAt: 0

  // Tab loads are CLI calls: opening a tab reuses data younger than these
  // limits; `force` (after an action) always reloads.
  readonly property int policyMaxAge: 15000
  readonly property int catalogMaxAge: 60000
  readonly property int pruneMaxAge: 30000

  function fresh(at, maxAge) { return at > 0 && Date.now() - at < maxAge }

  function loadPolicy(force) {
    if (!force && fresh(policyAt, policyMaxAge)) return
    if (!demo && daemon === "running" && !policyProc.running) policyProc.running = true
  }

  Process {
    id: policyProc
    command: svc.batch(25, [["policy", "log", "--json", "--limit", "80"], ["policy", "ls", "--json"]])
    stdout: StdioCollector { id: policyOut; waitForEnd: true }
    onExited: {
      if (svc.demo) return
      var parts = String(policyOut.text || "").split("\n\x1e\n")
      var log = svc.parseJson(parts[0])
      if (log) {
        svc.blockedHosts = log.blocked_hosts instanceof Array ? log.blocked_hosts : []
        svc.allowedHosts = log.allowed_hosts instanceof Array ? log.allowed_hosts : []
      }
      var ls = svc.parseJson(parts.length > 1 ? parts[1] : "")
      if (ls && ls.rules instanceof Array) svc.rules = ls.rules
      svc.policyAt = Date.now()
    }
  }

  // Setup and Launch: templates, MCP servers and stored secrets (names only;
  // `sbx secret ls` never prints a value).
  property var templates: []
  property var mcpServers: []
  property var mcpGateway: null
  property var secrets: []
  property double catalogAt: 0
  // Nothing read yet and the read is on its way (three CLI calls, a few
  // seconds): the tabs say "loading" instead of "none" meanwhile.
  readonly property bool catalogLoading: catalogAt === 0 && catalogProc.running

  function loadCatalog(force) {
    loadVersion()
    if (!force && fresh(catalogAt, catalogMaxAge)) return
    if (!demo && daemon === "running" && !catalogProc.running) catalogProc.running = true
  }

  Process {
    id: catalogProc
    command: svc.batch(30, [["template", "ls", "--json"], ["mcp", "ls", "--json"], ["secret", "ls", "--json"]])
    stdout: StdioCollector { id: catalogOut; waitForEnd: true }
    onExited: {
      if (svc.demo) return
      var parts = String(catalogOut.text || "").split("\n\x1e\n")
      var t = svc.parseJson(parts[0])
      if (t && t.images instanceof Array) svc.templates = t.images
      var m = svc.parseJson(parts.length > 1 ? parts[1] : "")
      if (m) {
        svc.mcpServers = m.servers instanceof Array ? m.servers : []
        svc.mcpGateway = m.gateway || null
      }
      var s = svc.parseJson(parts.length > 2 ? parts[2] : "")
      if (s) svc.secrets = (s.secrets instanceof Array ? s.secrets : []).concat(s.custom_secrets instanceof Array ? s.custom_secrets : [])
      svc.catalogAt = Date.now()
    }
  }

  // Setup: `sbx diagnose` (collects daemon diagnostics, takes a few seconds).
  property var health: []
  property var healthSummary: null
  property double healthAt: 0
  readonly property bool diagnosing: diagnoseProc.running || demoDiagnose.running

  function diagnose() {
    if (demo) { demoDiagnose.restart(); return }
    if (!diagnoseProc.running) diagnoseProc.running = true
  }

  Timer {
    id: demoDiagnose
    interval: 1400
    onTriggered: {
      var d = DemoData.build()
      svc.health = d.health
      svc.healthSummary = d.healthSummary
      svc.healthAt = Date.now()
    }
  }

  Process {
    id: diagnoseProc
    command: svc.timed(60, ["diagnose", "--json"])
    stdout: StdioCollector { id: diagnoseOut; waitForEnd: true }
    onExited: {
      if (svc.demo) return
      var d = svc.parseJson(diagnoseOut.text)
      if (d && d.checks instanceof Array) {
        svc.health = d.checks
        svc.healthSummary = d.summary || null
      }
      svc.healthAt = Date.now()
    }
  }

  // Setup: what `sbx prune` would remove.
  property var pruneCandidates: []
  property double pruneAt: 0
  // like catalogLoading, for the dry run
  readonly property bool pruneLoading: pruneAt === 0 && pruneProc.running

  function loadPrune(force) {
    if (!force && fresh(pruneAt, pruneMaxAge)) return
    if (!demo && daemon === "running" && !pruneProc.running) pruneProc.running = true
  }

  Process {
    id: pruneProc
    command: svc.timed(20, ["prune", "--dry-run", "--json"])
    stdout: StdioCollector { id: pruneOut; waitForEnd: true }
    onExited: {
      if (svc.demo) return
      var d = svc.parseJson(pruneOut.text)
      svc.pruneCandidates = d && d.would_remove instanceof Array ? d.would_remove : []
      svc.pruneAt = Date.now()
    }
  }

  // ------------------------------------------------------------------ actions
  // Commands that change something (stop, remove, policy rules, …) run as
  // background jobs, one per key: asking for a key that is still running is
  // refused, which guards against double clicks. Their output is read line by
  // line, so a card can show how a Stop or Remove goes. `done(ok, message)`
  // runs when the job ends; the list is refreshed afterwards.
  property var jobs: ({})               // key → { since, last } while it runs
  readonly property string sbxName: Sbx.binName(sbx)

  function isBusy(key) { return jobs[key] !== undefined }

  function setJob(key, info) {
    var next = Object.assign({}, jobs)
    if (info) next[key] = info
    else delete next[key]
    jobs = next
  }

  // "attach" has no process of its own to watch (sbx run hands off to a
  // detached terminal), so its "Starting …" job is cleared here instead of
  // by a job exiting: once the next list confirms the sandbox is running, or
  // after a timeout in case it never comes up.
  readonly property int attachJobTimeout: 25000
  function clearFinishedAttachJobs() {
    var keys = Object.keys(jobs)
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (key.indexOf("attach:") !== 0) continue
      var name = key.slice(7)
      var sandbox = sandboxes.find(function(s) { return s.name === name })
      if ((sandbox && sandbox.status === "running") || Date.now() - jobs[key].since > attachJobTimeout) setJob(key, null)
    }
  }

  // Returns false when the key is busy or the call is not possible.
  function act(key, argv, seconds, done) {
    if (demo || !resolved || !installed || isBusy(key)) return false
    var job = jobComp.createObject(svc, { key: key, done: done || null, command: timed(seconds || 30, argv) })
    setJob(key, { since: Date.now(), last: "" })
    job.running = true
    return true
  }

  // One line of sbx output without colour codes; a line that redraws itself
  // with \r gives its last part.
  function cleanLine(data) {
    var parts = String(data || "").split("\r").map(function(p) {
      return p.replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "").replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)?/g, "")
        .replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "").trim()
    }).filter(function(p) { return p !== "" })
    return parts.length ? parts[parts.length - 1] : ""
  }

  // Splits buf+chunk on "\n" and calls onLine for each complete line. With
  // flush (the process just exited), also emits a trailing line that never
  // got its "\n" — plain SplitParser buffers that remainder internally and
  // drops it on exit, which can hide the one line that matters most: sbx's
  // final error. Returns the new buffer (empty when flushed).
  function drainLines(buf, chunk, flush, onLine) {
    var lines = String(buf || "").concat(chunk || "").split("\n")
    var rest = lines.pop()
    for (var i = 0; i < lines.length; i++) onLine(lines[i])
    if (!flush) return rest
    if (rest !== "") onLine(rest)
    return ""
  }

  // Headings ("── TITLE ──") are not shown as the job's last line, only its
  // own output content is.
  function jobRead(key, data) {
    var info = jobs[key]
    if (!info) return
    var line = cleanLine(data)
    if (line === "" || /^─/.test(line)) return
    setJob(key, { since: info.since, last: line })
  }

  function finishJob(job, exitCode, out, err) {
    setJob(job.key, null)
    pruneAt = 0     // what is stopped may have changed: Setup re-reads the dry run
    var target = /^(stop|rm|ports):(.+)$/.exec(job.key)
    if (target) forgetInspect(target[2])
    var ok = exitCode === 0
    var message = ok ? Sbx.errorLine(out) : (exitCode === 124 || exitCode === 137
      ? "sbx did not answer in time" : Sbx.errorLine(err) || Sbx.errorLine(out) || "sbx exited with code " + exitCode)
    if (job.done) job.done(ok, message)
    refresh()
    job.destroy()
  }

  Component {
    id: jobComp
    Process {
      id: job
      property string key: ""
      property var done: null
      property string out: ""
      property string err: ""
      property string outBuf: ""
      property string errBuf: ""
      function onOutLine(line) { job.out += line + "\n"; svc.jobRead(job.key, line) }
      function onErrLine(line) { job.err += line + "\n"; svc.jobRead(job.key, line) }
      stdout: SplitParser { splitMarker: ""; onRead: function(data) { job.outBuf = svc.drainLines(job.outBuf, data, false, job.onOutLine) } }
      stderr: SplitParser { splitMarker: ""; onRead: function(data) { job.errBuf = svc.drainLines(job.errBuf, data, false, job.onErrLine) } }
      onExited: function(exitCode) {
        job.outBuf = svc.drainLines(job.outBuf, "", true, job.onOutLine)
        job.errBuf = svc.drainLines(job.errBuf, "", true, job.onErrLine)
        svc.finishJob(job, exitCode, job.out, job.err)
      }
    }
  }

  // ------------------------------------------------------------------ create
  // `sbx create` takes a while (image pull, VM set-up), so it runs on its own
  // and its output is read line by line. sbx gives no percentage, but it heads
  // each step with "── TITLE" and closes it with a line starting with ✓, so
  // Launch shows the step, the seconds so far and the last line. One create at
  // a time.
  //
  // `sbx create` leaves the new sandbox running until sbx notices that no
  // session needs it (the docs give no timeout), so it showed as running for
  // a while after "Create only". With `stopAfter` the plugin stops it right
  // away as a last step of its own: created means off until first use.
  readonly property var sbxCreateStepTitles: ["RESOLVE SETUP", "PREPARE IMAGE", "CREATE SANDBOX"]   // sbx 0.45
  readonly property string createStopTitle: "STOP SANDBOX"
  property bool createStopAfter: false
  readonly property var createStepTitles: createStopAfter ? sbxCreateStepTitles.concat([createStopTitle]) : sbxCreateStepTitles
  property string createName: ""
  property double createStartedAt: 0
  property string createLast: ""
  property string createStep: ""        // title of the step in progress
  property int createDone: 0            // steps closed with ✓
  readonly property int createSteps: Math.max(createStepTitles.length, createDone + (createStep !== "" ? 1 : 0))
  readonly property bool creating: createProc.running || createStopProc.running

  // Returns false while a create runs or when sbx is not usable.
  function create(name, argv, done, stopAfter) {
    if (demo || !resolved || !installed || creating) return false
    createName = String(name || "")
    createStopAfter = !!stopAfter
    createStartedAt = Date.now()
    createLast = ""
    createStep = ""
    createDone = 0
    createProc.done = done || null
    createProc.command = timed(600, argv)
    createProc.running = true
    return true
  }

  function createRead(data) {
    var line = cleanLine(data)
    if (line === "") return
    if (/^─/.test(line)) { createStep = line.replace(/^─+\s*/, ""); return }
    // sbx may print the next heading only when that step is over. A real
    // image pull can print more than 3 checkmark lines (one per layer); cap
    // createDone at sbx's named steps so the track never shows "done" early.
    if (/^✓/.test(line)) {
      createDone = Math.min(createDone + 1, sbxCreateStepTitles.length)
      createStep = createDone < sbxCreateStepTitles.length ? sbxCreateStepTitles[createDone] : ""
    }
    createLast = line
  }

  Process {
    id: createProc
    property var done: null
    property string outBuf: ""
    property string errBuf: ""
    stdout: SplitParser { splitMarker: ""; onRead: function(data) { createProc.outBuf = svc.drainLines(createProc.outBuf, data, false, svc.createRead) } }
    stderr: SplitParser { splitMarker: ""; onRead: function(data) { createProc.errBuf = svc.drainLines(createProc.errBuf, data, false, svc.createRead) } }
    onExited: function(exitCode) {
      createProc.outBuf = svc.drainLines(createProc.outBuf, "", true, svc.createRead)
      createProc.errBuf = svc.drainLines(createProc.errBuf, "", true, svc.createRead)
      var ok = exitCode === 0
      var message = ok ? "" : exitCode === 124 || exitCode === 137 ? "sbx did not answer in time"
        : Sbx.errorLine(svc.createLast) || "sbx exited with code " + exitCode
      if (ok && svc.createStopAfter) {
        svc.createDone = svc.sbxCreateStepTitles.length
        svc.createStep = svc.createStopTitle
        svc.createLast = "Stopping " + svc.createName + " until its first use"
        // the card shows "Stopping …" too, and its Stop button waits
        svc.setJob("stop:" + svc.createName, { since: Date.now(), last: "" })
        createStopProc.command = svc.timed(60, ["stop", "--", svc.createName])
        createStopProc.running = true
        return
      }
      svc.finishCreate(ok, message)
    }
  }

  // The sandbox exists either way; a failed stop only means it keeps running
  // until sbx stops it on its own, which the message says.
  Process {
    id: createStopProc
    stdout: StdioCollector { id: createStopOut; waitForEnd: true }
    stderr: StdioCollector { id: createStopErr; waitForEnd: true }
    onExited: function(exitCode) {
      svc.setJob("stop:" + svc.createName, null)
      if (exitCode === 0) { svc.createDone = svc.createStepTitles.length; svc.finishCreate(true, ""); return }
      var why = exitCode === 124 || exitCode === 137 ? "sbx did not answer in time"
        : Sbx.errorLine(createStopErr.text) || Sbx.errorLine(createStopOut.text) || "exit code " + exitCode
      svc.finishCreate(true, "It keeps running until sbx stops it on its own (" + why + ").")
    }
  }

  function finishCreate(ok, message) {
    var done = createProc.done
    createProc.done = null
    pruneAt = 0     // what is stopped may have changed: Setup re-reads the dry run
    if (done) done(ok, message)
    refresh()
  }

  // ------------------------------------------------------------------ cadence
  Timer {
    interval: svc.daemon === "unresponsive" ? 60000
      : svc.starting ? 2000 : svc.panelOpen ? 3000 : Math.max(5, svc.refreshSeconds) * 1000
    running: svc.resolved && svc.installed && svc.autoPoll && !svc.demo
    repeat: true
    onTriggered: svc.poll(false)
  }

  // Opening the popup reads afresh; without sbx it looks for it again, so
  // installing sbx while the shell runs needs no restart.
  onPanelOpenChanged: if (panelOpen) {
    if (resolved && !installed) resolve()
    else refresh()
  }

  Component.onCompleted: {
    if (demo) loadDemo()
    resolveProc.running = true
  }
}
