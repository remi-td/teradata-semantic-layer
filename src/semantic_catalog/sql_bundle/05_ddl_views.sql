-- =========================================================================
-- MODEL_DATASET: n:n junction between SEMANTIC_MODEL and DATASET.
-- Replaces the old model_id FK on DATASET, enabling dataset sharing
-- across models (e.g. supplier_risk_v2 reusing tpch_orders datasets).
-- =========================================================================

CREATE MULTISET TABLE demo_user.MODEL_DATASET, FALLBACK (
    model_id    INTEGER NOT NULL,
    dataset_id  INTEGER NOT NULL,
    is_primary  BYTEINT DEFAULT 0 NOT NULL
)
PRIMARY INDEX (model_id)
UNIQUE INDEX ux_model_dataset_pk (model_id, dataset_id);
