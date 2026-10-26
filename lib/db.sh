#!/usr/bin/env bash
# SQLite layer. All values from user input reach SQL through a temp JSON file
# and json_extract(readfile(...)), or through a correctly quoted SQL literal
# for read-only lookups. Nothing is interpolated raw.

: "${VEGABOND_DB:?VEGABOND_DB must be set}"
: "${VEGABOND_ROOT:?VEGABOND_ROOT must be set}"

DB_BUSY_TIMEOUT=5000

dbq() {
  sqlite3 --bail -cmd ".timeout $DB_BUSY_TIMEOUT" "$VEGABOND_DB" "$@"
}

db_json() {
  sqlite3 --json --bail -cmd ".timeout $DB_BUSY_TIMEOUT" "$VEGABOND_DB" "$@" 2>/dev/null || true
}

db_init() {
  local dbdir
  dbdir=$(dirname -- "$VEGABOND_DB")
  mkdir -p -- "$dbdir" "$VEGABOND_ROOT/data/backups"
  sqlite3 --bail "$VEGABOND_DB" 'PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;' >/dev/null
  sqlite3 --bail -cmd ".timeout $DB_BUSY_TIMEOUT" "$VEGABOND_DB" \
    <"$VEGABOND_ROOT/share/schema.sql" >/dev/null
  if [[ $(dbq 'PRAGMA user_version;') == "0" ]]; then
    dbq 'PRAGMA user_version=1;' >/dev/null
  fi
}

db_ready() {
  [[ -f $VEGABOND_DB ]] || return 1
  [[ $(dbq "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='tools';") == 1 ]]
}

sql_quote() {
  local s=${1//\'/\'\'}
  printf "'%s'" "$s"
}

sql_like() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//%/\\%}
  s=${s//_/\\_}
  sql_quote "%$s%"
}

valid_tool_name() {
  local name=$1
  [[ -n $name && $name != *$'\n'* && $name != *$'\t'* && $name != *$'\r'* ]]
}

normalize_tag_arg() {
  normalize_tags_json "${1:-}" | jq -r '.[0] // empty'
}

normalize_tags_json() {
  local csv=${1:-}
  printf '%s' "$csv" | jq -R -s -c '
    split(",")
    | map(
        ascii_downcase
        | gsub("^\\s+|\\s+$"; "")
        | gsub("\\s+"; "-")
        | gsub("-+"; "-")
        | gsub("^-+|-+$"; "")
        | select(length > 0)
      )
    | unique
  '
}

db_count_tools() {
  dbq 'SELECT count(*) FROM tools;'
}

db_count_tags() {
  dbq 'SELECT count(*) FROM tags;'
}

db_tag_list() {
  dbq 'SELECT name FROM tags ORDER BY name COLLATE NOCASE;'
}

db_tag_counts() {
  dbq -separator $'\t' "
    SELECT g.name, count(tt.tool_id)
    FROM tags g LEFT JOIN tool_tags tt ON tt.tag_id = g.id
    GROUP BY g.id
    ORDER BY g.name COLLATE NOCASE;
  "
}

db_resolve_id() {
  local query=$1 id
  if [[ $query =~ ^[0-9]+$ ]]; then
    id=$(dbq "SELECT id FROM tools WHERE id = $query;")
    [[ -n $id ]] && { printf '%s' "$id"; return 0; }
  fi
  id=$(dbq "SELECT id FROM tools WHERE name = $(sql_quote "$query") COLLATE NOCASE;")
  [[ -n $id ]] || return 1
  printf '%s' "$id"
}

db_get_tool_json() {
  local id=$1 raw
  [[ $id =~ ^[0-9]+$ ]] || return 1
  raw=$(db_json "SELECT name, description, url, usage_md, tags FROM v_tools WHERE id = $id;")
  [[ -n $raw ]] || return 1
  printf '%s' "$raw" | jq -c '.[0] // empty'
}

db_tool_name() {
  local id=$1
  [[ $id =~ ^[0-9]+$ ]] || return 1
  dbq "SELECT name FROM tools WHERE id = $id;"
}

db_tool_url() {
  local id=$1
  [[ $id =~ ^[0-9]+$ ]] || return 1
  dbq "SELECT url FROM tools WHERE id = $id;"
}

db_tool_usage() {
  local id=$1
  [[ $id =~ ^[0-9]+$ ]] || return 1
  dbq "SELECT usage_md FROM tools WHERE id = $id;"
}

db_name_exists() {
  local name=$1
  [[ $(dbq "SELECT count(*) FROM tools WHERE name = $(sql_quote "$name") COLLATE NOCASE;") != 0 ]]
}

db_tag_exists() {
  local name=$1
  [[ $(dbq "SELECT count(*) FROM tags WHERE name = $(sql_quote "$name") COLLATE NOCASE;") != 0 ]]
}

db_insert_tool() {
  local name=$1 description=${2:-} url=${3:-} usage=${4:-} tags_json=${5:-'[]'} tmp id
  [[ $tags_json == \[* ]] || tags_json=$(normalize_tags_json "$tags_json")
  tmp=$(mktemp "${TMPDIR:-/tmp}/vegabond.XXXXXX.json") || return 1

  if ! jq -n \
    --arg name "$name" \
    --arg description "$description" \
    --arg url "$url" \
    --arg usage_md "$usage" \
    --argjson tags "$tags_json" \
    '{name: $name, description: $description, url: $url, usage_md: $usage_md, tags: $tags}' \
    >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi

  id=$(sqlite3 --bail -cmd ".timeout $DB_BUSY_TIMEOUT" "$VEGABOND_DB" <<SQL
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
INSERT INTO tools(name, description, url, usage_md)
VALUES (
  json_extract(readfile('$tmp'), '\$.name'),
  json_extract(readfile('$tmp'), '\$.description'),
  json_extract(readfile('$tmp'), '\$.url'),
  json_extract(readfile('$tmp'), '\$.usage_md')
);
INSERT OR IGNORE INTO tags(name)
SELECT value FROM json_each(readfile('$tmp'), '\$.tags');
INSERT INTO tool_tags(tool_id, tag_id)
SELECT
  (SELECT id FROM tools WHERE name = json_extract(readfile('$tmp'), '\$.name')),
  tags.id
FROM tags
WHERE tags.name IN (SELECT value FROM json_each(readfile('$tmp'), '\$.tags'));
SELECT id FROM tools WHERE name = json_extract(readfile('$tmp'), '\$.name');
COMMIT;
SQL
  ) || { rm -f -- "$tmp"; return 1; }
  rm -f -- "$tmp"
  printf '%s' "$id"
}

db_update_tool() {
  local id=$1 name=$2 description=${3:-} url=${4:-} usage=${5:-} tags_json=${6:-'[]'} tmp
  [[ $id =~ ^[0-9]+$ ]] || return 1
  [[ $tags_json == \[* ]] || tags_json=$(normalize_tags_json "$tags_json")
  tmp=$(mktemp "${TMPDIR:-/tmp}/vegabond.XXXXXX.json") || return 1

  if ! jq -n \
    --arg name "$name" \
    --arg description "$description" \
    --arg url "$url" \
    --arg usage_md "$usage" \
    --argjson tags "$tags_json" \
    '{name: $name, description: $description, url: $url, usage_md: $usage_md, tags: $tags}' \
    >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi

  if ! sqlite3 --bail -cmd ".timeout $DB_BUSY_TIMEOUT" "$VEGABOND_DB" <<SQL
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
UPDATE tools SET
  name        = json_extract(readfile('$tmp'), '\$.name'),
  description = json_extract(readfile('$tmp'), '\$.description'),
  url         = json_extract(readfile('$tmp'), '\$.url'),
  usage_md    = json_extract(readfile('$tmp'), '\$.usage_md'),
  updated_at  = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE id = $id;
DELETE FROM tool_tags WHERE tool_id = $id;
INSERT OR IGNORE INTO tags(name)
SELECT value FROM json_each(readfile('$tmp'), '\$.tags');
INSERT INTO tool_tags(tool_id, tag_id)
SELECT $id, tags.id
FROM tags
WHERE tags.name IN (SELECT value FROM json_each(readfile('$tmp'), '\$.tags'));
DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM tool_tags);
COMMIT;
SQL
  then
    rm -f -- "$tmp"
    return 1
  fi
  rm -f -- "$tmp"
}

db_delete_tool() {
  local id=$1
  [[ $id =~ ^[0-9]+$ ]] || return 1
  dbq "
    PRAGMA foreign_keys = ON;
    BEGIN IMMEDIATE;
    DELETE FROM tools WHERE id = $id;
    DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM tool_tags);
    COMMIT;
  " >/dev/null
}

db_prune_tags() {
  dbq 'DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM tool_tags);' >/dev/null
}

db_list_raw() {
  dbq -noheader -separator $'\t' "
    SELECT id, name, tags
    FROM v_tools
    ORDER BY name COLLATE NOCASE;
  "
}

db_list_plain() {
  local tag=${1:-} limit=${2:-}
  local where="" tail=""
  if [[ -n $tag ]]; then
    where="WHERE EXISTS (
      SELECT 1 FROM tool_tags tt JOIN tags g ON g.id = tt.tag_id
      WHERE tt.tool_id = t.id AND g.name = $(sql_quote "$tag")
    )"
  fi
  [[ -n $limit && $limit =~ ^[0-9]+$ ]] && tail="LIMIT $limit"
  dbq -noheader -separator $'\t' "
    SELECT t.id, t.name, t.tags
    FROM v_tools t
    $where
    ORDER BY t.name COLLATE NOCASE
    $tail;
  "
}

db_list_json() {
  local tag=${1:-} limit=${2:-}
  local where="" tail=""
  if [[ -n $tag ]]; then
    where="WHERE EXISTS (
      SELECT 1 FROM tool_tags tt JOIN tags g ON g.id = tt.tag_id
      WHERE tt.tool_id = t.id AND g.name = $(sql_quote "$tag")
    )"
  fi
  [[ -n $limit && $limit =~ ^[0-9]+$ ]] && tail="LIMIT $limit"
  local raw
  raw=$(db_json "
    SELECT name, description, url, usage_md, tags
    FROM v_tools t
    $where
    ORDER BY t.name COLLATE NOCASE
    $tail;
  ")
  [[ -n $raw ]] || raw='[]'
  printf '%s' "$raw" | jq -c '
    map({
      name, description, url,
      usage: .usage_md,
      tags: (.tags | split(", ") | map(select(length > 0)))
    })
  '
}

db_search_where() {
  local q=$1 term pattern cond clause=""
  for term in $q; do
    pattern=$(sql_like "$term")
    cond="(t.name LIKE $pattern ESCAPE '\\'
        OR t.description LIKE $pattern ESCAPE '\\'
        OR t.usage_md LIKE $pattern ESCAPE '\\'
        OR t.tags LIKE $pattern ESCAPE '\\')"
    if [[ -z $clause ]]; then clause=$cond; else clause+=" AND $cond"; fi
  done
  printf '%s' "$clause"
}

db_search_plain() {
  local q=$1 tag=${2:-} limit=${3:-}
  local tail="" tag_clause="" where
  where=$(db_search_where "$q")
  [[ -n $limit && $limit =~ ^[0-9]+$ ]] && tail="LIMIT $limit"
  if [[ -n $tag ]]; then
    tag_clause="AND EXISTS (
      SELECT 1 FROM tool_tags tt JOIN tags g ON g.id = tt.tag_id
      WHERE tt.tool_id = t.id AND g.name = $(sql_quote "$tag")
    )"
  fi
  dbq -noheader -separator $'\t' "
    SELECT t.id, t.name, t.tags
    FROM v_tools t
    WHERE ($where)
      $tag_clause
    ORDER BY t.name COLLATE NOCASE
    $tail;
  "
}

db_search_json() {
  local q=$1 tag=${2:-} limit=${3:-}
  local tail="" tag_clause="" where
  where=$(db_search_where "$q")
  [[ -n $limit && $limit =~ ^[0-9]+$ ]] && tail="LIMIT $limit"
  if [[ -n $tag ]]; then
    tag_clause="AND EXISTS (
      SELECT 1 FROM tool_tags tt JOIN tags g ON g.id = tt.tag_id
      WHERE tt.tool_id = t.id AND g.name = $(sql_quote "$tag")
    )"
  fi
  local raw
  raw=$(db_json "
    SELECT name, description, url, usage_md, tags
    FROM v_tools t
    WHERE ($where)
      $tag_clause
    ORDER BY t.name COLLATE NOCASE
    $tail;
  ")
  [[ -n $raw ]] || raw='[]'
  printf '%s' "$raw" | jq -c '
    map({
      name, description, url,
      usage: .usage_md,
      tags: (.tags | split(", ") | map(select(length > 0)))
    })
  '
}

db_rename_tag() {
  local old=$1 new=$2
  [[ -n $old && -n $new ]] || return 1
  dbq "
    PRAGMA foreign_keys = ON;
    UPDATE tags SET name = $(sql_quote "$new") WHERE name = $(sql_quote "$old") COLLATE NOCASE;
  " >/dev/null 2>&1
}

db_merge_tags() {
  local src=$1 dst=$2
  [[ -n $src && -n $dst && $src != "$dst" ]] || return 1
  dbq "
    PRAGMA foreign_keys = ON;
    BEGIN IMMEDIATE;
    INSERT OR IGNORE INTO tool_tags(tool_id, tag_id)
      SELECT tt.tool_id, (SELECT id FROM tags WHERE name = $(sql_quote "$dst") COLLATE NOCASE)
      FROM tool_tags tt
      WHERE tt.tag_id = (SELECT id FROM tags WHERE name = $(sql_quote "$src") COLLATE NOCASE);
    DELETE FROM tags WHERE name = $(sql_quote "$src") COLLATE NOCASE;
    COMMIT;
  " >/dev/null
}

db_delete_tag() {
  local tag=$1
  dbq "
    PRAGMA foreign_keys = ON;
    DELETE FROM tags WHERE name = $(sql_quote "$tag") COLLATE NOCASE;
  " >/dev/null
}

db_import_json() {
  local file=$1 mode=${2:-skip} tmp before total
  [[ -f $file ]] || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/vegabond.XXXXXX.json") || return 1

  if ! jq -e '
    if type == "object" and has("tools") then .tools else . end
    | if type != "array" then error("expected a JSON array") else . end
    | if (map((.name // "" | tostring | ascii_downcase | gsub("^\\s+|\\s+$"; "")) | select(length > 0)) | length)
          != (map((.name // "" | tostring | ascii_downcase | gsub("^\\s+|\\s+$"; "")) | select(length > 0)) | unique | length)
        then error("duplicate tool names in the file") else . end
    | map(
        .name = ((.name // "") | tostring | gsub("^\\s+|\\s+$"; ""))
        | if .name == "" then error("record without name") else . end
        | if (.name | test("[\\n\\t\\r]")) then error("tool names must be a single line") else . end
        | .description = ((.description // "") | tostring)
        | .url = ((.url // "") | tostring)
        | .usage_md = ((.usage // .usage_md // "") | tostring)
        | .tags = (
            (.tags // [])
            | if type == "string" then split(",") else . end
            | map(
                tostring
                | ascii_downcase
                | gsub("^\\s+|\\s+$"; "")
                | gsub("\\s+"; "-")
                | gsub("-+"; "-")
                | gsub("^-+|-+$"; "")
                | select(length > 0)
              )
            | unique
          )
      )
  ' "$file" >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi

  total=$(jq 'length' "$tmp")
  before=$(dbq "SELECT count(*) FROM tools WHERE name IN (
    SELECT json_extract(value, '\$.name') FROM json_each(readfile('$tmp'))
  );")

  if [[ $mode == abort && $before != 0 ]]; then
    rm -f -- "$tmp"
    printf 'conflict:%s' "$before"
    return 2
  fi

  local conflict_clause tag_filter=""
  case $mode in
    update)
      conflict_clause="ON CONFLICT(name) DO UPDATE SET
        description = excluded.description,
        url         = excluded.url,
        usage_md    = excluded.usage_md,
        updated_at  = strftime('%Y-%m-%dT%H:%M:%fZ','now')"
      ;;
    *)
      conflict_clause="ON CONFLICT(name) DO NOTHING"
      # Skipped tools keep the tags they already have; only new tools get the
      # imported tags linked.
      tag_filter="AND t.name NOT IN (SELECT name FROM preexisting)"
      ;;
  esac

  if ! sqlite3 --bail -cmd ".timeout $DB_BUSY_TIMEOUT" "$VEGABOND_DB" <<SQL
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
CREATE TEMP TABLE preexisting(name TEXT PRIMARY KEY);
INSERT INTO preexisting(name) SELECT name FROM tools;
INSERT INTO tools(name, description, url, usage_md)
SELECT
  json_extract(value, '\$.name'),
  json_extract(value, '\$.description'),
  json_extract(value, '\$.url'),
  json_extract(value, '\$.usage_md')
FROM json_each(readfile('$tmp'))
WHERE true
$conflict_clause;

INSERT OR IGNORE INTO tags(name)
SELECT DISTINCT jt.value
FROM json_each(readfile('$tmp')) j
JOIN json_each(json_extract(j.value, '\$.tags')) jt;

INSERT OR IGNORE INTO tool_tags(tool_id, tag_id)
SELECT t.id, g.id
FROM json_each(readfile('$tmp')) j
JOIN tools t ON t.name = json_extract(j.value, '\$.name')
JOIN json_each(json_extract(j.value, '\$.tags')) jt
JOIN tags g ON g.name = jt.value
$tag_filter;

DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM tool_tags);
COMMIT;
SQL
  then
    rm -f -- "$tmp"
    return 1
  fi

  rm -f -- "$tmp"
  printf '%s:%s' "$total" "$before"
}

db_export_json() {
  local raw
  raw=$(db_json 'SELECT name, description, url, usage_md, tags FROM v_tools ORDER BY name COLLATE NOCASE;')
  [[ -n $raw ]] || raw='[]'
  printf '%s' "$raw" | jq '
    map({
      name, description, url,
      usage: .usage_md,
      tags: (.tags | split(", ") | map(select(length > 0)))
    })
  '
}

db_export_csv() {
  dbq -csv -header '
    SELECT name, description, url, usage_md AS usage, tags
    FROM v_tools
    ORDER BY name COLLATE NOCASE;
  '
}

db_export_markdown() {
  local raw
  raw=$(db_json 'SELECT name, description, url, usage_md, tags FROM v_tools ORDER BY name COLLATE NOCASE;')
  [[ -n $raw ]] || raw='[]'
  printf '%s' "$raw" | jq -r '
    map(
      "## " + .name + "\n\n"
      + (if .description != "" then .description + "\n\n" else "" end)
      + "**Tags:** " + (if .tags != "" then (.tags | split(", ") | map("`" + . + "`") | join(" ")) else "—" end)
      + "  \n**Reference:** " + (if .url != "" then .url else "—" end) + "\n\n"
      + (if .usage_md != "" then
          "### Usage\n\n" + (.usage_md | split("\n") | map("    " + .) | join("\n")) + "\n\n"
        else "" end)
    )
    | "# Vegabond\n\n" + join("")
  '
}

db_stats_json() {
  local raw
  raw=$(db_json "
    SELECT
      (SELECT count(*) FROM tools) AS tools,
      (SELECT count(*) FROM tags) AS tags,
      (SELECT count(*) FROM tool_tags) AS links,
      (SELECT count(*) FROM tools t WHERE NOT EXISTS (
        SELECT 1 FROM tool_tags tt WHERE tt.tool_id = t.id)) AS untagged,
      (SELECT count(*) FROM tools WHERE updated_at >= strftime('%Y-%m-%dT%H:%M:%fZ','now','-30 days')) AS updated_30d;
  ")
  [[ -n $raw ]] || raw='[]'
  printf '%s' "$raw"
}

db_top_tags() {
  local limit=${1:-8}
  [[ $limit =~ ^[0-9]+$ ]] || limit=8
  dbq -noheader -separator $'\t' "
    SELECT g.name, count(tt.tool_id) AS n
    FROM tags g JOIN tool_tags tt ON tt.tag_id = g.id
    GROUP BY g.id
    ORDER BY n DESC, g.name COLLATE NOCASE
    LIMIT $limit;
  "
}
