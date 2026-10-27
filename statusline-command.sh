#!/bin/bash
# Claude Code status line (three-line layout)
#
# Line 1: bar session-reset-time | 🗓️ bar weekly-reset-time | Model bar(used/context)
# Line 2: project branch dot (dot: green = clean, orange = dirty; git only)
# Line 3: effort / thinking / output style
#
# Colours are dimmed to suit Claude Code's status line rendering.
#
# Portable by design: no hardcoded absolute paths (the usage cache's location
# is derived from $HOME, falling back to this script's own directory, falling
# back to a temp dir), and every external dependency (jq, python3, git, a
# pre-existing cache file) is optional — missing tools/fields degrade to
# placeholders instead of making the script error out.

input=$(cat)

# Optional first argument: the Claude config dir. Passed as an argument rather
# than a `CLAUDE_CONFIG_DIR=... bash ...` prefix because Windows may run the
# statusLine command through PowerShell, where that prefix isn't valid syntax.
[ -n "${1:-}" ] && CLAUDE_CONFIG_DIR="$1"

# ---- helpers ----------------------------------------------------------

# Find a Python that actually runs. `command -v` alone isn't enough: on Windows
# `python3` is often the Microsoft Store stub, which exists on PATH but fails.
# Only called when jq is missing, so the probe costs nothing in the common case.
py=()
find_python() {
  [ "${#py[@]}" -gt 0 ] && return 0
  local c
  for c in python3 python; do
    command -v "$c" >/dev/null 2>&1 && "$c" -c '' >/dev/null 2>&1 && { py=("$c"); return 0; }
  done
  command -v py >/dev/null 2>&1 && py -3 -c '' >/dev/null 2>&1 && { py=(py -3); return 0; }
  return 1
}

# True if $1 looks like a plain (optionally decimal, optionally signed) number.
is_num() {
  case "$1" in
    '') return 1 ;;
    *[!0-9.+-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Turn an epoch timestamp into a local 12-hour clock time, e.g. "10:00pm"
fmt_time_of_day() {
  local epoch="$1" epoch_int
  is_num "$epoch" || { echo "--"; return; }
  epoch_int="${epoch%%.*}"
  { [ -z "$epoch_int" ] || [ "$epoch_int" -le 0 ] 2>/dev/null; } && { echo "--"; return; }
  date -d "@$epoch_int" +"%I:%M%p" 2>/dev/null || date -r "$epoch_int" +"%I:%M%p" 2>/dev/null || echo "--"
}

# Turn an epoch timestamp into a local weekday/date/time, e.g. "Tue 10 Jan 04:45am"
fmt_weekday_time() {
  local epoch="$1" epoch_int
  is_num "$epoch" || { echo "--"; return; }
  epoch_int="${epoch%%.*}"
  { [ -z "$epoch_int" ] || [ "$epoch_int" -le 0 ] 2>/dev/null; } && { echo "--"; return; }
  date -d "@$epoch_int" +"%a %d %b %I:%M%p" 2>/dev/null || date -r "$epoch_int" +"%a %d %b %I:%M%p" 2>/dev/null || echo "--"
}

# Turn a raw token count into a short label, e.g. 45231 -> 45k, 1200000 -> 1.2M
fmt_tokens() {
  local n="$1"
  is_num "$n" || { echo "--"; return; }
  n="${n%%.*}"
  [ -z "$n" ] && { echo "--"; return; }
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    printf '%sM' "$(( n / 1000000 ))"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    printf '%sk' "$(( n / 1000 ))"
  else
    printf '%s' "$n"
  fi
}

# Build a gradient progress bar of $2 cells wide, with $3 centred inside as a
# label. The fill colour reflects usage severity for THIS bar's own
# percentage: green (pct <= 50), yellow/amber (50 < pct < 85), red
# (pct >= 85) — each a tight, low-variance ramp (a few tones, each held for
# two cells) so the bar reads as one smooth fade instead of a rainbow, even
# at high usage. Unfilled cells use a lighter grey so empty bars stay
# visible. The label's text colour is chosen once per bar (from the active
# severity tier) so every character in it renders in the same colour, no
# matter which cell it lands on. Built cell-by-cell (never indexes the
# coloured string by length).
make_bar() {
  local pct="$1" width="$2" label="$3"
  local filled i idx bg fg cell lablen labstart labend ch out tier label_fg
  is_num "$pct" || pct=0
  pct="${pct%%.*}"
  [ -z "$pct" ] && pct=0
  filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0

  # Tight, low-variance ramps: a handful of tones (each held for two cells)
  # within a single hue family per severity, instead of a wide light->dark
  # sweep. This keeps high-usage bars looking like one smooth red fade
  # rather than a rainbow of unrelated shades.
  local green=(120 120 84 84 41 41 35 35 29 29 22 22)
  local yellow=(220 220 214 214 208 208 172 172 136 136 94 94)
  local red=(203 203 196 196 160 160 124 124 88 88 52 52)

  local grad
  if [ "$pct" -ge 85 ]; then
    grad=("${red[@]}")
    tier=red
  elif [ "$pct" -gt 50 ]; then
    grad=("${yellow[@]}")
    tier=yellow
  else
    grad=("${green[@]}")
    tier=green
  fi
  local gradlen=${#grad[@]}

  lablen=${#label}
  if [ "$lablen" -ge "$width" ]; then
    # No room for a label inside the bar; just show the label as plain text.
    printf '%s' "$label"
    return
  fi
  labstart=$(( (width - lablen) / 2 ))
  labend=$(( labstart + lablen - 1 ))

  # Decide the label's text colour ONCE per bar (based on the active
  # severity tier), not per character/cell — otherwise individual digits of
  # the same value can end up in different colours as the label crosses
  # cell boundaries with different backgrounds.
  case "$tier" in
    red) label_fg=15 ;;
    *) label_fg=232 ;;
  esac

  out=""
  for (( i=0; i<width; i++ )); do
    if [ "$i" -lt "$filled" ]; then
      idx=$(( i * gradlen / width ))
      bg="${grad[$idx]}"
    else
      # Unfilled cells: a lighter grey so empty bars stay visible instead
      # of disappearing into the terminal background.
      bg=240
    fi

    if [ "$i" -ge "$labstart" ] && [ "$i" -le "$labend" ]; then
      ch="${label:$((i-labstart)):1}"
      fg="$label_fg"
      printf -v cell '\033[48;5;%sm\033[38;5;%sm\033[1m%s\033[0m' "$bg" "$fg" "$ch"
    else
      printf -v cell '\033[48;5;%sm \033[0m' "$bg"
    fi
    out+="$cell"
  done
  printf '%s' "$out"
}

# ---- locate a writable place for the small usage cache -------------------
# Never hardcode an absolute path: prefer $HOME/.claude (Claude Code's own
# config dir), fall back to the directory this script itself lives in, and
# finally fall back to a temp dir. Any of these steps may fail (read-only
# filesystem, $HOME unset, etc.) without the script erroring out — caching
# is a nice-to-have, not a hard requirement, and a missing cache file is
# handled gracefully everywhere below.
script_source="${BASH_SOURCE[0]:-$0}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$script_source")" 2>/dev/null && pwd -P)"

# Config dir: a custom $CLAUDE_CONFIG_DIR wins (for account isolation), else
# Claude Code's default ~/.claude. The account file is $CLAUDE_CONFIG_DIR/.claude.json
# under a custom dir but $HOME/.claude.json by default. When a custom dir is in
# use we NEVER fall back to $HOME/.claude.json — that belongs to a different
# (main) account, and leaking its label into an isolated instance would show
# the wrong identity. Better to omit the label than show another account's.
config_dir="${CLAUDE_CONFIG_DIR:-${HOME:+$HOME/.claude}}"
claude_json=""
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  [ -r "$CLAUDE_CONFIG_DIR/.claude.json" ] && claude_json="$CLAUDE_CONFIG_DIR/.claude.json"
elif [ -n "${HOME:-}" ] && [ -r "$HOME/.claude.json" ]; then
  claude_json="$HOME/.claude.json"
fi

# ---- user options -------------------------------------------------------
# Every section is on by default. Two sources, both applied:
#  - the plugin's options (/plugin > Installed > Configure options, or
#    /config), saved by Claude Code under
#    pluginConfigs["claude-status-bar@<marketplace>"].options in settings.json:
#    false or "off" hides a section, "compact" shows a bar as plain text;
#  - an optional $config_dir/statusline.conf, for any install:
#      hide=weekly_reset,account
#      compact=five_hour,context
# Section names: five_hour, five_hour_reset, weekly, weekly_reset, model_name,
# context, account, project, git, effort, icons. Read fresh on every render,
# so changes show on the next refresh. Neither file is sourced or eval'd, and
# everything but letters and _ in a value becomes a separator.
hide="" compact="" opt_lines=""
settings_json="${config_dir:+$config_dir/settings.json}"
if [ -n "$settings_json" ] && [ -r "$settings_json" ]; then
  if command -v jq >/dev/null 2>&1; then
    opt_lines=$(jq -r '.pluginConfigs // {} | to_entries[]
      | select(.key | startswith("claude-status-bar@")) | .value.options // {}
      | to_entries[]
      | if .value == false or .value == "false" or .value == "off" then "hide \(.key)"
        elif .value == "compact" then "compact \(.key)" else empty end' "$settings_json" 2>/dev/null)
  elif find_python; then
    opt_lines=$("${py[@]}" -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8-sig") as fh:
        d = json.load(fh)
except Exception:
    d = {}
out = []
for k, v in ((d.get("pluginConfigs") if isinstance(d, dict) else None) or {}).items():
    if k.startswith("claude-status-bar@") and isinstance(v, dict):
        for o, val in (v.get("options") or {}).items():
            if val is False or val in ("false", "off"):
                out.append("hide %s\n" % o)
            elif val == "compact":
                out.append("compact %s\n" % o)
sys.stdout.buffer.write("".join(out).encode("utf-8"))
' "$settings_json" 2>/dev/null)
  fi
  while read -r _kind _key; do
    case "$_kind" in
      hide) hide="$hide $_key" ;;
      compact) compact="$compact $_key" ;;
    esac
  done <<< "$opt_lines"
fi
conf="${config_dir:+$config_dir/statusline.conf}"
if [ -n "$conf" ] && [ -r "$conf" ]; then
  hide="$hide $(grep -i -m1 '^[[:space:]]*hide[[:space:]]*=' "$conf" 2>/dev/null | cut -d= -f2-)"
  compact="$compact $(grep -i -m1 '^[[:space:]]*compact[[:space:]]*=' "$conf" 2>/dev/null | cut -d= -f2-)"
fi
hide=" $(printf '%s' "$hide" | tr 'A-Z' 'a-z' | tr -c 'a-z_' ' ') "
compact=" $(printf '%s' "$compact" | tr 'A-Z' 'a-z' | tr -c 'a-z_' ' ') "
hidden() { case "$hide" in *" $1 "*) return 0 ;; esac; return 1; }
is_compact() { case "$compact" in *" $1 "*) return 0 ;; esac; return 1; }

cache_dir=""
if [ -n "$config_dir" ]; then
  if [ -d "$config_dir" ] || mkdir -p "$config_dir" 2>/dev/null; then
    [ -w "$config_dir" ] && cache_dir="$config_dir"
  fi
fi
if [ -z "$cache_dir" ] && [ -n "$script_dir" ] && [ -w "$script_dir" ]; then
  cache_dir="$script_dir"
fi
if [ -n "$cache_dir" ]; then
  cache_base="$cache_dir/statusline-cache"
else
  # The temp dir is shared by every account, so key the file names by config
  # dir — otherwise one account's usage would show up in another's bar.
  cache_dir="${TMPDIR:-/tmp}"
  cache_key=$(printf '%s' "$config_dir" | cksum 2>/dev/null | cut -d' ' -f1)
  cache_base="$cache_dir/statusline-cache-${cache_key:-0}"
fi
# Rate limits belong to the account, so one file per config dir. Context usage
# belongs to a single session, so it lives in a per-session file under .d/ —
# a shared file would show one session's context in another session's bar.
cache_file="$cache_base.sh"
ctx_cache_dir="$cache_base.d"

# Read a single key out of a cache file, if it exists, without sourcing it
# (so a stray/foreign file can never inject arbitrary variables into this
# script's scope). Values are stored %q-quoted, so `eval` only ever expands
# a quoted string literal, never a variable name from the file.
cache_get() {
  local file="$1" key="$2" line val=""
  [ -r "$file" ] || { printf ''; return 0; }
  line=$(grep -m1 "^${key}=" "$file" 2>/dev/null)
  [ -z "$line" ] && { printf ''; return 0; }
  val="${line#*=}"
  eval "val=$val" 2>/dev/null
  printf '%s' "$val"
}

# Atomically write key=value pairs to a cache file, values %q-quoted.
cache_put() {
  local file="$1" tmp kv q
  shift
  tmp=$(mktemp "${file}.XXXXXX" 2>/dev/null) || return 0
  {
    for kv in "$@"; do
      printf -v q '%q' "${kv#*=}"
      printf '%s=%s\n' "${kv%%=*}" "$q"
    done
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# ---- gather data --------------------------------------------------------
# Prefer jq when available; fall back to python3; if neither is installed
# (or parsing fails), every field below simply stays empty and the
# defaults/cache fallbacks further down kick in instead of the script
# erroring out.

model="" dir="" five_pct="" five_reset="" week_pct="" week_reset=""
ctx_pct="" ctx_used="" ctx_size="" effort="" thinking="" style="" session_id=""

json_lines=""
if command -v jq >/dev/null 2>&1; then
  json_lines=$(printf '%s' "$input" | jq -r '
    (.model.display_name // "Model"),
    (.workspace.current_dir // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.context_window.used_percentage // ""),
    (.context_window.total_input_tokens // ""),
    (.context_window.context_window_size // ""),
    (.effort.level // "medium"),
    (if .thinking.enabled == true then "on" else "off" end),
    (.output_style.name // "default"),
    (.session_id // "")
  ' 2>/dev/null)
elif find_python; then
  # Read/write raw UTF-8 bytes: on Windows Python defaults to cp1252, which
  # crashes on non-ASCII payloads and prints CRLF line endings.
  json_lines=$(printf '%s' "$input" | "${py[@]}" -c '
import json, sys

try:
    d = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
except Exception:
    d = {}

def g(*path, default=""):
    v = d
    for k in path:
        if not isinstance(v, dict) or k not in v:
            return default
        v = v[k]
    return default if v is None else v

fields = [
    g("model", "display_name", default="Model"),
    g("workspace", "current_dir", default=""),
    g("rate_limits", "five_hour", "used_percentage", default=""),
    g("rate_limits", "five_hour", "resets_at", default=""),
    g("rate_limits", "seven_day", "used_percentage", default=""),
    g("rate_limits", "seven_day", "resets_at", default=""),
    g("context_window", "used_percentage", default=""),
    g("context_window", "total_input_tokens", default=""),
    g("context_window", "context_window_size", default=""),
    g("effort", "level", default="medium"),
    "on" if g("thinking", "enabled", default=False) is True else "off",
    g("output_style", "name", default="default"),
    g("session_id", default=""),
]
sys.stdout.buffer.write("".join("%s\n" % f for f in fields).encode("utf-8"))
' 2>/dev/null)
fi

if [ -n "$json_lines" ]; then
  # Read line-by-line instead of mapfile: macOS ships bash 3.2, which has no
  # mapfile builtin, and this script must run under /bin/bash there. Strip a
  # trailing CR: jq on Windows ends lines with CRLF, and "42\r" isn't a number.
  _fields=()
  while IFS= read -r _fline; do _fields+=("${_fline%$'\r'}"); done <<< "$json_lines"
  model="${_fields[0]:-}"
  dir="${_fields[1]:-}"
  five_pct="${_fields[2]:-}"
  five_reset="${_fields[3]:-}"
  week_pct="${_fields[4]:-}"
  week_reset="${_fields[5]:-}"
  ctx_pct="${_fields[6]:-}"
  ctx_used="${_fields[7]:-}"
  ctx_size="${_fields[8]:-}"
  effort="${_fields[9]:-}"
  thinking="${_fields[10]:-}"
  style="${_fields[11]:-}"
  session_id="${_fields[12]:-}"
fi

[ -z "$model" ] && model="Model"
[ -z "$dir" ] && dir="$PWD"
# Normalise Windows backslashes so basename finds the last path component.
project=$(basename "${dir//\\//}")

[ -z "$effort" ] && effort="medium"
[ -z "$thinking" ] && thinking="off"
[ -z "$style" ] && style="default"

# ---- usage cache: fall back to last known values, then persist -----------
# rate_limits is only sent after a session's first API response, and
# context_window's usage fields are null until messages have been
# exchanged, so a fresh session legitimately has nothing to show yet. Fall
# back to whatever was last cached (if anything) so the bars don't flash
# "n/a" on every render, then persist whatever we ended up with for next
# time. Works even if the cache file has never existed before.
#
# Values are restored as whole groups (a percentage with its reset time; the
# three context fields together), never field-by-field, so a live value is
# never paired with a stale cached one. A rate-limit window whose reset time
# has passed is dropped: Claude Code stops sending it at that point, and
# restoring it would show an expired usage figure as current.

now=$(date +%s 2>/dev/null)
is_num "$now" || now=0

# Take the newer of the payload's and the cache's value for one rate-limit
# window (five / week). Limits are per account, but a session's payload only
# reflects its own last API response, so usage from the account's other
# sessions arrives via the cache. Usage only rises within a window, so newer
# means a later reset, or the same reset with a higher percentage. No clock
# needed, and a stale session writing back can never roll the cache backwards.
# ponytail: assumes resets_at is stable within a window (it is, round epochs);
# compare with a tolerance if it ever starts jittering.
merge_window() {
  local name="$1" pct reset c_pct c_reset
  eval "pct=\$${name}_pct reset=\$${name}_reset"
  c_pct=$(cache_get "$cache_file" "${name}_pct")
  c_reset=$(cache_get "$cache_file" "${name}_reset")
  is_num "$c_pct" && is_num "$c_reset" || return 0
  [ "${c_reset%%.*}" -gt "$now" ] 2>/dev/null || return 0
  if is_num "$pct"; then
    is_num "$reset" || return 0
    [ "${c_reset%%.*}" -lt "${reset%%.*}" ] 2>/dev/null && return 0
    [ "${c_reset%%.*}" -eq "${reset%%.*}" ] 2>/dev/null && \
      [ "${c_pct%%.*}" -le "${pct%%.*}" ] 2>/dev/null && return 0
  fi
  eval "${name}_pct=\$c_pct ${name}_reset=\$c_reset"
}

merge_window five
merge_window week
{ is_num "$five_pct" || is_num "$week_pct"; } && cache_put "$cache_file" \
  "five_pct=$five_pct" "five_reset=$five_reset" \
  "week_pct=$week_pct" "week_reset=$week_reset"

# Context: per-session file, keyed by a sanitised session_id (so it can't
# escape the cache dir). No session_id means no context caching at all.
sid="${session_id//[^A-Za-z0-9_-]/}"
if [ -n "$sid" ]; then
  ctx_cache="$ctx_cache_dir/$sid.sh"
  if is_num "$ctx_pct" && is_num "$ctx_used" && is_num "$ctx_size"; then
    if [ ! -f "$ctx_cache" ]; then
      # New session: create the dir and prune files from long-gone sessions.
      mkdir -p "$ctx_cache_dir" 2>/dev/null
      find "$ctx_cache_dir" -type f -name '*.sh' -mtime +7 -delete 2>/dev/null
    fi
    cache_put "$ctx_cache" "ctx_pct=$ctx_pct" "ctx_used=$ctx_used" "ctx_size=$ctx_size"
  else
    c_pct=$(cache_get "$ctx_cache" ctx_pct)
    c_used=$(cache_get "$ctx_cache" ctx_used)
    c_size=$(cache_get "$ctx_cache" ctx_size)
    if is_num "$c_pct" && is_num "$c_used" && is_num "$c_size"; then
      ctx_pct="$c_pct" ctx_used="$c_used" ctx_size="$c_size"
    fi
  fi
fi

# ---- line 1: rate limits + model context usage --------------------------

# A usage figure for section $1: a bar, or for a section set to compact, its
# label as plain text in the bar's severity colour (grey when unknown).
# $2 is the integer percentage ("" when unknown), $3 the label.
bar() {
  local c=245
  if ! is_compact "$1"; then make_bar "${2:-0}" 12 "$3"; return; fi
  if is_num "$2"; then
    c=41
    [ "$2" -gt 50 ] 2>/dev/null && c=214
    [ "$2" -ge 85 ] 2>/dev/null && c=196
  fi
  printf '\033[1;38;5;%sm%s\033[0m' "$c" "$3"
}

# Hidden sections are skipped entirely, separators included.
line1=""
add1() { line1="${line1:+$line1 $(printf '\033[2m|\033[0m') }$1"; }

if ! hidden five_hour; then
  if is_num "$five_pct"; then
    five_int=$(printf '%.0f' "$five_pct")
    part=$(bar five_hour "$five_int" "${five_int}%")
  else
    part=$(bar five_hour "" "n/a")
  fi
  hidden five_hour_reset || part+=" $(fmt_time_of_day "$five_reset")"
  add1 "$part"
fi

if ! hidden weekly; then
  part=""
  hidden icons || part=$(printf '\033[2m🗓️\033[0m ')
  if is_num "$week_pct"; then
    week_int=$(printf '%.0f' "$week_pct")
    part+=$(bar weekly "$week_int" "${week_int}%")
  else
    part+=$(bar weekly "" "n/a")
  fi
  hidden weekly_reset || part+=" $(fmt_weekday_time "$week_reset")"
  add1 "$part"
fi

part=""
hidden model_name || part=$(printf '\033[1m%s\033[0m' "$model")
if ! hidden context; then
  if is_num "$ctx_pct" && is_num "$ctx_used" && is_num "$ctx_size"; then
    ctx_int=$(printf '%.0f' "$ctx_pct")
    ctx_bar=$(bar context "$ctx_int" "$(fmt_tokens "$ctx_used")/$(fmt_tokens "$ctx_size")")
  else
    ctx_bar=$(bar context "" "n/a")
  fi
  part="${part:+$part }$ctx_bar"
fi
[ -n "$part" ] && add1 "$part"

# ---- account / org label (from ~/.claude.json, not the stdin payload) ----
# The statusline JSON on stdin has no account/org field; that lives in
# $HOME/.claude.json under oauthAccount. Missing file/fields/tools all
# degrade to simply omitting the label — never hardcode an absolute path,
# always derive it from $HOME.

account_label=""
if ! hidden account && [ -n "$claude_json" ] && [ -r "$claude_json" ]; then
  org_name="" email_addr="" acct_lines=""
  if command -v jq >/dev/null 2>&1; then
    acct_lines=$(jq -r '(.oauthAccount.organizationName // ""), (.oauthAccount.emailAddress // "")' "$claude_json" 2>/dev/null)
  elif find_python; then
    acct_lines=$("${py[@]}" -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8-sig") as fh:
        d = json.load(fh)
except Exception:
    d = {}
oauth = d.get("oauthAccount") or {}
out = "%s\n%s\n" % (oauth.get("organizationName") or "", oauth.get("emailAddress") or "")
sys.stdout.buffer.write(out.encode("utf-8"))
' "$claude_json" 2>/dev/null)
  else
    # Last-resort grep/sed fallback when neither jq nor python3 is available.
    org_name=$(grep -o '"organizationName"[[:space:]]*:[[:space:]]*"[^"]*"' "$claude_json" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
    email_addr=$(grep -o '"emailAddress"[[:space:]]*:[[:space:]]*"[^"]*"' "$claude_json" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
    acct_lines="$org_name"$'\n'"$email_addr"
  fi

  if [ -n "$acct_lines" ]; then
    # bash-3.2-safe (no mapfile on macOS's /bin/bash).
    _acct_fields=()
    while IFS= read -r _aline; do _acct_fields+=("${_aline%$'\r'}"); done <<< "$acct_lines"
    org_name="${_acct_fields[0]:-}"
    email_addr="${_acct_fields[1]:-}"
  fi

  # U+FE0E VARIATION SELECTOR-15 forces text (monochrome) presentation for
  # the preceding icon codepoint, instead of the terminal's default colour
  # emoji glyph, so the icon inherits the orange ANSI colour below. Written
  # as the explicit UTF-8 byte sequence (EF B8 8E) to avoid any ambiguity
  # from an invisible literal character in the source.
  vs15=$'\357\270\216'
  org_icon="🏢${vs15} " user_icon="👤${vs15} "
  hidden icons && org_icon="" user_icon=""

  if [ -n "$org_name" ]; then
    # Org account: show the org name outright, building icon.
    account_label="${org_icon}$org_name"
  elif [ -n "$email_addr" ]; then
    # Individual account: never show the raw address — redact it to
    # "abc***@***.tld" (person icon). Anything that doesn't cleanly look
    # like local@domain.tld is left unset rather than guessed at.
    case "$email_addr" in
      *@*.*)
        local_part="${email_addr%%@*}"
        domain_part="${email_addr#*@}"
        tld="${domain_part##*.}"
        [ -n "$local_part" ] && [ -n "$tld" ] && \
          account_label="${user_icon}${local_part:0:3}***@***.${tld}"
        ;;
    esac
  fi
fi

# OS username, prefixed onto the project name as "user:project". Falls back
# to `id -un` if $USER isn't set; if neither yields anything, just the
# project name is shown (no dangling colon).
os_user="${USER:-}"
[ -z "$os_user" ] && os_user="$(id -un 2>/dev/null)"
if [ -n "$os_user" ]; then
  user_project="${os_user}:${project}"
else
  user_project="$project"
fi

# ---- line 2: account / user:project / git branch / clean-dirty indicator -

branch=""
dot=""
# Empty outside a repo and on a detached HEAD; the dot is only shown next to a
# branch, so there's no point paying for `git status` in either case.
! hidden git && command -v git >/dev/null 2>&1 && branch=$(git --no-optional-locks -C "$dir" branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
  # `git status` stats the whole worktree — 15s+ over sshfs/fuse mounts, which
  # blows Claude Code's statusLine timeout so nothing renders. Cap at 1s; if it
  # can't finish, skip the dot (branch still shows).
  # ponytail: 1s wall-clock cap, per-dir TTL cache if the dropped dot on slow mounts matters
  _st=$(mktemp)
  ( git --no-optional-locks -C "$dir" status --porcelain 2>/dev/null >"$_st" ) & _gp=$!
  # The watcher's fds go to /dev/null: killing it orphans its `sleep 1`, and if
  # that still held our stdout Claude Code would wait a full second for EOF on
  # every render — long enough that the next update cancels it mid-run.
  ( sleep 1; kill "$_gp" 2>/dev/null ) </dev/null >/dev/null 2>&1 & _kp=$!
  disown "$_kp" 2>/dev/null
  if wait "$_gp" 2>/dev/null; then
    kill "$_kp" 2>/dev/null
    if [ -s "$_st" ]; then
      dot=$(printf '\033[38;5;208m●\033[0m')
    else
      dot=$(printf '\033[32m●\033[0m')
    fi
  fi
  rm -f "$_st"
fi

# account · user:project ⎇ branch dot, each part optional.
line2=""
[ -n "$account_label" ] && line2=$(printf '\033[38;5;208m%s\033[0m' "$account_label")
hidden project || \
  line2="${line2:+$line2 $(printf '\033[2m·\033[0m') }$(printf '\033[34m%s\033[0m' "$user_project")"
if [ -n "$branch" ]; then
  hidden icons || line2="${line2:+$line2 }$(printf '\033[2m⎇\033[0m')"
  line2="${line2:+$line2 }$(printf '\033[33m%s\033[0m' "$branch")${dot:+ $dot}"
fi
[ -n "$line2" ] && ! hidden icons && line2="$(printf '\033[2m⤷\033[0m') $line2"

# ---- line 3: effort / thinking / output style ----------------------------
# One consistent colour (blue) across the entire line, rather than mixing
# a coloured label with greyed-out values.

line3=""
if ! hidden effort; then
  gear="⚙ "
  hidden icons && gear=""
  line3=$(printf '\033[38;5;111m%seffort:%s · think:%s · style:%s\033[0m' \
    "$gear" "$effort" "$thinking" "$style")
fi

# ---- output ---------------------------------------------------------------

# Skip lines whose every section is hidden rather than print blank rows.
for l in "$line1" "$line2" "$line3"; do
  [ -n "$l" ] && printf '%s\n' "$l"
done

