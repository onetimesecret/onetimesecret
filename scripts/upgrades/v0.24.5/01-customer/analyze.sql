-- Customer dump analysis queries.
--
-- Cutoff: today minus 5 years. Adjust the date literal at the top if needed.
-- Run interactively:   sqlite3 customer_dump.db < analyze.sql
-- Or single query:     sqlite3 -header -column customer_dump.db "SELECT ..."

----------------------------------------------------------------------
-- 0. Sanity: row count, distinct custids, and overall date range.
----------------------------------------------------------------------
SELECT 'totals' AS section,
       COUNT(*)                 AS rows,
       COUNT(DISTINCT custid)   AS distinct_custids,
       MIN(created)             AS earliest_created,
       MAX(created)             AS latest_created,
       MIN(updated)             AS earliest_updated,
       MAX(updated)             AS latest_updated
FROM customers;

----------------------------------------------------------------------
-- 1. THE CRITICAL CHECK
-- How many rows were updated in the past 5 years? Should be zero
-- if the dump only contains stale records.
-- (TIMESTAMP is ISO 8601 UTC, so lexicographic compare works.)
----------------------------------------------------------------------
SELECT
  SUM(updated >= datetime('now', '-5 years'))                 AS updated_within_5y,
  SUM(updated <  datetime('now', '-5 years'))                 AS updated_older_than_5y,
  SUM(updated IS NULL)                                        AS updated_null,
  SUM(created >= datetime('now', '-5 years'))                 AS created_within_5y,
  SUM(created IS NULL)                                        AS created_null
FROM customers;

----------------------------------------------------------------------
-- 2. Sample any offenders so you can eyeball them.
----------------------------------------------------------------------
SELECT custid, created, updated,
       json_extract(object, '$.planid')   AS planid,
       json_extract(object, '$.verified') AS verified
FROM customers
WHERE updated >= datetime('now', '-5 years')
ORDER BY updated DESC
LIMIT 20;

----------------------------------------------------------------------
-- 3. Distribution by update year (where the activity sits).
----------------------------------------------------------------------
SELECT strftime('%Y', updated) AS year,
       COUNT(*)                AS rows
FROM customers
GROUP BY year
ORDER BY year;

----------------------------------------------------------------------
-- 4. Distribution by created year (when accounts were opened).
----------------------------------------------------------------------
SELECT strftime('%Y', created) AS year,
       COUNT(*)                AS rows
FROM customers
GROUP BY year
ORDER BY year;

----------------------------------------------------------------------
-- 5. Plan breakdown (planid lives inside the JSON blob).
----------------------------------------------------------------------
SELECT json_extract(object, '$.planid') AS planid,
       COUNT(*)                         AS rows
FROM customers
GROUP BY planid
ORDER BY rows DESC;

----------------------------------------------------------------------
-- 6. Verified vs unverified vs missing.
----------------------------------------------------------------------
SELECT json_extract(object, '$.verified') AS verified,
       COUNT(*)                           AS rows
FROM customers
GROUP BY verified
ORDER BY rows DESC;

----------------------------------------------------------------------
-- 7. Activity buckets — how big is each cohort by recency of update?
----------------------------------------------------------------------
SELECT CASE
         WHEN updated IS NULL                            THEN 'null'
         WHEN updated >= datetime('now', '-1 years')     THEN '0-1y'
         WHEN updated >= datetime('now', '-3 years')     THEN '1-3y'
         WHEN updated >= datetime('now', '-5 years')     THEN '3-5y'
         WHEN updated >= datetime('now', '-10 years')    THEN '5-10y'
         ELSE '>10y'
       END                AS age_bucket,
       COUNT(*)           AS rows
FROM customers
GROUP BY age_bucket
ORDER BY MIN(updated);

----------------------------------------------------------------------
-- 8. Rows where updated < created (likely data weirdness).
----------------------------------------------------------------------
SELECT COUNT(*) AS updated_before_created
FROM customers
WHERE updated IS NOT NULL
  AND created IS NOT NULL
  AND updated < created;

----------------------------------------------------------------------
-- 9. Field coverage in the JSON blob — which top-level keys appear,
-- and in how many rows. Useful before you trust json_extract paths.
----------------------------------------------------------------------
SELECT key,
       COUNT(*) AS rows
FROM customers, json_each(customers.object)
GROUP BY key
ORDER BY rows DESC;

----------------------------------------------------------------------
-- 10. Per year: how many rows have created == updated (never modified
-- after creation) vs differ (touched at least once after signup).
----------------------------------------------------------------------
SELECT strftime('%Y', created)                  AS year,
       SUM(created = updated)                   AS unchanged,
       SUM(created <> updated)                  AS modified,
       SUM(created IS NULL OR updated IS NULL)  AS null_either,
       COUNT(*)                                 AS total
FROM customers
GROUP BY year
ORDER BY year;
