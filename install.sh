#!/usr/bin/env bash
# Install the vegabond entrypoint into ~/.local/bin.
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/vegabond"
FORCE=0

for arg in "$@"; do
  case $arg in
    --force) FORCE=1 ;;
    -h|--help)
      printf 'Usage: %s [--force]\n' "${0##*/}"
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

missing=0
for dep in gum sqlite3 jq fzf; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    printf 'missing: %s\n' "$dep" >&2
    missing=1
  fi
done
if ((missing)); then
  cat >&2 <<'EOF'
Install the missing packages first, for example:

  omarchy pkg add gum sqlite jq fzf
EOF
  exit 1
fi

chmod +x "$ROOT/bin/vegabond" "$ROOT/lib/fzf-mode.sh" "$ROOT/tests/run.sh"
mkdir -p -- "$BIN_DIR"

if [[ -e $TARGET || -L $TARGET ]]; then
  if [[ ! -L $TARGET && $FORCE == 0 ]]; then
    printf '%s exists and is not a symlink; re-run with --force to replace it.\n' "$TARGET" >&2
    exit 1
  fi
  rm -f -- "$TARGET"
fi

ln -s "$ROOT/bin/vegabond" "$TARGET"
printf 'Installed %s -> %s\n' "$TARGET" "$ROOT/bin/vegabond"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) printf 'Note: %s is not on PATH.\n' "$BIN_DIR" >&2 ;;
esac

printf 'Try: vegabond\n'
