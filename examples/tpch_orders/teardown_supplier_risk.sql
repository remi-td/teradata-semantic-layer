-- Teardown supplier_risk_v1 and supplier_risk_v2.
-- Removes metrics, MODEL_DATASET links, and the model rows.
-- Does NOT remove the underlying DATASET rows (they may be shared).
-- Run this to clean up after 14_supplier_risk.sql.

-- Remove metric expressions + field refs for supplier_risk models
DELETE FROM demo_user.METRIC_EXPRESSION
WHERE metric_id IN (
    SELECT mt.metric_id FROM demo_user.METRIC mt
    JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
    WHERE m.model_name IN ('supplier_risk_v1','supplier_risk_v2')
);

DELETE FROM demo_user.METRIC_FIELD_REF
WHERE metric_id IN (
    SELECT mt.metric_id FROM demo_user.METRIC mt
    JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
    WHERE m.model_name IN ('supplier_risk_v1','supplier_risk_v2')
);

-- Remove metrics
DELETE FROM demo_user.METRIC
WHERE model_id IN (
    SELECT model_id FROM demo_user.SEMANTIC_MODEL
    WHERE model_name IN ('supplier_risk_v1','supplier_risk_v2')
);

-- Remove AI_CONTEXT for models and the cube dataset
DELETE FROM demo_user.AI_CONTEXT
WHERE (entity_type='MODEL' AND entity_id IN (
    SELECT model_id FROM demo_user.SEMANTIC_MODEL
    WHERE model_name IN ('supplier_risk_v1','supplier_risk_v2')
))
OR (entity_type='DATASET' AND entity_id IN (
    SELECT dataset_id FROM demo_user.DATASET WHERE dataset_name='supplier_risk_cube'
));

-- Remove MODEL_DATASET links for both versions
DELETE FROM demo_user.MODEL_DATASET
WHERE model_id IN (
    SELECT model_id FROM demo_user.SEMANTIC_MODEL
    WHERE model_name IN ('supplier_risk_v1','supplier_risk_v2')
);

-- Remove fields on the v1 cube dataset
DELETE FROM demo_user.FIELD
WHERE dataset_id IN (
    SELECT dataset_id FROM demo_user.DATASET WHERE dataset_name='supplier_risk_cube'
);

-- Remove the v1 cube dataset itself
DELETE FROM demo_user.DATASET WHERE dataset_name='supplier_risk_cube';

-- Remove the model rows
DELETE FROM demo_user.SEMANTIC_MODEL
WHERE model_name IN ('supplier_risk_v1','supplier_risk_v2');
