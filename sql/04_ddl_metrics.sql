-- =========================================================================
-- Metric entities: METRIC, METRIC_EXPRESSION, METRIC_FIELD_REF, METRIC_FILTER.
--
-- Filtered metrics (Phase 1 design update) — a metric can be declared as
--   (base_metric_id, METRIC_FILTER[])
-- instead of an opaque SQL string. The compiler wraps the base's aggregate
-- inner expression in CASE WHEN <filters> THEN <inner> ELSE <zero/NULL> END.
-- This keeps curated KPIs (e.g. "net_interest_income" = amount filtered by
-- value_type='NII') declarative rather than a copy-pasted SQL blob.
-- =========================================================================

CREATE MULTISET TABLE demo_user.METRIC, FALLBACK (
    metric_id           INTEGER GENERATED ALWAYS AS IDENTITY
                            (START WITH 1 INCREMENT BY 1 MINVALUE 1
                             MAXVALUE 2147483647 NO CYCLE) NOT NULL,
    model_id            INTEGER NOT NULL,
    metric_name         VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description         VARCHAR(10000) CHARACTER SET UNICODE,
    primary_dataset_id  INTEGER,
    metric_type         VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC
                            DEFAULT 'SIMPLE' NOT NULL,
    is_additive         BYTEINT DEFAULT 1 NOT NULL,
    is_certified        BYTEINT DEFAULT 0 NOT NULL,
    owner_team          VARCHAR(200) CHARACTER SET UNICODE,
    default_time_grain  VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC,
    base_metric_id      INTEGER,
    aggregate_fn        VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC,
    aggregate_arg       VARCHAR(4000) CHARACTER SET UNICODE,
    created_ts          TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL,
    updated_ts          TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX (metric_id)
INDEX ux_metric_nk (model_id, metric_name)
INDEX ix_metric_base (base_metric_id);

CREATE MULTISET TABLE demo_user.METRIC_EXPRESSION, FALLBACK (
    metric_id   INTEGER NOT NULL,
    dialect     VARCHAR(50) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    expression  VARCHAR(32000) CHARACTER SET UNICODE NOT NULL
)
PRIMARY INDEX (metric_id)
UNIQUE INDEX ux_metric_expression_pk (metric_id, dialect);

CREATE MULTISET TABLE demo_user.METRIC_FIELD_REF, FALLBACK (
    metric_id   INTEGER NOT NULL,
    field_id    INTEGER NOT NULL,
    dep_role    VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC
                    DEFAULT 'MEASURE' NOT NULL
)
PRIMARY INDEX (metric_id)
UNIQUE INDEX ux_metric_field_ref_pk (metric_id, field_id, dep_role);

-- Filter predicates for "filtered rollup" metrics. A metric with
-- base_metric_id NOT NULL must have 1..N rows here. Each row contributes
-- an AND predicate in the compiled CASE WHEN.
CREATE MULTISET TABLE demo_user.METRIC_FILTER, FALLBACK (
    metric_id     INTEGER NOT NULL,
    filter_ord    SMALLINT NOT NULL,
    field_id      INTEGER NOT NULL,
    op            VARCHAR(10) CHARACTER SET UNICODE NOT CASESPECIFIC
                      DEFAULT '=' NOT NULL,
    filter_value  VARCHAR(500) CHARACTER SET UNICODE NOT NULL
)
PRIMARY INDEX (metric_id)
UNIQUE INDEX ux_metric_filter_pk (metric_id, filter_ord);
