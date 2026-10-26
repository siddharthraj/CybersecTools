# Vegabond

A personal cybersecurity tool knowledge base for Omarchy, rendered with
[gum](https://github.com/charmbracelet/gum) and navigated with **fzf** using
Vim-style modal keys. Everything lives in one local SQLite database.

Omarchy is not required, but when it is present the app follows the active
theme automatically: no hardcoded colors, no restart of the app when the theme
changes, and the same rounded, muted, single-accent look as the rest of the
desktop.

## What it stores

| Field | Notes |
| --- | --- |
| Name | Unique, case-insensitive |
| Description | Short summary, line breaks allowed |
| Tags | Many-to-many, normalized lowercase slugs (`active-directory`, `recon`) |
| Reference URL | Official site, docs, or repository |
| Usage guide | Optional markdown (commands, flags, notes) |

Plus `created_at` / `updated_at` timestamps. The schema is deliberately small;
the import/export format is plain JSON so the data stays portable.

## Requirements

- `gum` 2.x
- `sqlite3` 3.38+ (JSON functions, `readfile()`)
- `jq` 1.6+
- `fzf` 0.59+ (modal keys use `--no-input` / `FZF_INPUT_STATE`)
- Optional: `wl-copy` (copy actions), `omarchy-launch-browser` or `xdg-open`

On Omarchy:

```bash
omarchy pkg add gum sqlite jq fzf
```

## Install

```bash
./install.sh
```

This symlinks `bin/vegabond` into `~/.local/bin`. Run it as:

```bash
vegabond
```

The script keeps Omarchy command metadata at the top for compatibility, but it
is installed and used as a normal standalone command.

The database is **repo-local**:

```
data/tools.db          # SQLite, WAL mode, gitignored
data/backups/          # reserved for schema migrations
data/exports/          # produced by the interactive Export action
```

Override with `VEGABOND_DB=/path/to/tools.db` for tests or a portable copy.

## Usage

```bash
vegabond                        # interactive browser
vegabond menu                   # gum menu: browse, add, tags, stats, export, import, doctor

vegabond add                    # interactive wizard
vegabond add --name Nmap --description "Network mapper" \
  --tags "recon,network,linux" --url https://nmap.org \
  --usage "nmap -sV -p- 10.0.0.1"

vegabond edit nmap              # interactive field picker
vegabond edit nmap --tags "recon,network" --url https://nmap.org/book/
vegabond rm nmap --yes          # scripts must confirm with --yes

vegabond list                   # id<TAB>name<TAB>tags
vegabond list --tag recon --json
vegabond show nmap [--json]
vegabond search "sql injection" [--tag web] [--json]

vegabond tags                   # tag + count
vegabond tags rename OLD NEW
vegabond tags merge SRC DST
vegabond tags rm TAG
vegabond tags menu              # interactive tag manager

vegabond stats [--json]
vegabond export --format json|csv|md [--out FILE]
vegabond import file.json [--on-conflict skip|update|abort]
vegabond seed [--force]         # load the ~70-tool starter catalog
vegabond doctor                 # dependency, theme, schema and DB check
```

## Interactive keys

The list starts in normal mode. `/` opens the search field; `Esc` returns to
normal mode, and the detail panel is a separate toggle.

| Key | Action |
| --- | --- |
| `j` / `k` | Move down / up |
| `g` / `G` | First / last |
| `J` / `K` | Page down / up |
| `/` | Search (type to filter) |
| `Enter` | Open/close the detail panel |
| `Esc` | Leave search, close details, quit |
| `v` | Full detail view in `gum pager` |
| `e` | Edit the selected tool |
| `a` | Add a tool |
| `d` | Delete (asks first) |
| `o` | Open the reference URL |
| `y` | Copy the reference URL |
| `Y` | Copy the usage guide |
| `?` | Keymap help |
| `q` | Quit |

The detail panel is a rounded, theme-colored fzf preview pane that follows the
cursor. fzf's modal keys are implemented with `--no-input` plus
`unbind`/`rebind`, so letters still type normally while the search field is
open.

## Omarchy theming

On launch the app reads, in order:

1. `~/.local/state/omarchy/current/theme/gum_env.lua` — every `GUM_*` style
   variable, applied fresh (inherited variables can be stale after a theme
   switch inside a running terminal).
2. `~/.local/state/omarchy/current/theme/colors.toml` — semantic roles:
   `accent`, `text_accent`, `foreground`, `readable_muted` (falling back to
   `muted`), `selection`, `border`, `mode`.
3. `~/.local/state/omarchy/current/theme.name` — shown in `doctor` / stats.

Those roles drive the fzf palette, the ANSI detail renderer, and `gum style`
chrome. `mode = "light"` switches `gum format` to the light glamour theme.
Themes are applied at launch; relaunch the browser after `omarchy theme set`.

Fallbacks: if `gum_env.lua` is missing the key gum variables are derived from
`colors.toml`; with no Omarchy theme at all the app stays usable with gum/fzf
defaults. `VEGABOND_NO_THEME=1` disables theming entirely.

## Import format

```json
[
  {
    "name": "Nmap",
    "description": "Network discovery and port scanning.",
    "tags": ["recon", "network", "linux"],
    "url": "https://nmap.org/",
    "usage": "nmap -sV -p- 10.0.0.1"
  }
]
```

A top-level `{ "tools": [...] }` object is also accepted. `usage` and
`usage_md` are interchangeable; `tags` may be an array or a comma-separated
string. Names are trimmed, tags are lowercased and hyphenated, and the whole
import runs in one transaction. Conflicting names are skipped by default;
`--on-conflict update` refreshes existing rows, `abort` refuses before writing.

## Layout

```
bin/vegabond      entrypoint, metadata, command dispatch
lib/theme.sh           Omarchy palette + gum env + fzf colors
lib/db.sh              schema, safe JSON-backed writes, import/export
lib/ui.sh              gum/plain UI helpers
lib/render.sh          ANSI preview + markdown detail rendering
lib/forms.sh           gum add/edit/delete/tag flows
lib/browser.sh         fzf modal keymap and detail panel
lib/fzf-mode.sh        Enter/Esc state transitions
share/schema.sql       v1 schema (idempotent)
share/seed.json        curated starter catalog
tests/run.sh           non-interactive test suite
```

All user values reach SQL through a temporary JSON file and
`json_extract(readfile(...))`; read-only lookups use quoted literals. Writes run
in `BEGIN IMMEDIATE` transactions with WAL and a busy timeout.

## Testing

```bash
./tests/run.sh
```

52 assertions cover CRUD, tag normalization and merging, search across
name/description/usage/tags, duplicate handling, import/export round-trips, the
seed catalog, and non-interactive safety. The suite uses a throwaway database
and never opens a TUI.

## Known limits

- Single reference URL per tool (the schema is ready for a `tool_urls` table).
- No FTS5 index yet; `LIKE` with an `id`/name index is instant at this scale.
- The interactive browser needs a terminal and fzf; all CLI subcommands work
  without one.
- `gum format` uses glamour's built-in dark/light themes, not a generated
  palette-matched style (planned polish).
