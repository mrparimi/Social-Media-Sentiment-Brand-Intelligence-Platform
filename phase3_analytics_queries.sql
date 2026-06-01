-- ============================================================================
-- PHASE 3 — SQL ANALYTICS (read-only)
--
-- RUN FIRST: phase3_analytics_setup.sql
--
-- Source: public.master_data (Phase 1) via view analytics.master_enriched
-- Typical columns: row_id, target, ids, date, flag, user, text
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Total reviews by product (sentiment class as product)
-- ----------------------------------------------------------------------------
SELECT
    product_name,
    category,
    COUNT(*) AS total_reviews
FROM analytics.master_enriched
GROUP BY product_name, category
ORDER BY total_reviews DESC, product_name;


-- ----------------------------------------------------------------------------
-- 2. Sentiment count by product (target / sentiment class)
-- ----------------------------------------------------------------------------
SELECT
    product_name,
    category,
    COUNT(*) FILTER (WHERE sentiment = 'positive') AS positive_count,
    COUNT(*) FILTER (WHERE sentiment = 'neutral')  AS neutral_count,
    COUNT(*) FILTER (WHERE sentiment = 'negative') AS negative_count,
    COUNT(*) AS total_reviews
FROM analytics.master_enriched
GROUP BY product_name, category
ORDER BY total_reviews DESC;


-- ----------------------------------------------------------------------------
-- 3. Sentiment trend by week and month
-- ----------------------------------------------------------------------------
WITH weekly_sentiment AS (
    SELECT
        DATE_TRUNC('week', created_at)::DATE AS period_start,
        'week' AS period_grain,
        sentiment,
        COUNT(*) AS review_count
    FROM analytics.master_enriched
    WHERE created_at IS NOT NULL
    GROUP BY DATE_TRUNC('week', created_at), sentiment
),
monthly_sentiment AS (
    SELECT
        DATE_TRUNC('month', created_at)::DATE AS period_start,
        'month' AS period_grain,
        sentiment,
        COUNT(*) AS review_count
    FROM analytics.master_enriched
    WHERE created_at IS NOT NULL
    GROUP BY DATE_TRUNC('month', created_at), sentiment
)
SELECT period_start, period_grain, sentiment, review_count FROM weekly_sentiment
UNION ALL
SELECT period_start, period_grain, sentiment, review_count FROM monthly_sentiment
ORDER BY period_grain, period_start, sentiment;


-- ----------------------------------------------------------------------------
-- 4. Negative reviews by category (target class)
-- ----------------------------------------------------------------------------
SELECT
    category,
    COUNT(*) AS negative_review_count
FROM analytics.master_enriched
WHERE sentiment = 'negative'
GROUP BY category
ORDER BY negative_review_count DESC, category;


-- ----------------------------------------------------------------------------
-- 5. Top complaint topics (keyword search on review text)
-- ----------------------------------------------------------------------------
WITH complaint_keywords AS (
    SELECT unnest(ARRAY['bad', 'poor', 'broken', 'refund', 'delay']) AS keyword
),
matched AS (
    SELECT ck.keyword, m.row_id
    FROM analytics.master_enriched AS m
    CROSS JOIN complaint_keywords AS ck
    WHERE m.review_text IS NOT NULL
      AND LOWER(m.review_text) LIKE '%' || ck.keyword || '%'
)
SELECT
    keyword,
    COUNT(DISTINCT row_id) AS review_mentions,
    COUNT(*) AS keyword_occurrences
FROM matched
GROUP BY keyword
ORDER BY review_mentions DESC, keyword;


-- ----------------------------------------------------------------------------
-- 6. Region-wise sentiment (user as region / author dimension)
-- ----------------------------------------------------------------------------
SELECT
    region,
    COUNT(*) FILTER (WHERE sentiment = 'positive') AS positive_count,
    COUNT(*) FILTER (WHERE sentiment = 'neutral')  AS neutral_count,
    COUNT(*) FILTER (WHERE sentiment = 'negative') AS negative_count,
    COUNT(*) AS total_reviews
FROM analytics.master_enriched
GROUP BY region
ORDER BY total_reviews DESC, region
LIMIT 50;


-- ----------------------------------------------------------------------------
-- 7. Product rating vs sentiment (target class as rating + sentiment mix)
-- ----------------------------------------------------------------------------
WITH stats AS (
    SELECT
        product_name,
        category,
        AVG(rating) AS avg_rating,
        COUNT(*) FILTER (WHERE sentiment = 'positive') AS positive_count,
        COUNT(*) FILTER (WHERE sentiment = 'neutral')  AS neutral_count,
        COUNT(*) FILTER (WHERE sentiment = 'negative') AS negative_count,
        COUNT(*) AS total_reviews
    FROM analytics.master_enriched
    GROUP BY product_name, category
)
SELECT
    product_name,
    category,
    ROUND(avg_rating::NUMERIC, 2) AS avg_rating,
    positive_count,
    neutral_count,
    negative_count,
    total_reviews,
    ROUND(100.0 * positive_count / NULLIF(total_reviews, 0), 2) AS positive_pct,
    ROUND(100.0 * neutral_count  / NULLIF(total_reviews, 0), 2) AS neutral_pct,
    ROUND(100.0 * negative_count / NULLIF(total_reviews, 0), 2) AS negative_pct
FROM stats
ORDER BY avg_rating DESC NULLS LAST, total_reviews DESC;


-- ----------------------------------------------------------------------------
-- 8. Most reviewed products (top sentiment classes by volume)
-- ----------------------------------------------------------------------------
SELECT
    product_name,
    category,
    brand,
    COUNT(*) AS review_count
FROM analytics.master_enriched
GROUP BY product_name, category, brand
ORDER BY review_count DESC, product_name
LIMIT 10;


-- ----------------------------------------------------------------------------
-- 9. Latest negative reviews
-- ----------------------------------------------------------------------------
SELECT
    row_id,
    product_name,
    review_text,
    created_at,
    "user"
FROM analytics.master_enriched
WHERE sentiment = 'negative'
ORDER BY created_at DESC NULLS LAST, row_id DESC
LIMIT 20;


-- ----------------------------------------------------------------------------
-- 10. Brand-wise sentiment comparison (flag column as brand proxy)
-- ----------------------------------------------------------------------------
WITH brand_stats AS (
    SELECT
        brand,
        COUNT(*) AS total_reviews,
        COUNT(*) FILTER (WHERE sentiment = 'positive') AS positive_count,
        COUNT(*) FILTER (WHERE sentiment = 'neutral')  AS neutral_count,
        COUNT(*) FILTER (WHERE sentiment = 'negative') AS negative_count
    FROM analytics.master_enriched
    GROUP BY brand
)
SELECT
    brand,
    total_reviews,
    ROUND(100.0 * positive_count / NULLIF(total_reviews, 0), 2) AS positive_pct,
    ROUND(100.0 * negative_count / NULLIF(total_reviews, 0), 2) AS negative_pct,
    ROUND(100.0 * neutral_count  / NULLIF(total_reviews, 0), 2) AS neutral_pct
FROM brand_stats
ORDER BY total_reviews DESC, brand;


-- ----------------------------------------------------------------------------
-- 11. Average rating by category
-- ----------------------------------------------------------------------------
SELECT
    category,
    ROUND(AVG(rating)::NUMERIC, 2) AS avg_rating,
    COUNT(*) AS review_count
FROM analytics.master_enriched
WHERE rating IS NOT NULL
GROUP BY category
ORDER BY avg_rating DESC NULLS LAST, category;


-- ----------------------------------------------------------------------------
-- 12. Review volume trend — daily, last 90 days
-- ----------------------------------------------------------------------------
WITH bounds AS (
    SELECT MAX(created_at) AS max_created_at
    FROM analytics.master_enriched
    WHERE created_at IS NOT NULL
),
daily_counts AS (
    SELECT
        DATE_TRUNC('day', m.created_at)::DATE AS review_day,
        COUNT(*) AS review_count
    FROM analytics.master_enriched AS m
    CROSS JOIN bounds AS b
    WHERE m.created_at IS NOT NULL
      AND m.created_at >= b.max_created_at - INTERVAL '90 days'
    GROUP BY DATE_TRUNC('day', m.created_at)
)
SELECT review_day, review_count
FROM daily_counts
ORDER BY review_day;
