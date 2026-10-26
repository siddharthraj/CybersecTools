#!/usr/bin/env bash
# Omarchy-aware theme bootstrap.
#
# Reads the live theme (not the inherited, possibly stale environment) so the
# app follows `omarchy theme set` on its next launch.
#
# Exports:
#   TH_*        semantic roles (hex + "r;g;b" for ANSI truecolor)
#   GUM_*       every style variable Omarchy generates for gum
#   FZF_THEME_OPTS  fzf --color options, derived from the same palette
#
# Fallbacks: missing gum_env.lua -> derive the key gum vars from colors.toml;
# no Omarchy theme at all -> plain output and gum/fzf defaults.

_theme_state_dir() {
  printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current"
}

_toml_get() {
  local key=$1 file=$2
  [[ -f $file ]] || return 0
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p" "$file" | head -n 1
}

_hex_to_rgb() {
  local hex=${1#\#}
  if [[ $hex =~ ^[0-9a-fA-F]{3}$ ]]; then
    hex="${hex:0:1}${hex:0:1}${hex:1:1}${hex:1:1}${hex:2:1}${hex:2:1}"
  fi
  [[ $hex =~ ^[0-9a-fA-F]{6}$ ]] || return 0
  printf '%d;%d;%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

_export_gum_env() {
  local file=$1 key value
  [[ -f $file ]] || return 1
  while IFS='=' read -r key value; do
    [[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
    export "$key=$value"
  done < <(sed -n 's/^hl\.env("\([^"]*\)", "\([^"]*\)")$/\1=\2/p' "$file")
}

_fallback_gum_env() {
  # Only used when gum_env.lua is absent (older/custom theme).
  export FOREGROUND="${TH_FG:-}" BACKGROUND="${TH_BG:-}"
  export BORDER_FOREGROUND="${TH_ACCENT:-}" BORDER_BACKGROUND="${TH_BG:-}"

  export GUM_CONFIRM_PROMPT_FOREGROUND="${TH_ACCENT:-}"
  export GUM_CONFIRM_SELECTED_FOREGROUND="${TH_BRIGHT:-}" GUM_CONFIRM_SELECTED_BACKGROUND="${TH_SEL_BG:-}"
  export GUM_CONFIRM_UNSELECTED_FOREGROUND="${TH_FG:-}" GUM_CONFIRM_UNSELECTED_BACKGROUND="${TH_BG:-}"

  export GUM_INPUT_PROMPT_FOREGROUND="${TH_ACCENT:-}"
  export GUM_INPUT_PLACEHOLDER_FOREGROUND="${TH_MUTED:-}"
  export GUM_INPUT_CURSOR_FOREGROUND="${TH_BRIGHT:-}"
  export GUM_INPUT_HEADER_FOREGROUND="${TH_FG:-}"

  export GUM_CHOOSE_CURSOR_FOREGROUND="${TH_ACCENT:-}"
  export GUM_CHOOSE_HEADER_FOREGROUND="${TH_FG:-}"
  export GUM_CHOOSE_ITEM_FOREGROUND="${TH_FG:-}"
  export GUM_CHOOSE_SELECTED_FOREGROUND="${TH_BRIGHT:-}" GUM_CHOOSE_SELECTED_BACKGROUND="${TH_SEL_BG:-}"

  export GUM_FILTER_PROMPT_FOREGROUND="${TH_ACCENT:-}"
  export GUM_FILTER_TEXT_FOREGROUND="${TH_FG:-}"
  export GUM_FILTER_MATCH_FOREGROUND="${TH_TEXT_ACCENT:-}"
  export GUM_FILTER_CURSOR_TEXT_FOREGROUND="${TH_BRIGHT:-}"
  export GUM_FILTER_HEADER_FOREGROUND="${TH_FG:-}"
  export GUM_FILTER_PLACEHOLDER_FOREGROUND="${TH_MUTED:-}"
  export GUM_FILTER_INDICATOR_FOREGROUND="${TH_ACCENT:-}"
  export GUM_FILTER_SELECTED_PREFIX_FOREGROUND="${TH_BRIGHT:-}" GUM_FILTER_SELECTED_PREFIX_BACKGROUND="${TH_SEL_BG:-}"
  export GUM_FILTER_UNSELECTED_PREFIX_FOREGROUND="${TH_MUTED:-}"

  export GUM_TABLE_HEADER_FOREGROUND="${TH_FG:-}"
  export GUM_TABLE_CELL_FOREGROUND="${TH_FG:-}"
  export GUM_TABLE_BORDER_FOREGROUND="${TH_BORDER:-}"
  export GUM_TABLE_SELECTED_FOREGROUND="${TH_BRIGHT:-}" GUM_TABLE_SELECTED_BACKGROUND="${TH_SEL_BG:-}"

  export GUM_PAGER_FOREGROUND="${TH_FG:-}" GUM_PAGER_BACKGROUND="${TH_BG:-}"
  export GUM_PAGER_LINE_NUMBER_FOREGROUND="${TH_MUTED:-}"
  export GUM_PAGER_MATCH_FOREGROUND="${TH_TEXT_ACCENT:-}"
  export GUM_PAGER_MATCH_HIGH_FOREGROUND="${TH_TEXT_ACCENT:-}"
  export GUM_PAGER_HELP_FOREGROUND="${TH_MUTED:-}"

  export GUM_WRITE_BASE_FOREGROUND="${TH_FG:-}"
  export GUM_WRITE_CURSOR_LINE_FOREGROUND="${TH_FG:-}" GUM_WRITE_CURSOR_LINE_BACKGROUND="${TH_SEL_BG:-}"
  export GUM_WRITE_CURSOR_LINE_NUMBER_FOREGROUND="${TH_MUTED:-}"
  export GUM_WRITE_CURSOR_FOREGROUND="${TH_BRIGHT:-}"
  export GUM_WRITE_LINE_NUMBER_FOREGROUND="${TH_MUTED:-}"
  export GUM_WRITE_HEADER_FOREGROUND="${TH_FG:-}"
  export GUM_WRITE_PLACEHOLDER_FOREGROUND="${TH_MUTED:-}"
  export GUM_WRITE_PROMPT_FOREGROUND="${TH_FG:-}"

  export GUM_SPIN_SPINNER_FOREGROUND="${TH_ACCENT:-}"
  export GUM_SPIN_TITLE_FOREGROUND="${TH_FG:-}"

  export GUM_LOG_LEVEL_FOREGROUND="${TH_ACCENT:-}"
  export GUM_LOG_TIME_FOREGROUND="${TH_MUTED:-}"
  export GUM_LOG_PREFIX_FOREGROUND="${TH_FG:-}"
  export GUM_LOG_MESSAGE_FOREGROUND="${TH_FG:-}"
  export GUM_LOG_KEY_FOREGROUND="${TH_FG:-}"
  export GUM_LOG_VALUE_FOREGROUND="${TH_FG:-}"
  export GUM_LOG_SEPARATOR_FOREGROUND="${TH_MUTED:-}"
}

load_theme() {
  FZF_THEME_OPTS=()
  if [[ -n ${VEGABOND_NO_THEME:-} ]]; then
    TH_NAME="none"
    TH_MODE="dark"
    TH_ACCENT="" TH_FG="" TH_BG="" TH_SEL_BG="" TH_BRIGHT="" TH_MUTED=""
    TH_BORDER="" TH_TEXT_ACCENT=""
    TH_ACCENT_RGB="" TH_FG_RGB="" TH_BG_RGB="" TH_SEL_BG_RGB="" TH_BRIGHT_RGB=""
    TH_MUTED_RGB="" TH_BORDER_RGB="" TH_TEXT_ACCENT_RGB=""
    export TH_NAME TH_MODE TH_ACCENT TH_FG TH_BG TH_SEL_BG TH_BRIGHT TH_MUTED
    export TH_BORDER TH_TEXT_ACCENT TH_ACCENT_RGB TH_FG_RGB TH_BG_RGB
    export TH_SEL_BG_RGB TH_BRIGHT_RGB TH_MUTED_RGB TH_BORDER_RGB TH_TEXT_ACCENT_RGB
    export VEGABOND_THEME_LOADED=1
    return 0
  fi

  local state theme_dir colors gum_env
  state=$(_theme_state_dir)
  theme_dir="$state/theme"
  colors="$theme_dir/colors.toml"
  gum_env="$theme_dir/gum_env.lua"

  TH_NAME=$(cat "$state/theme.name" 2>/dev/null || printf 'unknown')
  TH_MODE=$(_toml_get mode "$colors")
  TH_MODE=${TH_MODE:-dark}

  TH_ACCENT=$(_toml_get accent "$colors")
  TH_FG=$(_toml_get foreground "$colors")
  TH_BG=$(_toml_get background "$colors")
  # Omarchy's own fzf styling keeps the selected row on the authored
  # "selection" fill, not the loud terminal selection_background.
  TH_SEL_BG=$(_toml_get selection "$colors")
  TH_SEL_BG=${TH_SEL_BG:-$(_toml_get selection_background "$colors")}
  TH_SEL_BG=${TH_SEL_BG:-$TH_BG}
  TH_BRIGHT=$(_toml_get bright_foreground "$colors")
  TH_MUTED=$(_toml_get readable_muted "$colors")
  TH_MUTED=${TH_MUTED:-$(_toml_get muted "$colors")}
  TH_BORDER=$(_toml_get border "$colors")
  TH_BORDER=${TH_BORDER:-$TH_MUTED}
  TH_TEXT_ACCENT=$(_toml_get text_accent "$colors")
  TH_TEXT_ACCENT=${TH_TEXT_ACCENT:-$TH_ACCENT}

  TH_ACCENT_RGB=$(_hex_to_rgb "$TH_ACCENT")
  TH_FG_RGB=$(_hex_to_rgb "$TH_FG")
  TH_BG_RGB=$(_hex_to_rgb "$TH_BG")
  TH_SEL_BG_RGB=$(_hex_to_rgb "$TH_SEL_BG")
  TH_BRIGHT_RGB=$(_hex_to_rgb "$TH_BRIGHT")
  TH_MUTED_RGB=$(_hex_to_rgb "$TH_MUTED")
  TH_BORDER_RGB=$(_hex_to_rgb "$TH_BORDER")
  TH_TEXT_ACCENT_RGB=$(_hex_to_rgb "$TH_TEXT_ACCENT")

  export TH_NAME TH_MODE
  export TH_ACCENT TH_FG TH_BG TH_SEL_BG TH_BRIGHT TH_MUTED TH_BORDER TH_TEXT_ACCENT
  export TH_ACCENT_RGB TH_FG_RGB TH_BG_RGB TH_SEL_BG_RGB TH_BRIGHT_RGB TH_MUTED_RGB
  export TH_BORDER_RGB TH_TEXT_ACCENT_RGB

  if ! _export_gum_env "$gum_env"; then
    _fallback_gum_env
  fi

  FZF_THEME_OPTS=()
  if [[ -n $TH_BG ]]; then
    local spec="bg:$TH_BG,bg+:$TH_SEL_BG,fg:$TH_FG,fg+:$TH_BRIGHT"
    spec+=",hl:$TH_TEXT_ACCENT,hl+:$TH_TEXT_ACCENT,prompt:$TH_TEXT_ACCENT"
    spec+=",pointer:$TH_ACCENT,marker:$TH_ACCENT,spinner:$TH_ACCENT"
    spec+=",header:$TH_MUTED,info:$TH_MUTED,border:$TH_BORDER"
    spec+=",scrollbar:$TH_MUTED,gutter:$TH_BG,separator:$TH_BORDER"
    spec+=",header-border:$TH_BORDER,query:$TH_BRIGHT,ghost:$TH_MUTED"
    spec+=",preview-bg:$TH_BG,preview-fg:$TH_FG,preview-label:$TH_TEXT_ACCENT"
    FZF_THEME_OPTS=(--color "$spec")
  fi

  export VEGABOND_THEME_LOADED=1
}

# The markdown renderer used by gum format only ships fixed glamour themes.
gum_markdown_theme() {
  case ${TH_MODE:-dark} in
    light) printf 'light' ;;
    *)     printf 'dark' ;;
  esac
}

# ANSI helpers for the preview renderer (fast path: no external process).
ansi_fg() { [[ -n $1 ]] && printf '\033[38;2;%sm' "$1"; return 0; }
ansi_bg() { [[ -n $1 ]] && printf '\033[48;2;%sm' "$1"; return 0; }
ANSI_RESET=$'\033[0m'
ANSI_BOLD=$'\033[1m'
ANSI_DIM=$'\033[2m'
ANSI_UNDERLINE=$'\033[4m'

load_theme
