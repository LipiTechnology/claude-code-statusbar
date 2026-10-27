#!/usr/bin/env bash
# SessionStart hook: make the plugin's status bar actually work.
#
# Plugins cannot declare a statusLine, and statusLine commands don't expand
# ${CLAUDE_PLUGIN_ROOT}. So we copy the script to the stable plugin data dir
# (survives updates, unlike the versioned cache path) and write that literal
# absolute path into the user's settings.json — but only if they don't already
# have a statusLine, so a user's own choice is never clobbered.
#
# Must never fail a session start: every step degrades quietly.

root="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$root" ] && [ -f "$root/statusline-command.sh" ] || exit 0

# ponytail: data dir is stable across updates; fall back to plugin root if the
# runtime is too old to set CLAUDE_PLUGIN_DATA (works until the next update).
data="${CLAUDE_PLUGIN_DATA:-$root}"
mkdir -p "$data" 2>/dev/null || data="$root"
cp "$root/statusline-command.sh" "$data/statusline-command.sh" 2>/dev/null || data="$root"
chmod +x "$data/statusline-command.sh" 2>/dev/null || true

settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
script_raw="$data/statusline-command.sh"
script="$script_raw"
config_dir="${CLAUDE_CONFIG_DIR:-}"

# Windows (Git Bash): Claude Code may hand us C:\... paths, and unquoted
# backslashes get eaten when the command runs. Write forward-slash paths.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    if command -v cygpath >/dev/null 2>&1; then
      script="$(cygpath -m "$script_raw" 2>/dev/null || printf '%s' "$script_raw")"
      [ -n "$config_dir" ] && config_dir="$(cygpath -m "$config_dir" 2>/dev/null || printf '%s' "$config_dir")"
    fi
    ;;
esac

# Pass a custom config dir as an argument so the script reads the right account
# file / cache dir even if CLAUDE_CONFIG_DIR isn't inherited. An argument, not
# a `VAR=... bash` prefix, because Windows may run the command via PowerShell.
# Only when a custom dir is in use — default installs stay a plain command.
if [ -n "$config_dir" ]; then
  cmd="bash \"$script\" \"$config_dir\""
else
  cmd="bash \"$script\""
fi

# Find a Python that actually runs (on Windows `python3` is often the Store
# stub: on PATH, but fails).
py=()
for c in python3 python; do
  command -v "$c" >/dev/null 2>&1 && "$c" -c '' >/dev/null 2>&1 && { py=("$c"); break; }
done
[ "${#py[@]}" -eq 0 ] && command -v py >/dev/null 2>&1 && py -3 -c '' >/dev/null 2>&1 && py=(py -3)

# Set statusLine only if absent. Prefer python3 (already a script dependency),
# fall back to jq if Python is missing or fails.
done=""
if [ "${#py[@]}" -gt 0 ]; then
  "${py[@]}" - "$settings" "$cmd" "$script" "$script_raw" <<'PY' 2>/dev/null && done=1
import json, os, sys
path, cmd = sys.argv[1], sys.argv[2]
scripts = [s for s in sys.argv[3:] if s]
if os.path.exists(path):
    # An existing file we can't read/parse is left alone: rewriting it from
    # scratch would wipe the user's other settings.
    try:
        with open(path, encoding="utf-8-sig") as f:
            data = json.load(f)
    except Exception:
        sys.exit(0)
    if not isinstance(data, dict):
        sys.exit(0)
else:
    data = {}
sl = data.get("statusLine")
# Create if absent; else rewrite only a statusLine that is OURS -- identified by
# it pointing at our script path -- so we can upgrade an older command to the
# current one (config dir argument + refreshInterval) without ever clobbering
# a status line the user set up themselves.
if not isinstance(sl, dict):
    data["statusLine"] = {"type": "command", "command": cmd, "refreshInterval": 30}
elif isinstance(sl.get("command"), str) and any(s in sl["command"] for s in scripts) and (sl.get("command") != cmd or sl.get("refreshInterval") != 30):
    sl["command"] = cmd
    sl["refreshInterval"] = 30
else:
    sys.exit(0)
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
os.replace(tmp, path)
PY
fi

if [ -z "$done" ] && command -v jq >/dev/null 2>&1; then
  filter='if (.statusLine|type)!="object" then .statusLine={type:"command",command:$c,refreshInterval:30} elif (.statusLine.command|type)=="string" and ((.statusLine.command|contains($s)) or (.statusLine.command|contains($r))) then .statusLine.command=$c | .statusLine.refreshInterval=30 else . end'
  tmp="$(mktemp)" || exit 0
  if [ -f "$settings" ]; then
    # jq fails on an unparseable file, so nothing is written in that case.
    jq --arg c "$cmd" --arg s "$script" --arg r "$script_raw" "$filter" "$settings" >"$tmp" 2>/dev/null && mv "$tmp" "$settings"
  else
    mkdir -p "$(dirname "$settings")" 2>/dev/null
    jq -n --arg c "$cmd" --arg s "$script" --arg r "$script_raw" "{} | $filter" >"$tmp" 2>/dev/null && mv "$tmp" "$settings"
  fi
  rm -f "$tmp" 2>/dev/null
fi

exit 0
