-- =========================================================================
-- m_semantic_describe(p_entity_type, p_entity_name, p_model_name)
-- Returns a long-form description pack for a single entity. Output is an
-- UNPIVOTED key/value result set so an agent can iterate attributes.
--
-- entity_type: MODEL | DATASET | FIELD | METRIC | VIEW
-- Usage:
--   EXEC demo_user.m_semantic_describe('METRIC', 'total_revenue', 'tpch_osi');
--   EXEC demo_user.m_semantic_describe('DATASET', 'lineitem', 'tpch_orders');
--
-- Implementation note: scalar attributes are flattened via UNPIVOT (one
-- JOIN per entity type) rather than N UNION-ALL branches. Multi-row
-- attributes (field list, relationships, view members, etc.) and
-- conditional attributes (ai_*, format, dialect-specific expressions)
-- stay as UNION ALL because they emit 0..N rows.
-- =========================================================================
REPLACE MACRO demo_user.m_semantic_describe(
    p_entity_type VARCHAR(20),
    p_entity_name VARCHAR(200),
    p_model_name  VARCHAR(200)
) AS (

    SELECT CAST(x.attr_ordinal AS INTEGER) AS attr_ordinal,
           CAST(x.attr_key AS VARCHAR(50)) AS attr_key,
           CAST(SUBSTRING(x.attr_value FROM 1 FOR 4000) AS VARCHAR(4000)) AS attr_value
    FROM (

        -- =================== MODEL ===================
        -- Scalar attrs: entity_type, name, description, owner
        SELECT (CASE u.attr_key
                    WHEN 'entity_type' THEN 1
                    WHEN 'name'        THEN 2
                    WHEN 'description' THEN 3
                    WHEN 'owner'       THEN 4 ELSE 99 END) AS attr_ordinal,
               u.attr_key, u.attr_value
        FROM (
            SELECT CAST('MODEL' AS VARCHAR(4000)) AS c_entity_type,
                   CAST(m.model_name AS VARCHAR(4000)) AS c_name,
                   CAST(SUBSTRING(COALESCE(m.description,'') FROM 1 FOR 4000) AS VARCHAR(4000)) AS c_description,
                   CAST(TRIM(COALESCE(m.owner_user,'')) || '/' || TRIM(COALESCE(m.owner_group,'')) AS VARCHAR(4000)) AS c_owner
              FROM demo_user.SEMANTIC_MODEL m
             WHERE UPPER(:p_entity_type) = 'MODEL' AND m.model_name = :p_entity_name
        ) src UNPIVOT (attr_value FOR attr_key IN (
            c_entity_type AS 'entity_type',
            c_name        AS 'name',
            c_description AS 'description',
            c_owner       AS 'owner'
        )) u

        UNION ALL
        SELECT 5, 'ai_instructions', ac.instructions
          FROM demo_user.SEMANTIC_MODEL m
          JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='MODEL' AND ac.entity_id=m.model_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name AND ac.instructions IS NOT NULL
        UNION ALL
        SELECT 6, 'ai_synonyms', CAST(ac.synonyms AS VARCHAR(4000))
          FROM demo_user.SEMANTIC_MODEL m
          JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='MODEL' AND ac.entity_id=m.model_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name AND ac.synonyms IS NOT NULL
        UNION ALL
        SELECT 10, 'dataset', d.dataset_name
          FROM demo_user.SEMANTIC_MODEL m
          JOIN demo_user.MODEL_DATASET md ON md.model_id=m.model_id
          JOIN demo_user.DATASET d ON d.dataset_id=md.dataset_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name
        UNION ALL
        SELECT 11, 'metric', mt.metric_name
          FROM demo_user.SEMANTIC_MODEL m
          JOIN demo_user.METRIC mt ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name

        UNION ALL

        -- =================== DATASET ===================
        -- Scalars: entity_type, name, model, description, granularity, source_table, has_source_query
        SELECT (CASE u.attr_key
                    WHEN 'entity_type'       THEN 1
                    WHEN 'name'              THEN 2
                    WHEN 'model'             THEN 3
                    WHEN 'description'       THEN 4
                    WHEN 'granularity'       THEN 5
                    WHEN 'source_table'      THEN 6
                    WHEN 'has_source_query'  THEN 7 ELSE 99 END) AS attr_ordinal,
               u.attr_key, u.attr_value
        FROM (
            SELECT CAST('DATASET' AS VARCHAR(4000)) AS c_entity_type,
                   CAST(d.dataset_name AS VARCHAR(4000)) AS c_name,
                   CAST(m.model_name AS VARCHAR(4000)) AS c_model,
                   CAST(SUBSTRING(COALESCE(d.description,'') FROM 1 FOR 4000) AS VARCHAR(4000)) AS c_description,
                   CAST(COALESCE(d.granularity_desc,'') AS VARCHAR(4000)) AS c_granularity,
                   CAST(CASE WHEN d.DataBaseName IS NOT NULL THEN TRIM(d.DataBaseName) || '.' || TRIM(d.TableName) ELSE '' END AS VARCHAR(4000)) AS c_source_table,
                   CAST(CASE WHEN d.source_query IS NOT NULL THEN 'true' ELSE 'false' END AS VARCHAR(4000)) AS c_has_source_query
              FROM demo_user.DATASET d
              JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
             WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
               AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        ) src UNPIVOT (attr_value FOR attr_key IN (
            c_entity_type      AS 'entity_type',
            c_name             AS 'name',
            c_model            AS 'model',
            c_description      AS 'description',
            c_granularity      AS 'granularity',
            c_source_table     AS 'source_table',
            c_has_source_query AS 'has_source_query'
        )) u

        UNION ALL
        SELECT 20, 'pk_field', f.field_name
          FROM demo_user.DATASET d
          JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
          JOIN demo_user.DATASET_KEY dk ON dk.dataset_id=d.dataset_id AND dk.key_type='PK'
          JOIN demo_user.FIELD f ON f.field_id=dk.field_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 30, 'field',
               f.field_name || ' : ' || COALESCE(f.data_type,'') ||
               CASE WHEN f.is_dimension=1 THEN ' (dim)' ELSE '' END ||
               CASE WHEN f.field_type_code='K' THEN ' (key)' ELSE '' END
          FROM demo_user.DATASET d
          JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
          JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 40, 'outgoing_relationship',
               r.relationship_name || ' -> ' || dt.dataset_name || ' [' || r.cardinality || ']'
          FROM demo_user.DATASET d
          JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
          JOIN demo_user.RELATIONSHIP r ON r.from_dataset_id=d.dataset_id
          JOIN demo_user.DATASET dt ON dt.dataset_id=r.to_dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 41, 'incoming_relationship',
               r.relationship_name || ' <- ' || df.dataset_name || ' [' || r.cardinality || ']'
          FROM demo_user.DATASET d
          JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
          JOIN demo_user.RELATIONSHIP r ON r.to_dataset_id=d.dataset_id
          JOIN demo_user.DATASET df ON df.dataset_id=r.from_dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 50, 'ai_instructions', ac.instructions
          FROM demo_user.DATASET d
          JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
          JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='DATASET' AND ac.entity_id=d.dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.instructions IS NOT NULL
        UNION ALL
        SELECT 51, 'ai_synonyms', CAST(ac.synonyms AS VARCHAR(4000))
          FROM demo_user.DATASET d
          JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
          JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='DATASET' AND ac.entity_id=d.dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.synonyms IS NOT NULL

        UNION ALL

        -- =================== FIELD ===================
        -- Field names can collide across datasets; p_model_name + p_entity_name is the
        -- natural key. To disambiguate, pass p_entity_name as 'dataset.field'.
        -- Scalars: entity_type, name, label, description, expression, data_type, flags
        SELECT (CASE u.attr_key
                    WHEN 'entity_type' THEN 1
                    WHEN 'name'        THEN 2
                    WHEN 'label'       THEN 3
                    WHEN 'description' THEN 4
                    WHEN 'expression'  THEN 5
                    WHEN 'data_type'   THEN 6
                    WHEN 'flags'       THEN 7 ELSE 99 END) AS attr_ordinal,
               u.attr_key, u.attr_value
        FROM (
            SELECT CAST('FIELD' AS VARCHAR(4000)) AS c_entity_type,
                   CAST(d.dataset_name || '.' || f.field_name AS VARCHAR(4000)) AS c_name,
                   CAST(COALESCE(f.label,'') AS VARCHAR(4000)) AS c_label,
                   CAST(SUBSTRING(COALESCE(f.description,'') FROM 1 FOR 4000) AS VARCHAR(4000)) AS c_description,
                   CAST(COALESCE(f.expression,'') AS VARCHAR(4000)) AS c_expression,
                   CAST(COALESCE(f.data_type,'') AS VARCHAR(4000)) AS c_data_type,
                   CAST('type=' || f.field_type_code ||
                        CASE WHEN f.is_dimension=1 THEN ',dimension' ELSE '' END ||
                        CASE WHEN f.is_time_dimension=1 THEN ',time' ELSE '' END
                        AS VARCHAR(4000)) AS c_flags
              FROM demo_user.FIELD f
              JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
              JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
             WHERE UPPER(:p_entity_type)='FIELD'
               AND (f.field_name = :p_entity_name
                    OR d.dataset_name || '.' || f.field_name = :p_entity_name)
               AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        ) src UNPIVOT (attr_value FOR attr_key IN (
            c_entity_type AS 'entity_type',
            c_name        AS 'name',
            c_label       AS 'label',
            c_description AS 'description',
            c_expression  AS 'expression',
            c_data_type   AS 'data_type',
            c_flags       AS 'flags'
        )) u

        UNION ALL
        SELECT 10, 'ai_synonyms', CAST(ac.synonyms AS VARCHAR(4000))
          FROM demo_user.FIELD f
          JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
          JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='FIELD' AND ac.entity_id=f.field_id
         WHERE UPPER(:p_entity_type)='FIELD'
           AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.synonyms IS NOT NULL
        UNION ALL
        SELECT 11, 'format',
               fs.format_type ||
               CASE WHEN fs.currency_code IS NOT NULL THEN '|' || fs.currency_code ELSE '' END ||
               CASE WHEN fs.decimal_places IS NOT NULL THEN '|dp=' || TRIM(CAST(fs.decimal_places AS VARCHAR(4))) ELSE '' END
          FROM demo_user.FIELD f
          JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.MODEL_DATASET md ON md.dataset_id=d.dataset_id
              JOIN demo_user.SEMANTIC_MODEL m ON m.model_id=md.model_id
          JOIN demo_user.FORMAT_SPEC fs ON fs.entity_type='FIELD' AND fs.entity_id=f.field_id
         WHERE UPPER(:p_entity_type)='FIELD'
           AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)

        UNION ALL

        -- =================== METRIC ===================
        -- Scalars: entity_type, name, model, description, metric_type, is_additive, is_certified
        SELECT (CASE u.attr_key
                    WHEN 'entity_type'  THEN 1
                    WHEN 'name'         THEN 2
                    WHEN 'model'        THEN 3
                    WHEN 'description'  THEN 4
                    WHEN 'metric_type'  THEN 5
                    WHEN 'is_additive'  THEN 6
                    WHEN 'is_certified' THEN 7 ELSE 99 END) AS attr_ordinal,
               u.attr_key, u.attr_value
        FROM (
            SELECT CAST('METRIC' AS VARCHAR(4000)) AS c_entity_type,
                   CAST(mt.metric_name AS VARCHAR(4000)) AS c_name,
                   CAST(m.model_name AS VARCHAR(4000)) AS c_model,
                   CAST(SUBSTRING(COALESCE(mt.description,'') FROM 1 FOR 4000) AS VARCHAR(4000)) AS c_description,
                   CAST(COALESCE(mt.metric_type,'') AS VARCHAR(4000)) AS c_metric_type,
                   CAST(CASE WHEN mt.is_additive=1 THEN 'true' ELSE 'false' END AS VARCHAR(4000)) AS c_is_additive,
                   CAST(CASE WHEN mt.is_certified=1 THEN 'true' ELSE 'false' END AS VARCHAR(4000)) AS c_is_certified
              FROM demo_user.METRIC mt
              JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
             WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
               AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        ) src UNPIVOT (attr_value FOR attr_key IN (
            c_entity_type  AS 'entity_type',
            c_name         AS 'name',
            c_model        AS 'model',
            c_description  AS 'description',
            c_metric_type  AS 'metric_type',
            c_is_additive  AS 'is_additive',
            c_is_certified AS 'is_certified'
        )) u

        UNION ALL
        SELECT 10, 'expression_' || me.dialect, CAST(me.expression AS VARCHAR(4000))
          FROM demo_user.METRIC mt
          JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          JOIN demo_user.METRIC_EXPRESSION me ON me.metric_id=mt.metric_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 20, 'field_ref', d.dataset_name || '.' || f.field_name || ' [' || mfr.dep_role || ']'
          FROM demo_user.METRIC mt
          JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          JOIN demo_user.METRIC_FIELD_REF mfr ON mfr.metric_id=mt.metric_id
          JOIN demo_user.FIELD f ON f.field_id=mfr.field_id
          JOIN demo_user.DATASET d ON d.dataset_id=f.dataset_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 30, 'ai_instructions', ac.instructions
          FROM demo_user.METRIC mt
          JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='METRIC' AND ac.entity_id=mt.metric_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.instructions IS NOT NULL
        UNION ALL
        SELECT 31, 'ai_synonyms', CAST(ac.synonyms AS VARCHAR(4000))
          FROM demo_user.METRIC mt
          JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='METRIC' AND ac.entity_id=mt.metric_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.synonyms IS NOT NULL
        UNION ALL
        SELECT 32, 'format',
               fs.format_type ||
               CASE WHEN fs.currency_code IS NOT NULL THEN '|' || fs.currency_code ELSE '' END ||
               CASE WHEN fs.decimal_places IS NOT NULL THEN '|dp=' || TRIM(CAST(fs.decimal_places AS VARCHAR(4))) ELSE '' END
          FROM demo_user.METRIC mt
          JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          JOIN demo_user.FORMAT_SPEC fs ON fs.entity_type='METRIC' AND fs.entity_id=mt.metric_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)

    ) x
    ORDER BY x.attr_ordinal, x.attr_key, x.attr_value;
);
