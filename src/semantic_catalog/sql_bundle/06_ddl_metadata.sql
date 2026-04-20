-- =========================================================================
-- Polymorphic metadata tables: AI_CONTEXT, FORMAT_SPEC, SECURITY_POLICY,
-- CUSTOM_EXTENSION.
-- These tables attach to any entity via (entity_type, entity_id).
-- =========================================================================

CREATE MULTISET TABLE demo_user.AI_CONTEXT, FALLBACK (
    entity_type    VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    entity_id      INTEGER NOT NULL,
    instructions   VARCHAR(10000) CHARACTER SET UNICODE,
    synonyms       JSON(8000) INLINE LENGTH 8000,
    examples       JSON(8000) INLINE LENGTH 8000,
    display_name   VARCHAR(500) CHARACTER SET UNICODE,
    created_ts     TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL,
    updated_ts     TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX ux_ai_ctx_pk (entity_type, entity_id);

CREATE MULTISET TABLE demo_user.FORMAT_SPEC, FALLBACK (
    entity_type     VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    entity_id       INTEGER NOT NULL,
    format_type     VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    currency_code   VARCHAR(10) CHARACTER SET UNICODE NOT CASESPECIFIC,
    decimal_places  SMALLINT,
    abbreviation    VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC,
    date_format     VARCHAR(50) CHARACTER SET UNICODE NOT CASESPECIFIC,
    custom_format   VARCHAR(200) CHARACTER SET UNICODE,
    created_ts      TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX ux_format_spec_pk (entity_type, entity_id);

CREATE MULTISET TABLE demo_user.SECURITY_POLICY, FALLBACK (
    entity_type        VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    entity_id          INTEGER NOT NULL,
    policy_ordinal     SMALLINT NOT NULL,
    policy_type        VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    group_name         VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    policy_expression  VARCHAR(10000) CHARACTER SET UNICODE,
    created_ts         TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
PRIMARY INDEX (entity_type, entity_id)
UNIQUE INDEX ux_security_policy_pk (entity_type, entity_id, policy_ordinal);

CREATE MULTISET TABLE demo_user.CUSTOM_EXTENSION, FALLBACK (
    entity_type     VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    entity_id       INTEGER NOT NULL,
    vendor_name     VARCHAR(50) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    extension_data  JSON(64000) INLINE LENGTH 32000,
    created_ts      TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
PRIMARY INDEX (entity_type, entity_id)
UNIQUE INDEX ux_custom_ext_pk (entity_type, entity_id, vendor_name);
