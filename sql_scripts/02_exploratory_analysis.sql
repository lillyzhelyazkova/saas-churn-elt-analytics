-- ====================================================================
-- FEATURE USAGE DUPLICATE EVALUATION
-- ====================================================================

-- Run during ELT pipeline development to isolate duplicate usage_id anomalies
SELECT *
FROM stg_feature_usage
WHERE usage_id IN (
    SELECT usage_id
	FROM stg_feature_usage
	GROUP BY usage_id
	HAVING COUNT(*) > 1
)
ORDER BY usage_id;

-- ====================================================================
-- SANITY CHECK
-- ====================================================================

-- Calculates baseline totals to secure accurate numbers in PowerBI
SELECT (SELECT COUNT(*) FROM dim_accounts) AS total_accounts,
       (SELECT COUNT(*) FROM fact_churn_events) AS total_churn_events,
	   (SELECT COUNT(*) FROM fact_subscriptions) AS total_subscriptions,
	   (SELECT COUNT(*) FROM fact_feature_usage) AS total_feature_usage,
	   (SELECT COUNT(*) FROM fact_support_tickets) AS total_tickets,
	   (SELECT SUM(mrr_amount) FROM fact_subscriptions) AS total_mrr;
	   
-- ====================================================================
-- DATA INTEGRITY GAPS IDENTIFICATION
-- ====================================================================

-- Identifies 214 churned accounts missing from subscriptions table 
SELECT fce.churn_event_id,
       fce.account_id,
	   fce.reason_code,
	   fs.subscription_id AS matching_subscription_id,
	   fs.churn_flag AS subscriptions_churn_flag
FROM fact_churn_events fce
LEFT JOIN fact_subscriptions fs ON fce.account_id = fs.account_id AND fs.churn_flag = 1 -- Filters only canceled subscriptions
WHERE fs.account_id IS NULL; -- Identifies missing records in subscriptions fact table

-- Reveals that 168 missing accounts were paid tiers and 46 were free trials, exposing a billing tracking bug
SELECT da.is_trial,
       da.plan_tier,
	   COUNT(fce.churn_event_id) AS total_missing churns
FROM fact_churn_events fce
JOIN dim_accounts da ON fce.account_id = da.account_id
LEFT JOIN fact_subscriptions fs ON fce.account_id = fs.account_id AND fs.churn_flag = 1
WHERE fs.account_id IS NULL
GROUP BY da.is_trial, da.plan_tier;

-- ====================================================================
-- BUSINESS QUESTION QUERIES
-- ====================================================================

-- Monthly financial revenue loss and refunds
WITH average_mrr_calculations AS (
    SELECT AVG(mrr_amount) AS avg_mrr
	FROM fact_subscriptions
	WHERE is_trial = 0 AND mrr_amount > 0 -- Calculates average MRR per account
)
SELECT dc.year,
       dc.month,
	   fce.reason_code,
	   COUNT(DISTINCT fce.account_id) AS total_churned_accounts,
	   SUM(fce.refund_amount_usd) AS total_refunds,
	   SUM(COALESCE(fs.mrr_amount, -- Replaces missing values of paid accounts with average MRR
	   	                 CASE WHEN da.is_trial = 0
					     THEN (SELECT avg_mrr FROM average_mrr_calculations)
						 ELSE 0
						 END)) AS estimated_lost_mrr
FROM fact_churn_events fce
JOIN dim_accounts da ON fce.account_id = da.account_id
JOIN dim_calendar dc ON fce.churn_date = dc.date_id
LEFT JOIN fact_subscriptions fs ON fce.account_id = fs.account_id AND fs.churn_flag = 1
GROUP BY dc.year, dc.month, fce.reason_code
ORDER BY dc.year, dc.month, total_refunds DESC;

-- Product engagement by churn status					
SELECT da.churn_flag,
       COUNT(DISTINCT da.account_id) AS total_accounts,
	   ROUND(AVG(ffu.usage_count), 2) AS avg_daily_usage_count,
	   ROUND(AVG(ffu.usage_duration_secs) / 60.0, 2) AS avg_daily_usage_mins
FROM dim_accounts da
LEFT JOIN fact_subscriptions fs ON da.account_id = fs.account_id
LEFT JOIN fact_feature_usage ffu ON fs.subscription_id = ffu.subscription_id
GROUP BY da.churn_flag;

-- Average ticket volume per account by churn status
WITH account_ticket_counts AS (
    SELECT da.account_id,
	       da.churn_flag,
		   COUNT(fst.ticket_id) AS total_tickets
	FROM dim_accounts da
	LEFT JOIN fact_support_tickets fst ON da.account_id = fst.account_id
	GROUP BY da.account_id, da.churn_flag
)
SELECT churn_flag,
       COUNT(account_id) AS total_accounts,
	   ROUND(AVG(total_tickets), 1) AS avg_tickets_per_account,
	   MAX(total_tickets) AS max_tickets_per_account
FROM account_ticket_counts
GROUP BY churn_flag;
