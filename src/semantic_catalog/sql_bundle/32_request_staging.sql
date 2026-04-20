-- =========================================================================
-- Staging tables for sp_semantic_request.
--
-- These are GLOBAL TEMPORARY TABLES: the definition is catalog-persistent
-- (so the stored procedure can reference them at compile time) while the
-- data is materialised per session. Two concurrent callers never see each
-- other's rows, which makes the compiler safe for 100s of concurrent users
-- on the same model without any cross-session lock.
--
-- ON COMMIT PRESERVE ROWS so ANSI-mode callers keep their staging data
-- across the implicit COMMIT that ends a stored-procedure call. The SP
-- truncates every table at the start of each invocation, so stale rows
-- from a prior call in the same session can't leak into the next.
-- =========================================================================

-- Required datasets for the current compile. Populated from metrics + dims.
CREATE GLOBAL TEMPORARY TABLE demo_user.request_required_ds (
    dataset_id    INTEGER NOT NULL,
    dataset_name  VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    reason        VARCHAR(500)  CHARACTER SET UNICODE,
    in_plan       BYTEINT DEFAULT 0 NOT NULL,
    alias         VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC
)
PRIMARY INDEX (dataset_id)
ON COMMIT PRESERVE ROWS;

-- Join chain in order. Row order = LEFT-to-RIGHT order of joins to emit.
CREATE GLOBAL TEMPORARY TABLE demo_user.request_join_step (
    step_ordinal      INTEGER NOT NULL,
    relationship_id   INTEGER,
    from_dataset_id   INTEGER,
    to_dataset_id     INTEGER,
    join_sql          VARCHAR(4000) CHARACTER SET UNICODE
)
PRIMARY INDEX (step_ordinal)
ON COMMIT PRESERVE ROWS;

-- Parsed metric list (with resolved TERADATA expression).
CREATE GLOBAL TEMPORARY TABLE demo_user.request_metric (
    metric_id     INTEGER NOT NULL,
    metric_name   VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    expression    VARCHAR(32000) CHARACTER SET UNICODE,
    primary_ds    INTEGER
)
PRIMARY INDEX (metric_id)
ON COMMIT PRESERVE ROWS;

-- Parsed dimension list.
CREATE GLOBAL TEMPORARY TABLE demo_user.request_dimension (
    field_id      INTEGER NOT NULL,
    dataset_id    INTEGER,
    dataset_name  VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    field_name    VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    expression    VARCHAR(10000) CHARACTER SET UNICODE,
    is_time       BYTEINT,
    grain         VARCHAR(20)  CHARACTER SET UNICODE,
    role_edge_id  INTEGER,
    alias         VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC
)
PRIMARY INDEX (field_id)
ON COMMIT PRESERVE ROWS;

-- Filter list (F2). WHERE vs HAVING selected by `kind`.
CREATE GLOBAL TEMPORARY TABLE demo_user.request_filter (
    ord           INTEGER NOT NULL,
    kind          VARCHAR(10)  CHARACTER SET UNICODE NOT NULL,
    left_token    VARCHAR(400) CHARACTER SET UNICODE NOT NULL,
    op            VARCHAR(10)  CHARACTER SET UNICODE,
    rhs           VARCHAR(4000) CHARACTER SET UNICODE,
    dataset_id    INTEGER,
    role_edge_id  INTEGER,
    resolved_left VARCHAR(400) CHARACTER SET UNICODE
)
PRIMARY INDEX (ord)
ON COMMIT PRESERVE ROWS;

-- Per-grain sub-SELECTs (F6 chasm split).
CREATE GLOBAL TEMPORARY TABLE demo_user.request_grain (
    grain_ord        INTEGER NOT NULL,
    grain_dataset_id INTEGER NOT NULL,
    grain_alias      VARCHAR(10) CHARACTER SET UNICODE NOT NULL,
    subquery_sql     VARCHAR(32000) CHARACTER SET UNICODE
)
PRIMARY INDEX (grain_ord)
ON COMMIT PRESERVE ROWS;
