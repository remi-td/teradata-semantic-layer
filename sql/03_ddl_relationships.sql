-- =========================================================================
-- Relationship entities: RELATIONSHIP, REL_COLUMN_MAP.
-- =========================================================================

CREATE MULTISET TABLE demo_user.RELATIONSHIP, FALLBACK (
    relationship_id      INTEGER GENERATED ALWAYS AS IDENTITY
                             (START WITH 1 INCREMENT BY 1 MINVALUE 1
                              MAXVALUE 2147483647 NO CYCLE) NOT NULL,
    from_dataset_id      INTEGER NOT NULL,
    to_dataset_id        INTEGER NOT NULL,
    relationship_name    VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    description          VARCHAR(10000) CHARACTER SET UNICODE,
    cardinality          VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC
                             DEFAULT 'MANY_TO_ONE' NOT NULL,
    join_type_hint       VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC
                             DEFAULT 'INNER' NOT NULL,
    role_name            VARCHAR(128) CHARACTER SET UNICODE NOT CASESPECIFIC,
    is_scd2              BYTEINT DEFAULT 0 NOT NULL,
    scd2_effective_col   VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    scd2_expiry_col      VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    created_ts           TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX (relationship_id)
INDEX ix_rel_from (from_dataset_id)
INDEX ix_rel_to (to_dataset_id)
UNIQUE INDEX ux_rel_nk (from_dataset_id, to_dataset_id, relationship_name)
UNIQUE INDEX ux_rel_role (from_dataset_id, to_dataset_id, role_name);

CREATE MULTISET TABLE demo_user.REL_COLUMN_MAP, FALLBACK (
    relationship_id   INTEGER NOT NULL,
    column_position   SMALLINT NOT NULL,
    from_field_id     INTEGER NOT NULL,
    to_field_id       INTEGER NOT NULL
)
PRIMARY INDEX (relationship_id)
UNIQUE INDEX ux_rcm_pk (relationship_id, column_position);
