-- Migration: Initial schema
-- Description: Creates the photos table with base fields
-- Version: 001
-- Date: 2025-12-20

CREATE TABLE IF NOT EXISTS photos (
  id TEXT PRIMARY KEY,
  original_filename TEXT NOT NULL,
  date_taken TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  mime_type TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_date_taken ON photos(date_taken);
CREATE INDEX IF NOT EXISTS idx_created_at ON photos(created_at);
