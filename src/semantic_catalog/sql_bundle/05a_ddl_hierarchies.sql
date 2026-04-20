-- =========================================================================
-- Dimension hierarchy metadata: FIELD_HIERARCHY, FIELD_HIERARCHY_LEVEL.
--
-- A hierarchy is a named ordered chain of FIELDs (typically LVL1, LVL2, ...
-- denormalized columns on a single dim dataset, or parent/child columns
-- across datasets) that represents a drill-up/drill-down path.
--
-- This is metadata only — the compiler does NOT rewrite queries based on
-- hierarchies. It exists so agents and the GUI can surface "what rolls up
-- to what" without having to infer it from naming conventions.
-- =========================================================================

CREATE MULTISET TABLE demo_user.FIELD_HIERARCHY, FALLBACK (
    hierarchy_id     INTEGER GENERATED ALWAYS AS IDENTITY
                         (START WITH 1 INCREMENT BY 1 MINVALUE 1
                          MAXVALUE 2147483647 NO CYCLE) NOT NULL,
    model_id         INTEGER NOT NULL,
    hierarchy_name   VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description      VARCHAR(10000) CHARACTER SET UNICODE,
    created_ts       TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX (hierarchy_id)
UNIQUE INDEX ux_fh_nk (model_id, hierarchy_name);

CREATE MULTISET TABLE demo_user.FIELD_HIERARCHY_LEVEL, FALLBACK (
    hierarchy_id     INTEGER NOT NULL,
    level_ord        SMALLINT NOT NULL,        -- 1 = top (most aggregated)
    field_id         INTEGER NOT NULL,
    level_name       VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC
)
PRIMARY INDEX (hierarchy_id)
UNIQUE INDEX ux_fhl_pk (hierarchy_id, level_ord)
UNIQUE INDEX ux_fhl_field (hierarchy_id, field_id);
