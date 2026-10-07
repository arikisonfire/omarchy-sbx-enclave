.pragma library

// Made-up but realistic sbx state for demo mode (screenshots, trying the
// popup without Docker Sandboxes). Shapes follow sbx 0.45.1 JSON output.

function iso(msAgo) { return new Date(Date.now() - msAgo).toISOString() }
var MIN = 60000, HOUR = 3600000, DAY = 86400000

function build(home) {
  var h = String(home || "/home/demo")
  var w = function(p) { return h + p }

  var sandboxes = [
    { name: "claude-webshop", id: "demo-1", agent: "claude", status: "running", last_used_at: iso(2 * MIN),
      workspaces: [w("/Work/webshop")], ports: ["127.0.0.1:8080->3000/tcp4"], created_at: iso(2 * DAY) },
    { name: "codex-api", id: "demo-2", agent: "codex", status: "running", last_used_at: iso(9 * MIN),
      workspaces: [w("/Work/api"), w("/Work/shared-libs:ro")], created_at: iso(5 * HOUR) },
    { name: "gemini-docs", id: "demo-3", agent: "gemini", status: "stopped", last_used_at: iso(3 * HOUR),
      workspaces: [w("/Notes/docs")], created_at: iso(4 * DAY) },
    { name: "scratch", id: "demo-4", agent: "shell", status: "stopped", last_used_at: iso(2 * DAY),
      workspaces: [], created_at: iso(6 * DAY) }
  ]

  var details = {
    "claude-webshop": { name: "claude-webshop", agent: "claude", kits: [], state: "running", uptime: "1h 12m",
      image: "docker/sandbox-templates:claude-code-docker", auth_mode: "oauth · anthropic", workspace: w("/Work/webshop"),
      network_policy: { scope: "global" }, proxy: "172.17.0.2:3128",
      secrets: [{ name: "anthropic", source: "uploaded" }, { name: "github", source: "uploaded" }], mcp_gateway: true, sessions: 1 },
    "codex-api": { name: "codex-api", agent: "codex", kits: [], state: "running", uptime: "5h 4m",
      image: "docker/sandbox-templates:codex-docker", auth_mode: "oauth · openai", workspace: w("/Work/api"),
      additional_workspaces: [{ dir: w("/Work/shared-libs"), read_only: true }],
      network_policy: { scope: "global" }, proxy: "172.17.0.3:3128",
      secrets: [{ name: "openai", source: "uploaded" }], mcp_gateway: true, sessions: 2 },
    "gemini-docs": { name: "gemini-docs", agent: "gemini", kits: [], state: "stopped",
      image: "docker/sandbox-templates:gemini-docker", auth_mode: "api key · google", workspace: w("/Notes/docs"),
      network_policy: { scope: "global" }, proxy: "172.17.0.4:3128", secrets: [], mcp_gateway: false, sessions: 0 },
    "scratch": { name: "scratch", agent: "shell", kits: [], state: "stopped",
      image: "docker/sandbox-templates:shell-docker", auth_mode: "none", workspace: "",
      network_policy: { scope: "global" }, proxy: "172.17.0.5:3128", secrets: [], mcp_gateway: false, sessions: 0 }
  }

  var approvals = [
    { id: "network:demo-a", sandbox: "claude-webshop", title: "api.stripe.com:443",
      detail: "Protocol: TCP Resource type: domain no matching allow rule (default deny)",
      options: [{ id: "allow", label: "Allow" }, { id: "dismiss", label: "Dismiss" }] },
    { id: "network:demo-b", sandbox: "codex-api", title: "telemetry.example.dev:443",
      detail: "Protocol: TCP Resource type: domain no matching allow rule (default deny)",
      options: [{ id: "allow", label: "Allow" }, { id: "dismiss", label: "Dismiss" }] }
  ]

  var blocked = [
    { host: "api.stripe.com:443", vm_name: "claude-webshop", last_seen: iso(1 * MIN), count_since: 3, reason: "No matching allow rule (default deny)" },
    { host: "telemetry.example.dev:443", vm_name: "codex-api", last_seen: iso(6 * MIN), count_since: 41, reason: "No matching allow rule (default deny)" },
    { host: "fonts.example-cdn.net:443", vm_name: "claude-webshop", last_seen: iso(48 * MIN), count_since: 2, reason: "No matching allow rule (default deny)" }
  ]
  var allowed = [
    { host: "api.anthropic.com:443", vm_name: "claude-webshop", last_seen: iso(1 * MIN), count_since: 412 },
    { host: "registry.npmjs.org:443", vm_name: "claude-webshop", last_seen: iso(4 * MIN), count_since: 96 },
    { host: "api.openai.com:443", vm_name: "codex-api", last_seen: iso(9 * MIN), count_since: 233 },
    { host: "github.com:443", vm_name: "codex-api", last_seen: iso(12 * MIN), count_since: 18 },
    { host: "pypi.org:443", vm_name: "codex-api", last_seen: iso(25 * MIN), count_since: 41 }
  ]

  var rule = function(id, name, decision, resources, applies, via, editable) {
    return { id: id, name: name, policy_id: "local-policy", scope: applies === "all" ? "global" : applies, applies_to: applies,
             resource_type: "network", decision: decision, resources: resources, origin: "local", layer: "local",
             status: "active", editable: editable, provenance: { created_via: via }, actions: ["net:connect:tcp"] }
  }
  var rules = [
    rule("default-ai-services", "default-ai-services", "allow", ["api.anthropic.com:443", "api.openai.com:443", "generativelanguage.googleapis.com:443"], "all", "default", true),
    rule("default-package-managers", "default-package-managers", "allow", ["registry.npmjs.org:443", "pypi.org:443", "files.pythonhosted.org:443"], "all", "default", true),
    rule("default-code-and-containers", "default-code-and-containers", "allow", ["github.com:443", "api.github.com:443", "registry-1.docker.io:443"], "all", "default", true),
    // sbx names added rules after their id and answered requests "approval:<id>"
    rule("51c0be77-2a8e-4d0b-b6f3-94c2e1d7a508", "51c0be77-2a8e-4d0b-b6f3-94c2e1d7a508", "deny", ["ads.example.com"], "all", "added", true),
    rule("c41f9e07-6d2a-4b8e-a1c3-5e7f90b2d416", "approval:c41f9e07-6d2a-4b8e-a1c3-5e7f90b2d416", "allow", ["registry.yarnpkg.com:443"], "sandbox:claude-webshop", "approval", true),
    rule("8d2e7c1a-5b3f-4e21-9c7d-2f61a0b4e913", "8d2e7c1a-5b3f-4e21-9c7d-2f61a0b4e913", "allow", ["*.ingest.sentry.io:443"], "sandbox:claude-webshop", "added", true)
  ]

  var secrets = [
    { scope: "global", type: "service", name: "anthropic", secret: "(oauth configured)" },
    { scope: "global", type: "service", name: "openai", secret: "(stored)" },
    { scope: "global", type: "service", name: "github", secret: "(stored)" }
  ]

  var mcp = {
    gateway: { name: "LOCAL", local: true, operator: "managed by you", signed_in_as: "demo" },
    servers: [
      { name: "notion", transport: "remote", status: "ready", type: "remote" },
      { name: "github", transport: "local stdio", status: "ready", type: "local" }
    ]
  }

  var templates = [
    { id: "549730947ed8", repository: "docker.io/docker/sandbox-templates", tag: "claude-code-docker", created_at: iso(8 * DAY), size: 920132471 },
    { id: "a17c55e09b31", repository: "docker.io/docker/sandbox-templates", tag: "codex-docker", created_at: iso(8 * DAY), size: 874213004 },
    { id: "1560168ac5fb", repository: "docker.io/docker/sandbox-templates", tag: "shell-docker", created_at: iso(8 * DAY), size: 583004110 }
  ]

  var health = [
    { name: "CLI binary", status: "pass", message: "found", hint: "" },
    { name: "Binary version", status: "pass", message: "v0.47.0", hint: "" },
    { name: "Daemon", status: "pass", message: "healthy", hint: "" },
    { name: "Virtualization", status: "pass", message: "supported", hint: "" },
    { name: "Disk space", status: "warn", message: "9.4GiB free", hint: "Sandboxes and their images need room to grow. Remove stopped sandboxes under Clean up, or see https://docs.docker.com/ai/sandboxes/" },
    { name: "Authentication", status: "pass", message: "authenticated", hint: "" }
  ]

  return {
    sandboxes: sandboxes, details: details, approvals: approvals, blocked: blocked, allowed: allowed,
    rules: rules, secrets: secrets, mcp: mcp, templates: templates, health: health,
    healthSummary: { pass: 5, warn: 1, fail: 0, skip: 0 },
    prune: [
      { name: "gemini-docs", agent: "gemini", stopped_at: iso(3 * HOUR), workspaces: [w("/Notes/docs")] },
      { name: "scratch", agent: "shell", stopped_at: iso(2 * DAY), workspaces: [] }
    ],
    version: { client: "v0.47.0", server: "v0.47.0" },
    daemonLog: h + "/.local/state/sandboxes/sandboxes/sandboxd/daemon.log"
  }
}
