-- ============================================================================
-- PHASE 3 — ANALYTICS SETUP
-- Prerequisite: Phase 1 loaded data into public.master_data
--
-- Creates ONE read-only view (analytics.master_enriched) that maps Twitter /
-- sentiment columns to names used by Phase 3 analytics queries.
--
-- Does NOT create users, products, or reviews tables.
-- Safe to re-run (idempotent view DDL).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS analytics;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'master_data'
    ) THEN
        RAISE EXCEPTION
            'Table public.master_data not found. Run phase1_load_clean_store.ipynb first.';
    END IF;
END $$;

CREATE OR REPLACE VIEW analytics.master_enriched AS
SELECT
    m.row_id,
    m."user",
    m.target,
    m.ids,
    m.date,
    m.flag,
    m.text,
    m.text                                            AS review_text,
    ('Sentiment ' || COALESCE(m.target::TEXT, '?'))    AS product_name,
    COALESCE(m.target::TEXT, 'unknown')               AS category,
    COALESCE(m.flag, 'n/a')                           AS brand,
    m."user"                                          AS region,
    CASE COALESCE(m.target::TEXT, '')
        WHEN '4' THEN 'positive'
        WHEN '0' THEN 'negative'
        WHEN '2' THEN 'neutral'
        ELSE 'neutral'
    END                                               AS sentiment,
    CASE
        WHEN COALESCE(m.target::TEXT, '') ~ '^[0-9]+$' THEN m.target::INTEGER
        ELSE NULL
    END                                               AS rating,
    CASE
        WHEN m.date IS NOT NULL AND BTRIM(m.date::TEXT) <> '' THEN
            to_timestamp(
                SUBSTRING(m.date::TEXT FROM 1 FOR 30),
                'Dy Mon DD HH24:MI:SS TZ YYYY'
            )
        ELSE NULL
    END                                               AS created_at
FROM public.master_data AS m;

-- Verification
SELECT 'public.master_data'     AS object_name, COUNT(*)::BIGINT AS row_count FROM public.master_data
UNION ALL
SELECT 'analytics.master_enriched', COUNT(*)::BIGINT FROM analytics.master_enriched;
