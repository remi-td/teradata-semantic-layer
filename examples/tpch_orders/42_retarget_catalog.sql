-- =========================================================================
-- Retarget catalog datasets from the non-existent 'tpch' database to
-- 'demo_user' where the sample tables now live. Affects TPC-H scenarios
-- only; the exec_dashboard cube uses source_query so it's unaffected.
-- =========================================================================

UPDATE demo_user.DATASET
   SET DataBaseName = 'demo_user'
 WHERE DataBaseName = 'tpch';
