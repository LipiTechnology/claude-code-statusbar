# Claude Status Bar

A three-line status bar for Claude Code:

1. 5-hour rate-limit bar + reset time · weekly rate-limit bar + reset time · model + context-usage bar
2. account/org · `user:project` · git branch · clean/dirty dot
3. effort / thinking / output style

## Install as a plugin (recommended)

```
/plugin marketplace add LipiTechnology/claude-code-statusbar
/plugin install claude-status-bar@claude-status-bar
```

Restart Claude Code. A `SessionStart` hook copies the script into the plugin's
data dir and adds a `statusLine` entry to your `settings.json` — **only if you
don't already have one**, so a custom status line is never overwritten. Restart
once more and the bar appears.

To remove: `/plugin uninstall claude-status-bar@claude-status-bar`, then delete
the `statusLine` key from `~/.claude/settings.json`.

## Install manually (no plugin)

```
./install.sh     # copies to ~/.claude and wires settings.json
./uninstall.sh   # reverses it
```

## Customize

**Plugin installs:** `/plugin` → **Installed** → Claude Status Bar →
**Configure options** (the same toggles also appear in `/config`). Changes
show within 30 seconds, no restart.

**Any install:** create `statusline.conf` in your Claude config dir (`~/.claude`, or
`$CLAUDE_CONFIG_DIR`) with one line listing the parts to hide:

```
hide=weekly,reset,icons
```

| Name | Hides |
|------|-------|
| `five_hour` | 5-hour usage bar |
| `weekly` | weekly usage bar |
| `model` | model name + context bar |
| `reset` | reset times |
| `bars` | the bars themselves (shows plain `42%` instead) |
| `icons` | all icons |
| `account` | account / org label |
| `git` | branch + clean/dirty dot |
| `effort` | the effort / thinking / style line |

Both are honoured together: a part hidden in either place stays hidden.

## Requirements

`git` for the branch/dot line; `jq` **or** `python3` for parsing. All are
optional — missing tools degrade to placeholders, never an error.

On Windows, [Git for Windows](https://gitforwindows.org/) (Git Bash) is
required: the status bar is a Bash script and won't run without `bash`.
