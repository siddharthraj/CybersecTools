#!/usr/bin/env bash
# The fzf browser surface: vim-style modal keys, themed list, detail panel.

browser_list_line() {
  # Column-aligned, colored row for the fzf list.
  local id=$1 name=$2 tags=$3 width=$4
  local fg muted pad
  fg=$(ansi_fg "${TH_FG_RGB:-}")
  muted=$(ansi_fg "${TH_MUTED_RGB:-}")
  pad=$(printf '%-*s' "$width" "$name")
  if [[ -n $tags ]]; then
    printf '%s\t%s%s%s%s  ·  %s%s\n' "$id" "$fg" "$pad" "$ANSI_RESET" "$muted" "$tags" "$ANSI_RESET"
  else
    printf '%s\t%s%s%s%s  ·  %s(no tags)%s\n' \
      "$id" "$fg" "$pad" "$ANSI_RESET" "$muted" "" "$ANSI_RESET"
  fi
}

cmd_browse() {
  require_tty || return 1
  require_fzf || return 1
  require_gum || return 1

  db_init

  if [[ $(db_count_tools) == 0 && -n ${VEGABOND_ROOT:-} && -f $VEGABOND_ROOT/share/seed.json ]]; then
    ui_title "Vegabond" "Your cybersecurity tool knowledge base"
    if gum confirm --default "The database is empty. Load the starter catalog?"; then
      cmd_seed
    fi
  fi

  local state self
  state=$(mktemp -d "${TMPDIR:-/tmp}/vegabond.XXXXXX") || return 1
  self=${SELF:-$VEGABOND_ROOT/bin/vegabond}

  export TB_STATE=$state
  export TB_NORMAL_KEYS='j,k,g,G,J,K,q,/,e,o,y,Y,v,d,a,?'

  local q
  q=$(printf '%q' "$self")

  local h1 h2 h3
  h1="$(fzf_key j)/$(fzf_key k) $(fzf_dim move) · $(fzf_key /) $(fzf_dim search) · $(fzf_key enter) $(fzf_dim details) · $(fzf_key q) $(fzf_dim quit)"
  h2="$(fzf_key a) add · $(fzf_key e) edit · $(fzf_key d) delete · $(fzf_key v) view"
  h3="$(fzf_key o) open · $(fzf_key y) copy URL · $(fzf_key Y) copy usage · $(fzf_key ?) help"

  local -a args=(
    --ansi
    --no-input
    --layout=reverse
    --height=100%
    --delimiter '\t'
    --with-nth 2
    --prompt '> '
    --pointer ''
    --marker ''
    --header "$h1"$'\n'"$h2"$'\n'"$h3"
    --header-border bottom
    --preview "$q _preview {1}"
    --preview-window 'right,55%,border-rounded,wrap,hidden'
    --preview-label ' Details '
    --bind 'j:down'
    --bind 'k:up'
    --bind 'g:first'
    --bind 'G:last'
    --bind 'J:page-down'
    --bind 'K:page-up'
    --bind "/:show-input+unbind($TB_NORMAL_KEYS)+change-prompt(Search: )"
    --bind 'q:abort'
    --bind "e:execute($q _edit {1})+reload($q _list-lines)"
    --bind "a:execute($q _add)+reload($q _list-lines)"
    --bind "d:execute($q _rm {1})+reload($q _list-lines)"
    --bind "o:execute-silent($q _open {1})"
    --bind "y:execute-silent($q _copy-url {1})"
    --bind "Y:execute-silent($q _copy-usage {1})"
    --bind "v:execute($q _view {1})"
    --bind "?:execute($q _help)"
    --bind "enter:transform:$q _mode enter"
    --bind "esc:transform:$q _mode esc"
  )

  if ((${#FZF_THEME_OPTS[@]} > 0)); then
    args+=("${FZF_THEME_OPTS[@]}")
  fi

  local rc=0
  "$self" _list-lines | fzf "${args[@]}"
  rc=$?

  rm -rf -- "$state"
  # Esc/q is a normal way to leave the browser, not an error.
  ((rc == 130)) && rc=0
  return $rc
}
