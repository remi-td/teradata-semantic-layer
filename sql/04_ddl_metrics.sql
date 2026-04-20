-- =========================================================================
-- Metric entities: METRIC, METRIC_EXPRESSION, METRIC_FIELD_REF.
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
    created_ts          TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL,
    updated_ts          TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX (metric_id)
INDEX ux_metric_nk (model_id, metric_name);

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
