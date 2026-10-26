#!/usr/bin/env bash
# Detail renderers. ANSI output is generated directly from the theme palette
# (no subprocess) because this runs on every fzf cursor move.

: "${VEGABOND_ROOT:?}"

_render_width() {
  local cols=${FZF_PREVIEW_COLUMNS:-64}
  local width=$((cols - 4))
  ((width < 20)) && width=20
  ((width > 110)) && width=110
  printf '%s' "$width"
}

_render_usage_lines() {
  local usage=$1 max=$2 bar=$3 text=$4 muted=$5
  local -a lines=()
  local line count=0 total
  while IFS= read -r line; do
    lines+=("$line")
  done <<<"$usage"
  total=${#lines[@]}
  ((total == 0)) && return 0

  for line in "${lines[@]}"; do
    ((count >= max)) && break
    printf '  %s│%s %s%s%s\n' "$bar" "$ANSI_RESET" "$text" "$line" "$ANSI_RESET"
    count=$((count + 1))
  done
  if ((total > max)); then
    printf '  %s│%s %s… %d more line(s) · %sv%s opens the full view%s\n' \
      "$bar" "$ANSI_RESET" "$muted" "$((total - max))" "$muted" "$ANSI_RESET" "$ANSI_RESET"
  fi
}

render_ansi() {
  local id=$1
  [[ $id =~ ^[0-9]+$ ]] || return 1

  local json name description url usage tags width preview_lines updated
  json=$(db_get_tool_json "$id") || {
    printf '%s\n' "${ANSI_DIM}Tool not found${ANSI_RESET}"
    return 1
  }

  name=$(jq -r '.name' <<<"$json")
  description=$(jq -r '.description // ""' <<<"$json")
  url=$(jq -r '.url // ""' <<<"$json")
  usage=$(jq -r '.usage_md // ""' <<<"$json")
  tags=$(jq -r '.tags // ""' <<<"$json")
  updated=$(jq -r '.updated_at // ""' <<<"$json" | cut -c1-16 | tr 'T' ' ')
  width=$(_render_width)
  preview_lines=${FZF_PREVIEW_LINES:-24}
  ((preview_lines < 10)) && preview_lines=10
  local usage_max=$((preview_lines - 12))
  ((usage_max < 3)) && usage_max=3

  local accent muted fg bright reset border
  accent=$(ansi_fg "$TH_TEXT_ACCENT_RGB")
  muted=$(ansi_fg "$TH_MUTED_RGB")
  fg=$(ansi_fg "$TH_FG_RGB")
  bright=$(ansi_fg "$TH_BRIGHT_RGB")
  border=$(ansi_fg "$TH_BORDER_RGB")
  reset=$ANSI_RESET

  printf '%s%s%s%s\n' "$accent" "$ANSI_BOLD" "$name" "$reset"
  printf '%s%s%s\n' "$border" "$(printf '─%.0s' $(seq 1 "$width"))" "$reset"

  if [[ -n $tags ]]; then
    printf '%s\n' "$tags" | fold -s -w "$width" | while IFS= read -r line; do
      printf '%s%s%s\n' "$muted" "$line" "$reset"
    done
  fi
  if [[ -n $url ]]; then
    printf '%s\n' "$url" | fold -s -w "$width" | while IFS= read -r line; do
      printf '%s%s%s%s\n' "$(ansi_fg "$TH_ACCENT_RGB")" "$ANSI_UNDERLINE" "$line" "$reset"
    done
  fi

  if [[ -n $description ]]; then
    printf '\n'
    printf '%s\n' "$description" |
      fold -s -w "$width" |
      while IFS= read -r line; do
        printf '%s%s%s\n' "$fg" "$line" "$reset"
      done
  fi

  if [[ -n $usage ]]; then
    printf '\n%s%sUSAGE%s\n' "$muted" "$ANSI_BOLD" "$reset"
    _render_usage_lines "$usage" "$usage_max" "$border" "$fg" "$muted"
  fi

  if [[ -n $updated ]]; then
    printf '\n%sUpdated %s%s\n' "$muted" "$updated" "$reset"
  fi

  printf '\n%s%sj%s/k move · %s/%s search · %senter%s close · %sv%s full · %sq%s quit%s\n' \
    "$muted" "$ANSI_BOLD" "$reset" \
    "$ANSI_BOLD$accent" "$reset$muted" \
    "$ANSI_BOLD$accent" "$reset$muted" \
    "$ANSI_BOLD$accent" "$reset$muted" \
    "$ANSI_BOLD$accent" "$reset$muted" "$reset"
}

render_markdown() {
  local id=$1
  [[ $id =~ ^[0-9]+$ ]] || return 1

  local json name description url usage tags
  json=$(db_get_tool_json "$id") || return 1

  name=$(jq -r '.name' <<<"$json")
  description=$(jq -r '.description // ""' <<<"$json")
  url=$(jq -r '.url // ""' <<<"$json")
  usage=$(jq -r '.usage_md // ""' <<<"$json")
  tags=$(jq -r '.tags // ""' <<<"$json")

  printf '# %s\n\n' "$name"
  if [[ -n $tags ]]; then
    printf '**Tags:** %s\n\n' "$tags"
  fi
  if [[ -n $url ]]; then
    printf '**Reference:** %s\n\n' "$url"
  fi
  if [[ -n $description ]]; then
    printf '%s\n\n' "$description"
  fi
  if [[ -n $usage ]]; then
    printf '# Usage\n\n'
    # Indented block: safe even when the guide contains code fences.
    printf '%s\n' "$usage" | sed 's/^/    /'
    printf '\n'
  fi
  printf '\n*e* edit · *d* delete · *o* open reference · back in the list\n'
}

render_help_markdown() {
  cat <<'EOF'
# Vegabond

A personal cybersecurity tool knowledge base, themed by Omarchy.

# Keys

| Key | Action |
| --- | --- |
| `j` / `k` | Move down / up |
| `g` / `G` | First / last |
| `J` / `K` | Page down / up |
| `/` | Search (type to filter) |
| `Esc` | Leave search, close details, quit |
| `Enter` | Open the detail panel |
| `v` | Full detail view |
| `e` | Edit the selected tool |
| `a` | Add a tool |
| `d` | Delete the selected tool |
| `o` | Open the reference URL |
| `y` | Copy the reference URL |
| `Y` | Copy the usage guide |
| `q` | Quit |

# Command line

```
vegabond                      interactive browser
vegabond add                  add wizard
vegabond list --tag recon     plain list
vegabond show nmap            detail
vegabond search sql           search
vegabond tags                 tag manager
vegabond stats                counts and top tags
vegabond export --format md   markdown handbook
vegabond import file.json     bulk import
vegabond doctor               environment check
```
EOF
}
