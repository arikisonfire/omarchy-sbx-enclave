.pragma library

// The sbx guide: the words you meet, then the commands grouped by what you
// want to do. Checked against sbx 0.45 and 0.47.

var CONCEPTS = [
  { term: "Sandbox", text: "A small virtual machine (microVM) for one agent: its own Linux, its own Docker, its own network. It sees only the folders you hand it." },
  { term: "Agent", text: "The AI coding tool inside: Claude Code, Codex, Gemini CLI, Copilot, OpenCode … or just a shell." },
  { term: "Workspace", text: "A host folder mounted into the sandbox at the same path. The first one is where the agent starts. Append :ro to make one read-only." },
  { term: "Direct or clone", text: "Direct: the agent edits your folder and you see changes at once. Clone: it works on a private Git clone, you fetch its commits when you want them." },
  { term: "Policy", text: "Rules for the network: which hosts sandboxes may reach. Unknown hosts are blocked or wait for your approval." },
  { term: "Secret", text: "An API key or token stored on your machine. The proxy adds it to the agent's requests; the value never enters the sandbox." },
  { term: "Template", text: "The image a sandbox starts from. Save a set-up sandbox as a template to start the next one ready-made." },
  { term: "Kit", text: "A package of tools, configuration and network rules to add to a sandbox (experimental)." },
  { term: "Daemon", text: "sandboxd, the background service that runs the VMs. Most sbx commands start it when it is down." }
]

var SECTIONS = [
  { id: "start", title: "Start and come back", items: [
    { title: "Start an agent in a folder", cmd: "sbx run claude ~/my-project",
      text: "Creates the sandbox if it does not exist and attaches you to the agent. Without a path it uses the current folder." },
    { title: "Give it a name", cmd: "sbx run --name my-project claude ~/my-project",
      text: "A name makes it easy to come back. Without one, sbx uses <agent>-<folder>." },
    { title: "Come back later", cmd: "sbx run --name my-project",
      text: "Works from any folder; the agent is read from the sandbox. Running the same folder again also reconnects." },
    { title: "Pass arguments to the agent", cmd: "sbx run claude -- --continue",
      text: "Everything after -- goes to the agent itself, e.g. to resume the last conversation." },
    { title: "Create without attaching", cmd: "sbx create --name my-project claude .",
      text: "Sets it up in the background. It stops again when no session keeps it running." },
    { title: "Work on a private Git clone", cmd: "sbx run --clone claude .",
      text: "Your working tree stays untouched. Get the agent's commits with git fetch sandbox-<name>. Fixed at creation." },
    { title: "More folders, some read-only", cmd: "sbx run claude ~/app ~/docs:ro",
      text: "Extra folders appear at the same path inside. :ro keeps a folder, or a single file, out of the agent's reach for writing." },
    { title: "No host folder at all", cmd: "sbx create --name scratch claude",
      text: "The agent works in the sandbox's own filesystem, which is deleted with the sandbox." },
    { title: "Environment variables", cmd: "sbx run -e LOG_LEVEL=debug claude",
      text: "Readable by everything inside: never put keys here, store them with sbx secret." },
    { title: "CPU and memory", cmd: "sbx run --cpus 4 --memory 8g claude",
      text: "Defaults: all host CPUs (at most 16 on arm64) and half the host memory." }
  ]},
  { id: "manage", title: "See and manage", items: [
    { title: "List sandboxes", cmd: "sbx ls",
      text: "Name, agent, status, ports and workspace of every sandbox. Add --json for scripts." },
    { title: "Everything about one", cmd: "sbx inspect my-project",
      text: "Image, folders, network policy, secrets, ports and how many sessions are attached." },
    { title: "Open a shell inside", cmd: "sbx exec -it my-project bash",
      text: "Starts a stopped sandbox first and opens in the primary workspace." },
    { title: "Run one command inside", cmd: "sbx exec my-project git status",
      text: "Like docker exec. Wrap pipes and redirects in bash -c '…' so they run inside, not on your machine." },
    { title: "Stop", cmd: "sbx stop my-project",
      text: "Pauses the VM. Installed packages, Docker images and files inside stay." },
    { title: "Remove", cmd: "sbx rm my-project",
      text: "Deletes the VM with everything installed inside and its own secrets. Your project folder is not touched." },
    { title: "Remove all stopped ones", cmd: "sbx prune --dry-run",
      text: "Lists what would go; run it without --dry-run to remove. Running sandboxes are never pruned." },
    { title: "Dashboard", cmd: "sbx",
      text: "Interactive terminal dashboard: live CPU and memory, attach, shell, network rules." }
  ]},
  { id: "files", title: "Files and ports", items: [
    { title: "Copy into a sandbox", cmd: "sbx cp ./config.json my-project:/home/agent/workspace/",
      text: "One side is SANDBOX:/absolute/path. Copying between two sandboxes is not supported." },
    { title: "Copy out of a sandbox", cmd: "sbx cp my-project:/home/agent/workspace/out.log ./",
      text: "For results that do not live in a mounted folder." },
    { title: "Add a folder to a running sandbox", cmd: "sbx mount my-project ~/data:/data:ro",
      text: "Kept across restarts. Undo with sbx umount my-project ~/data:/data." },
    { title: "Publish a port", cmd: "sbx ports my-project --publish 8080:3000",
      text: "Sandbox port 3000 becomes http://localhost:8080. The server inside must listen on 0.0.0.0." },
    { title: "Let the system pick the port", cmd: "sbx ports my-project --publish 3000",
      text: "sbx ls then shows which host port it got." },
    { title: "Stop forwarding a port", cmd: "sbx ports my-project --unpublish 8080:3000",
      text: "" },
    { title: "Reach your machine from inside", cmd: "curl http://host.docker.internal:3000",
      text: "Inside a sandbox, host.docker.internal is your machine. The policy must allow it." }
  ]},
  { id: "network", title: "Network rules", items: [
    { title: "See the rules", cmd: "sbx policy ls",
      text: "--wide shows rule IDs; add a sandbox name for the rules that apply to it." },
    { title: "What was blocked or allowed", cmd: "sbx policy log",
      text: "Hosts with counts and the rule that decided. Add a sandbox name to filter." },
    { title: "Allow a host", cmd: "sbx policy allow network api.example.com",
      text: "Also *.example.com, **.example.com, IPs, CIDR and :port. --sandbox NAME limits it to one sandbox." },
    { title: "Block a host", cmd: "sbx policy deny network ads.example.com",
      text: "A deny always beats an allow for the same host." },
    { title: "Remove a rule", cmd: "sbx policy rm network --resource api.example.com",
      text: "Or by --id from sbx policy ls --wide." },
    { title: "Would this be allowed?", cmd: "sbx policy check network https://api.example.com",
      text: "Evaluates the current rules without connecting anywhere." },
    { title: "Answer a waiting request", cmd: "sbx policy approval ls",
      text: "Then sbx policy approval respond <ID> --option allow (or dismiss)." },
    { title: "Start over", cmd: "sbx policy reset",
      text: "Deletes all custom rules and stops running sandboxes; you pick a preset again: allow-all, balanced or deny-all." }
  ]},
  { id: "secrets", title: "Keys and sign-in", items: [
    { title: "Sign in to Docker", cmd: "sbx login",
      text: "Needed once. sbx logout stops running sandboxes and signs out." },
    { title: "Store an API key", cmd: "sbx secret set anthropic",
      text: "Asks for the value. Services include anthropic, openai, github, google, cursor, xai. --sandbox NAME stores it for one sandbox." },
    { title: "Take a token from another tool", cmd: "sbx secret set github --command 'gh auth token'",
      text: "Resolved on your machine when needed. 1Password works with --ref op://…" },
    { title: "Sign in to OpenAI instead of a key", cmd: "sbx secret set openai --oauth",
      text: "The sign-in runs on your machine, not inside a sandbox." },
    { title: "List stored secrets", cmd: "sbx secret ls",
      text: "Names and scopes; never the values." },
    { title: "Remove a secret", cmd: "sbx secret rm github",
      text: "Running sandboxes lose it right away." }
  ]},
  { id: "extend", title: "Templates, MCP and kits", items: [
    { title: "Save a sandbox as a template", cmd: "sbx template save my-project my-template:v1",
      text: "Captures the tools installed inside, not your folders. Never save one where you typed keys into files." },
    { title: "Start from a template", cmd: "sbx run -t my-template:v1 --pull never claude",
      text: "--pull never uses the local image without asking a registry." },
    { title: "List templates", cmd: "sbx template ls",
      text: "Images in the sandbox runtime, with their size." },
    { title: "Register an MCP server", cmd: "sbx mcp add notion --url https://mcp.notion.com/mcp",
      text: "Start sandboxes with --static-mcp notion to give them its tools." },
    { title: "Load MCP into a running sandbox", cmd: "sbx mcp load notion --sandbox my-project",
      text: "The agent sees the new tools without a restart." },
    { title: "Add a kit", cmd: "sbx run claude --kit ./my-mixin/",
      text: "Experimental: tools, configuration and network rules as one package." }
  ]},
  { id: "trouble", title: "Daemon and trouble", items: [
    { title: "Is the daemon running?", cmd: "sbx daemon status",
      text: "Shows its socket and where its log is." },
    { title: "Restart the daemon", cmd: "sbx daemon restart",
      text: "Running sandboxes stop." },
    { title: "Check the installation", cmd: "sbx diagnose",
      text: "CLI, daemon, virtualization, disk space and sign-in. --output github-issue formats a bug report." },
    { title: "Versions", cmd: "sbx version",
      text: "CLI and daemon versions." },
    { title: "Settings", cmd: "sbx settings list",
      text: "Every setting with its value and where it comes from. Change one with sbx settings set KEY VALUE." },
    { title: "Factory reset", cmd: "sbx reset",
      text: "Deletes every sandbox, image, rule and secret. --preserve-secrets keeps your keys." }
  ]}
]

function matches(item, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return true
  var hay = (item.title + " " + item.cmd + " " + item.text).toLowerCase()
  var words = q.split(/\s+/)
  for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false
  return true
}

function filtered(query) {
  var out = []
  for (var i = 0; i < SECTIONS.length; i++) {
    var items = SECTIONS[i].items.filter(function(it) { return matches(it, query) })
    if (items.length) out.push({ id: SECTIONS[i].id, title: SECTIONS[i].title, items: items })
  }
  return out
}

function count() {
  var n = 0
  for (var i = 0; i < SECTIONS.length; i++) n += SECTIONS[i].items.length
  return n
}
