-- Vegabond schema (v1)
-- Applied idempotently on every launch. Never drops data.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tools (
  id          INTEGER PRIMARY KEY,
  name        TEXT NOT NULL COLLATE NOCASE,
  description TEXT NOT NULL DEFAULT '',
  url         TEXT NOT NULL DEFAULT '',
  usage_md    TEXT NOT NULL DEFAULT '',
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tools_name ON tools(name);

CREATE TABLE IF NOT EXISTS tags (
  id   INTEGER PRIMARY KEY,
  name TEXT NOT NULL COLLATE NOCASE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name ON tags(name);

CREATE TABLE IF NOT EXISTS tool_tags (
  tool_id INTEGER NOT NULL REFERENCES tools(id) ON DELETE CASCADE,
  tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
  PRIMARY KEY (tool_id, tag_id)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_tool_tags_tag ON tool_tags(tag_id);

DROP VIEW IF EXISTS v_tools;
CREATE VIEW v_tools AS
SELECT
  t.id,
  t.name,
  t.description,
  t.url,
  t.usage_md,
  t.created_at,
  t.updated_at,
  COALESCE((
    SELECT group_concat(name, ', ')
    FROM (
      SELECT g.name
      FROM tool_tags tt
      JOIN tags g ON g.id = tt.tag_id
      WHERE tt.tool_id = t.id
      ORDER BY g.name COLLATE NOCASE
    )
  ), '') AS tags
FROM tools t;

INSERT INTO meta(key, value) VALUES ('schema_version', '1')
  ON CONFLICT(key) DO NOTHING;
