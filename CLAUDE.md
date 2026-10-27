# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A custom three-line status line for Claude Code, written as a single portable Bash script. There is no build system, no dependencies to install, and no test suite — it's shell scripts plus a plugin manifest.

- `statusline-command.sh` — reads the statusline JSON payload from stdin and prints three ANSI-coloured lines to stdout. This is the whole product; everything else just delivers it.
- `install.sh` / `uninstall.sh` — manual (non-plugin) install: copies the script into `~/.claude` (or `$CLAUDE_CONFIG_DIR`) and wires/unwires `statusLine.command` in `settings.json`.
- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — makes the repo installable via `/plugin`. The repo is its own single-plugin marketplace (`source: "./"`).
- `hooks/hooks.json` + `hooks/setup.sh` — the plugin's delivery mechanism (see below).

### Why the plugin needs a hook (non-obvious platform constraints)

Three hard limits force the design, verified against the plugin docs:
1. A plugin **cannot** declare a `statusLine` (only `agent`/`subagentStatusLine` are honoured in a plugin's settings).
2. `${CLAUDE_PLUGIN_ROOT}` is **not** expanded inside `statusLine` commands (only in hook/monitor/MCP/LSP commands and skill/agent content).
3. The plugin's install path is a versioned cache dir that **changes on every update**; `${CLAUDE_PLUGIN_DATA}` is the only stable per-plugin path.

So `hooks/setup.sh` runs on `SessionStart`: it copies the script into `$CLAUDE_PLUGIN_DATA` (stable) and writes that **literal absolute path** into the user's `settings.json` — **only if no `statusLine` already exists**, so a user's own status line is never clobbered. It must never fail a session start; every step degrades quietly and it always `exit 0`s. Prefers `python3`, falls back to `jq`.

## Commands

```bash
# Install (copies script to ~/.claude and updates settings.json)
./install.sh

# Test a render without installing — feed it a sample payload on stdin
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$PWD"'"},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1736200000},"seven_day":{"used_percentage":70,"resets_at":1736700000}},"context_window":{"used_percentage":30,"total_input_tokens":60000,"context_window_size":200000},"effort":{"level":"high"},"thinking":{"enabled":true},"output_style":{"name":"default"}}' | bash statusline-command.sh
```

The input schema (stdin JSON) is the contract with Claude Code: `model.display_name`, `workspace.current_dir`, `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`, `context_window.{used_percentage,total_input_tokens,context_window_size}`, `effort.level`, `thinking.enabled`, `output_style.name`.

## Output layout

- **Line 1**: 5-hour rate-limit bar + reset time · weekly rate-limit bar + reset time · model name + context-usage bar.
- **Line 2**: account/org label (redacted) · `user:project` · git branch · clean/dirty dot.
- **Line 3**: effort / thinking / output style.

Any section can be hidden via the plugin's `userConfig` toggles (`show_<name>` in `plugin.json`; the script reads them straight from `pluginConfigs` in `settings.json`, because option values only reach hooks, not the statusLine command) or via `hide=` in `$config_dir/statusline.conf` (names in README). A new section needs both a `show_` option and a `hidden` check. Use `hidden <name>` when adding a section, and drop its separator too. The file is read with `grep`, never sourced or eval'd, the same as the cache.

## Design constraints (these are load-bearing — preserve them when editing)

- **Never error out, never hardcode absolute paths.** Every external dependency (`jq`, `python3`, `git`, the cache file) is optional; a missing tool or field must degrade to a placeholder (`n/a`, `--`) or omitted section, not a failure. Paths are derived from `$HOME`/`$0`, never hardcoded.
- **Two JSON parsers.** Data gathering prefers `jq`, falls back to `python3`, and (for the account label only) has a final `grep`/`sed` fallback. Any change to parsed fields must be mirrored across all paths.
- **Usage cache**: rate-limit and context fields are null on a fresh session, so last-known values are cached and restored to avoid flashing `n/a`. Rate limits are per account: `statusline-cache.sh` in the config dir, shared by all of that account's sessions. Each window is merged, not overwritten: later `resets_at` wins, same reset → higher pct wins (usage only rises within a window). That's how one session shows another's usage, and why an idle session's stale payload can't roll the cache back. Context is per session: `statusline-cache.d/<session_id>.sh`, pruned after 7 days. A shared file would show one session's context in another session. Values are restored as whole groups (pct+reset, or all three ctx fields), never one field at a time. Windows whose `resets_at` has passed are dropped. The cache is read by grepping one key at a time and `eval`-ing a `%q`-quoted value — never `source`d — so a foreign file can't inject variables. Keep it that way.
- **Config dir is passed as `$1`**, not a `CLAUDE_CONFIG_DIR=... bash` prefix: Windows may run statusLine commands through PowerShell, which can't parse that prefix.
- **Windows (Git Bash)**: jq/Python emit CRLF, so parsed lines are stripped of `\r`. Python reads and writes raw UTF-8 bytes, because the default there is cp1252. Python is probed by actually running it, since `python3` may be the Store stub. Command paths are written with forward slashes (`cygpath -m`).
- **`setup.sh` never rewrites a `settings.json` it can't parse** — that would wipe the user's other settings.
- **`make_bar`** builds the gradient bar cell-by-cell (never indexes the ANSI-coloured string by length). Fill colour follows severity tiers (green ≤50%, yellow 50–85%, red ≥85%); the label's fg colour is chosen once per bar, not per character, so digits don't split colours across cell boundaries.
- **Account label is privacy-sensitive**: org names show verbatim, but individual emails are always redacted to `abc***@***.tld`. Don't print raw addresses.
