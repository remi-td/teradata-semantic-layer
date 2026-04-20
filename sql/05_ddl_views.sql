-- =========================================================================
-- Semantic view entities: SEMANTIC_VIEW, VIEW_MEMBER.
-- =========================================================================

CREATE MULTISET TABLE demo_user.SEMANTIC_VIEW, FALLBACK (
    view_id              INTEGER GENERATED ALWAYS AS IDENTITY
                             (START WITH 1 INCREMENT BY 1 MINVALUE 1
                              MAXVALUE 2147483647 NO CYCLE) NOT NULL,
    model_id             INTEGER NOT NULL,
    view_name            VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    description          VARCHAR(10000) CHARACTER SET UNICODE,
    primary_dataset_id   INTEGER,
    timeseries_field     VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC,
    is_certified         BYTEINT DEFAULT 0 NOT NULL,
    is_public            BYTEINT DEFAULT 1 NOT NULL,
    owner_user           VARCHAR(128) CHARACTER SET UNICODE NOT CASESPECIFIC,
    created_ts           TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL,
    updated_ts           TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) NOT NULL
)
UNIQUE PRIMARY INDEX (view_id)
INDEX ux_semantic_view_nk (model_id, view_name);

CREATE MULTISET TABLE demo_user.VIEW_MEMBER, FALLBACK (
    view_id            INTEGER NOT NULL,
    member_ordinal     SMALLINT NOT NULL,
    member_name        VARCHAR(200) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    member_type        VARCHAR(20) CHARACTER SET UNICODE NOT CASESPECIFIC NOT NULL,
    field_id           INTEGER,
    metric_id          INTEGER,
    inline_expression  VARCHAR(10000) CHARACTER SET UNICODE,
    display_name       VARCHAR(500) CHARACTER SET UNICODE,
    is_public          BYTEINT DEFAULT 1 NOT NULL,
    member_order       SMALLINT DEFAULT 0 NOT NULL
)
PRIMARY INDEX (view_id)
UNIQUE INDEX ux_view_member_pk (view_id, member_ordinal)
INDEX ux_view_member_name (view_id, member_name);
