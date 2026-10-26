#!/usr/bin/env bash
# Shared UI helpers. Gum is used whenever it is available and the session is
# interactive; plain text is the fallback for scripts and tests.

have() { command -v "$1" >/dev/null 2>&1; }
is_tty() { [[ -t 0 && -t 1 ]]; }

ui_error() {
  if is_tty && have gum; then
    gum log --level error -- "$*" >&2
  else
    printf 'error: %s\n' "$*" >&2
  fi
}

ui_warn() {
  if is_tty && have gum; then
    gum log --level warn -- "$*" >&2
  else
    printf 'warning: %s\n' "$*" >&2
  fi
}

ui_info() {
  if is_tty && have gum; then
    gum log --level info -- "$*"
  else
    printf '%s\n' "$*"
  fi
}

ui_success() {
  if is_tty && have gum; then
    gum log --level info -- "$*"
  else
    printf '%s\n' "$*"
  fi
}

ui_title() {
  local text=$1 subtitle=${2:-}
  if is_tty && have gum; then
    local -a accent=() muted=()
    [[ -n ${TH_TEXT_ACCENT:-} ]] && accent=(--foreground "$TH_TEXT_ACCENT")
    [[ -n ${TH_MUTED:-} ]] && muted=(--foreground "$TH_MUTED")
    gum style "${accent[@]}" --bold "$text"
    [[ -n $subtitle ]] && gum style "${muted[@]}" --italic "$subtitle"
  else
    printf '%s\n' "$text"
    [[ -n $subtitle ]] && printf '%s\n' "$subtitle"
  fi
}

trim_text() {
  local s=${1:-}
  while [[ $s == *$'\n' || $s == *$'\r' ]]; do
    s=${s%$'\n'}
    s=${s%$'\r'}
  done
  while [[ $s == $'\n'* || $s == $'\r'* ]]; do
    s=${s#$'\n'}
    s=${s#$'\r'}
  done
  printf '%s' "$s"
}

trim_line() {
  local s=${1:-}
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

copy_to_clipboard() {
  local text=$1
  if have wl-copy; then
    printf '%s' "$text" | wl-copy
  elif have xclip; then
    printf '%s' "$text" | xclip -selection clipboard
  elif have pbcopy; then
    printf '%s' "$text" | pbcopy
  else
    return 1
  fi
}

open_url() {
  local url=$1
  [[ -n $url ]] || return 1
  if have omarchy-launch-browser; then
    omarchy-launch-browser "$url" >/dev/null 2>&1 &
  elif have xdg-open; then
    xdg-open "$url" >/dev/null 2>&1 &
  else
    return 1
  fi
}

# Column rows for tag listings and stats.
ui_tags_header() {
  if is_tty; then
    printf '  %s%-26s%s %s%5s%s\n' \
      "$(ansi_fg "${TH_MUTED_RGB:-}")" "TAG" "$ANSI_RESET" \
      "$(ansi_fg "${TH_MUTED_RGB:-}")" "TOOLS" "$ANSI_RESET"
  else
    printf '  %-26s %5s\n' "TAG" "TOOLS"
  fi
}

ui_tag_row() {
  if is_tty; then
    printf '  %s%-26s%s %s%5s%s\n' \
      "$(ansi_fg "${TH_FG_RGB:-}")" "$1" "$ANSI_RESET" \
      "$(ansi_fg "${TH_MUTED_RGB:-}")" "$2" "$ANSI_RESET"
  else
    printf '  %-26s %5s\n' "$1" "$2"
  fi
}

ui_kv() {
  if is_tty; then
    printf '%s%-14s%s %s%s%s\n' \
      "$(ansi_fg "${TH_MUTED_RGB:-}")" "$1" "$ANSI_RESET" \
      "$(ansi_fg "${TH_FG_RGB:-}")" "$2" "$ANSI_RESET"
  else
    printf '%-14s %s\n' "$1" "$2"
  fi
}

# Keybind hints: accent + bold for keys, muted for their meaning.
fzf_key() {
  printf '%s%s%s%s' "$(ansi_fg "${TH_TEXT_ACCENT_RGB:-}")" "$ANSI_BOLD" "$1" "$ANSI_RESET"
}

fzf_dim() {
  printf '%s%s%s' "$(ansi_fg "${TH_MUTED_RGB:-}")" "$1" "$ANSI_RESET"
}

# Gum renders its UI through the terminal; never redirect its stderr.
gum_choose() { gum choose "$@"; }
gum_filter() { gum filter "$@"; }
gum_file()   { gum file "$@"; }

require_gum() {
  have gum || { ui_error "gum is required for the interactive UI."; return 1; }
}

require_fzf() {
  have fzf || { ui_error "fzf is required for the browser."; return 1; }
}

require_tty() {
  is_tty || { ui_error "This command needs an interactive terminal."; return 1; }
}
