-- ==============================================================================
-- Stripe Sigma Queries for Zombie Subscription Detection
-- ==============================================================================
-- These queries should be run in Stripe Sigma dashboard to analyze subscription
-- usage patterns and identify potential zombie accounts.
-- ==============================================================================

-- -----------------------------------------------------------------------------
-- Query 1: Active Subscriptions Summary
-- -----------------------------------------------------------------------------
-- Shows all active subscriptions with key metrics
-- Use this to get a baseline of all paying customers

SELECT
  s.id AS subscription_id,
  c.id AS customer_id,
  c.email,
  c.created AS customer_created_date,
  s.created AS subscription_created_date,
  s.current_period_start,
  s.current_period_end,
  s.status,
  p.id AS plan_id,
  p.nickname AS plan_name,
  (p.amount / 100.0) AS plan_amount_usd,
  p.interval AS billing_interval,
  s.cancel_at_period_end,
  DATEDIFF(NOW(), s.created) AS subscription_age_days,
  DATEDIFF(NOW(), c.created) AS customer_age_days
FROM subscriptions s
JOIN customers c ON s.customer = c.id
JOIN plans p ON s.plan = p.id
WHERE s.status IN ('active', 'trialing')
ORDER BY s.created DESC;


-- -----------------------------------------------------------------------------
-- Query 2: Zombie Candidate Detection - No Recent Charges
-- -----------------------------------------------------------------------------
-- Identifies subscriptions with successful payments but no usage indicators
-- Zombie criteria: Active subscription, but no API activity correlation

SELECT
  s.id AS subscription_id,
  c.id AS customer_id,
  c.email,
  c.metadata AS customer_metadata,
  s.created AS subscription_created_date,
  (p.amount / 100.0) AS monthly_amount_usd,
  p.interval,
  COUNT(ch.id) AS total_charges,
  MAX(ch.created) AS last_charge_date,
  DATEDIFF(NOW(), MAX(ch.created)) AS days_since_last_charge,
  SUM(CASE WHEN ch.status = 'succeeded' THEN 1 ELSE 0 END) AS successful_charges,
  SUM(CASE WHEN ch.status = 'succeeded' THEN (ch.amount / 100.0) ELSE 0 END) AS total_revenue_usd
FROM subscriptions s
JOIN customers c ON s.customer = c.id
JOIN plans p ON s.plan = p.id
LEFT JOIN charges ch ON ch.customer = c.id
WHERE s.status = 'active'
  AND s.created < DATE_SUB(NOW(), INTERVAL 30 DAY)  -- At least 30 days old
GROUP BY s.id, c.id, c.email, c.metadata, s.created, p.amount, p.interval
HAVING successful_charges > 0
ORDER BY total_revenue_usd DESC;


-- -----------------------------------------------------------------------------
-- Query 3: MRR Analysis by Subscription Age Cohorts
-- -----------------------------------------------------------------------------
-- Analyzes Monthly Recurring Revenue by how long subscriptions have been active
-- Helps identify which cohorts have the most zombie risk

SELECT
  CASE
    WHEN DATEDIFF(NOW(), s.created) <= 30 THEN '0-30 days'
    WHEN DATEDIFF(NOW(), s.created) <= 90 THEN '31-90 days'
    WHEN DATEDIFF(NOW(), s.created) <= 180 THEN '91-180 days'
    WHEN DATEDIFF(NOW(), s.created) <= 365 THEN '181-365 days'
    ELSE '365+ days'
  END AS subscription_age_cohort,
  COUNT(DISTINCT s.id) AS subscription_count,
  SUM(CASE WHEN p.interval = 'month' THEN (p.amount / 100.0)
           WHEN p.interval = 'year' THEN (p.amount / 100.0 / 12)
           ELSE 0 END) AS estimated_mrr_usd,
  AVG(p.amount / 100.0) AS avg_plan_amount_usd,
  MIN(s.created) AS oldest_subscription,
  MAX(s.created) AS newest_subscription
FROM subscriptions s
JOIN plans p ON s.plan = p.id
WHERE s.status = 'active'
GROUP BY subscription_age_cohort
ORDER BY
  CASE subscription_age_cohort
    WHEN '0-30 days' THEN 1
    WHEN '31-90 days' THEN 2
    WHEN '91-180 days' THEN 3
    WHEN '181-365 days' THEN 4
    ELSE 5
  END;


-- -----------------------------------------------------------------------------
-- Query 4: Subscription Retention by Plan
-- -----------------------------------------------------------------------------
-- Shows retention rates and identifies which plans have higher zombie rates

SELECT
  p.id AS plan_id,
  p.nickname AS plan_name,
  (p.amount / 100.0) AS plan_amount_usd,
  COUNT(DISTINCT s.id) AS active_subscriptions,
  COUNT(DISTINCT CASE WHEN s.cancel_at_period_end THEN s.id END) AS pending_cancellations,
  AVG(DATEDIFF(NOW(), s.created)) AS avg_subscription_age_days,
  SUM(CASE WHEN p.interval = 'month' THEN (p.amount / 100.0)
           WHEN p.interval = 'year' THEN (p.amount / 100.0 / 12)
           ELSE 0 END) AS total_mrr_usd
FROM subscriptions s
JOIN plans p ON s.plan = p.id
WHERE s.status = 'active'
GROUP BY p.id, p.nickname, p.amount
ORDER BY total_mrr_usd DESC;


-- -----------------------------------------------------------------------------
-- Query 5: Payment Success Rate Analysis
-- -----------------------------------------------------------------------------
-- Identifies customers with payment issues that might indicate disengagement

SELECT
  c.id AS customer_id,
  c.email,
  s.id AS subscription_id,
  COUNT(ch.id) AS total_charge_attempts,
  SUM(CASE WHEN ch.status = 'succeeded' THEN 1 ELSE 0 END) AS successful_charges,
  SUM(CASE WHEN ch.status = 'failed' THEN 1 ELSE 0 END) AS failed_charges,
  (SUM(CASE WHEN ch.status = 'succeeded' THEN 1 ELSE 0 END) * 100.0 / COUNT(ch.id)) AS success_rate_pct,
  MAX(ch.created) AS last_charge_attempt,
  SUM(CASE WHEN ch.status = 'succeeded' THEN (ch.amount / 100.0) ELSE 0 END) AS total_revenue_usd
FROM customers c
JOIN subscriptions s ON s.customer = c.id
LEFT JOIN charges ch ON ch.customer = c.id
WHERE s.status = 'active'
  AND ch.created IS NOT NULL
GROUP BY c.id, c.email, s.id
HAVING total_charge_attempts >= 2
ORDER BY success_rate_pct ASC, failed_charges DESC;


-- -----------------------------------------------------------------------------
-- Query 6: Recently Created Subscriptions (30 days)
-- -----------------------------------------------------------------------------
-- New subscriptions to monitor for early zombie warning signs

SELECT
  s.id AS subscription_id,
  c.email,
  s.created AS subscription_created_date,
  s.status,
  p.nickname AS plan_name,
  (p.amount / 100.0) AS plan_amount_usd,
  DATEDIFF(NOW(), s.created) AS days_old,
  COUNT(ch.id) AS charge_count,
  s.metadata AS subscription_metadata
FROM subscriptions s
JOIN customers c ON s.customer = c.id
JOIN plans p ON s.plan = p.id
LEFT JOIN charges ch ON ch.customer = c.id AND ch.created >= s.created
WHERE s.created >= DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND s.status IN ('active', 'trialing')
GROUP BY s.id, c.email, s.created, s.status, p.nickname, p.amount, s.metadata
ORDER BY s.created DESC;


-- -----------------------------------------------------------------------------
-- Query 7: Churn Risk by Failed Payment Patterns
-- -----------------------------------------------------------------------------
-- Customers with recent failed payments may be zombies waiting to churn

SELECT
  c.id AS customer_id,
  c.email,
  s.id AS subscription_id,
  s.status AS subscription_status,
  COUNT(CASE WHEN ch.status = 'failed'
             AND ch.created >= DATE_SUB(NOW(), INTERVAL 90 DAY)
        THEN ch.id END) AS recent_failures,
  MAX(CASE WHEN ch.status = 'failed' THEN ch.created END) AS last_failure_date,
  MAX(CASE WHEN ch.status = 'succeeded' THEN ch.created END) AS last_success_date,
  (p.amount / 100.0) AS plan_amount_usd,
  p.nickname AS plan_name
FROM customers c
JOIN subscriptions s ON s.customer = c.id
LEFT JOIN charges ch ON ch.customer = c.id
JOIN plans p ON s.plan = p.id
WHERE s.status = 'active'
GROUP BY c.id, c.email, s.id, s.status, p.amount, p.nickname
HAVING recent_failures > 0
ORDER BY recent_failures DESC, last_failure_date DESC;


-- -----------------------------------------------------------------------------
-- Query 8: Revenue at Risk - Zombie MRR Estimate
-- -----------------------------------------------------------------------------
-- Estimates potential revenue from subscriptions older than 60 days
-- These are candidates for zombie status if no usage detected

SELECT
  'Zombie Risk Analysis' AS category,
  COUNT(DISTINCT s.id) AS at_risk_subscriptions,
  SUM(CASE WHEN p.interval = 'month' THEN (p.amount / 100.0)
           WHEN p.interval = 'year' THEN (p.amount / 100.0 / 12)
           ELSE 0 END) AS potential_zombie_mrr_usd,
  AVG(DATEDIFF(NOW(), s.created)) AS avg_subscription_age_days,
  MIN(s.created) AS oldest_subscription_date
FROM subscriptions s
JOIN plans p ON s.plan = p.id
WHERE s.status = 'active'
  AND s.created < DATE_SUB(NOW(), INTERVAL 60 DAY)
  AND NOT s.cancel_at_period_end;


-- -----------------------------------------------------------------------------
-- Query 9: Customer Lifetime Value for Active Subscriptions
-- -----------------------------------------------------------------------------
-- Calculate total revenue per active subscription to prioritize re-engagement

SELECT
  c.id AS customer_id,
  c.email,
  s.id AS subscription_id,
  s.created AS subscription_start_date,
  DATEDIFF(NOW(), s.created) AS subscription_age_days,
  (p.amount / 100.0) AS current_plan_amount_usd,
  COUNT(ch.id) AS total_charges,
  SUM(CASE WHEN ch.status = 'succeeded' THEN (ch.amount / 100.0) ELSE 0 END) AS lifetime_revenue_usd,
  (SUM(CASE WHEN ch.status = 'succeeded' THEN (ch.amount / 100.0) ELSE 0 END) /
   NULLIF(DATEDIFF(NOW(), s.created) / 30.0, 0)) AS avg_monthly_revenue_usd
FROM subscriptions s
JOIN customers c ON s.customer = c.id
JOIN plans p ON s.plan = p.id
LEFT JOIN charges ch ON ch.customer = c.id AND ch.created >= s.created
WHERE s.status = 'active'
GROUP BY c.id, c.email, s.id, s.created, p.amount
HAVING lifetime_revenue_usd > 0
ORDER BY lifetime_revenue_usd DESC;


-- -----------------------------------------------------------------------------
-- Query 10: Subscription Status Distribution
-- -----------------------------------------------------------------------------
-- Overview of all subscription statuses to understand overall health

SELECT
  s.status,
  COUNT(DISTINCT s.id) AS subscription_count,
  COUNT(DISTINCT c.id) AS customer_count,
  SUM(CASE WHEN p.interval = 'month' THEN (p.amount / 100.0)
           WHEN p.interval = 'year' THEN (p.amount / 100.0 / 12)
           ELSE 0 END) AS estimated_mrr_usd,
  (COUNT(DISTINCT s.id) * 100.0 / (SELECT COUNT(*) FROM subscriptions)) AS pct_of_total
FROM subscriptions s
JOIN customers c ON s.customer = c.id
JOIN plans p ON s.plan = p.id
GROUP BY s.status
ORDER BY subscription_count DESC;


-- ==============================================================================
-- USAGE INSTRUCTIONS
-- ==============================================================================
--
-- 1. Log into Stripe Dashboard → Reports → Query data (Sigma)
-- 2. Create a new query
-- 3. Copy and paste each query above individually
-- 4. Run the query and export results as CSV
-- 5. Import CSV data into the zombie detection system for correlation with
--    application-level usage metrics (secrets created, logins, etc.)
--
-- CORRELATION STRATEGY:
-- - Export Query 2 results (customer emails and subscription data)
-- - Match Stripe customer emails with application Customer records
-- - Compare Stripe billing data against app usage metrics:
--   * secrets_created
--   * secrets_shared
--   * last_login
--   * session activity
-- - Identify discrepancies: active billing + low/zero usage = zombie
--
-- ==============================================================================
