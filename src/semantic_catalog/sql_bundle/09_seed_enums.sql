-- =========================================================================
-- Seed reference / enum tables.
-- =========================================================================

INSERT INTO demo_user.DIALECT_ENUM (dialect, description, sort_order) VALUES ('TERADATA', 'Teradata native SQL dialect.', 1);
INSERT INTO demo_user.DIALECT_ENUM (dialect, description, sort_order) VALUES ('ANSI_SQL', 'Portable ANSI SQL (used for OSI projection).', 2);

INSERT INTO demo_user.VENDOR_ENUM (vendor_name, description, sort_order) VALUES ('TERADATA', 'Teradata-specific custom extensions.', 1);
INSERT INTO demo_user.VENDOR_ENUM (vendor_name, description, sort_order) VALUES ('COMMON', 'Vendor-neutral / cross-platform extension payloads.', 2);

INSERT INTO demo_user.FIELD_TYPE_ENUM (field_type_code, field_type_name, description) VALUES ('A', 'ATTRIBUTE', 'Non-key attribute or dimension.');
INSERT INTO demo_user.FIELD_TYPE_ENUM (field_type_code, field_type_name, description) VALUES ('K', 'KEY', 'Key field (primary or join column).');

INSERT INTO demo_user.METRIC_TYPE_ENUM (metric_type, description, sort_order) VALUES ('SIMPLE', 'Single aggregate expression over fields in the anchor dataset.', 1);
INSERT INTO demo_user.METRIC_TYPE_ENUM (metric_type, description, sort_order) VALUES ('RATIO', 'Ratio of two aggregate expressions.', 2);
INSERT INTO demo_user.METRIC_TYPE_ENUM (metric_type, description, sort_order) VALUES ('CUMULATIVE', 'Running / cumulative aggregate over a time dimension.', 3);
INSERT INTO demo_user.METRIC_TYPE_ENUM (metric_type, description, sort_order) VALUES ('DERIVED', 'Derived from other metrics (metric-of-metrics).', 4);

INSERT INTO demo_user.CARDINALITY_ENUM (cardinality, description, sort_order) VALUES ('MANY_TO_ONE', 'Many rows on the from side for each row on the to side.', 1);
INSERT INTO demo_user.CARDINALITY_ENUM (cardinality, description, sort_order) VALUES ('ONE_TO_ONE',  'At most one row on the from side per to row.', 2);
INSERT INTO demo_user.CARDINALITY_ENUM (cardinality, description, sort_order) VALUES ('ONE_TO_MANY', 'Many rows on the to side for each row on the from side.', 3);
INSERT INTO demo_user.CARDINALITY_ENUM (cardinality, description, sort_order) VALUES ('MANY_TO_MANY', 'Many-to-many (generally requires bridge).', 4);
