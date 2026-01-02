class Migration {
  const Migration({required this.version, required this.statements});

  final int version;
  final List<String> statements;
}

const List<Migration> schemaMigrations = [
  Migration(
    version: 1,
    statements: [
      '''
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''',
      '''
CREATE TABLE IF NOT EXISTS place (
  place_code TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  name_ja TEXT NOT NULL,
  name_en TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL DEFAULT 0,
  geometry_id TEXT,
  updated_at INTEGER NOT NULL
);
''',
      '''
CREATE TABLE IF NOT EXISTS place_alias (
  place_code TEXT NOT NULL REFERENCES place(place_code) ON DELETE CASCADE,
  alias TEXT NOT NULL,
  alias_norm TEXT NOT NULL,
  PRIMARY KEY (place_code, alias_norm)
);
''',
      '''
CREATE INDEX IF NOT EXISTS idx_place_alias_norm ON place_alias(alias_norm);
''',
      '''
CREATE TABLE IF NOT EXISTS visit (
  visit_id TEXT PRIMARY KEY,
  place_code TEXT NOT NULL REFERENCES place(place_code),
  title TEXT NOT NULL,
  start_date TEXT,
  end_date TEXT,
  level INTEGER NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,

  CHECK (length(trim(title)) > 0),
  CHECK (level BETWEEN 1 AND 5),
  CHECK (start_date IS NULL OR length(start_date) = 10),
  CHECK (end_date IS NULL OR length(end_date) = 10),
  CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date)
);
''',
      '''
CREATE INDEX IF NOT EXISTS idx_visit_place_code ON visit(place_code);
''',
      '''
CREATE INDEX IF NOT EXISTS idx_visit_start_date ON visit(start_date);
''',
      '''
CREATE INDEX IF NOT EXISTS idx_visit_updated_at ON visit(updated_at);
''',
      '''
CREATE TABLE IF NOT EXISTS tag (
  tag_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_norm TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,

  CHECK (length(trim(name)) > 0)
);
''',
      '''
CREATE UNIQUE INDEX IF NOT EXISTS ux_tag_name_norm ON tag(name_norm);
''',
      '''
CREATE TABLE IF NOT EXISTS visit_tag (
  visit_id TEXT NOT NULL REFERENCES visit(visit_id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tag(tag_id) ON DELETE CASCADE,
  PRIMARY KEY (visit_id, tag_id)
);
''',
      '''
CREATE INDEX IF NOT EXISTS idx_visit_tag_tag_id ON visit_tag(tag_id);
''',
      '''
CREATE TABLE IF NOT EXISTS place_stats (
  place_code TEXT PRIMARY KEY REFERENCES place(place_code) ON DELETE CASCADE,
  max_level INTEGER NOT NULL DEFAULT 0,
  visit_count INTEGER NOT NULL DEFAULT 0,
  last_visit_date TEXT,
  updated_at INTEGER NOT NULL
);
''',
      '''
CREATE TABLE IF NOT EXISTS user_setting (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
''',
      '''
CREATE TRIGGER IF NOT EXISTS trg_visit_ai_place_stats
AFTER INSERT ON visit
BEGIN
  UPDATE place_stats
  SET
    visit_count = (SELECT COUNT(*) FROM visit WHERE place_code = NEW.place_code),
    max_level = COALESCE((SELECT MAX(level) FROM visit WHERE place_code = NEW.place_code), 0),
    last_visit_date = (SELECT MAX(COALESCE(end_date, start_date)) FROM visit WHERE place_code = NEW.place_code),
    updated_at = CAST(strftime('%s','now') AS INTEGER) * 1000
  WHERE place_code = NEW.place_code;
END;
''',
      '''
CREATE TRIGGER IF NOT EXISTS trg_visit_ad_place_stats
AFTER DELETE ON visit
BEGIN
  UPDATE place_stats
  SET
    visit_count = (SELECT COUNT(*) FROM visit WHERE place_code = OLD.place_code),
    max_level = COALESCE((SELECT MAX(level) FROM visit WHERE place_code = OLD.place_code), 0),
    last_visit_date = (SELECT MAX(COALESCE(end_date, start_date)) FROM visit WHERE place_code = OLD.place_code),
    updated_at = CAST(strftime('%s','now') AS INTEGER) * 1000
  WHERE place_code = OLD.place_code;
END;
''',
      '''
CREATE TRIGGER IF NOT EXISTS trg_visit_au_place_stats
AFTER UPDATE ON visit
BEGIN
  UPDATE place_stats
  SET
    visit_count = (SELECT COUNT(*) FROM visit WHERE place_code = OLD.place_code),
    max_level = COALESCE((SELECT MAX(level) FROM visit WHERE place_code = OLD.place_code), 0),
    last_visit_date = (SELECT MAX(COALESCE(end_date, start_date)) FROM visit WHERE place_code = OLD.place_code),
    updated_at = CAST(strftime('%s','now') AS INTEGER) * 1000
  WHERE place_code = OLD.place_code;

  UPDATE place_stats
  SET
    visit_count = (SELECT COUNT(*) FROM visit WHERE place_code = NEW.place_code),
    max_level = COALESCE((SELECT MAX(level) FROM visit WHERE place_code = NEW.place_code), 0),
    last_visit_date = (SELECT MAX(COALESCE(end_date, start_date)) FROM visit WHERE place_code = NEW.place_code),
    updated_at = CAST(strftime('%s','now') AS INTEGER) * 1000
  WHERE place_code = NEW.place_code;
END;
''',
    ],
  ),
];
