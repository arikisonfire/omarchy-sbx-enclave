.pragma library

// Pure helpers for sbxEnclave: agent catalog, sandbox names, sbx argument
// lists, daemon API parsing and display formatting. No QML, no state.

// ------------------------------------------------------------------ agents
// Built-in agents of sbx 0.45/0.46. `secret` is the service an API key is
// stored under with `sbx secret set <service>`; `login` says how to sign in
// without one.
var AGENTS = [
  { id: "claude", label: "Claude Code", vendor: "Anthropic", secret: "anthropic",
    login: "No API key stored? Type /login inside Claude Code to sign in with your subscription." },
  { id: "codex", label: "Codex", vendor: "OpenAI", secret: "openai",
    login: "Store an OpenAI key, or run `sbx secret set openai --oauth` once to sign in." },
  { id: "copilot", label: "Copilot CLI", vendor: "GitHub", secret: "github",
    login: "Store a GitHub token, e.g. `sbx secret set github --command 'gh auth token'`." },
  { id: "cursor", label: "Cursor", vendor: "Cursor", secret: "cursor",
    login: "Store a Cursor API key, or sign in when Cursor asks on first start." },
  { id: "devin", label: "Devin", vendor: "Cognition", secret: "devin",
    login: "Sign in when Devin asks on first start; the proxy keeps the login." },
  { id: "docker-agent", label: "Docker Agent", vendor: "Docker", secret: "",
    login: "Uses the provider keys you store (openai, anthropic, google, …)." },
  { id: "droid", label: "Droid", vendor: "Factory", secret: "droid",
    login: "Store a Factory API key, or sign in when Droid asks on first start." },
  { id: "gemini", label: "Gemini CLI", vendor: "Google", secret: "google",
    login: "Store a Google API key, or sign in with your Google account when asked." },
  { id: "kiro", label: "Kiro", vendor: "AWS", secret: "",
    login: "Sign in once with the device flow: `sbx run kiro --name <name> -- login --use-device-flow`." },
  { id: "opencode", label: "OpenCode", vendor: "Open source", secret: "",
    login: "Uses the provider keys you store (openai, anthropic, google, groq, …)." },
  { id: "shell", label: "Shell", vendor: "No agent", secret: "",
    login: "A Bash login shell with its own Docker, for manual work and testing." }
]

function agent(id) {
  for (var i = 0; i < AGENTS.length; i++) if (AGENTS[i].id === id) return AGENTS[i]
  return { id: String(id || ""), label: String(id || "agent"), vendor: "", secret: "", login: "" }
}

// ------------------------------------------------------------------ names
// sbx: at least two characters, starts with a letter or digit, then letters,
// digits, hyphens and periods; "default" is reserved.
function nameProblem(name) {
  var n = String(name || "")
  if (n === "") return ""
  if (n.length < 2) return "At least two characters"
  if (!/^[A-Za-z0-9]/.test(n)) return "Start with a letter or a digit"
  if (!/^[A-Za-z0-9][A-Za-z0-9.-]*$/.test(n)) return "Only letters, digits, hyphens and periods"
  if (n.toLowerCase() === "default") return "\"default\" is reserved"
  return ""
}

function baseName(path) {
  var p = String(path || "").replace(/\/+$/, "")
  var i = p.lastIndexOf("/")
  return i >= 0 ? p.substr(i + 1) : p
}

// A path without trailing slashes ("/" stays "/").
function cleanPath(path) {
  var p = String(path || "")
  return p.replace(/\/+$/, "") || (p.charAt(0) === "/" ? "/" : "")
}

// "~" and "~/…" as the home folder.
function expandHome(path, home) {
  var p = String(path || "")
  return home && /^~(\/|$)/.test(p) ? home + p.substr(1) : p
}

// sbx names a sandbox <agent>-<workdir>; spell that out with the characters a
// name may hold, so the name the plugin shows is the one sbx will use. Accents
// are dropped rather than the whole letter ("Ärger" → "Arger").
function defaultName(agentId, path) {
  var base = baseName(path).normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9.-]+/g, "-").replace(/-+/g, "-").replace(/^[-.]+|[-.]+$/g, "")
  var a = String(agentId || "shell")
  return base ? a + "-" + base : a
}

// ------------------------------------------------------------------ commands
// spec: { agent, path, extra: [{ path, ro }], name, clone, cpus, memory,
//         ports: [], env: [], envFiles: [], template, pull, skills, mcp: [],
//         kits: [], deny: [] }
// verb: "run" (attach in a terminal) or "create" (background)
function launchArgs(spec, verb) {
  var s = spec || {}
  var a = [verb === "create" ? "create" : "run"]
  if (s.name) a.push("--name", s.name)
  if (s.clone) a.push("--clone")
  if (Number(s.cpus) > 0) a.push("--cpus", String(Math.round(Number(s.cpus))))
  if (s.memory) a.push("--memory", String(s.memory))
  each(s.ports, function(p) { a.push("--publish", p) })
  each(s.env, function(e) { a.push("--env", e) })
  each(s.envFiles, function(f) { a.push("--env-file", f) })
  if (s.template) a.push("--template", s.template)
  if (s.pull && s.pull !== "always") a.push("--pull", s.pull)
  if (s.skills) a.push("--skills", s.skills)
  if (s.mcp && s.mcp.length) a.push("--static-mcp", s.mcp.join(","))
  each(s.kits, function(k) { a.push("--kit", k) })
  each(s.deny, function(d) { a.push("--deny-network", d) })
  a.push(s.agent || "claude")
  if (s.path) a.push(s.path)
  each(s.extra, function(x) { if (x && x.path) a.push(x.path + (x.ro ? ":ro" : "")) })
  return a
}

// Window class for an agent's terminal, so window switchers can tell agents
// apart (org.omarchy.sbx.claude, org.omarchy.sbx.codex, ...). Shells and
// unknown ids keep omarchy-launch-tui's default (org.omarchy.sbx).
function terminalAppId(agentId) {
  var a = String(agentId || "")
  if (a === "" || a === "shell" || !/^[a-z0-9-]+$/.test(a)) return ""
  return "org.omarchy.sbx." + a
}

function each(list, fn) {
  if (!list) return
  for (var i = 0; i < list.length; i++) {
    var v = list[i]
    if (v !== undefined && v !== null && String(v) !== "") fn(typeof v === "string" ? v.trim() : v)
  }
}

// Display form of an argv: words with shell metacharacters get single quotes.
function shellWord(w) {
  var s = String(w)
  if (s !== "" && /^[A-Za-z0-9_@%+=:,./-]+$/.test(s)) return s
  return "'" + s.replace(/'/g, "'\\''") + "'"
}

function commandLine(argv, bin) {
  return [bin || "sbx"].concat(argv || []).map(shellWord).join(" ")
}

// The short name when sbx sits in a standard PATH folder (window titles and
// app ids then read "sbx"), else the full path.
function binName(path) {
  var p = String(path || "")
  return /^\/usr(\/local)?\/bin\/sbx$/.test(p) || p === "" ? "sbx" : p
}

// First line of an error text, without the "Error: " prefix sbx adds.
function errorLine(text) {
  var lines = String(text || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  return lines.length ? lines[0].replace(/^(error|fatal):\s*/i, "") : ""
}

// The daemon refuses most requests until you sign in to Docker; its error
// then reads "user is not authenticated to Docker: …" (sbx 0.45 to 0.47).
function signedOut(message) {
  return /not authenticated to docker|not signed in to docker|sign in to docker/i.test(String(message || ""))
}

// What a sandbox status means for the light: "running", "stopped", "busy"
// (on its way somewhere: starting, stopping, …) or "alert" (anything else,
// e.g. an error). The API has only shown running and stopped so far.
function statusKind(status) {
  var s = String(status || "").toLowerCase()
  if (s === "running") return "running"
  if (s === "stopped" || s === "") return "stopped"
  if (/^(start|stop|creat|remov|restart|pausing|resum|boot|provision|initiali[sz]|pending)/.test(s)) return "busy"
  return "alert"
}

// ------------------------------------------------------------------ daemon API
// GET /sandbox (sandboxd API 0.36) in the shape of `sbx ls --json`: the
// workspace and its additional folders become "path" and "path:ro" strings.
function sandboxFromApi(s) {
  var o = s || {}
  var ws = []
  if (o.workspace) ws.push(String(o.workspace))
  var more = o.additional_workspaces instanceof Array ? o.additional_workspaces : []
  for (var i = 0; i < more.length; i++)
    if (more[i] && more[i].dir) ws.push(String(more[i].dir) + (more[i].read_only ? ":ro" : ""))
  return { name: String(o.name || ""), id: String(o.id || ""), agent: String(o.agent || ""), status: String(o.status || ""),
           created_at: o.created_at || "", last_used_at: o.last_used_at || "", workspaces: ws,
           ports: o.ports instanceof Array ? o.ports.map(portText) : [] }
}

// A published port as `sbx ls` prints it ("127.0.0.1:8080->3000/tcp4"). The
// API's own form is not documented yet; an unknown object is spelled out.
function portText(p) {
  if (typeof p === "string") return p
  if (!p || typeof p !== "object") return String(p)
  var inner = p.sandbox_port !== undefined ? p.sandbox_port : p.container_port
  if (p.host_port !== undefined && inner !== undefined)
    return (p.host_ip ? p.host_ip + ":" : "") + p.host_port + "->" + inner + (p.protocol ? "/" + p.protocol : "")
  return Object.keys(p).map(function(k) { return k + "=" + p[k] }).join(" ")
}

// GET /user-prompts streams NDJSON: {"action":"requested","prompt":{…}} per
// waiting request, then {"action":"synced"}, then live changes (any other
// action drops the prompt). Returns approvals as { id, sandbox, title, detail,
// options: [{ id, label }] }, or null when the stream ended before "synced"
// (keep the last list then).
function parsePromptStream(text) {
  var byId = {}
  var order = []
  var synced = false
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var ev = null
    try { ev = JSON.parse(lines[i]) } catch (e) { continue }
    if (!ev) continue
    if (ev.action === "synced") { synced = true; continue }
    var p = ev.prompt
    if (!p || !p.id) continue
    if (ev.action === "requested") {
      if (order.indexOf(p.id) < 0) order.push(p.id)
      byId[p.id] = p
    } else delete byId[p.id]
  }
  if (!synced) return null
  return order.filter(function(id) { return byId[id] }).map(function(id) {
    var p = byId[id]
    var options = (p.options instanceof Array ? p.options : []).map(function(o) {
      return { id: String(o.id || ""), label: String(o.label || o.id || "") }
    }).filter(function(o) { return o.id !== "" })
    return { id: String(p.id), sandbox: String(p.sandbox_name || ""), title: String(p.title || ""),
             detail: String(p.detail || "").replace(/\s*\n\s*/g, " ").trim(), options: options }
  })
}

// ------------------------------------------------------------------ format
function prettyPath(path, home) {
  var p = String(path || "")
  if (home && (p === home || p.indexOf(home + "/") === 0)) return "~" + p.substr(home.length)
  return p
}

// "/usr/share/omarchy:ro" → { path, ro }
function splitMount(spec) {
  var s = String(spec || "")
  if (/:ro$/.test(s)) return { path: s.slice(0, -3), ro: true }
  if (/:rw$/.test(s)) return { path: s.slice(0, -3), ro: false }
  return { path: s, ro: false }
}

function ago(iso, nowMs) {
  var t = Date.parse(iso)
  if (!isFinite(t)) return ""
  var s = Math.max(0, Math.round(((nowMs || Date.now()) - t) / 1000))
  if (s < 60) return "just now"
  if (s < 3600) return Math.round(s / 60) + "m ago"
  if (s < 86400) return Math.round(s / 3600) + "h ago"
  return Math.round(s / 86400) + "d ago"
}

function clock(iso) {
  var d = new Date(Date.parse(iso))
  if (!isFinite(d.getTime())) return ""
  function two(n) { return (n < 10 ? "0" : "") + n }
  return two(d.getHours()) + ":" + two(d.getMinutes())
}

function bytes(n) {
  var v = Number(n)
  if (!isFinite(v) || v <= 0) return ""
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (v >= 1000 && i < units.length - 1) { v /= 1000; i++ }
  return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i]
}

// "api.anthropic.com:443" → "api.anthropic.com" (443 is the default)
function host(h) {
  return String(h || "").replace(/:443$/, "")
}

// One concrete host as the proxy reports it: a DNS name or an IPv4 address,
// or an IPv6 address in brackets, each with an optional port. The hosts in
// approvals and in the policy log come from what an agent tried to reach,
// so they are untrusted. sbx reads a rule's resource as a comma separated
// list of patterns ("a.example,**" would also allow every host), so a
// one-click Allow or Block is only offered for plain hosts: no wildcards,
// commas, CIDR, spaces or a leading "-".
function isPlainHost(h) {
  var s = String(h || "")
  if (s.length === 0 || s.length > 300) return false
  if (/^\[[0-9A-Fa-f:.]+\](:\d{1,5})?$/.test(s)) return true
  return /^[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,62})(?:\.[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,62}))*\.?(:\d{1,5})?$/.test(s)
}

// The resource for a rule about one plain host: without the default ":443",
// except for an IPv6 address, which sbx takes only with its port.
function ruleHost(h) {
  var s = String(h || "")
  return s.charAt(0) === "[" ? s : host(s)
}

// `sbx policy rm network` looks in the global policy unless --sandbox names
// the one sandbox a rule applies to ("sandbox:<name>"), so without it a
// sandbox's rule (Block on a request, an approved request, a rule added for
// one sandbox) is never found. null when the rule has no id or its scope is
// not a sandbox name.
function ruleRemoveArgs(rule) {
  var r = rule || {}
  var id = String(r.id || "")
  if (id === "") return null
  var argv = ["policy", "rm", "network"]
  var scope = String(r.applies_to || "")
  if (scope.indexOf("sandbox:") === 0) {
    var name = scope.slice("sandbox:".length)
    if (name === "" || nameProblem(name) !== "") return null
    argv.push("--sandbox", name)
  }
  return argv.concat(["--id", id, "--force"])
}

// sbx names a rule you add after its id ("893ffe03-cf75-…") and one made by
// answering a request after the request ("approval:50e455ee-…"). Such a
// name says nothing, so the rule is shown by its hosts instead; the defaults
// drop their "default-" prefix and kits keep their name. (instanceof, not
// Array.isArray: a list that reaches a delegate as modelData is a QML
// sequence, which Array.isArray rejects.)
function ruleShowsHosts(rule) {
  var r = rule || {}
  var name = String(r.name || "")
  return r.resources instanceof Array && r.resources.length > 0
    && (name === "" || /^([a-z]+:)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(name))
}

function ruleTitle(rule) {
  var r = rule || {}
  if (ruleShowsHosts(r)) return r.resources.map(function(h) { return host(h) }).join(", ")
  return String(r.name || r.id || "").replace(/^default-/, "")
}

function escapeHtml(s) {
  return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// Turns bare http(s) URLs in plain sbx output into clickable links for a
// Text.StyledText; everything else is escaped so stray "<"/"&" in sbx's own
// messages can't break the markup.
function linkify(text) {
  var s = String(text || "")
  var re = /https?:\/\/[^\s<>"']+/g
  var out = ""
  var last = 0
  var m
  while ((m = re.exec(s)) !== null) {
    var url = m[0].replace(/[.,;:)]+$/, "")   // trailing punctuation is not part of the URL
    out += escapeHtml(s.slice(last, m.index)) + '<a href="' + escapeHtml(url) + '">' + escapeHtml(url) + '</a>'
    last = m.index + url.length
  }
  out += escapeHtml(s.slice(last))
  return out
}

// ------------------------------------------------------------------ settings
// The protectedSandboxes value in the text of shell.json, looked up where
// protect.sh writes it: on the widget's own bar entry, else in Bar Folder's
// widgetSettings when the widget sits in the folder. null when the text does
// not parse or no entry holds the widget, so the caller can fall back to the
// settings the bar handed in.
function protectedSetting(text, pluginId, folderId) {
  var config
  try { config = JSON.parse(String(text || "")) } catch (e) { return null }
  var layout = config && config.bar && config.bar.layout
  if (!layout || typeof layout !== "object") return null
  var own = null
  var folder = null
  var regions = ["left", "center", "right"]
  for (var r = 0; r < regions.length; r++) {
    var entries = Array.isArray(layout[regions[r]]) ? layout[regions[r]] : []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var id = e && typeof e === "object" ? String(e.id || "") : String(e)
      if (id === pluginId && own === null) own = e && typeof e === "object" ? e : {}
      else if (id === folderId && folder === null && e && typeof e === "object"
               && Array.isArray(e.widgets) && e.widgets.indexOf(pluginId) >= 0)
        folder = (e.widgetSettings && e.widgetSettings[pluginId]) || {}
    }
  }
  var entry = own !== null ? own : folder
  if (entry === null) return null
  var value = entry.protectedSandboxes
  return value === undefined || value === null ? "" : String(value)
}
