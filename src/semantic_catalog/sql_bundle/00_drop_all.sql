-- Drop all catalog objects in reverse dependency order.
-- Each statement is independent; tq will stop at the first error, but these
-- are mainly for idempotent re-runs — on a clean sandbox they will all fail
-- with 3807 "object does not exist" and that is fine.

DROP VIEW demo_user.v_catalog_model_tree;
DROP VIEW demo_user.v_catalog_entity_index;
DROP PROCEDURE demo_user.sp_semantic_search;
DROP PROCEDURE demo_user.sp_semantic_request;
DROP PROCEDURE demo_user.sp_semantic_describe;
DROP PROCEDURE demo_user.sp_export_osi_yaml;
DROP PROCEDURE demo_user.sp_drop_if_exists;

-- Session-scoped GTTs (definitions live in the catalog even if data is per-session).
DROP TABLE demo_user.request_required_ds;
DROP TABLE demo_user.request_join_step;
DROP TABLE demo_user.request_metric;
DROP TABLE demo_user.request_dimension;
DROP TABLE demo_user.request_filter;
DROP TABLE demo_user.request_grain;
DROP TABLE demo_user.yaml_tmp;

DROP MACRO demo_user.m_semantic_search;
DROP MACRO demo_user.m_semantic_describe;

DROP TABLE demo_user.CUSTOM_EXTENSION;
DROP TABLE demo_user.SECURITY_POLICY;
DROP TABLE demo_user.FORMAT_SPEC;
DROP TABLE demo_user.AI_CONTEXT;
DROP TABLE demo_user.MODEL_DATASET;
-- Legacy tables (present in older installs; drop silently if missing):
DROP TABLE demo_user.VIEW_MEMBER;
DROP TABLE demo_user.SEMANTIC_VIEW;
DROP TABLE demo_user.METRIC_FILTER;
DROP TABLE demo_user.METRIC_FIELD_REF;
DROP TABLE demo_user.METRIC_EXPRESSION;
DROP TABLE demo_user.METRIC;
DROP TABLE demo_user.FIELD_HIERARCHY_LEVEL;
DROP TABLE demo_user.FIELD_HIERARCHY;
DROP TABLE demo_user.REL_COLUMN_MAP;
DROP TABLE demo_user.RELATIONSHIP;
DROP TABLE demo_user.DATASET_KEY;
DROP TABLE demo_user.FIELD;
DROP TABLE demo_user.DATASET;
DROP TABLE demo_user.SEMANTIC_MODEL;
DROP TABLE demo_user.CARDINALITY_ENUM;
DROP TABLE demo_user.METRIC_TYPE_ENUM;
DROP TABLE demo_user.FIELD_TYPE_ENUM;
DROP TABLE demo_user.VENDOR_ENUM;
DROP TABLE demo_user.DIALECT_ENUM;
