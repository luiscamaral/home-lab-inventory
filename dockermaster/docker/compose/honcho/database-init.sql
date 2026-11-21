-- Honcho database init: enable pgvector extension on first boot.
-- Mirrored from upstream: https://github.com/plastic-labs/honcho/blob/main/database/init.sql
CREATE EXTENSION IF NOT EXISTS vector;
