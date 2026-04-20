-- =========================================================================
-- Core entities: SEMANTIC_MODEL, DATASET, FIELD, DATASET_KEY.
-- =========================================================================

CREATE MULTISET TABLE demo_user.SEMANTIC_MODEL, FALLBACK (
    model_id      INTEGER GENERATED ALWAYS AS IDENTITY
                      (START WITH 1 INCREMENT BY 1 MINVALUE 1
                       MAXVALUE 2147483647 NO CYCLE) NOT NULL,
    model_name    VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description   VARCHAR(10000) CHARACTER SET UNICODE,
    owner_user    VARCHAR(128) CHARACTER SET UNICODE NOT CASESPECIFIC,
    owner_group   VARCHAR(128) CHARACTER SET UNICODE NOT CASESPECIFIC,
    is_active     BYTEINT DEFAULT 1 NOT NULL,
    created_ts    TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL,
    updated_ts    TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX (model_id)
INDEX ux_semantic_model_name (model_name);

CREATE MULTISET TABLE demo_user.DATASET, FALLBACK (
    dataset_id        INTEGER GENERATED ALWAYS AS IDENTITY
                          (START WITH 1 INCREMENT BY 1 MINVALUE 1
                           MAXVALUE 2147483647 NO CYCLE) NOT NULL,
    model_id          INTEGER NOT NULL,
    dataset_name      VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description       VARCHAR(10000) CHARACTER SET UNICODE,
    granularity_desc  VARCHAR(1000) CHARACTER SET UNICODE,
    DataBaseName      VARCHAR(128) CHARACTER SET UNICODE NOT CASESPECIFIC,
    TableName         VARCHAR(128) CHARACTER SET UNICODE NOT CASESPECIFIC,
    source_query      CLOB(1048576) CHARACTER SET UNICODE,
    created_ts        TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL,
    updated_ts        TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX (dataset_id)
INDEX ux_dataset_nk (model_id, dataset_name)
INDEX ix_dataset_phys (DataBaseName, TableName);

CREATE MULTISET TABLE demo_user.FIELD, FALLBACK (
    field_id           INTEGER GENERATED ALWAYS AS IDENTITY
                           (START WITH 1 INCREMENT BY 1 MINVALUE 1
                            MAXVALUE 2147483647 NO CYCLE) NOT NULL,
    dataset_id         INTEGER NOT NULL,
    field_name         VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    field_type_code    CHAR(1) CHARACTER SET UNICODE NOT CASESPECIFIC
                           DEFAULT 'A' NOT NULL,
    expression         VARCHAR(10000) CHARACTER SET UNICODE,
    description        VARCHAR(10000) CHARACTER SET UNICODE,
    label              VARCHAR(500) CHARACTER SET UNICODE,
    is_dimension       BYTEINT DEFAULT 0 NOT NULL,
    is_time_dimension  BYTEINT DEFAULT 0 NOT NULL,
    data_type          VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    ColumnName         VARCHAR(128) CHARACTER SET UNICODE NOT CASESPECIFIC,
    field_order        SMALLINT DEFAULT 0 NOT NULL,
    created_ts         TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL,
    updated_ts         TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
PRIMARY INDEX (dataset_id)
UNIQUE INDEX ux_field_id (field_id)
UNIQUE INDEX ux_field_nk (dataset_id, field_name);

CREATE MULTISET TABLE demo_user.DATASET_KEY, FALLBACK (
    dataset_id        INTEGER NOT NULL,
    key_type          VARCHAR(10) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    key_ordinal       SMALLINT NOT NULL,
    column_position   SMALLINT NOT NULL,
    field_id          INTEGER NOT NULL
)
PRIMARY INDEX (dataset_id)
UNIQUE INDEX ux_dataset_key_pk (dataset_id, key_type, key_ordinal, column_position);
