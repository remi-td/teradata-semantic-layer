-- =========================================================================
-- Collect statistics on PI / join / filter columns.
-- Runs empty (count=0) at this point; structures are created so that
-- subsequent COLLECT STATISTICS can refresh them after data loads.
-- =========================================================================

COLLECT STATISTICS COLUMN (model_id)          ON demo_user.SEMANTIC_MODEL;
COLLECT STATISTICS COLUMN (model_name)        ON demo_user.SEMANTIC_MODEL;

COLLECT STATISTICS COLUMN (dataset_id)        ON demo_user.DATASET;
COLLECT STATISTICS COLUMN (dataset_name)      ON demo_user.DATASET;
COLLECT STATISTICS COLUMN (DataBaseName, TableName) ON demo_user.DATASET;

COLLECT STATISTICS COLUMN (field_id)          ON demo_user.FIELD;
COLLECT STATISTICS COLUMN (dataset_id)        ON demo_user.FIELD;
COLLECT STATISTICS COLUMN (field_name)        ON demo_user.FIELD;
COLLECT STATISTICS COLUMN (is_dimension)      ON demo_user.FIELD;

COLLECT STATISTICS COLUMN (dataset_id)        ON demo_user.DATASET_KEY;
COLLECT STATISTICS COLUMN (field_id)          ON demo_user.DATASET_KEY;

COLLECT STATISTICS COLUMN (relationship_id)   ON demo_user.RELATIONSHIP;
COLLECT STATISTICS COLUMN (from_dataset_id)   ON demo_user.RELATIONSHIP;
COLLECT STATISTICS COLUMN (to_dataset_id)     ON demo_user.RELATIONSHIP;

COLLECT STATISTICS COLUMN (relationship_id)   ON demo_user.REL_COLUMN_MAP;
COLLECT STATISTICS COLUMN (from_field_id)     ON demo_user.REL_COLUMN_MAP;
COLLECT STATISTICS COLUMN (to_field_id)       ON demo_user.REL_COLUMN_MAP;

COLLECT STATISTICS COLUMN (metric_id)         ON demo_user.METRIC;
COLLECT STATISTICS COLUMN (model_id)          ON demo_user.METRIC;
COLLECT STATISTICS COLUMN (metric_name)       ON demo_user.METRIC;

COLLECT STATISTICS COLUMN (metric_id)         ON demo_user.METRIC_EXPRESSION;
COLLECT STATISTICS COLUMN (dialect)           ON demo_user.METRIC_EXPRESSION;

COLLECT STATISTICS COLUMN (metric_id)         ON demo_user.METRIC_FIELD_REF;
COLLECT STATISTICS COLUMN (field_id)          ON demo_user.METRIC_FIELD_REF;

COLLECT STATISTICS COLUMN (model_id)          ON demo_user.MODEL_DATASET;
COLLECT STATISTICS COLUMN (dataset_id)        ON demo_user.MODEL_DATASET;

COLLECT STATISTICS COLUMN (entity_type, entity_id) ON demo_user.AI_CONTEXT;
COLLECT STATISTICS COLUMN (entity_type, entity_id) ON demo_user.FORMAT_SPEC;
COLLECT STATISTICS COLUMN (entity_type, entity_id) ON demo_user.SECURITY_POLICY;
COLLECT STATISTICS COLUMN (entity_type, entity_id) ON demo_user.CUSTOM_EXTENSION;
