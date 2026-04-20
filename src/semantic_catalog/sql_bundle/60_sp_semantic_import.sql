-- =========================================================================
-- sp_semantic_import — single-entity import / validation procedure.
--
-- Designed to be called once per entity from the GUI's import workflow.
-- All validation and foreign-key resolution runs inside the database; the
-- caller only needs to parse YAML/JSON at the boundary and dispatch in
-- topological order (MODEL → DATASET → FIELD → METRIC → METRIC_EXPR →
-- RELATIONSHIP → REL_COL → VIEW → VIEW_MEMBER → AI_CONTEXT).
--
-- Each call is atomic: either it inserts the entity and returns OK, or it
-- returns ERROR with a human-readable explanation and does not touch the
-- catalog. For true multi-entity dry-run, wrap the batch in an explicit
-- transaction at the client side and ROLLBACK if any op reports ERROR.
--
-- Payload shapes (JSON object, key names mirror the OSI/YAML vocabulary):
--   MODEL        {"name", "description", "owner_user", "owner_group"}
--   DATASET      {"name", "description", "granularity", "source_table"|"source_query"}
--   FIELD        {"dataset", "name", "type"(A|K), "expression", "description",
--                 "label", "is_dimension", "is_time_dimension", "data_type",
--                 "column_name", "field_order"}
--   METRIC       {"name", "description", "primary_dataset", "metric_type",
--                 "is_additive", "is_certified", "owner_team", "default_time_grain"}
--   METRIC_EXPR  {"metric", "dialect"(TERADATA|ANSI_SQL), "expression"}
--   RELATIONSHIP {"name", "from", "to", "cardinality", "join_type", "description"}
--   REL_COL      {"relationship", "from_dataset", "to_dataset",
--                 "from_field", "to_field", "position"}
--   VIEW         {"name", "description", "primary_dataset", "timeseries_field",
--                 "is_certified", "is_public", "owner_user"}
--   VIEW_MEMBER  {"view", "ordinal", "name", "member_type"(DIMENSION|MEASURE|TIME_DIMENSION),
--                 "parent_dataset"(for field), "field", "metric", "inline_expression",
--                 "display_name", "is_public", "member_order"}
--   AI_CONTEXT   {"entity_type"(MODEL|DATASET|FIELD|METRIC|VIEW), "entity_name",
--                 "parent"(dataset for FIELD), "instructions", "synonyms"[..],
--                 "examples"[..], "display_name"}
-- =========================================================================
REPLACE PROCEDURE demo_user.sp_semantic_import(
    IN  p_model_name  VARCHAR(200),
    IN  p_kind        VARCHAR(30),
    IN  p_payload     VARCHAR(16000) CHARACTER SET UNICODE,
    OUT p_status      VARCHAR(10),
    OUT p_message     VARCHAR(4000),
    OUT p_entity_id   INTEGER
)
sp_body:
BEGIN
    DECLARE v_json       JSON(16000) CHARACTER SET UNICODE;
    DECLARE v_kind       VARCHAR(30);
    DECLARE v_name       VARCHAR(200);
    DECLARE v_parent     VARCHAR(200);
    DECLARE v_model_id   INTEGER DEFAULT NULL;
    DECLARE v_dataset_id INTEGER DEFAULT NULL;
    DECLARE v_field_id   INTEGER DEFAULT NULL;
    DECLARE v_metric_id  INTEGER DEFAULT NULL;
    DECLARE v_rel_id     INTEGER DEFAULT NULL;
    DECLARE v_view_id    INTEGER DEFAULT NULL;
    DECLARE v_count      INTEGER DEFAULT 0;

    DECLARE v_ds_name    VARCHAR(200);
    DECLARE v_from_ds    VARCHAR(200);
    DECLARE v_to_ds      VARCHAR(200);
    DECLARE v_from_field VARCHAR(200);
    DECLARE v_to_field   VARCHAR(200);
    DECLARE v_from_ds_id INTEGER;
    DECLARE v_to_ds_id   INTEGER;
    DECLARE v_from_fid   INTEGER;
    DECLARE v_to_fid     INTEGER;
    DECLARE v_eid        INTEGER;

    DECLARE v_src_tbl    VARCHAR(300);
    DECLARE v_db         VARCHAR(128);
    DECLARE v_tbl        VARCHAR(128);
    DECLARE v_dot        INTEGER;

    DECLARE v_type       CHAR(1);
    DECLARE v_is_dim     BYTEINT;
    DECLARE v_is_tdim    BYTEINT;

    DECLARE v_pds        VARCHAR(200);
    DECLARE v_pds_id     INTEGER;
    DECLARE v_met_name   VARCHAR(200);
    DECLARE v_dialect    VARCHAR(50);
    DECLARE v_expr       VARCHAR(32000);

    DECLARE v_card       VARCHAR(20);
    DECLARE v_jth        VARCHAR(20);

    DECLARE v_rel_name   VARCHAR(200);
    DECLARE v_pos        INTEGER;

    DECLARE v_view_name  VARCHAR(200);
    DECLARE v_member_ord INTEGER;
    DECLARE v_member_type VARCHAR(20);
    DECLARE v_field_name VARCHAR(200);
    DECLARE v_f_parent   VARCHAR(200);

    DECLARE v_ent_type   VARCHAR(20);
    DECLARE v_ent_name   VARCHAR(200);
    DECLARE v_parent_ds  VARCHAR(200);
    DECLARE v_syn        JSON(8000);
    DECLARE v_ex         JSON(8000);

    DECLARE v_err_state  CHAR(5);
    DECLARE v_err_msg    VARCHAR(2000);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS EXCEPTION 1 v_err_msg = MESSAGE_TEXT;
        GET DIAGNOSTICS EXCEPTION 1 v_err_state = RETURNED_SQLSTATE;
        SET p_status = 'ERROR';
        SET p_message = 'SQLSTATE=' || COALESCE(v_err_state, '?????') || ' ' ||
                        COALESCE(v_err_msg, 'unspecified SQL error');
    END;

    SET p_status = 'OK';
    SET p_message = '';
    SET p_entity_id = NULL;

    -- Parse the JSON payload (UNICODE to preserve non-ASCII content).
    SET v_json = NEW JSON(p_payload, UNICODE);
    SET v_kind = UPPER(COALESCE(p_kind, ''));

    -- Resolve target model for every non-MODEL kind.
    IF v_kind <> 'MODEL' THEN
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_model_id = NULL;
            SELECT model_id INTO v_model_id
              FROM demo_user.SEMANTIC_MODEL
             WHERE model_name = p_model_name;
        END;
        IF v_model_id IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown semantic model "' || COALESCE(p_model_name,'<null>') || '"';
            LEAVE sp_body;
        END IF;
    END IF;

    -- ===================================================================
    -- MODEL
    -- ===================================================================
    IF v_kind = 'MODEL' THEN
        SET v_name = v_json.JSONExtractValue('$.name');
        IF v_name IS NULL OR v_name = '' THEN
            SET v_name = p_model_name;
        END IF;
        IF v_name IS NULL OR v_name = '' THEN
            SET p_status = 'ERROR';
            SET p_message = 'MODEL payload is missing "name"';
            LEAVE sp_body;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.SEMANTIC_MODEL WHERE model_name = v_name;
        IF v_count > 0 THEN
            SET p_status = 'ERROR';
            SET p_message = 'Model "' || v_name || '" already exists';
            LEAVE sp_body;
        END IF;
        INSERT INTO demo_user.SEMANTIC_MODEL
            (model_name, description, owner_user, owner_group)
        VALUES (v_name,
                v_json.JSONExtractValue('$.description'),
                v_json.JSONExtractValue('$.owner_user'),
                v_json.JSONExtractValue('$.owner_group'));
        SELECT model_id INTO v_model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name = v_name;
        SET p_entity_id = v_model_id;
        SET p_message = 'Created model "' || v_name || '" (id=' || TRIM(v_model_id) || ')';
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- DATASET
    -- ===================================================================
    IF v_kind = 'DATASET' THEN
        SET v_name = v_json.JSONExtractValue('$.name');
        IF v_name IS NULL OR v_name = '' THEN
            SET p_status = 'ERROR';
            SET p_message = 'DATASET payload is missing "name"';
            LEAVE sp_body;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.DATASET
         WHERE model_id = v_model_id AND dataset_name = v_name;
        IF v_count > 0 THEN
            SET p_status = 'ERROR';
            SET p_message = 'Dataset "' || v_name || '" already exists in model "' || p_model_name || '"';
            LEAVE sp_body;
        END IF;
        SET v_src_tbl = v_json.JSONExtractValue('$.source_table');
        SET v_db = NULL;
        SET v_tbl = NULL;
        IF v_src_tbl IS NOT NULL AND v_src_tbl <> '' THEN
            SET v_dot = POSITION('.' IN v_src_tbl);
            IF v_dot > 0 THEN
                SET v_db  = TRIM(SUBSTRING(v_src_tbl FROM 1 FOR v_dot - 1));
                SET v_tbl = TRIM(SUBSTRING(v_src_tbl FROM v_dot + 1));
            ELSE
                SET v_tbl = TRIM(v_src_tbl);
            END IF;
        END IF;
        INSERT INTO demo_user.DATASET
            (model_id, dataset_name, description, granularity_desc,
             DataBaseName, TableName, source_query)
        VALUES (v_model_id, v_name,
                v_json.JSONExtractValue('$.description'),
                v_json.JSONExtractValue('$.granularity'),
                v_db, v_tbl,
                v_json.JSONExtractValue('$.source_query'));
        SELECT dataset_id INTO v_dataset_id FROM demo_user.DATASET
         WHERE model_id = v_model_id AND dataset_name = v_name;
        SET p_entity_id = v_dataset_id;
        SET p_message  = 'Created dataset "' || v_name || '" (id=' || TRIM(v_dataset_id) || ')';
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- FIELD
    -- ===================================================================
    IF v_kind = 'FIELD' THEN
        SET v_ds_name = v_json.JSONExtractValue('$.dataset');
        SET v_name    = v_json.JSONExtractValue('$.name');
        IF v_ds_name IS NULL OR v_name IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'FIELD payload requires "dataset" and "name"';
            LEAVE sp_body;
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_dataset_id = NULL;
            SELECT dataset_id INTO v_dataset_id FROM demo_user.DATASET
             WHERE model_id = v_model_id AND dataset_name = v_ds_name;
        END;
        IF v_dataset_id IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown dataset "' || v_ds_name || '" in model "' || p_model_name || '"';
            LEAVE sp_body;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.FIELD
         WHERE dataset_id = v_dataset_id AND field_name = v_name;
        IF v_count > 0 THEN
            SET p_status = 'ERROR';
            SET p_message = 'Field "' || v_ds_name || '.' || v_name || '" already exists';
            LEAVE sp_body;
        END IF;
        SET v_type = COALESCE(v_json.JSONExtractValue('$.type'), 'A');
        IF v_type NOT IN ('A','K') THEN
            SET p_status = 'ERROR';
            SET p_message = 'FIELD.type must be "A" or "K" (got "' || v_type || '")';
            LEAVE sp_body;
        END IF;
        SET v_is_dim  = CAST(COALESCE(v_json.JSONExtractValue('$.is_dimension'), '0') AS BYTEINT);
        SET v_is_tdim = CAST(COALESCE(v_json.JSONExtractValue('$.is_time_dimension'), '0') AS BYTEINT);
        INSERT INTO demo_user.FIELD
            (dataset_id, field_name, field_type_code, expression, description,
             label, is_dimension, is_time_dimension, data_type, ColumnName, field_order)
        VALUES (v_dataset_id, v_name, v_type,
                v_json.JSONExtractValue('$.expression'),
                v_json.JSONExtractValue('$.description'),
                v_json.JSONExtractValue('$.label'),
                v_is_dim, v_is_tdim,
                v_json.JSONExtractValue('$.data_type'),
                v_json.JSONExtractValue('$.column_name'),
                CAST(COALESCE(v_json.JSONExtractValue('$.field_order'), '0') AS SMALLINT));
        SELECT field_id INTO v_field_id FROM demo_user.FIELD
         WHERE dataset_id = v_dataset_id AND field_name = v_name;
        SET p_entity_id = v_field_id;
        SET p_message  = 'Created field "' || v_ds_name || '.' || v_name || '" (id=' || TRIM(v_field_id) || ')';
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- METRIC
    -- ===================================================================
    IF v_kind = 'METRIC' THEN
        SET v_name = v_json.JSONExtractValue('$.name');
        IF v_name IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'METRIC payload missing "name"';
            LEAVE sp_body;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.METRIC
         WHERE model_id = v_model_id AND metric_name = v_name;
        IF v_count > 0 THEN
            SET p_status = 'ERROR';
            SET p_message = 'Metric "' || v_name || '" already exists in model "' || p_model_name || '"';
            LEAVE sp_body;
        END IF;
        SET v_pds = v_json.JSONExtractValue('$.primary_dataset');
        SET v_pds_id = NULL;
        IF v_pds IS NOT NULL AND v_pds <> '' THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND
                    SET v_pds_id = NULL;
                SELECT dataset_id INTO v_pds_id FROM demo_user.DATASET
                 WHERE model_id = v_model_id AND dataset_name = v_pds;
            END;
            IF v_pds_id IS NULL THEN
                SET p_status = 'ERROR';
                SET p_message = 'Unknown primary_dataset "' || v_pds || '"';
                LEAVE sp_body;
            END IF;
        END IF;
        INSERT INTO demo_user.METRIC
            (model_id, metric_name, description, primary_dataset_id,
             metric_type, is_additive, is_certified, owner_team, default_time_grain)
        VALUES (v_model_id, v_name,
                v_json.JSONExtractValue('$.description'),
                v_pds_id,
                UPPER(COALESCE(v_json.JSONExtractValue('$.metric_type'), 'SIMPLE')),
                CAST(COALESCE(v_json.JSONExtractValue('$.is_additive'), '1') AS BYTEINT),
                CAST(COALESCE(v_json.JSONExtractValue('$.is_certified'), '0') AS BYTEINT),
                v_json.JSONExtractValue('$.owner_team'),
                UPPER(v_json.JSONExtractValue('$.default_time_grain')));
        SELECT metric_id INTO v_metric_id FROM demo_user.METRIC
         WHERE model_id = v_model_id AND metric_name = v_name;
        SET p_entity_id = v_metric_id;
        SET p_message  = 'Created metric "' || v_name || '" (id=' || TRIM(v_metric_id) || ')';
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- METRIC_EXPR  (upsert per (metric, dialect))
    -- ===================================================================
    IF v_kind = 'METRIC_EXPR' THEN
        SET v_met_name = v_json.JSONExtractValue('$.metric');
        SET v_dialect  = UPPER(COALESCE(v_json.JSONExtractValue('$.dialect'), ''));
        SET v_expr     = v_json.JSONExtractValue('$.expression');
        IF v_met_name IS NULL OR v_expr IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'METRIC_EXPR requires "metric" and "expression"';
            LEAVE sp_body;
        END IF;
        IF v_dialect NOT IN ('TERADATA','ANSI_SQL') THEN
            SET p_status = 'ERROR';
            SET p_message = 'METRIC_EXPR.dialect must be TERADATA or ANSI_SQL (got "' || v_dialect || '")';
            LEAVE sp_body;
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_metric_id = NULL;
            SELECT metric_id INTO v_metric_id FROM demo_user.METRIC
             WHERE model_id = v_model_id AND metric_name = v_met_name;
        END;
        IF v_metric_id IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown metric "' || v_met_name || '" in model "' || p_model_name || '"';
            LEAVE sp_body;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.METRIC_EXPRESSION
         WHERE metric_id = v_metric_id AND dialect = v_dialect;
        IF v_count > 0 THEN
            UPDATE demo_user.METRIC_EXPRESSION
               SET expression = v_expr
             WHERE metric_id = v_metric_id AND dialect = v_dialect;
            SET p_message = 'Updated ' || v_dialect || ' expression for metric "' || v_met_name || '"';
        ELSE
            INSERT INTO demo_user.METRIC_EXPRESSION (metric_id, dialect, expression)
            VALUES (v_metric_id, v_dialect, v_expr);
            SET p_message = 'Added ' || v_dialect || ' expression for metric "' || v_met_name || '"';
        END IF;
        SET p_entity_id = v_metric_id;
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- RELATIONSHIP
    -- ===================================================================
    IF v_kind = 'RELATIONSHIP' THEN
        SET v_name    = v_json.JSONExtractValue('$.name');
        SET v_from_ds = v_json.JSONExtractValue('$.from');
        SET v_to_ds   = v_json.JSONExtractValue('$.to');
        IF v_name IS NULL OR v_from_ds IS NULL OR v_to_ds IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'RELATIONSHIP requires "name", "from", "to"';
            LEAVE sp_body;
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_from_ds_id = NULL;
            SELECT dataset_id INTO v_from_ds_id FROM demo_user.DATASET
             WHERE model_id = v_model_id AND dataset_name = v_from_ds;
        END;
        IF v_from_ds_id IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown "from" dataset "' || v_from_ds || '"';
            LEAVE sp_body;
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_to_ds_id = NULL;
            SELECT dataset_id INTO v_to_ds_id FROM demo_user.DATASET
             WHERE model_id = v_model_id AND dataset_name = v_to_ds;
        END;
        IF v_to_ds_id IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown "to" dataset "' || v_to_ds || '"';
            LEAVE sp_body;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.RELATIONSHIP
         WHERE from_dataset_id = v_from_ds_id AND to_dataset_id = v_to_ds_id
           AND relationship_name = v_name;
        IF v_count > 0 THEN
            SET p_status = 'ERROR';
            SET p_message = 'Relationship "' || v_name || '" already exists';
            LEAVE sp_body;
        END IF;
        SET v_card = UPPER(COALESCE(v_json.JSONExtractValue('$.cardinality'), 'MANY_TO_ONE'));
        SET v_jth  = UPPER(COALESCE(v_json.JSONExtractValue('$.join_type'), 'INNER'));
        INSERT INTO demo_user.RELATIONSHIP
            (from_dataset_id, to_dataset_id, relationship_name, description,
             cardinality, join_type_hint)
        VALUES (v_from_ds_id, v_to_ds_id, v_name,
                v_json.JSONExtractValue('$.description'),
                v_card, v_jth);
        SELECT relationship_id INTO v_rel_id FROM demo_user.RELATIONSHIP
         WHERE from_dataset_id = v_from_ds_id AND to_dataset_id = v_to_ds_id
           AND relationship_name = v_name;
        SET p_entity_id = v_rel_id;
        SET p_message  = 'Created relationship "' || v_name || '" (' || v_from_ds || ' -> ' || v_to_ds || ')';
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- REL_COL
    -- ===================================================================
    IF v_kind = 'REL_COL' THEN
        SET v_rel_name   = v_json.JSONExtractValue('$.relationship');
        SET v_from_ds    = v_json.JSONExtractValue('$.from_dataset');
        SET v_to_ds      = v_json.JSONExtractValue('$.to_dataset');
        SET v_from_field = v_json.JSONExtractValue('$.from_field');
        SET v_to_field   = v_json.JSONExtractValue('$.to_field');
        SET v_pos = CAST(COALESCE(v_json.JSONExtractValue('$.position'), '1') AS INTEGER);
        IF v_rel_name IS NULL OR v_from_ds IS NULL OR v_to_ds IS NULL
           OR v_from_field IS NULL OR v_to_field IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'REL_COL requires "relationship","from_dataset","to_dataset","from_field","to_field"';
            LEAVE sp_body;
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_rel_id = NULL;
            SELECT r.relationship_id, r.from_dataset_id, r.to_dataset_id
              INTO v_rel_id, v_from_ds_id, v_to_ds_id
              FROM demo_user.RELATIONSHIP r
              JOIN demo_user.DATASET df ON df.dataset_id = r.from_dataset_id AND df.model_id = v_model_id
              JOIN demo_user.DATASET dt ON dt.dataset_id = r.to_dataset_id
             WHERE r.relationship_name = v_rel_name
               AND df.dataset_name = v_from_ds
               AND dt.dataset_name = v_to_ds;
        END;
        IF v_rel_id IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown relationship "' || v_rel_name ||
                            '" (' || v_from_ds || ' -> ' || v_to_ds || ')';
            LEAVE sp_body;
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_from_fid = NULL;
            SELECT field_id INTO v_from_fid FROM demo_user.FIELD
             WHERE dataset_id = v_from_ds_id AND field_name = v_from_field;
        END;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_to_fid = NULL;
            SELECT field_id INTO v_to_fid FROM demo_user.FIELD
             WHERE dataset_id = v_to_ds_id AND field_name = v_to_field;
        END;
        IF v_from_fid IS NULL OR v_to_fid IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown join column(s): ' ||
                 CASE WHEN v_from_fid IS NULL THEN v_from_ds || '.' || v_from_field ELSE '' END ||
                 CASE WHEN v_to_fid   IS NULL THEN ' ' || v_to_ds   || '.' || v_to_field   ELSE '' END;
            LEAVE sp_body;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.REL_COLUMN_MAP
         WHERE relationship_id = v_rel_id AND column_position = v_pos;
        IF v_count > 0 THEN
            SET p_status = 'ERROR';
            SET p_message = 'Column mapping at position ' || TRIM(v_pos) || ' already exists';
            LEAVE sp_body;
        END IF;
        INSERT INTO demo_user.REL_COLUMN_MAP (relationship_id, column_position, from_field_id, to_field_id)
        VALUES (v_rel_id, v_pos, v_from_fid, v_to_fid);
        SET p_entity_id = v_rel_id;
        SET p_message  = 'Mapped ' || v_from_ds || '.' || v_from_field ||
                         ' -> ' || v_to_ds || '.' || v_to_field;
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- VIEW
    -- ===================================================================
    IF v_kind = 'VIEW' THEN
        SET v_name = v_json.JSONExtractValue('$.name');
        IF v_name IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'VIEW payload missing "name"';
            LEAVE sp_body;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.SEMANTIC_VIEW
         WHERE model_id = v_model_id AND view_name = v_name;
        IF v_count > 0 THEN
            SET p_status = 'ERROR';
            SET p_message = 'View "' || v_name || '" already exists';
            LEAVE sp_body;
        END IF;
        SET v_pds = v_json.JSONExtractValue('$.primary_dataset');
        SET v_pds_id = NULL;
        IF v_pds IS NOT NULL AND v_pds <> '' THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND
                    SET v_pds_id = NULL;
                SELECT dataset_id INTO v_pds_id FROM demo_user.DATASET
                 WHERE model_id = v_model_id AND dataset_name = v_pds;
            END;
            IF v_pds_id IS NULL THEN
                SET p_status = 'ERROR';
                SET p_message = 'Unknown primary_dataset "' || v_pds || '"';
                LEAVE sp_body;
            END IF;
        END IF;
        INSERT INTO demo_user.SEMANTIC_VIEW
            (model_id, view_name, description, primary_dataset_id,
             timeseries_field, is_certified, is_public, owner_user)
        VALUES (v_model_id, v_name,
                v_json.JSONExtractValue('$.description'),
                v_pds_id,
                v_json.JSONExtractValue('$.timeseries_field'),
                CAST(COALESCE(v_json.JSONExtractValue('$.is_certified'), '0') AS BYTEINT),
                CAST(COALESCE(v_json.JSONExtractValue('$.is_public'),   '1') AS BYTEINT),
                v_json.JSONExtractValue('$.owner_user'));
        SELECT view_id INTO v_view_id FROM demo_user.SEMANTIC_VIEW
         WHERE model_id = v_model_id AND view_name = v_name;
        SET p_entity_id = v_view_id;
        SET p_message  = 'Created view "' || v_name || '" (id=' || TRIM(v_view_id) || ')';
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- VIEW_MEMBER
    -- ===================================================================
    IF v_kind = 'VIEW_MEMBER' THEN
        SET v_view_name   = v_json.JSONExtractValue('$.view');
        SET v_member_ord  = CAST(COALESCE(v_json.JSONExtractValue('$.ordinal'), '0') AS INTEGER);
        SET v_name        = v_json.JSONExtractValue('$.name');
        SET v_member_type = UPPER(COALESCE(v_json.JSONExtractValue('$.member_type'), 'DIMENSION'));
        IF v_view_name IS NULL OR v_name IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'VIEW_MEMBER requires "view" and "name"';
            LEAVE sp_body;
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_view_id = NULL;
            SELECT view_id INTO v_view_id FROM demo_user.SEMANTIC_VIEW
             WHERE model_id = v_model_id AND view_name = v_view_name;
        END;
        IF v_view_id IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown view "' || v_view_name || '"';
            LEAVE sp_body;
        END IF;
        SET v_field_id = NULL;
        SET v_metric_id = NULL;
        SET v_field_name = v_json.JSONExtractValue('$.field');
        SET v_f_parent   = v_json.JSONExtractValue('$.parent_dataset');
        SET v_met_name   = v_json.JSONExtractValue('$.metric');
        IF v_field_name IS NOT NULL AND v_field_name <> '' THEN
            IF v_f_parent IS NULL THEN
                SET p_status = 'ERROR';
                SET p_message = 'VIEW_MEMBER.field requires "parent_dataset"';
                LEAVE sp_body;
            END IF;
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND
                    SET v_field_id = NULL;
                SELECT f.field_id INTO v_field_id
                  FROM demo_user.FIELD f
                  JOIN demo_user.DATASET d ON d.dataset_id = f.dataset_id
                 WHERE d.model_id = v_model_id AND d.dataset_name = v_f_parent
                   AND f.field_name = v_field_name;
            END;
            IF v_field_id IS NULL THEN
                SET p_status = 'ERROR';
                SET p_message = 'Unknown field "' || v_f_parent || '.' || v_field_name || '"';
                LEAVE sp_body;
            END IF;
        END IF;
        IF v_met_name IS NOT NULL AND v_met_name <> '' THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND
                    SET v_metric_id = NULL;
                SELECT metric_id INTO v_metric_id FROM demo_user.METRIC
                 WHERE model_id = v_model_id AND metric_name = v_met_name;
            END;
            IF v_metric_id IS NULL THEN
                SET p_status = 'ERROR';
                SET p_message = 'Unknown metric "' || v_met_name || '"';
                LEAVE sp_body;
            END IF;
        END IF;
        SELECT COUNT(*) INTO v_count FROM demo_user.VIEW_MEMBER
         WHERE view_id = v_view_id AND member_ordinal = v_member_ord;
        IF v_count > 0 THEN
            SET p_status = 'ERROR';
            SET p_message = 'VIEW_MEMBER ordinal ' || TRIM(v_member_ord) || ' already used';
            LEAVE sp_body;
        END IF;
        INSERT INTO demo_user.VIEW_MEMBER
            (view_id, member_ordinal, member_name, member_type, field_id, metric_id,
             inline_expression, display_name, is_public, member_order)
        VALUES (v_view_id, v_member_ord, v_name, v_member_type, v_field_id, v_metric_id,
                v_json.JSONExtractValue('$.inline_expression'),
                v_json.JSONExtractValue('$.display_name'),
                CAST(COALESCE(v_json.JSONExtractValue('$.is_public'), '1') AS BYTEINT),
                CAST(COALESCE(v_json.JSONExtractValue('$.member_order'), '0') AS SMALLINT));
        SET p_entity_id = v_view_id;
        SET p_message  = 'Added view member "' || v_view_name || '.' || v_name || '"';
        LEAVE sp_body;
    END IF;

    -- ===================================================================
    -- AI_CONTEXT  (upsert by entity_type+entity_id)
    -- ===================================================================
    IF v_kind = 'AI_CONTEXT' THEN
        SET v_ent_type  = UPPER(v_json.JSONExtractValue('$.entity_type'));
        SET v_ent_name  = v_json.JSONExtractValue('$.entity_name');
        SET v_parent_ds = v_json.JSONExtractValue('$.parent');
        IF v_ent_type IS NULL OR v_ent_name IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'AI_CONTEXT requires "entity_type","entity_name"';
            LEAVE sp_body;
        END IF;
        SET v_eid = NULL;
        IF v_ent_type = 'MODEL' THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_eid = NULL;
                SELECT model_id INTO v_eid FROM demo_user.SEMANTIC_MODEL WHERE model_name = v_ent_name;
            END;
        ELSEIF v_ent_type = 'DATASET' THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_eid = NULL;
                SELECT dataset_id INTO v_eid FROM demo_user.DATASET
                 WHERE model_id = v_model_id AND dataset_name = v_ent_name;
            END;
        ELSEIF v_ent_type = 'FIELD' THEN
            IF v_parent_ds IS NULL THEN
                SET p_status = 'ERROR';
                SET p_message = 'AI_CONTEXT for FIELD requires "parent" (dataset name)';
                LEAVE sp_body;
            END IF;
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_eid = NULL;
                SELECT f.field_id INTO v_eid FROM demo_user.FIELD f
                  JOIN demo_user.DATASET d ON d.dataset_id = f.dataset_id
                 WHERE d.model_id = v_model_id AND d.dataset_name = v_parent_ds
                   AND f.field_name = v_ent_name;
            END;
        ELSEIF v_ent_type = 'METRIC' THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_eid = NULL;
                SELECT metric_id INTO v_eid FROM demo_user.METRIC
                 WHERE model_id = v_model_id AND metric_name = v_ent_name;
            END;
        ELSEIF v_ent_type = 'VIEW' THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_eid = NULL;
                SELECT view_id INTO v_eid FROM demo_user.SEMANTIC_VIEW
                 WHERE model_id = v_model_id AND view_name = v_ent_name;
            END;
        ELSE
            SET p_status = 'ERROR';
            SET p_message = 'Unknown AI_CONTEXT entity_type "' || v_ent_type || '"';
            LEAVE sp_body;
        END IF;
        IF v_eid IS NULL THEN
            SET p_status = 'ERROR';
            SET p_message = 'Unknown ' || v_ent_type || ' "' || v_ent_name || '"';
            LEAVE sp_body;
        END IF;
        SET v_syn = v_json.JSONExtract('$.synonyms');
        SET v_ex  = v_json.JSONExtract('$.examples');
        DELETE FROM demo_user.AI_CONTEXT WHERE entity_type = v_ent_type AND entity_id = v_eid;
        INSERT INTO demo_user.AI_CONTEXT
            (entity_type, entity_id, instructions, synonyms, examples, display_name)
        VALUES (v_ent_type, v_eid,
                v_json.JSONExtractValue('$.instructions'),
                v_syn, v_ex,
                v_json.JSONExtractValue('$.display_name'));
        SET p_entity_id = v_eid;
        SET p_message  = 'AI_CONTEXT set for ' || v_ent_type || ' "' || v_ent_name || '"';
        LEAVE sp_body;
    END IF;

    -- Unknown kind.
    SET p_status = 'ERROR';
    SET p_message = 'Unknown entity kind "' || p_kind || '"';

END;
