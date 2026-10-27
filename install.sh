#!/usr/bin/env bash
# Install the Claude Code status bar.
# Copies statusline-command.sh into ~/.claude and points settings.json at it.
set -eu

src_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
dest_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
script="$dest_dir/statusline-command.sh"
settings="$dest_dir/settings.json"

mkdir -p "$dest_dir"
cp "$src_dir/statusline-command.sh" "$script"
chmod +x "$script"
echo "Installed $script"

# Windows (Git Bash): write forward-slash paths; backslashes get eaten when the
# command runs.
cmd_script="$script"
config_dir="${CLAUDE_CONFIG_DIR:-}"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    if command -v cygpath >/dev/null 2>&1; then
      cmd_script="$(cygpath -m "$script")"
      [ -n "$config_dir" ] && config_dir="$(cygpath -m "$config_dir")"
    fi
    ;;
esac

# Pass the config dir if custom, so the script finds the right account file/cache.
# An argument, not a `VAR=... bash` prefix, which PowerShell can't run.
if [ -n "$config_dir" ]; then
  cmd="bash \"$cmd_script\" \"$config_dir\""
else
  cmd="bash \"$cmd_script\""
fi

# Wire up settings.json -> statusLine.command, preserving existing settings.
if command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  if [ -f "$settings" ]; then
    jq --arg c "$cmd" '.statusLine = {type:"command", command:$c, refreshInterval:30}' "$settings" >"$tmp"
  else
    jq -n --arg c "$cmd" '{statusLine:{type:"command", command:$c, refreshInterval:30}}' >"$tmp"
  fi
  mv "$tmp" "$settings"
  echo "Configured $settings"
else
  # ponytail: no jq -> can't safely merge JSON, tell the user the one line to add.
  echo "jq not found. Add this to $settings manually:"
  echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$cmd\", \"refreshInterval\": 30 }"
fi

echo "Done. Restart Claude Code or run /statusline to see it."
