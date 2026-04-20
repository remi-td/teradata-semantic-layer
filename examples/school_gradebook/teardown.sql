-- Remove school_gradebook catalog rows. Run BEFORE tearing down the
-- school_physical tables.

DELETE FROM demo_user.FIELD_HIERARCHY_LEVEL
 WHERE hierarchy_id IN (
    SELECT h.hierarchy_id FROM demo_user.FIELD_HIERARCHY h
    JOIN demo_user.SEMANTIC_MODEL m ON h.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.FIELD_HIERARCHY
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='school_gradebook');

DELETE FROM demo_user.METRIC_FILTER
 WHERE metric_id IN (
    SELECT mt.metric_id FROM demo_user.METRIC mt
    JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.METRIC_FIELD_REF
 WHERE metric_id IN (
    SELECT mt.metric_id FROM demo_user.METRIC mt
    JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.METRIC_EXPRESSION
 WHERE metric_id IN (
    SELECT mt.metric_id FROM demo_user.METRIC mt
    JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.METRIC
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='school_gradebook');
DELETE FROM demo_user.VIEW_MEMBER
 WHERE view_id IN (
    SELECT v.view_id FROM demo_user.SEMANTIC_VIEW v
    JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.SEMANTIC_VIEW
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='school_gradebook');
DELETE FROM demo_user.REL_COLUMN_MAP
 WHERE relationship_id IN (
    SELECT r.relationship_id FROM demo_user.RELATIONSHIP r
    JOIN demo_user.DATASET d ON d.dataset_id=r.from_dataset_id
    JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.RELATIONSHIP
 WHERE from_dataset_id IN (
    SELECT d.dataset_id FROM demo_user.DATASET d
    JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.DATASET_KEY
 WHERE dataset_id IN (
    SELECT d.dataset_id FROM demo_user.DATASET d
    JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.FIELD
 WHERE dataset_id IN (
    SELECT d.dataset_id FROM demo_user.DATASET d
    JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
    WHERE m.model_name='school_gradebook');
DELETE FROM demo_user.DATASET
 WHERE model_id IN (SELECT model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name='school_gradebook');
DELETE FROM demo_user.SEMANTIC_MODEL WHERE model_name='school_gradebook';
