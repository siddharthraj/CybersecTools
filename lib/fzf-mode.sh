#!/usr/bin/env bash
# Emits fzf actions for Enter/Esc, switching between normal and search mode.
# fzf runs this via `transform:`; it must print exactly one action chain.
set -u

key=${1:-}
state=${TB_STATE:?TB_STATE is not set}
keys=${TB_NORMAL_KEYS:?TB_NORMAL_KEYS is not set}
flag="$state/preview"

if [[ ${FZF_INPUT_STATE:-} == enabled ]]; then
  printf 'rebind(%s)+hide-input+change-prompt(> )' "$keys"
  exit 0
fi

case $key in
  enter)
    if [[ -e $flag ]]; then
      rm -f -- "$flag"
      printf 'hide-preview'
    else
      : >"$flag"
      printf 'show-preview'
    fi
    ;;
  esc)
    if [[ -e $flag ]]; then
      rm -f -- "$flag"
      printf 'hide-preview'
    else
      printf 'abort'
    fi
    ;;
  *)
    printf 'abort'
    ;;
esac
