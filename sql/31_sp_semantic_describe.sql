-- =========================================================================
-- m_semantic_describe(p_entity_type, p_entity_name, p_model_name)
-- Returns a long-form description pack for a single entity. Output is a
-- pivoted key/value result set so an agent can iterate attributes.
--
-- entity_type: MODEL | DATASET | FIELD | METRIC | VIEW
-- Usage:
--   EXEC demo_user.m_semantic_describe('METRIC', 'total_revenue', 'tpch_osi');
--   EXEC demo_user.m_semantic_describe('DATASET', 'lineitem', 'tpch_orders');
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
        SELECT 1 AS attr_ordinal, CAST('entity_type' AS VARCHAR(50)) AS attr_key, CAST('MODEL' AS VARCHAR(4000)) AS attr_value
          FROM demo_user.SEMANTIC_MODEL m
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name
        UNION ALL
        SELECT 2, 'name', m.model_name FROM demo_user.SEMANTIC_MODEL m
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name
        UNION ALL
        SELECT 3, 'description', SUBSTRING(COALESCE(m.description,'') FROM 1 FOR 4000)
          FROM demo_user.SEMANTIC_MODEL m
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name
        UNION ALL
        SELECT 4, 'owner', COALESCE(m.owner_user,'') || '/' || COALESCE(m.owner_group,'')
          FROM demo_user.SEMANTIC_MODEL m
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name
        UNION ALL
        SELECT 5, 'ai_instructions', COALESCE(ac.instructions,'')
          FROM demo_user.SEMANTIC_MODEL m
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='MODEL' AND ac.entity_id=m.model_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name AND ac.instructions IS NOT NULL
        UNION ALL
        SELECT 6, 'ai_synonyms', COALESCE(CAST(ac.synonyms AS VARCHAR(4000)),'')
          FROM demo_user.SEMANTIC_MODEL m
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='MODEL' AND ac.entity_id=m.model_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name AND ac.synonyms IS NOT NULL
        UNION ALL
        SELECT 10, 'dataset', d.dataset_name
          FROM demo_user.SEMANTIC_MODEL m
          JOIN demo_user.DATASET d ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name
        UNION ALL
        SELECT 11, 'metric', mt.metric_name
          FROM demo_user.SEMANTIC_MODEL m
          JOIN demo_user.METRIC mt ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name
        UNION ALL
        SELECT 12, 'view', v.view_name
          FROM demo_user.SEMANTIC_MODEL m
          JOIN demo_user.SEMANTIC_VIEW v ON v.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='MODEL' AND m.model_name = :p_entity_name

        UNION ALL

        -- =================== DATASET ===================
        SELECT 1, 'entity_type', 'DATASET'
          FROM demo_user.DATASET d
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 2, 'name', d.dataset_name FROM demo_user.DATASET d
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 3, 'model', m.model_name FROM demo_user.DATASET d
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 4, 'description', SUBSTRING(COALESCE(d.description,'') FROM 1 FOR 4000)
          FROM demo_user.DATASET d JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 5, 'granularity', COALESCE(d.granularity_desc,'')
          FROM demo_user.DATASET d JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 6, 'source_table',
               CASE WHEN d.DataBaseName IS NOT NULL THEN TRIM(d.DataBaseName) || '.' || TRIM(d.TableName) ELSE '' END
          FROM demo_user.DATASET d JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 7, 'has_source_query',
               CASE WHEN d.source_query IS NOT NULL THEN 'true' ELSE 'false' END
          FROM demo_user.DATASET d JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 20, 'pk_field', f.field_name
          FROM demo_user.DATASET d
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
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
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
          JOIN demo_user.FIELD f ON f.dataset_id=d.dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 40, 'outgoing_relationship',
               r.relationship_name || ' -> ' || dt.dataset_name || ' [' || r.cardinality || ']'
          FROM demo_user.DATASET d
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
          JOIN demo_user.RELATIONSHIP r ON r.from_dataset_id=d.dataset_id
          JOIN demo_user.DATASET dt ON dt.dataset_id=r.to_dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 41, 'incoming_relationship',
               r.relationship_name || ' <- ' || df.dataset_name || ' [' || r.cardinality || ']'
          FROM demo_user.DATASET d
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
          JOIN demo_user.RELATIONSHIP r ON r.to_dataset_id=d.dataset_id
          JOIN demo_user.DATASET df ON df.dataset_id=r.from_dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 50, 'ai_instructions', COALESCE(ac.instructions,'')
          FROM demo_user.DATASET d JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='DATASET' AND ac.entity_id=d.dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.instructions IS NOT NULL
        UNION ALL
        SELECT 51, 'ai_synonyms', COALESCE(CAST(ac.synonyms AS VARCHAR(4000)),'')
          FROM demo_user.DATASET d JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='DATASET' AND ac.entity_id=d.dataset_id
         WHERE UPPER(:p_entity_type)='DATASET' AND d.dataset_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.synonyms IS NOT NULL

        UNION ALL

        -- =================== FIELD ===================
        -- Field names can collide across datasets; p_model_name + p_entity_name is the
        -- natural key. To disambiguate, pass p_entity_name as 'dataset.field' OR accept
        -- all matches.
        SELECT 1, 'entity_type', 'FIELD'
          FROM demo_user.FIELD f
          JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 2, 'name', d.dataset_name || '.' || f.field_name
          FROM demo_user.FIELD f JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 3, 'label', COALESCE(f.label,'')
          FROM demo_user.FIELD f JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 4, 'description', SUBSTRING(COALESCE(f.description,'') FROM 1 FOR 4000)
          FROM demo_user.FIELD f JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 5, 'expression', COALESCE(f.expression,'')
          FROM demo_user.FIELD f JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 6, 'data_type', COALESCE(f.data_type,'')
          FROM demo_user.FIELD f JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 7, 'flags',
               'type=' || f.field_type_code ||
               CASE WHEN f.is_dimension=1 THEN ',dimension' ELSE '' END ||
               CASE WHEN f.is_time_dimension=1 THEN ',time' ELSE '' END
          FROM demo_user.FIELD f JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 10, 'ai_synonyms', COALESCE(CAST(ac.synonyms AS VARCHAR(4000)),'')
          FROM demo_user.FIELD f JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='FIELD' AND ac.entity_id=f.field_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.synonyms IS NOT NULL
        UNION ALL
        SELECT 11, 'format',
               fs.format_type ||
               CASE WHEN fs.currency_code IS NOT NULL THEN '|' || fs.currency_code ELSE '' END ||
               CASE WHEN fs.decimal_places IS NOT NULL THEN '|dp=' || TRIM(CAST(fs.decimal_places AS VARCHAR(4))) ELSE '' END
          FROM demo_user.FIELD f JOIN demo_user.DATASET d ON f.dataset_id=d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id=m.model_id
          JOIN demo_user.FORMAT_SPEC fs ON fs.entity_type='FIELD' AND fs.entity_id=f.field_id
         WHERE UPPER(:p_entity_type)='FIELD' AND (f.field_name = :p_entity_name
                OR d.dataset_name || '.' || f.field_name = :p_entity_name)
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)

        UNION ALL

        -- =================== METRIC ===================
        SELECT 1, 'entity_type', 'METRIC'
          FROM demo_user.METRIC mt
          JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 2, 'name', mt.metric_name
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 3, 'model', m.model_name
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 4, 'description', SUBSTRING(COALESCE(mt.description,'') FROM 1 FOR 4000)
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 5, 'metric_type', mt.metric_type
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 6, 'is_additive', CASE WHEN mt.is_additive=1 THEN 'true' ELSE 'false' END
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 7, 'is_certified', CASE WHEN mt.is_certified=1 THEN 'true' ELSE 'false' END
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 10, 'expression_' || me.dialect, CAST(me.expression AS VARCHAR(4000))
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          JOIN demo_user.METRIC_EXPRESSION me ON me.metric_id=mt.metric_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 20, 'field_ref', d.dataset_name || '.' || f.field_name || ' [' || mfr.dep_role || ']'
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          JOIN demo_user.METRIC_FIELD_REF mfr ON mfr.metric_id=mt.metric_id
          JOIN demo_user.FIELD f ON f.field_id=mfr.field_id
          JOIN demo_user.DATASET d ON d.dataset_id=f.dataset_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 30, 'ai_instructions', COALESCE(ac.instructions,'')
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='METRIC' AND ac.entity_id=mt.metric_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.instructions IS NOT NULL
        UNION ALL
        SELECT 31, 'ai_synonyms', COALESCE(CAST(ac.synonyms AS VARCHAR(4000)),'')
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='METRIC' AND ac.entity_id=mt.metric_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND ac.synonyms IS NOT NULL
        UNION ALL
        SELECT 32, 'format',
               fs.format_type ||
               CASE WHEN fs.currency_code IS NOT NULL THEN '|' || fs.currency_code ELSE '' END ||
               CASE WHEN fs.decimal_places IS NOT NULL THEN '|dp=' || TRIM(CAST(fs.decimal_places AS VARCHAR(4))) ELSE '' END
          FROM demo_user.METRIC mt JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id=m.model_id
          JOIN demo_user.FORMAT_SPEC fs ON fs.entity_type='METRIC' AND fs.entity_id=mt.metric_id
         WHERE UPPER(:p_entity_type)='METRIC' AND mt.metric_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)

        UNION ALL

        -- =================== VIEW ===================
        SELECT 1, 'entity_type', 'VIEW'
          FROM demo_user.SEMANTIC_VIEW v JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='VIEW' AND v.view_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 2, 'name', v.view_name
          FROM demo_user.SEMANTIC_VIEW v JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='VIEW' AND v.view_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 3, 'model', m.model_name
          FROM demo_user.SEMANTIC_VIEW v JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='VIEW' AND v.view_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 4, 'description', SUBSTRING(COALESCE(v.description,'') FROM 1 FOR 4000)
          FROM demo_user.SEMANTIC_VIEW v JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='VIEW' AND v.view_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 5, 'primary_dataset', d.dataset_name
          FROM demo_user.SEMANTIC_VIEW v JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
          LEFT JOIN demo_user.DATASET d ON d.dataset_id=v.primary_dataset_id
         WHERE UPPER(:p_entity_type)='VIEW' AND v.view_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND d.dataset_name IS NOT NULL
        UNION ALL
        SELECT 6, 'timeseries', COALESCE(v.timeseries_field,'')
          FROM demo_user.SEMANTIC_VIEW v JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
         WHERE UPPER(:p_entity_type)='VIEW' AND v.view_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
        UNION ALL
        SELECT 10 + vm.member_ordinal, 'member_' || vm.member_type,
               vm.member_name ||
               CASE WHEN vm.display_name IS NOT NULL THEN ' = "' || vm.display_name || '"' ELSE '' END
          FROM demo_user.SEMANTIC_VIEW v JOIN demo_user.SEMANTIC_MODEL m ON v.model_id=m.model_id
          JOIN demo_user.VIEW_MEMBER vm ON vm.view_id=v.view_id
         WHERE UPPER(:p_entity_type)='VIEW' AND v.view_name = :p_entity_name
           AND (:p_model_name IS NULL OR m.model_name = :p_model_name)
    ) x
    ORDER BY x.attr_ordinal, x.attr_key, x.attr_value;
);
