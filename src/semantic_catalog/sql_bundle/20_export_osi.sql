-- =========================================================================
-- sp_export_osi_yaml(p_model_name) — emits an OSI-compatible YAML document
-- for the named semantic model as a dynamic result set (line_no, line_text).
-- Call with:
--    CALL demo_user.sp_export_osi_yaml('tpch_osi');
-- and order by line_no to reconstruct the YAML.
-- =========================================================================
REPLACE PROCEDURE demo_user.sp_export_osi_yaml(
    IN p_model_name VARCHAR(200)
)
DYNAMIC RESULT SETS 1
BEGIN
    DECLARE v_model_id   INTEGER;
    DECLARE v_line_no    INTEGER DEFAULT 0;
    DECLARE v_dt_id      INTEGER;
    DECLARE v_fld_id     INTEGER;
    DECLARE v_mt_id      INTEGER;
    DECLARE v_rel_id     INTEGER;

    -- Clear working GTT (rows are session-local; wipe any lines from a prior call)
    DELETE FROM demo_user.yaml_tmp;

    SELECT model_id INTO v_model_id FROM demo_user.SEMANTIC_MODEL WHERE model_name = p_model_name;

    -- -------------------- Header --------------------
    SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, 'version: "0.1.1"');
    SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, 'semantic_model:');

    -- -------------------- Model block --------------------
    FOR r_model AS cur_model CURSOR FOR
        SELECT m.model_name, m.description,
               ac.instructions, ac.synonyms, ac.display_name
          FROM demo_user.SEMANTIC_MODEL m
          LEFT JOIN demo_user.AI_CONTEXT ac
                 ON ac.entity_type='MODEL' AND ac.entity_id=m.model_id
         WHERE m.model_id = v_model_id
    DO
        SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '  - name: ' || r_model.model_name);
        IF r_model.description IS NOT NULL THEN
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '    description: "' || OREPLACE(r_model.description, '"', '\"') || '"');
        END IF;
        IF r_model.display_name IS NOT NULL OR r_model.instructions IS NOT NULL OR r_model.synonyms IS NOT NULL THEN
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '    ai_context:');
            IF r_model.display_name IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '      display_name: "' || OREPLACE(r_model.display_name, '"', '\"') || '"');
            END IF;
            IF r_model.instructions IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '      instructions: "' || OREPLACE(r_model.instructions, '"', '\"') || '"');
            END IF;
            IF r_model.synonyms IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '      synonyms: ' || CAST(r_model.synonyms AS VARCHAR(4000)));
            END IF;
        END IF;
    END FOR;

    -- -------------------- Datasets --------------------
    SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '    datasets:');

    FOR r_ds AS cur_ds CURSOR FOR
        SELECT d.dataset_id, d.dataset_name, d.description, d.granularity_desc,
               d.DataBaseName, d.TableName, d.source_query
          FROM demo_user.DATASET d
         WHERE d.model_id = v_model_id
      ORDER BY d.dataset_id
    DO
        SET v_dt_id = r_ds.dataset_id;
        SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '      - name: ' || r_ds.dataset_name);
        IF r_ds.description IS NOT NULL THEN
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        description: "' || OREPLACE(r_ds.description, '"', '\"') || '"');
        END IF;
        IF r_ds.DataBaseName IS NOT NULL THEN
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        source: ' || TRIM(r_ds.DataBaseName) || '.' || TRIM(r_ds.TableName));
        ELSEIF r_ds.source_query IS NOT NULL THEN
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        source_query: |');
            -- Embed the query with 10-space indent, line-by-line.
            -- (Teradata CLOB split by newline isn't trivial — embed as single block with the delimited scalar "|".)
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          ' || CAST(SUBSTRING(r_ds.source_query FROM 1 FOR 30000) AS VARCHAR(30000)));
        END IF;
        IF r_ds.granularity_desc IS NOT NULL THEN
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        granularity: "' || OREPLACE(r_ds.granularity_desc, '"', '\"') || '"');
        END IF;

        -- Primary key
        IF EXISTS (SELECT 1 FROM demo_user.DATASET_KEY dk WHERE dk.dataset_id = v_dt_id AND dk.key_type='PK') THEN
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        primary_key:');
            FOR r_pk AS cur_pk CURSOR FOR
                SELECT f.field_name
                  FROM demo_user.DATASET_KEY dk
                  JOIN demo_user.FIELD f ON dk.field_id = f.field_id
                 WHERE dk.dataset_id = v_dt_id AND dk.key_type = 'PK'
              ORDER BY dk.column_position
            DO
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          - ' || r_pk.field_name);
            END FOR;
        END IF;

        -- Fields
        SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        fields:');
        FOR r_fld AS cur_fld CURSOR FOR
            SELECT f.field_id, f.field_name, f.field_type_code, f.expression, f.description,
                   f.label, f.is_dimension, f.is_time_dimension, f.data_type, f.ColumnName,
                   ac.synonyms, ac.display_name
              FROM demo_user.FIELD f
              LEFT JOIN demo_user.AI_CONTEXT ac
                     ON ac.entity_type='FIELD' AND ac.entity_id=f.field_id
             WHERE f.dataset_id = v_dt_id
          ORDER BY f.field_order, f.field_id
        DO
            SET v_fld_id = r_fld.field_id;
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          - name: ' || r_fld.field_name);
            IF r_fld.description IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '            description: "' || OREPLACE(r_fld.description, '"', '\"') || '"');
            END IF;
            IF r_fld.data_type IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '            data_type: ' || r_fld.data_type);
            END IF;
            IF r_fld.expression IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '            expression:');
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '              dialects:');
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '                - dialect: ANSI_SQL');
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '                  expression: "' || OREPLACE(r_fld.expression, '"', '\"') || '"');
            END IF;
            IF r_fld.is_dimension = 1 THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '            dimension:');
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '              is_time: ' || CASE WHEN r_fld.is_time_dimension=1 THEN 'true' ELSE 'false' END);
            END IF;
            IF r_fld.field_type_code = 'K' THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '            is_key: true');
            END IF;
            IF r_fld.display_name IS NOT NULL OR r_fld.synonyms IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '            ai_context:');
                IF r_fld.display_name IS NOT NULL THEN
                    SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '              display_name: "' || OREPLACE(r_fld.display_name, '"', '\"') || '"');
                END IF;
                IF r_fld.synonyms IS NOT NULL THEN
                    SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '              synonyms: ' || CAST(r_fld.synonyms AS VARCHAR(4000)));
                END IF;
            END IF;
        END FOR;
    END FOR;

    -- -------------------- Relationships --------------------
    IF EXISTS (SELECT 1 FROM demo_user.RELATIONSHIP r
                JOIN demo_user.DATASET df ON r.from_dataset_id=df.dataset_id
               WHERE df.model_id = v_model_id) THEN
        SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '    relationships:');
        FOR r_rel AS cur_rel CURSOR FOR
            SELECT r.relationship_id, r.relationship_name, r.description,
                   r.cardinality, r.join_type_hint,
                   df.dataset_name AS from_ds, dt.dataset_name AS to_ds
              FROM demo_user.RELATIONSHIP r
              JOIN demo_user.DATASET df ON r.from_dataset_id = df.dataset_id
              JOIN demo_user.DATASET dt ON r.to_dataset_id   = dt.dataset_id
             WHERE df.model_id = v_model_id
          ORDER BY r.relationship_id
        DO
            SET v_rel_id = r_rel.relationship_id;
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '      - name: ' || r_rel.relationship_name);
            IF r_rel.description IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        description: "' || OREPLACE(r_rel.description, '"', '\"') || '"');
            END IF;
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        from: ' || r_rel.from_ds);
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        to: ' || r_rel.to_ds);
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        cardinality: ' || r_rel.cardinality);
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        join_type: ' || r_rel.join_type_hint);
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        from_columns:');
            FOR r_fcol AS cur_fcol CURSOR FOR
                SELECT f.field_name
                  FROM demo_user.REL_COLUMN_MAP rcm
                  JOIN demo_user.FIELD f ON rcm.from_field_id = f.field_id
                 WHERE rcm.relationship_id = v_rel_id
              ORDER BY rcm.column_position
            DO
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          - ' || r_fcol.field_name);
            END FOR;
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        to_columns:');
            FOR r_tcol AS cur_tcol CURSOR FOR
                SELECT f.field_name
                  FROM demo_user.REL_COLUMN_MAP rcm
                  JOIN demo_user.FIELD f ON rcm.to_field_id = f.field_id
                 WHERE rcm.relationship_id = v_rel_id
              ORDER BY rcm.column_position
            DO
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          - ' || r_tcol.field_name);
            END FOR;
        END FOR;
    END IF;

    -- -------------------- Metrics --------------------
    IF EXISTS (SELECT 1 FROM demo_user.METRIC WHERE model_id = v_model_id) THEN
        SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '    metrics:');
        FOR r_m AS cur_m CURSOR FOR
            SELECT mt.metric_id, mt.metric_name, mt.description, mt.metric_type,
                   mt.is_additive, mt.is_certified, mt.default_time_grain,
                   ac.synonyms, ac.display_name, ac.instructions
              FROM demo_user.METRIC mt
              LEFT JOIN demo_user.AI_CONTEXT ac
                     ON ac.entity_type='METRIC' AND ac.entity_id=mt.metric_id
             WHERE mt.model_id = v_model_id
          ORDER BY mt.metric_id
        DO
            SET v_mt_id = r_m.metric_id;
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '      - name: ' || r_m.metric_name);
            IF r_m.description IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        description: "' || OREPLACE(r_m.description, '"', '\"') || '"');
            END IF;
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        metric_type: ' || r_m.metric_type);
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        is_additive: ' || CASE WHEN r_m.is_additive=1 THEN 'true' ELSE 'false' END);
            IF r_m.default_time_grain IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        default_time_grain: ' || r_m.default_time_grain);
            END IF;
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        expression:');
            SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          dialects:');
            FOR r_me AS cur_me CURSOR FOR
                SELECT dialect, expression
                  FROM demo_user.METRIC_EXPRESSION
                 WHERE metric_id = v_mt_id
              ORDER BY CASE WHEN dialect='ANSI_SQL' THEN 1 ELSE 2 END
            DO
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '            - dialect: ' || r_me.dialect);
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '              expression: "' || OREPLACE(CAST(r_me.expression AS VARCHAR(30000)), '"', '\"') || '"');
            END FOR;
            IF r_m.display_name IS NOT NULL OR r_m.synonyms IS NOT NULL OR r_m.instructions IS NOT NULL THEN
                SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '        ai_context:');
                IF r_m.display_name IS NOT NULL THEN
                    SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          display_name: "' || OREPLACE(r_m.display_name, '"', '\"') || '"');
                END IF;
                IF r_m.instructions IS NOT NULL THEN
                    SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          instructions: "' || OREPLACE(r_m.instructions, '"', '\"') || '"');
                END IF;
                IF r_m.synonyms IS NOT NULL THEN
                    SET v_line_no = v_line_no + 1; INSERT INTO demo_user.yaml_tmp VALUES (v_line_no, '          synonyms: ' || CAST(r_m.synonyms AS VARCHAR(4000)));
                END IF;
            END IF;
        END FOR;
    END IF;

    -- Return the lines as a dynamic result set
    BEGIN
        DECLARE c_result CURSOR WITH RETURN FOR
            SELECT line_no, line_text FROM demo_user.yaml_tmp ORDER BY line_no;
        OPEN c_result;
    END;
END;
