-- =========================================================================
-- m_semantic_search(p_term, p_model_name) — agent-facing discovery search.
--
-- Scans DATASET / FIELD / METRIC / VIEW and their AI_CONTEXT entries for
-- the supplied term, returning a ranked result set.
--
-- Match logic: a single LIKE per entity type against a concatenated
-- "haystack" of all searchable columns (separated by '|' so a match
-- cannot straddle column boundaries). The relevance CASE stays
-- per-field because each column contributes a different score.
--
-- Usage:
--     EXEC demo_user.m_semantic_search('revenue', 'tpch_osi');
--     EXEC demo_user.m_semantic_search('customer', NULL);
-- =========================================================================
REPLACE MACRO demo_user.m_semantic_search(
    p_term       VARCHAR(200),
    p_model_name VARCHAR(200)
) AS (

    SELECT * FROM (

        -- DATASETS
        SELECT CAST('DATASET' AS VARCHAR(20))                                                 AS entity_type,
               CAST(d.dataset_name AS VARCHAR(200))                                           AS entity_name,
               CAST(m.model_name AS VARCHAR(200))                                             AS parent_name,
               CAST(SUBSTRING(COALESCE(d.description,'') FROM 1 FOR 300) AS VARCHAR(300))     AS description,
               CAST(COALESCE(CAST(ac.synonyms AS VARCHAR(1000)), '') AS VARCHAR(1000))        AS synonyms,
               (CASE WHEN LOWER(d.dataset_name) = LOWER(:p_term)                              THEN CAST(100 AS INTEGER)
                     WHEN LOWER(d.dataset_name) LIKE '%' || LOWER(:p_term) || '%'             THEN CAST(70  AS INTEGER)
                     WHEN LOWER(COALESCE(ac.display_name,'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(60  AS INTEGER)
                     WHEN LOWER(COALESCE(CAST(ac.synonyms AS VARCHAR(1000)),'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(50 AS INTEGER)
                     WHEN LOWER(COALESCE(d.description,'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(20  AS INTEGER)
                     ELSE CAST(0 AS INTEGER) END)                                             AS relevance
          FROM demo_user.DATASET d
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id = m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='DATASET' AND ac.entity_id=d.dataset_id
         WHERE (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND LOWER(COALESCE(d.dataset_name,'') || '|' || COALESCE(d.description,'') || '|' || COALESCE(ac.display_name,'') || '|' || COALESCE(ac.instructions,'') || '|' || COALESCE(CAST(ac.synonyms AS VARCHAR(1000)),'')) LIKE '%' || LOWER(:p_term) || '%'

        UNION ALL

        -- FIELDS
        SELECT CAST('FIELD' AS VARCHAR(20)),
               CAST(f.field_name AS VARCHAR(200)),
               CAST(m.model_name || '.' || d.dataset_name AS VARCHAR(200)),
               CAST(SUBSTRING(COALESCE(f.description,'') FROM 1 FOR 300) AS VARCHAR(300)),
               CAST(COALESCE(CAST(ac.synonyms AS VARCHAR(1000)), '') AS VARCHAR(1000)),
               (CASE WHEN LOWER(f.field_name) = LOWER(:p_term)                                THEN CAST(100 AS INTEGER)
                     WHEN LOWER(f.field_name) LIKE '%' || LOWER(:p_term) || '%'               THEN CAST(75  AS INTEGER)
                     WHEN LOWER(COALESCE(f.label,'')) = LOWER(:p_term)                        THEN CAST(80  AS INTEGER)
                     WHEN LOWER(COALESCE(f.label,'')) LIKE '%' || LOWER(:p_term) || '%'       THEN CAST(55  AS INTEGER)
                     WHEN LOWER(COALESCE(ac.display_name,'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(55  AS INTEGER)
                     WHEN LOWER(COALESCE(CAST(ac.synonyms AS VARCHAR(1000)),'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(45 AS INTEGER)
                     WHEN LOWER(COALESCE(f.description,'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(20  AS INTEGER)
                     ELSE CAST(0 AS INTEGER) END)
          FROM demo_user.FIELD f
          JOIN demo_user.DATASET d ON f.dataset_id = d.dataset_id
          JOIN demo_user.SEMANTIC_MODEL m ON d.model_id = m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='FIELD' AND ac.entity_id=f.field_id
         WHERE (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND LOWER(COALESCE(f.field_name,'') || '|' || COALESCE(f.label,'') || '|' || COALESCE(f.description,'') || '|' || COALESCE(ac.display_name,'') || '|' || COALESCE(CAST(ac.synonyms AS VARCHAR(1000)),'')) LIKE '%' || LOWER(:p_term) || '%'

        UNION ALL

        -- METRICS
        SELECT CAST('METRIC' AS VARCHAR(20)),
               CAST(mt.metric_name AS VARCHAR(200)),
               CAST(m.model_name AS VARCHAR(200)),
               CAST(SUBSTRING(COALESCE(mt.description,'') FROM 1 FOR 300) AS VARCHAR(300)),
               CAST(COALESCE(CAST(ac.synonyms AS VARCHAR(1000)), '') AS VARCHAR(1000)),
               (CASE WHEN LOWER(mt.metric_name) = LOWER(:p_term)                              THEN CAST(100 AS INTEGER)
                     WHEN LOWER(mt.metric_name) LIKE '%' || LOWER(:p_term) || '%'             THEN CAST(78  AS INTEGER)
                     WHEN LOWER(COALESCE(ac.display_name,'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(60  AS INTEGER)
                     WHEN LOWER(COALESCE(CAST(ac.synonyms AS VARCHAR(1000)),'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(50 AS INTEGER)
                     WHEN LOWER(COALESCE(mt.description,'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(25  AS INTEGER)
                     ELSE CAST(0 AS INTEGER) END)
          FROM demo_user.METRIC mt
          JOIN demo_user.SEMANTIC_MODEL m ON mt.model_id = m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='METRIC' AND ac.entity_id=mt.metric_id
         WHERE (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND LOWER(COALESCE(mt.metric_name,'') || '|' || COALESCE(mt.description,'') || '|' || COALESCE(ac.display_name,'') || '|' || COALESCE(ac.instructions,'') || '|' || COALESCE(CAST(ac.synonyms AS VARCHAR(1000)),'')) LIKE '%' || LOWER(:p_term) || '%'

        UNION ALL

        -- SEMANTIC VIEWS
        SELECT CAST('VIEW' AS VARCHAR(20)),
               CAST(v.view_name AS VARCHAR(200)),
               CAST(m.model_name AS VARCHAR(200)),
               CAST(SUBSTRING(COALESCE(v.description,'') FROM 1 FOR 300) AS VARCHAR(300)),
               CAST(COALESCE(CAST(ac.synonyms AS VARCHAR(1000)), '') AS VARCHAR(1000)),
               (CASE WHEN LOWER(v.view_name) = LOWER(:p_term)                                 THEN CAST(100 AS INTEGER)
                     WHEN LOWER(v.view_name) LIKE '%' || LOWER(:p_term) || '%'                THEN CAST(70  AS INTEGER)
                     WHEN LOWER(COALESCE(ac.display_name,'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(55  AS INTEGER)
                     WHEN LOWER(COALESCE(CAST(ac.synonyms AS VARCHAR(1000)),'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(45 AS INTEGER)
                     WHEN LOWER(COALESCE(v.description,'')) LIKE '%' || LOWER(:p_term) || '%' THEN CAST(25  AS INTEGER)
                     ELSE CAST(0 AS INTEGER) END)
          FROM demo_user.SEMANTIC_VIEW v
          JOIN demo_user.SEMANTIC_MODEL m ON v.model_id = m.model_id
          LEFT JOIN demo_user.AI_CONTEXT ac ON ac.entity_type='VIEW' AND ac.entity_id=v.view_id
         WHERE (:p_model_name IS NULL OR m.model_name = :p_model_name)
           AND LOWER(COALESCE(v.view_name,'') || '|' || COALESCE(v.description,'') || '|' || COALESCE(ac.display_name,'') || '|' || COALESCE(CAST(ac.synonyms AS VARCHAR(1000)),'')) LIKE '%' || LOWER(:p_term) || '%'

    ) h
    WHERE h.relevance > 0
    ORDER BY h.relevance DESC, h.entity_type, h.entity_name;
);
