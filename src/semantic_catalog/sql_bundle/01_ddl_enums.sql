-- =========================================================================
-- Enumeration / reference tables for the semantic catalog.
-- These hold the small, fixed vocabularies referenced by catalog entities.
-- =========================================================================

CREATE MULTISET TABLE demo_user.DIALECT_ENUM, FALLBACK (
    dialect       VARCHAR(50) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description   VARCHAR(500) CHARACTER SET UNICODE,
    sort_order    SMALLINT NOT NULL
)
UNIQUE PRIMARY INDEX (dialect);

CREATE MULTISET TABLE demo_user.VENDOR_ENUM, FALLBACK (
    vendor_name   VARCHAR(50) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description   VARCHAR(500) CHARACTER SET UNICODE,
    sort_order    SMALLINT NOT NULL
)
UNIQUE PRIMARY INDEX (vendor_name);

CREATE MULTISET TABLE demo_user.FIELD_TYPE_ENUM, FALLBACK (
    field_type_code  CHAR(1) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    field_type_name  VARCHAR(50) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description      VARCHAR(500) CHARACTER SET UNICODE
)
UNIQUE PRIMARY INDEX (field_type_code);

CREATE MULTISET TABLE demo_user.METRIC_TYPE_ENUM, FALLBACK (
    metric_type   VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description   VARCHAR(500) CHARACTER SET UNICODE,
    sort_order    SMALLINT NOT NULL
)
UNIQUE PRIMARY INDEX (metric_type);

CREATE MULTISET TABLE demo_user.CARDINALITY_ENUM, FALLBACK (
    cardinality   VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description   VARCHAR(500) CHARACTER SET UNICODE,
    sort_order    SMALLINT NOT NULL
)
UNIQUE PRIMARY INDEX (cardinality);
