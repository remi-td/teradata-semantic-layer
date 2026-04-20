-- =========================================================================
-- sp_semantic_answer(model, metrics, dimensions, where_filters, having_filters,
--                    sort, row_limit, dry_run)
--
-- Single-CALL front-end for the semantic compiler, consumed by the
-- `sem_answer` MCP tool.
--
--   dry_run = 0  → compile + EXPLAIN + execute. Returns data rows whose
--                  columns are the requested dimensions and metrics.
--                  On compile failure, returns a single-row three-column
--                  result set (status, message, compiled_sql).
--   dry_run = 1  → compile only. Always returns a single-row five-column
--                  result set (status, message, compiled_sql, anchor_dataset,
--                  joined_datasets) for inspection / audit.
--
-- This wrapper exists to let the LOCKED-DOWN `semantic_guided` persona
-- execute compiled SQL through ONE governed tool, without being granted
-- free-form SQL access (no base_* tools).
--
-- Deploy order (after the base catalog is installed):
--     semantic-catalog deploy --mode whole --include mcp/sql/70_sp_semantic_answer
-- or  bteq < mcp/sql/70_sp_semantic_answer.sql
-- =========================================================================
REPLACE PROCEDURE demo_user.sp_semantic_answer(
    IN p_model_name     VARCHAR(200),
    IN p_metrics        VARCHAR(4000),
    IN p_dimensions     VARCHAR(4000),
    IN p_where_filters  VARCHAR(4000),
    IN p_having_filters VARCHAR(2000),
    IN p_sort           VARCHAR(500),
    IN p_row_limit      INTEGER,
    IN p_dry_run        BYTEINT
)
DYNAMIC RESULT SETS 1
BEGIN
    DECLARE v_sql     VARCHAR(30000) CHARACTER SET UNICODE;
    DECLARE v_valid   BYTEINT;
    DECLARE v_msg     VARCHAR(4000) CHARACTER SET UNICODE;
    DECLARE v_anchor  VARCHAR(200)  CHARACTER SET UNICODE;
    DECLARE v_joined  VARCHAR(4000) CHARACTER SET UNICODE;

    -- 1) Compile. Returns the plan via OUT parameters; no shared staging.
    CALL demo_user.sp_semantic_request(
        p_model_name, p_metrics, p_dimensions,
        p_where_filters, p_having_filters, p_sort, p_row_limit,
        v_sql, v_valid, v_msg, v_anchor, v_joined
    );

    -- 2) Inspect path — dry_run OR compile failed.
    IF p_dry_run = 1 OR v_valid IS NULL OR v_valid = 0 THEN
        BEGIN
            DECLARE c_plan CURSOR WITH RETURN FOR
                SELECT CASE WHEN v_valid = 1 THEN 'OK' ELSE 'ERROR' END AS status,
                       COALESCE(v_msg,'') AS message,
                       v_sql              AS compiled_sql,
                       v_anchor           AS anchor_dataset,
                       v_joined           AS joined_datasets;
            OPEN c_plan;
        END;
    ELSE
        -- 3) Execute path — run the compiled SQL and stream its rows.
        BEGIN
            DECLARE c_data CURSOR WITH RETURN FOR S_ANSWER;
            PREPARE S_ANSWER FROM v_sql;
            OPEN c_data;
        END;
    END IF;
END;
