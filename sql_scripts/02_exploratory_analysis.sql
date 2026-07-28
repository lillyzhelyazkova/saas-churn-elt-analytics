-- ====================================================================
-- DATA QUALITY AUDIT: FEATURE USAGE DUPLICATE EVALUATION
-- Run during development to isolate duplicate usage_id anomalies
-- ====================================================================

SELECT *
FROM stg_feature_usage
WHERE usage_id IN (
    SELECT usage_id
	FROM stg_feature_usage
	GROUP BY usage_id
	HAVING COUNT(*) > 1
)
ORDER BY usage_id;