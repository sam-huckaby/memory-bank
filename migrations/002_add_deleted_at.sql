-- Migration: Add soft delete support
-- Description: Adds deleted_at column and index for soft delete functionality
-- Version: 002
-- Date: 2025-12-20

ALTER TABLE photos ADD COLUMN deleted_at TEXT;
CREATE INDEX IF NOT EXISTS idx_deleted_at ON photos(deleted_at);
