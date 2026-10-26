#!/usr/bin/env bash
# Non-interactive test suite. Uses a throwaway database and never calls gum/fzf.
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/vegabond"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/vegabond-tests.XXXXXX")
export VEGABOND_DB="$TMP/tools.db"
export VEGABOND_NO_THEME=1
trap 'rm -rf -- "$TMP"' EXIT

pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

check() {
  local label=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then ok "$label"; else bad "$label (expected [$expected], got [$actual])"; fi
}

check_contains() {
  local label=$1 needle=$2 haystack=$3
  if [[ $haystack == *"$needle"* ]]; then ok "$label"; else bad "$label (missing [$needle])"; fi
}

check_rc() {
  local label=$1 expected=$2 actual=$3
  check "$label" "$expected" "$actual"
}

printf 'Vegabond tests\n'

# --- add / list / show -------------------------------------------------------
out=$("$CLI" add --name "O'Brien's Tool" \
  --description $'Line one\nLine two with "quotes"' \
  --tags " Windows , TEST tag,test-tag" \
  --url "https://example.com/a'b" \
  --usage $'tool --flag\nsecond line') || bad "add exits 0"
check_contains "add reports the tool" "Added" "$out"

out=$("$CLI" list --json)
check "one tool listed" "1" "$(jq 'length' <<<"$out")"
check "tags normalized" '["test-tag","windows"]' "$(jq -c '.[0].tags | sort' <<<"$out")"
check "newline preserved" "Line two with \"quotes\"" "$(jq -r '.[0].description' <<<"$out" | tail -n 1)"
check "url preserved" "https://example.com/a'b" "$(jq -r '.[0].url' <<<"$out")"
check "tags are sorted in the view" '["test-tag","windows"]' "$(jq -c '.[0].tags' <<<"$out")"

out=$("$CLI" show "O'Brien's Tool" --json)
check "show json name" "O'Brien's Tool" "$(jq -r '.name' <<<"$out")"
check "show json usage" $'tool --flag\nsecond line' "$(jq -r '.usage' <<<"$out")"

"$CLI" add --name "O'Brien's Tool" --description duplicate >/dev/null 2>&1
check_rc "duplicate name rejected" 1 "$?"

# --- search ------------------------------------------------------------------
check "search name" "1" "$("$CLI" search "o'brien" --json | jq 'length')"
check "search description" "1" "$("$CLI" search quotes --json | jq 'length')"
check "search usage terms" "1" "$("$CLI" search "tool flag" --json | jq 'length')"
check "search tag" "1" "$("$CLI" search windows --json | jq 'length')"
check "search miss" "0" "$("$CLI" search zzzznotfound --json | jq 'length')"

# --- edit --------------------------------------------------------------------
"$CLI" edit "O'Brien's Tool" --description "changed" --tags "linux,test-tag" --url "https://changed.example" >/dev/null
out=$("$CLI" show "O'Brien's Tool" --json)
check "edit description" "changed" "$(jq -r '.description' <<<"$out")"
check "edit tags" '["linux","test-tag"]' "$(jq -c '.tags | sort' <<<"$out")"
check "edit url" "https://changed.example" "$(jq -r '.url' <<<"$out")"
check "edit keeps usage" $'tool --flag\nsecond line' "$(jq -r '.usage' <<<"$out")"

"$CLI" add --name "Tag Order" --tags "zebra,alpha" >/dev/null
check "tags sorted after add" '["alpha","zebra"]' "$("$CLI" show "Tag Order" --json | jq -c '.tags')"
"$CLI" rm "Tag Order" --yes >/dev/null

"$CLI" add --name Other --description other --tags "linux" >/dev/null
"$CLI" edit Other --name "Renamed Other" >/dev/null
check "rename works" "Renamed Other" "$("$CLI" show "Renamed Other" --json | jq -r '.name')"

# --- list filters ------------------------------------------------------------
check "list --tag linux" "2" "$("$CLI" list --tag linux --json | jq 'length')"
check "list --tag none" "0" "$("$CLI" list --tag nope --json | jq 'length')"
check "list --tag is normalized" "2" "$("$CLI" list --tag LINUX --json | jq 'length')"
check "list --limit" "1" "$("$CLI" list --limit 1 --json | jq 'length')"

# --- tags --------------------------------------------------------------------
"$CLI" tags merge test-tag linux >/dev/null
check "merge removes source" "0" "$("$CLI" list --tag test-tag --json | jq 'length')"
check "merge keeps dest" "2" "$("$CLI" list --tag linux --json | jq 'length')"

"$CLI" tags rename linux unix >/dev/null
check "rename tag" "2" "$("$CLI" list --tag unix --json | jq 'length')"

"$CLI" tags rename unix UNIX >/dev/null 2>&1
check_rc "tag name is normalized before rename" 1 "$?"

"$CLI" tags rm UNIX >/dev/null
check "delete tag unlinks" "0" "$("$CLI" list --tag unix --json | jq 'length')"
check "delete tag prunes" "0" "$("$CLI" tags | grep -c '^unix' || true)"

# --- import / export ---------------------------------------------------------
cat >"$TMP/import.json" <<'JSON'
{
  "tools": [
    {"name": "Alpha", "description": "alpha desc", "url": "https://a.example",
     "tags": ["web", " Reconn "], "usage": "alpha -x"},
    {"name": "Beta", "description": "beta desc", "tags": "cloud,web"}
  ]
}
JSON

out=$("$CLI" import "$TMP/import.json")
check_contains "import reports new" "2 new" "$out"
check "import count" "4" "$("$CLI" list --json | jq 'length')"
check "import normalizes tags" '["reconn","web"]' "$("$CLI" show Alpha --json | jq -c '.tags | sort')"

out=$("$CLI" import "$TMP/import.json" --on-conflict skip)
check_contains "skip existing" "0 new" "$out"

"$CLI" import "$TMP/import.json" --on-conflict abort >/dev/null 2>&1
check_rc "abort on conflict" 1 "$?"

"$CLI" import "$TMP/import.json" --on-conflict update >/dev/null
check "update count unchanged" "4" "$("$CLI" list --json | jq 'length')"

cat >"$TMP/dupes.json" <<'JSON'
[{"name": "Same", "tags": []}, {"name": "same", "tags": []}]
JSON
"$CLI" import "$TMP/dupes.json" >/dev/null 2>&1
check_rc "duplicate names in file rejected" 1 "$?"

printf '[{"name": "tab\tname", "tags": []}]' >"$TMP/tab.json"
"$CLI" import "$TMP/tab.json" >/dev/null 2>&1
check_rc "tab in imported name rejected" 1 "$?"

"$CLI" export --format json --out "$TMP/export.json" >/dev/null
check "json export exists" "4" "$(jq 'length' "$TMP/export.json")"

"$CLI" export --format csv --out "$TMP/export.csv" >/dev/null
check "csv export header" "name,description,url,usage,tags" "$(head -n 1 "$TMP/export.csv" | tr -d '\r')"

"$CLI" export --format md --out "$TMP/export.md" >/dev/null
check_contains "markdown export" "## Alpha" "$(cat "$TMP/export.md")"
check_contains "markdown usage" "    alpha -x" "$(cat "$TMP/export.md")"

# Round trip into a second database.
VEGABOND_DB="$TMP/roundtrip.db" "$CLI" import "$TMP/export.json" >/dev/null
check "round-trip count" "4" "$(VEGABOND_DB="$TMP/roundtrip.db" "$CLI" list --json | jq 'length')"

# --- delete ------------------------------------------------------------------
"$CLI" rm "Renamed Other" --yes >/dev/null
check "delete removes tool" "3" "$("$CLI" list --json | jq 'length')"
check "delete prunes orphan tags" "0" "$("$CLI" tags | grep -c '^nope' || true)"

"$CLI" rm Alpha >/dev/null 2>&1
check_rc "delete without --yes needs a tty" 1 "$?"

# --- stats / doctor ----------------------------------------------------------
check "stats reports tools" "3" "$("$CLI" stats --json | jq '.[0].tools')"
check "stats has tag count" "true" "$("$CLI" stats --json | jq '.[0].tags > 0')"

"$CLI" doctor >/dev/null 2>&1
check_rc "doctor exits 0" 0 "$?"

# --- seed --------------------------------------------------------------------
VEGABOND_DB="$TMP/seed.db" "$CLI" seed >/dev/null
check "seed count" "70" "$(VEGABOND_DB="$TMP/seed.db" "$CLI" list --json | jq 'length')"
check "seed has unique names" "70" "$(VEGABOND_DB="$TMP/seed.db" "$CLI" list --json | jq '[.[].name] | unique | length')"
VEGABOND_DB="$TMP/seed.db" "$CLI" seed >/dev/null
check "seed is idempotent" "70" "$(VEGABOND_DB="$TMP/seed.db" "$CLI" list --json | jq 'length')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
