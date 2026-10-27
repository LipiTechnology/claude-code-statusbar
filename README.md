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
**Configure options** (the same options also appear in `/config`). Changes
show within 30 seconds, no restart.

| Option | Values |
|--------|--------|
| 5-hour usage | `bar` · `compact` (just `42%`) · `off` |
| 5-hour reset time | on / off |
| Weekly usage | `bar` · `compact` · `off` |
| Weekly reset time | on / off |
| Model name | on / off |
| Model context | `bar` · `compact` (just `120k/200k`) · `off` |
| Account / org | on / off |
| User and project | on / off |
| Git branch and dirty status | on / off |
| Effort line | on / off |
| Icons | on / off |

Compact values keep the bar's colour: green, then yellow above 50%, red from 85%.

**Any install:** create `statusline.conf` in your Claude config dir
(`~/.claude`, or `$CLAUDE_CONFIG_DIR`):

```
hide=weekly_reset,account
compact=five_hour,context
```

Names: `five_hour`, `five_hour_reset`, `weekly`, `weekly_reset`,
`model_name`, `context`, `account`, `project`, `git`, `effort`, `icons`.
Both are honoured together: a part hidden in either place stays hidden.

## Requirements

`git` for the branch/dot line; `jq` **or** `python3` for parsing. All are
optional — missing tools degrade to placeholders, never an error.

On Windows, [Git for Windows](https://gitforwindows.org/) (Git Bash) is
required: the status bar is a Bash script and won't run without `bash`.
