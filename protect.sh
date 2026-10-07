#!/bin/bash
# Adds a sandbox to sbxEnclave's protectedSandboxes setting or takes it out:
#
#   protect.sh on  <sandbox>
#   protect.sh off <sandbox>
#
# The setting lives in ~/.config/omarchy/shell.json, on the widget's bar entry,
# or under widgetSettings when the widget sits in Bar Folder. Omarchy's own
# helper writes the file atomically and makes the shell reload it. Nothing
# here runs unless the user clicks the lock on a sandbox card.

set -euo pipefail

source omarchy-shell-config

PLUGIN_ID="io.github.arikisonfire.sbx-enclave"
FOLDER_ID="io.github.arikisonfire.bar-folder"

mode=${1:?on or off required}
name=${2:?sandbox name required}
[[ $mode == on || $mode == off ]] || fail "invalid mode: $mode"
# sbx names: a letter or digit first, then letters, digits, hyphens and periods
[[ $name =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail "invalid sandbox name: $name"

# The lock Bar Folder's layout.sh takes too: the config directory itself, so
# the two never overwrite each other and no lock file is created.
config_dir=$(dirname -- "$CONFIG_FILE")
mkdir -p -- "$config_dir"
exec {lock_fd}<"$config_dir"
flock -w 10 "$lock_fd" || fail "timed out waiting for another shell.json change"

# Without an entry for the widget there is nowhere to keep the setting; say
# so instead of reporting a protection that was never stored.
jq -e "$NORMALIZE
  | def entry_id: if type == \"object\" then (.id // \"\") else tostring end;
  [.bar.layout[] | arrays | .[]
    | select(entry_id == \$plugin
        or (entry_id == \$folder and type == \"object\" and ((.widgets // []) | index(\$plugin)) != null))]
  | length > 0
" --arg plugin "$PLUGIN_ID" --arg folder "$FOLDER_ID" "$(source_file)" >/dev/null \
  || fail "sbxEnclave has no entry in the bar layout of shell.json"

commit "$NORMALIZE
  | def entry_id: if type == \"object\" then (.id // \"\") else tostring end;
  def names: if type == \"string\" then split(\",\") | map(gsub(\"^\\\\s+|\\\\s+\$\"; \"\")) | map(select(. != \"\")) else [] end;
  def toggled: (names | map(select(. != \$name))) + (if \$on then [\$name] else [] end) | join(\", \");
  .bar.layout |= with_entries(.value |= map(
    if entry_id == \$plugin then
      (if type == \"object\" then . else {id: entry_id} end)
      | .protectedSandboxes = (.protectedSandboxes | toggled)
    elif entry_id == \$folder and type == \"object\" and ((.widgets // []) | index(\$plugin)) != null then
      .widgetSettings = ((.widgetSettings // {}) | .[\$plugin] = ((.[\$plugin] // {}) | .protectedSandboxes = (.protectedSandboxes | toggled)))
    else . end))
" --arg plugin "$PLUGIN_ID" --arg folder "$FOLDER_ID" --arg name "$name" \
  --argjson on "$([[ $mode == on ]] && echo true || echo false)"
