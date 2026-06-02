-- Remove all catalog rows for model 'tpch_orders'. Deletes are leaf-to-root to
-- respect integrity. Run via: semantic-catalog uninstall-example tpch_orders

DELETE FROM demo_user.METRIC_FIELD_REF
 WHERE metric_id IN (SELECT metric_id FROM demo_user.METRIC mt
                     INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
                     WHERE m.model_name = 'tpch_orders');

DELETE FROM demo_user.METRIC_EXPRESSION
 WHERE metric_id IN (SELECT metric_id FROM demo_user.METRIC mt
                     INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
                     WHERE m.model_name = 'tpch_orders');

DELETE FROM demo_user.FORMAT_SPEC
 WHERE (entity_type='METRIC' AND entity_id IN (SELECT metric_id FROM demo_user.METRIC mt
           INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
           WHERE m.model_name = 'tpch_orders'))
    OR (entity_type='DATASET' AND entity_id IN (SELECT d.dataset_id FROM demo_user.DATASET d
           INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
           WHERE m.model_name = 'tpch_orders'))
    OR (entity_type='FIELD' AND entity_id IN (SELECT f.field_id FROM demo_user.FIELD f
           INNER JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
           INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
           WHERE m.model_name = 'tpch_orders'))
    OR (entity_type='MODEL' AND entity_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL
           WHERE model_name = 'tpch_orders'));

DELETE FROM demo_user.CUSTOM_EXTENSION
 WHERE (entity_type='DATASET' AND entity_id IN (SELECT d.dataset_id FROM demo_user.DATASET d
           INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
           WHERE m.model_name = 'tpch_orders'))
    OR (entity_type='FIELD' AND entity_id IN (SELECT f.field_id FROM demo_user.FIELD f
           INNER JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
           INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
           WHERE m.model_name = 'tpch_orders'))
    OR (entity_type='MODEL' AND entity_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL
           WHERE model_name = 'tpch_orders'));

DELETE FROM demo_user.METRIC
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name = 'tpch_orders');

DELETE FROM demo_user.VIEW_MEMBER
 WHERE view_id IN (SELECT view_id FROM demo_user.SEMANTIC_VIEW v
                   INNER JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
                   WHERE m.model_name = 'tpch_orders');

DELETE FROM demo_user.SEMANTIC_VIEW
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name = 'tpch_orders');

DELETE FROM demo_user.REL_COLUMN_MAP
 WHERE relationship_id IN (SELECT r.relationship_id FROM demo_user.RELATIONSHIP r
                           INNER JOIN demo_user.DATASET d ON r.from_dataset_id=d.dataset_id
                           INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
                           WHERE m.model_name = 'tpch_orders');

DELETE FROM demo_user.RELATIONSHIP
 WHERE from_dataset_id IN (SELECT d.dataset_id FROM demo_user.DATASET d
                           INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
                           WHERE m.model_name = 'tpch_orders');

DELETE FROM demo_user.DATASET_KEY
 WHERE dataset_id IN (SELECT d.dataset_id FROM demo_user.DATASET d
                      INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
                      WHERE m.model_name = 'tpch_orders');

DELETE FROM demo_user.FIELD
 WHERE dataset_id IN (SELECT d.dataset_id FROM demo_user.DATASET d
                      INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
                      WHERE m.model_name = 'tpch_orders');

DELETE FROM demo_user.AI_CONTEXT
 WHERE (entity_type='DATASET' AND entity_id IN (SELECT d.dataset_id FROM demo_user.DATASET d
           INNER JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
           WHERE m.model_name = 'tpch_orders'))
    OR (entity_type='METRIC' AND entity_id IN (SELECT metric_id FROM demo_user.METRIC mt
           INNER JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
           WHERE m.model_name = 'tpch_orders'))
    OR (entity_type='MODEL' AND entity_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL
           WHERE model_name = 'tpch_orders'));

DELETE FROM demo_user.SECURITY_POLICY
 WHERE entity_type='MODEL' AND entity_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL
                                             WHERE model_name = 'tpch_orders');

DELETE FROM demo_user.DATASET
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name = 'tpch_orders');

DELETE FROM demo_user.SEMANTIC_MODEL WHERE model_name = 'tpch_orders';

-- Physical sample tables (tolerant — may not exist on first install)
DROP TABLE lineitem;
DROP TABLE partsupp;
DROP TABLE orders;
DROP TABLE customer;
DROP TABLE supplier;
DROP TABLE part;
DROP TABLE nation;
DROP TABLE region;
