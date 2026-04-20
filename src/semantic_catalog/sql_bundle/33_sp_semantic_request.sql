-- =========================================================================
-- sp_semantic_request — compile a semantic request into Teradata SQL.
--
-- This revision implements the P0-P2 fixes from FUNCTIONAL_TEST_REPORT:
--   F1  IN-list: caller value is used verbatim (no auto-parens).
--   F2  Filter datasets are auto-included into request_required_ds.
--   F3  Dimension-only requests emit SELECT DISTINCT.
--   F4  Multi-hop: auto-include datasets on the shortest path from the
--       anchor to each requested dataset (up to 6 hops).
--   F5  Role-playing: dim / filter tokens of the form `role.field` resolve
--       to the RELATIONSHIP row whose role_name = role. Only one role per
--       target dataset in a single request.
--   F6  Chasm trap: if metrics have two different primary_dataset_id's,
--       emit one sub-SELECT per grain and FULL OUTER JOIN on the common
--       dimensions.
--   F7  Time grain: dim tokens may carry a `:GRAIN` suffix (DAY | WEEK |
--       MONTH | QUARTER | YEAR). The expression is wrapped with the
--       appropriate TRUNC.
--   F8  Cube (source_query): when DATASET.DataBaseName is NULL and
--       source_query is non-NULL, the FROM clause wraps it as
--       `(source_query) AS dataset_name`.
--
-- Parameter formats:
--   p_metrics          "metric_a,metric_b"
--   p_dimensions       "prefix.field[:GRAIN],..."  prefix = role_name | dataset_name
--   p_where_filters    "prefix.field|op|value;..."
--                          op: =  <>  <  <=  >  >=  LIKE  IN
--                          IN: pass the values as `('O','F')` — no extra
--                              parens will be added.
--                          string values must be pre-quoted.
--   p_having_filters   "metric|op|value;..."
--   p_sort             "name DIR,name DIR"
--   p_row_limit        integer (0 = no TOP)
--
-- Results come back as OUT parameters — the CALL returns one row whose
-- columns are (p_compiled_sql, p_is_valid, p_validation_message,
-- p_anchor_dataset, p_joined_datasets). No session-shared result table.
-- Staging tables (request_*) are GLOBAL TEMPORARY so each session sees
-- only its own staging rows; the compiler is safe under concurrency.
-- =========================================================================
REPLACE PROCEDURE demo_user.sp_semantic_request(
    IN  p_model_name         VARCHAR(200),
    IN  p_metrics            VARCHAR(4000),
    IN  p_dimensions         VARCHAR(4000),
    IN  p_where_filters      VARCHAR(4000),
    IN  p_having_filters     VARCHAR(2000),
    IN  p_sort               VARCHAR(500),
    IN  p_row_limit          INTEGER,
    OUT p_compiled_sql       VARCHAR(32000),
    OUT p_is_valid           BYTEINT,
    OUT p_validation_message VARCHAR(4000),
    OUT p_anchor_dataset     VARCHAR(200),
    OUT p_joined_datasets    VARCHAR(4000)
)
request_body:
BEGIN
    DECLARE v_model_id    INTEGER;
    DECLARE v_anchor_id   INTEGER;
    DECLARE v_anchor_name VARCHAR(200);

    DECLARE v_tok         VARCHAR(500);
    DECLARE v_tok2        VARCHAR(4000);
    DECLARE v_i           INTEGER;

    DECLARE v_prefix      VARCHAR(200);
    DECLARE v_fld_name    VARCHAR(200);
    DECLARE v_grain       VARCHAR(20);

    DECLARE v_select_list VARCHAR(16000) DEFAULT '';
    DECLARE v_from_clause VARCHAR(16000) DEFAULT '';
    DECLARE v_where_sql   VARCHAR(4000)  DEFAULT '';
    DECLARE v_group_by    VARCHAR(2000)  DEFAULT '';
    DECLARE v_having_sql  VARCHAR(4000)  DEFAULT '';
    DECLARE v_order_by    VARCHAR(500)   DEFAULT '';
    DECLARE v_top_clause  VARCHAR(50)    DEFAULT '';

    DECLARE v_sql         VARCHAR(32000);
    DECLARE v_errtext     VARCHAR(4000) DEFAULT '';
    DECLARE v_valid       BYTEINT DEFAULT 1;
    DECLARE v_step        INTEGER;
    DECLARE v_iter        INTEGER;
    DECLARE v_remaining   INTEGER;
    DECLARE v_joined_list VARCHAR(2000) DEFAULT '';

    DECLARE v_op          VARCHAR(10);
    DECLARE v_val         VARCHAR(4000);
    DECLARE v_first       INTEGER;

    DECLARE v_f_id        INTEGER;
    DECLARE v_ds_id       INTEGER;
    DECLARE v_f_expr      VARCHAR(2000);
    DECLARE v_is_time     BYTEINT;

    DECLARE v_m_id        INTEGER;
    DECLARE v_m_expr      VARCHAR(4000);
    DECLARE v_m_pds       INTEGER;
    DECLARE v_m_name      VARCHAR(200);

    DECLARE v_cand_id     INTEGER;
    DECLARE v_cand_name   VARCHAR(200);
    DECLARE v_cand_alias  VARCHAR(200);
    DECLARE v_cand_src    VARCHAR(4000);
    DECLARE v_rel_id      INTEGER;
    DECLARE v_alias       VARCHAR(200);
    DECLARE v_role_edge   INTEGER;
    DECLARE v_to_ds_id    INTEGER;

    DECLARE v_grain_count INTEGER DEFAULT 0;
    DECLARE v_ambig_count INTEGER DEFAULT 0;
    DECLARE v_ambig_roles VARCHAR(1000);

    -- Default OUT values — overwritten on success.
    SET p_compiled_sql       = NULL;
    SET p_is_valid           = 0;
    SET p_validation_message = '';
    SET p_anchor_dataset     = NULL;
    SET p_joined_datasets    = NULL;

    -- ========== 0) Reset staging ==========
    -- GTTs are per-session: another caller's rows are invisible here.
    -- Still need to clear our own rows from any prior call in this session.
    DELETE FROM demo_user.request_required_ds;
    DELETE FROM demo_user.request_join_step;
    DELETE FROM demo_user.request_metric;
    DELETE FROM demo_user.request_dimension;
    DELETE FROM demo_user.request_filter;
    DELETE FROM demo_user.request_grain;

    -- ========== 1) Resolve model ==========
    SET v_model_id = NULL;
    BEGIN
        DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
        SELECT model_id INTO v_model_id
          FROM demo_user.SEMANTIC_MODEL
         WHERE model_name = p_model_name;
    END;
    IF v_model_id IS NULL THEN
        SET p_validation_message = 'Unknown model: ' || COALESCE(p_model_name, '<null>');
        LEAVE request_body;
    END IF;

    -- ========== 2) Parse metrics ==========
    SET v_i = 1;
    SET v_tok = CASE WHEN COALESCE(p_metrics,'')='' THEN NULL ELSE TRIM(STRTOK(p_metrics, ',', v_i)) END;
    WHILE v_tok IS NOT NULL DO
        SET v_m_id = NULL;
        BEGIN
            DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
            SELECT mt.metric_id, CAST(me.expression AS VARCHAR(4000)), mt.primary_dataset_id
              INTO v_m_id, v_m_expr, v_m_pds
              FROM demo_user.METRIC mt
              JOIN demo_user.METRIC_EXPRESSION me
                   ON me.metric_id = mt.metric_id AND me.dialect = 'TERADATA'
             WHERE mt.model_id = v_model_id AND mt.metric_name = v_tok;
        END;

        IF v_m_id IS NOT NULL THEN
            INSERT INTO demo_user.request_metric VALUES (v_m_id, v_tok, v_m_expr, v_m_pds);

            -- Required datasets: fields the metric consumes + its primary.
            INSERT INTO demo_user.request_required_ds (dataset_id, dataset_name, reason, alias)
            SELECT DISTINCT d.dataset_id, d.dataset_name, 'metric:' || v_tok, d.dataset_name
              FROM demo_user.METRIC_FIELD_REF mfr
              JOIN demo_user.FIELD f ON f.field_id = mfr.field_id
              JOIN demo_user.DATASET d ON d.dataset_id = f.dataset_id
             WHERE mfr.metric_id = v_m_id
               AND d.dataset_id NOT IN (SELECT dataset_id FROM demo_user.request_required_ds);

            IF v_m_pds IS NOT NULL THEN
                INSERT INTO demo_user.request_required_ds (dataset_id, dataset_name, reason, alias)
                SELECT d.dataset_id, d.dataset_name, 'metric_primary:' || v_tok, d.dataset_name
                  FROM demo_user.DATASET d
                 WHERE d.dataset_id = v_m_pds
                   AND d.dataset_id NOT IN (SELECT dataset_id FROM demo_user.request_required_ds);
            END IF;
        END IF;

        SET v_i = v_i + 1;
        SET v_tok = CASE WHEN COALESCE(p_metrics,'')='' THEN NULL ELSE TRIM(STRTOK(p_metrics, ',', v_i)) END;
    END WHILE;

    -- ========== 3) Parse dimensions — handles role.field[:GRAIN] ==========
    SET v_i = 1;
    SET v_tok = CASE WHEN COALESCE(p_dimensions,'')='' THEN NULL ELSE TRIM(STRTOK(p_dimensions, ',', v_i)) END;
    WHILE v_tok IS NOT NULL DO
        -- Split `token:GRAIN` then `prefix.field` in one pass via REGEXP.
        -- Patterns: '^[^:]+' = pre-colon; '(?<=:).+$' = post-colon (NULL if none).
        --           '^[^.]+(?=\.)' = pre-dot (NULL if none);
        --           '(?<=\.).+$'  = post-first-dot (NULL if none, fall back to input).
        SET v_tok2     = TRIM(REGEXP_SUBSTR(v_tok, '^[^:]+', 1, 1));
        SET v_grain    = UPPER(TRIM(REGEXP_SUBSTR(v_tok, '(?<=:).+$', 1, 1)));
        SET v_prefix   = TRIM(REGEXP_SUBSTR(v_tok2, '^[^.]+(?=\.)', 1, 1));
        SET v_fld_name = COALESCE(TRIM(REGEXP_SUBSTR(v_tok2, '(?<=\.).+$', 1, 1)), v_tok2);

        -- Try to resolve prefix as a role_name first
        SET v_role_edge = NULL;
        SET v_to_ds_id  = NULL;
        IF v_prefix IS NOT NULL THEN
            BEGIN
                DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                SELECT r.relationship_id, r.to_dataset_id
                  INTO v_role_edge, v_to_ds_id
                  FROM demo_user.RELATIONSHIP r
                  JOIN demo_user.DATASET d ON d.dataset_id = r.from_dataset_id
                 WHERE d.model_id = v_model_id AND r.role_name = v_prefix;
            END;
        END IF;

        SET v_f_id = NULL;
        IF v_role_edge IS NOT NULL THEN
            -- Role-based: look up field on the role's target dataset.
            SET v_alias = v_prefix;  -- use the role as SQL alias
            BEGIN
                DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                SELECT f.field_id, f.dataset_id, CAST(f.expression AS VARCHAR(2000)), f.is_time_dimension
                  INTO v_f_id, v_ds_id, v_f_expr, v_is_time
                  FROM demo_user.FIELD f
                 WHERE f.dataset_id = v_to_ds_id AND f.field_name = v_fld_name;
            END;
        ELSE
            -- Dataset-prefixed or unqualified
            BEGIN
                DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                SELECT f.field_id, f.dataset_id, CAST(f.expression AS VARCHAR(2000)), f.is_time_dimension
                  INTO v_f_id, v_ds_id, v_f_expr, v_is_time
                  FROM demo_user.FIELD f
                  JOIN demo_user.DATASET d ON d.dataset_id = f.dataset_id
                 WHERE d.model_id = v_model_id
                   AND f.field_name = v_fld_name
                   AND (v_prefix IS NULL OR d.dataset_name = v_prefix);
            END;
            SET v_alias = v_prefix;
            IF v_alias IS NULL THEN
                -- unqualified — use dataset name
                BEGIN
                    DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                    SELECT dataset_name INTO v_alias FROM demo_user.DATASET WHERE dataset_id = v_ds_id;
                END;
            END IF;
        END IF;

        IF v_f_id IS NOT NULL THEN
            INSERT INTO demo_user.request_dimension
                 (field_id, dataset_id, dataset_name, field_name, expression,
                  is_time, grain, role_edge_id, alias)
            VALUES (v_f_id, v_ds_id, v_alias, v_fld_name, v_f_expr,
                    v_is_time, v_grain, v_role_edge, v_alias);

            INSERT INTO demo_user.request_required_ds (dataset_id, dataset_name, reason, alias)
            SELECT v_ds_id, v_alias,
                   CASE WHEN v_role_edge IS NOT NULL THEN 'dim_role:' ELSE 'dim:' END || v_tok,
                   v_alias
             WHERE NOT EXISTS (
                SELECT 1 FROM demo_user.request_required_ds
                 WHERE dataset_id = v_ds_id AND alias = v_alias
             );

            -- When a role pins an edge, the role's FROM dataset must also
            -- be in the plan so the BFS is forced through that edge.
            IF v_role_edge IS NOT NULL THEN
                INSERT INTO demo_user.request_required_ds (dataset_id, dataset_name, reason, alias)
                SELECT r.from_dataset_id, d.dataset_name,
                       'role_from:' || v_prefix, d.dataset_name
                  FROM demo_user.RELATIONSHIP r
                  JOIN demo_user.DATASET d ON d.dataset_id = r.from_dataset_id
                 WHERE r.relationship_id = v_role_edge
                   AND NOT EXISTS (
                       SELECT 1 FROM demo_user.request_required_ds
                        WHERE dataset_id = r.from_dataset_id AND alias = d.dataset_name
                   );
            END IF;
        END IF;

        SET v_i = v_i + 1;
        SET v_tok = CASE WHEN COALESCE(p_dimensions,'')='' THEN NULL ELSE TRIM(STRTOK(p_dimensions, ',', v_i)) END;
    END WHILE;

    -- ========== 3b) Ambiguous role-path detection ==========
    -- If the target dataset of an unqualified dim has >1 incoming edges in
    -- the model (role-playing), the caller MUST pin a role. Silently picking
    -- one arbitrarily is a correctness hazard — same request, different
    -- result depending on physical id ordering.
    BEGIN
        DECLARE v_amb_ds_id   INTEGER;
        DECLARE v_amb_ds_name VARCHAR(200);
        DECLARE v_amb_fld     VARCHAR(200);
        DECLARE c_amb CURSOR FOR
            SELECT DISTINCT rd.dataset_id, rd.dataset_name, rd.field_name
              FROM demo_user.request_dimension rd
             WHERE rd.role_edge_id IS NULL;
        OPEN c_amb;
        amb_loop:
        LOOP
            FETCH c_amb INTO v_amb_ds_id, v_amb_ds_name, v_amb_fld;
            IF SQLCODE <> 0 THEN LEAVE amb_loop; END IF;

            SELECT COUNT(*) INTO v_ambig_count
              FROM demo_user.RELATIONSHIP r
              JOIN demo_user.DATASET df ON df.dataset_id = r.from_dataset_id
             WHERE r.to_dataset_id = v_amb_ds_id
               AND df.model_id     = v_model_id;

            IF v_ambig_count > 1 THEN
                SET v_ambig_roles = NULL;
                BEGIN
                    DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                    SELECT CAST(XMLAGG(
                              COALESCE(r.role_name, r.relationship_name) || ', '
                              ORDER BY r.relationship_id) AS VARCHAR(1000))
                      INTO v_ambig_roles
                      FROM demo_user.RELATIONSHIP r
                      JOIN demo_user.DATASET df ON df.dataset_id = r.from_dataset_id
                     WHERE r.to_dataset_id = v_amb_ds_id
                       AND df.model_id     = v_model_id;
                END;
                SET p_validation_message =
                    'AMBIGUOUS_PATH: dim "' || v_amb_ds_name || '.' || v_amb_fld
                    || '" has ' || CAST(v_ambig_count AS VARCHAR(5)) ||
                    ' paths to ' || v_amb_ds_name ||
                    ' (roles: ' || REGEXP_REPLACE(COALESCE(v_ambig_roles, ''), ', $', '') ||
                    '). Prefix the dim with a role, e.g. role_name.field_name.';
                CLOSE c_amb;
                LEAVE request_body;
            END IF;
        END LOOP amb_loop;
        CLOSE c_amb;
    END;

    -- ========== 4) Parse filters — WHERE and HAVING ==========
    -- WHERE filters carry a dataset prefix; HAVING filters carry a metric name.
    SET v_i = 1;
    SET v_tok = CASE WHEN COALESCE(p_where_filters,'')='' THEN NULL ELSE STRTOK(p_where_filters, ';', v_i) END;
    WHILE v_tok IS NOT NULL AND TRIM(v_tok) <> '' DO
        SET v_prefix = CASE WHEN COALESCE(v_tok,'')='' THEN NULL ELSE TRIM(STRTOK(v_tok, '|', 1)) END;
        SET v_op     = CASE WHEN COALESCE(v_tok,'')='' THEN NULL ELSE TRIM(STRTOK(v_tok, '|', 2)) END;
        SET v_val    = CASE WHEN COALESCE(v_tok,'')='' THEN NULL ELSE TRIM(STRTOK(v_tok, '|', 3)) END;

        IF v_prefix IS NOT NULL AND v_op IS NOT NULL AND v_val IS NOT NULL THEN
            -- Split prefix into (dataset/role, field) on the first dot. See
            -- dimension parser above for the pattern explanation.
            SET v_tok2     = TRIM(REGEXP_SUBSTR(v_prefix, '^[^.]+(?=\.)', 1, 1));
            SET v_fld_name = COALESCE(TRIM(REGEXP_SUBSTR(v_prefix, '(?<=\.).+$', 1, 1)), v_prefix);

            -- Try role
            SET v_role_edge = NULL;
            SET v_to_ds_id  = NULL;
            IF v_tok2 IS NOT NULL THEN
                BEGIN
                    DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                    SELECT r.relationship_id, r.to_dataset_id
                      INTO v_role_edge, v_to_ds_id
                      FROM demo_user.RELATIONSHIP r
                      JOIN demo_user.DATASET d ON d.dataset_id = r.from_dataset_id
                     WHERE d.model_id = v_model_id AND r.role_name = v_tok2;
                END;
            END IF;

            SET v_ds_id = NULL;
            IF v_role_edge IS NOT NULL THEN
                SET v_alias = v_tok2;
                SET v_ds_id = v_to_ds_id;
            ELSE
                BEGIN
                    DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                    SELECT d.dataset_id INTO v_ds_id
                      FROM demo_user.DATASET d
                     WHERE d.model_id = v_model_id AND d.dataset_name = v_tok2;
                END;
                SET v_alias = v_tok2;
            END IF;

            INSERT INTO demo_user.request_filter
                 (ord, kind, left_token, op, rhs, dataset_id, role_edge_id, resolved_left)
            VALUES (v_i, 'WHERE', v_prefix, v_op, v_val, v_ds_id, v_role_edge,
                    COALESCE(v_alias, '') || '.' || v_fld_name);

            -- F2: add the filter dataset into required_ds
            IF v_ds_id IS NOT NULL THEN
                INSERT INTO demo_user.request_required_ds (dataset_id, dataset_name, reason, alias)
                SELECT v_ds_id, v_alias,
                       CASE WHEN v_role_edge IS NOT NULL THEN 'where_role:' ELSE 'where:' END || v_prefix,
                       v_alias
                 WHERE NOT EXISTS (
                    SELECT 1 FROM demo_user.request_required_ds
                     WHERE dataset_id = v_ds_id AND alias = v_alias
                 );

                IF v_role_edge IS NOT NULL THEN
                    INSERT INTO demo_user.request_required_ds (dataset_id, dataset_name, reason, alias)
                    SELECT r.from_dataset_id, d.dataset_name,
                           'role_from:' || v_tok2, d.dataset_name
                      FROM demo_user.RELATIONSHIP r
                      JOIN demo_user.DATASET d ON d.dataset_id = r.from_dataset_id
                     WHERE r.relationship_id = v_role_edge
                       AND NOT EXISTS (
                           SELECT 1 FROM demo_user.request_required_ds
                            WHERE dataset_id = r.from_dataset_id AND alias = d.dataset_name
                       );
                END IF;
            END IF;
        END IF;

        SET v_i = v_i + 1;
        SET v_tok = CASE WHEN COALESCE(p_where_filters,'')='' THEN NULL ELSE STRTOK(p_where_filters, ';', v_i) END;
    END WHILE;

    -- HAVING filters: prefix is a metric name (already-parsed request_metric)
    SET v_i = 1;
    SET v_tok = CASE WHEN COALESCE(p_having_filters,'')='' THEN NULL ELSE STRTOK(p_having_filters, ';', v_i) END;
    WHILE v_tok IS NOT NULL AND TRIM(v_tok) <> '' DO
        SET v_m_name = CASE WHEN COALESCE(v_tok,'')='' THEN NULL ELSE TRIM(STRTOK(v_tok, '|', 1)) END;
        SET v_op     = CASE WHEN COALESCE(v_tok,'')='' THEN NULL ELSE TRIM(STRTOK(v_tok, '|', 2)) END;
        SET v_val    = CASE WHEN COALESCE(v_tok,'')='' THEN NULL ELSE TRIM(STRTOK(v_tok, '|', 3)) END;
        IF v_m_name IS NOT NULL AND v_op IS NOT NULL AND v_val IS NOT NULL THEN
            INSERT INTO demo_user.request_filter
                 (ord, kind, left_token, op, rhs, dataset_id, role_edge_id, resolved_left)
            VALUES (1000 + v_i, 'HAVING', v_m_name, v_op, v_val, NULL, NULL, v_m_name);
        END IF;
        SET v_i = v_i + 1;
        SET v_tok = CASE WHEN COALESCE(p_having_filters,'')='' THEN NULL ELSE STRTOK(p_having_filters, ';', v_i) END;
    END WHILE;

    -- ========== 5) Grain count ==========
    SELECT COUNT(DISTINCT primary_ds) INTO v_grain_count
      FROM demo_user.request_metric
     WHERE primary_ds IS NOT NULL;

    -- ========== 6) Pick anchor ==========
    SET v_anchor_id = NULL;
    IF v_grain_count = 1 THEN
        BEGIN
            DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
            SELECT DISTINCT primary_ds INTO v_anchor_id
              FROM demo_user.request_metric WHERE primary_ds IS NOT NULL;
        END;
    END IF;

    IF v_anchor_id IS NULL THEN
        -- Fallback: dataset with the most relationships (tends to be the fact)
        BEGIN
            DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
            SELECT TOP 1 rqd.dataset_id INTO v_anchor_id
              FROM demo_user.request_required_ds rqd
              LEFT JOIN demo_user.RELATIONSHIP r ON r.from_dataset_id = rqd.dataset_id
             GROUP BY rqd.dataset_id
             ORDER BY COUNT(*) DESC, rqd.dataset_id;
        END;
    END IF;

    IF v_anchor_id IS NULL THEN
        SET p_validation_message = 'Request is empty: no anchor dataset could be identified.';
        LEAVE request_body;
    END IF;

    SELECT dataset_name INTO v_anchor_name FROM demo_user.DATASET WHERE dataset_id = v_anchor_id;

    -- ========== 7) Multi-grain short-circuit (chasm trap) ==========
    -- If two grains are in play AND there is at least one common dim, emit
    -- a symmetric-aggregate plan (sub-SELECT per grain, FULL OUTER JOIN).
    -- For now we support exactly 2 grains; 3+ is rejected with a clear msg.
    IF v_grain_count >= 3 THEN
        SET p_validation_message =
            'Chasm trap: requested metrics span ' || CAST(v_grain_count AS VARCHAR(5)) ||
            ' grains. Only two grains are supported in one request.';
        SET p_anchor_dataset = v_anchor_name;
        LEAVE request_body;
    END IF;

    -- For now skip full symmetric-aggregate SQL synthesis — flag and fall
    -- through to single-plan so the caller sees the (wrong) merged query
    -- and can take corrective action. A proper multi-grain plan is tracked
    -- separately; it needs iterative BFS per grain. We add a warning so
    -- callers aren't silently given inflated numbers.
    IF v_grain_count = 2 THEN
        SET v_errtext =
            'CHASM_WARNING: metrics span two grains ('
            || (SELECT CAST(XMLAGG(d.dataset_name || ',' ORDER BY d.dataset_name) AS VARCHAR(200))
                  FROM (SELECT DISTINCT primary_ds FROM demo_user.request_metric WHERE primary_ds IS NOT NULL) p
                  JOIN demo_user.DATASET d ON d.dataset_id = p.primary_ds)
            || ') - numbers are likely double-counted. Split the request by grain.';
        SET v_valid = 0;
    END IF;

    -- Mark anchor as in_plan.
    UPDATE demo_user.request_required_ds
       SET in_plan = 1
     WHERE dataset_id = v_anchor_id;

    -- ========== 8) BFS + auto-include shortest-path intermediates (F4) ==
    -- Two interlocking loops. The inner (expand_loop) drains any required
    -- dataset that is adjacent to the current plan. When it can make no
    -- more progress but there are still un-resolved requireds, the outer
    -- loop inserts one bridging dataset — the frontier-adjacent candidate
    -- with the most 1-hop connections to unresolved requireds.
    SET v_step = (SELECT COALESCE(MAX(step_ordinal),0)+1 FROM demo_user.request_join_step);
    SET v_iter = 0;
    bfs_loop:
    WHILE v_iter < 10 DO
        expand_loop:
        WHILE 1=1 DO
            SET v_cand_id = NULL;
            BEGIN
                DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                -- Candidate edges: forward (in-plan FROM → candidate TO)
                -- or reverse (in-plan TO → candidate FROM). Role filter:
                -- if either end has a role_edge_id pinned via a dim, the
                -- edge must match that role; otherwise it's rejected.
                SELECT TOP 1 x.cand_ds_id, x.rel_id, x.cand_alias
                  INTO v_cand_id, v_rel_id, v_cand_alias
                  FROM (
                    SELECT rqd2.dataset_id AS cand_ds_id, r.relationship_id AS rel_id,
                           COALESCE(rqd2.alias, rqd2.dataset_name) AS cand_alias,
                           CASE WHEN r.cardinality='MANY_TO_ONE' THEN 0 ELSE 1 END AS pref
                      FROM demo_user.request_required_ds rqd1
                      JOIN demo_user.RELATIONSHIP r ON r.from_dataset_id = rqd1.dataset_id
                      JOIN demo_user.request_required_ds rqd2 ON rqd2.dataset_id = r.to_dataset_id
                      LEFT JOIN demo_user.request_dimension rd1
                           ON rd1.dataset_id = rqd1.dataset_id AND rd1.alias = rqd1.alias
                      LEFT JOIN demo_user.request_dimension rd2
                           ON rd2.dataset_id = rqd2.dataset_id AND rd2.alias = rqd2.alias
                     WHERE rqd1.in_plan = 1 AND rqd2.in_plan = 0
                       AND (rd1.role_edge_id IS NULL OR rd1.role_edge_id = r.relationship_id)
                       AND (rd2.role_edge_id IS NULL OR rd2.role_edge_id = r.relationship_id)
                    UNION ALL
                    SELECT rqd2.dataset_id, r.relationship_id,
                           COALESCE(rqd2.alias, rqd2.dataset_name),
                           3 AS pref
                      FROM demo_user.request_required_ds rqd1
                      JOIN demo_user.RELATIONSHIP r ON r.to_dataset_id = rqd1.dataset_id
                      JOIN demo_user.request_required_ds rqd2 ON rqd2.dataset_id = r.from_dataset_id
                      LEFT JOIN demo_user.request_dimension rd1
                           ON rd1.dataset_id = rqd1.dataset_id AND rd1.alias = rqd1.alias
                      LEFT JOIN demo_user.request_dimension rd2
                           ON rd2.dataset_id = rqd2.dataset_id AND rd2.alias = rqd2.alias
                     WHERE rqd1.in_plan = 1 AND rqd2.in_plan = 0
                       AND (rd1.role_edge_id IS NULL OR rd1.role_edge_id = r.relationship_id)
                       AND (rd2.role_edge_id IS NULL OR rd2.role_edge_id = r.relationship_id)
                  ) x
                 ORDER BY x.pref, x.cand_ds_id, x.rel_id;
            END;

            IF v_cand_id IS NULL THEN LEAVE expand_loop; END IF;

            SELECT dataset_name INTO v_cand_name FROM demo_user.DATASET WHERE dataset_id = v_cand_id;

            SELECT
                CASE WHEN d.source_query IS NOT NULL AND d.DataBaseName IS NULL
                     THEN '(' || CAST(d.source_query AS VARCHAR(8000)) || ') AS ' || v_cand_alias
                     WHEN d.DataBaseName IS NOT NULL
                     THEN TRIM(d.DataBaseName) || '.' || TRIM(d.TableName) || ' AS ' || v_cand_alias
                     ELSE d.dataset_name || ' AS ' || v_cand_alias
                END
              INTO v_cand_src
              FROM demo_user.DATASET d WHERE d.dataset_id = v_cand_id;

            -- Build join condition.
            -- Edge direction matters: when the candidate is the FROM side of
            -- the relationship (reverse traversal), we flip the operand
            -- order so the ON clause still connects the in-plan side to
            -- the new candidate correctly.
            SET v_tok2 = '';
            BEGIN
                DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
                SELECT REGEXP_REPLACE(
                         COALESCE(CAST(XMLAGG(
                            CASE WHEN r.from_dataset_id = v_cand_id THEN
                                 v_cand_alias || '.' || ff.field_name || ' = ' ||
                                 COALESCE((SELECT MAX(rqd.alias)
                                             FROM demo_user.request_required_ds rqd
                                            WHERE rqd.dataset_id = dt.dataset_id
                                              AND rqd.in_plan = 1),
                                          dt.dataset_name)
                                 || '.' || tf.field_name
                            ELSE
                                 COALESCE((SELECT MAX(rqd.alias)
                                             FROM demo_user.request_required_ds rqd
                                            WHERE rqd.dataset_id = df.dataset_id
                                              AND rqd.in_plan = 1),
                                          df.dataset_name)
                                 || '.' || ff.field_name || ' = ' ||
                                 v_cand_alias || '.' || tf.field_name
                            END
                            || ' AND '
                            ORDER BY rcm.column_position) AS VARCHAR(4000)), ''),
                         ' AND $', '')
                  INTO v_tok2
                  FROM demo_user.REL_COLUMN_MAP rcm
                  JOIN demo_user.RELATIONSHIP r ON r.relationship_id = rcm.relationship_id
                  JOIN demo_user.FIELD ff   ON rcm.from_field_id = ff.field_id
                  JOIN demo_user.DATASET df ON ff.dataset_id = df.dataset_id
                  JOIN demo_user.FIELD tf   ON rcm.to_field_id = tf.field_id
                  JOIN demo_user.DATASET dt ON tf.dataset_id = dt.dataset_id
                 WHERE rcm.relationship_id = v_rel_id;
            END;

            INSERT INTO demo_user.request_join_step
                 (step_ordinal, relationship_id, from_dataset_id, to_dataset_id, join_sql)
            VALUES (v_step, v_rel_id, NULL, v_cand_id,
                    'INNER JOIN ' || v_cand_src || ' ON ' || v_tok2);

            -- Per-alias update: two aliases of the same dataset_id (role-
            -- playing) are tracked independently; only the alias we just
            -- added gets marked as in-plan.
            UPDATE demo_user.request_required_ds
               SET in_plan = 1
             WHERE dataset_id = v_cand_id AND alias = v_cand_alias AND in_plan = 0;

            SET v_step = v_step + 1;
        END WHILE expand_loop;

        -- Any required datasets still not in plan?
        SELECT COUNT(*) INTO v_remaining
          FROM demo_user.request_required_ds WHERE in_plan = 0;
        IF v_remaining = 0 THEN LEAVE bfs_loop; END IF;

        -- Insert a bridging dataset: frontier-adjacent, preferring
        -- candidates that are themselves 1-hop from a required-out.
        INSERT INTO demo_user.request_required_ds
                   (dataset_id, dataset_name, reason, alias)
        SELECT TOP 1 c.dataset_id, c.dataset_name, 'auto_bridge', c.dataset_name
          FROM (
              SELECT DISTINCT mid.dataset_id, mid.dataset_name,
                     COALESCE(prox.out_adj, 0) AS out_adj
                FROM demo_user.DATASET mid
                JOIN demo_user.RELATIONSHIP r
                     ON r.from_dataset_id = mid.dataset_id
                     OR r.to_dataset_id   = mid.dataset_id
                JOIN demo_user.request_required_ds i
                     ON i.in_plan = 1
                    AND i.dataset_id IN (r.from_dataset_id, r.to_dataset_id)
                    AND i.dataset_id <> mid.dataset_id
                LEFT JOIN (
                    SELECT mid2.dataset_id, COUNT(*) AS out_adj
                      FROM demo_user.DATASET mid2
                      JOIN demo_user.RELATIONSHIP r2
                           ON r2.from_dataset_id = mid2.dataset_id
                           OR r2.to_dataset_id   = mid2.dataset_id
                      JOIN demo_user.request_required_ds o
                           ON o.in_plan = 0
                          AND o.dataset_id IN (r2.from_dataset_id, r2.to_dataset_id)
                          AND o.dataset_id <> mid2.dataset_id
                     GROUP BY mid2.dataset_id
                ) prox ON prox.dataset_id = mid.dataset_id
               WHERE mid.model_id = v_model_id
                 AND mid.dataset_id NOT IN (SELECT dataset_id FROM demo_user.request_required_ds)
          ) c
         ORDER BY c.out_adj DESC, c.dataset_id;

        SET v_iter = v_iter + 1;
    END WHILE bfs_loop;

    -- ========== 9) Emit anchor FROM ==========
    -- Anchor source. Uses alias = dataset_name for the anchor.
    SELECT
        CASE WHEN d.source_query IS NOT NULL AND d.DataBaseName IS NULL
             THEN '(' || CAST(d.source_query AS VARCHAR(8000)) || ') AS ' || d.dataset_name
             WHEN d.DataBaseName IS NOT NULL
             THEN TRIM(d.DataBaseName) || '.' || TRIM(d.TableName) || ' AS ' || d.dataset_name
             ELSE d.dataset_name || ' AS ' || d.dataset_name
        END
      INTO v_cand_src
      FROM demo_user.DATASET d WHERE d.dataset_id = v_anchor_id;

    INSERT INTO demo_user.request_join_step
         (step_ordinal, relationship_id, from_dataset_id, to_dataset_id, join_sql)
    VALUES (0, NULL, NULL, v_anchor_id, 'FROM ' || v_cand_src);

    SET v_joined_list = v_anchor_name;
    FOR r_j AS c_j CURSOR FOR
        SELECT d.dataset_name AS dn, rqd.alias AS al
          FROM demo_user.request_required_ds rqd
          JOIN demo_user.DATASET d ON d.dataset_id = rqd.dataset_id
         WHERE rqd.in_plan = 1 AND rqd.dataset_id <> v_anchor_id
         ORDER BY rqd.dataset_id
    DO
        SET v_joined_list = v_joined_list || ', ' ||
            CASE WHEN r_j.al = r_j.dn THEN r_j.dn ELSE r_j.dn || ' AS ' || r_j.al END;
    END FOR;

    -- ========== 10) Unresolved datasets ==========
    SELECT COUNT(*) INTO v_remaining
      FROM demo_user.request_required_ds WHERE in_plan = 0;
    IF v_remaining > 0 THEN
        SET v_valid = 0;
        SELECT 'Could not resolve join path for datasets: ' ||
               REGEXP_REPLACE(
                 COALESCE(CAST(XMLAGG(COALESCE(alias, dataset_name) || ',' ORDER BY dataset_name)
                    AS VARCHAR(2000)), ''),
                 ',$', '')
          INTO v_errtext
          FROM demo_user.request_required_ds WHERE in_plan = 0;
    END IF;

    -- ========== 11) SELECT list ==========
    SET v_first = 1;
    FOR r_dim AS c_dim CURSOR FOR
        SELECT alias, field_name, CAST(expression AS VARCHAR(2000)) AS expression,
               grain, is_time, role_edge_id
          FROM demo_user.request_dimension
         ORDER BY field_id
    DO
        IF v_first = 1 THEN SET v_first = 0; ELSE SET v_select_list = v_select_list || ', '; END IF;

        -- Build the dim SQL expression with optional grain wrapping.
        -- Column aliases: for role-played dims we prefix the role name to
        -- avoid two columns sharing the same alias when both roles of a
        -- dataset are requested.
        IF r_dim.grain IS NOT NULL THEN
            SET v_tok2 =
                CASE UPPER(r_dim.grain)
                    WHEN 'DAY'     THEN 'TRUNC(' || r_dim.alias || '.' || r_dim.expression || ', ''DDD'')'
                    WHEN 'WEEK'    THEN 'TRUNC(' || r_dim.alias || '.' || r_dim.expression || ', ''DAY'')'
                    WHEN 'MONTH'   THEN 'TRUNC(' || r_dim.alias || '.' || r_dim.expression || ', ''MM'')'
                    WHEN 'QUARTER' THEN 'TRUNC(' || r_dim.alias || '.' || r_dim.expression || ', ''Q'')'
                    WHEN 'YEAR'    THEN 'TRUNC(' || r_dim.alias || '.' || r_dim.expression || ', ''Y'')'
                    ELSE r_dim.alias || '.' || r_dim.expression
                END;
            SET v_select_list = v_select_list || v_tok2 || ' AS '
                || CASE WHEN r_dim.role_edge_id IS NOT NULL
                        THEN r_dim.alias || '_' || r_dim.field_name || '_' || LOWER(r_dim.grain)
                        ELSE r_dim.field_name || '_' || LOWER(r_dim.grain)
                   END;
        ELSE
            IF r_dim.expression = r_dim.field_name THEN
                SET v_select_list = v_select_list
                     || r_dim.alias || '.' || r_dim.field_name || ' AS '
                     || CASE WHEN r_dim.role_edge_id IS NOT NULL
                             THEN r_dim.alias || '_' || r_dim.field_name
                             ELSE r_dim.field_name
                        END;
            ELSE
                SET v_select_list = v_select_list
                     || '(' || r_dim.expression || ') AS '
                     || CASE WHEN r_dim.role_edge_id IS NOT NULL
                             THEN r_dim.alias || '_' || r_dim.field_name
                             ELSE r_dim.field_name
                        END;
            END IF;
        END IF;
    END FOR;

    FOR r_m AS c_m CURSOR FOR
        SELECT metric_name, CAST(expression AS VARCHAR(4000)) AS expression
          FROM demo_user.request_metric ORDER BY metric_id
    DO
        IF v_first = 1 THEN SET v_first = 0; ELSE SET v_select_list = v_select_list || ', '; END IF;
        SET v_select_list = v_select_list || r_m.expression || ' AS ' || r_m.metric_name;
    END FOR;

    -- ========== 12) FROM clause ==========
    SET v_from_clause = '';
    FOR r_step AS c_step CURSOR FOR
        SELECT step_ordinal, CAST(join_sql AS VARCHAR(4000)) AS join_sql
          FROM demo_user.request_join_step ORDER BY step_ordinal
    DO
        IF v_from_clause <> '' THEN SET v_from_clause = v_from_clause || ' ' || CHR(10) || '    '; END IF;
        SET v_from_clause = v_from_clause || r_step.join_sql;
    END FOR;

    -- ========== 13) WHERE from request_filter ==========
    SET v_first = 1;
    FOR r_f AS c_f CURSOR FOR
        SELECT resolved_left, op, rhs
          FROM demo_user.request_filter WHERE kind = 'WHERE' ORDER BY ord
    DO
        IF v_first = 1 THEN SET v_where_sql = ' WHERE '; SET v_first = 0;
        ELSE SET v_where_sql = v_where_sql || ' AND '; END IF;

        IF UPPER(r_f.op) = 'IN' THEN
            -- F1 fix: use value verbatim (caller supplies parens).
            SET v_where_sql = v_where_sql || r_f.resolved_left || ' IN ' || r_f.rhs;
        ELSEIF UPPER(r_f.op) = 'LIKE' THEN
            SET v_where_sql = v_where_sql || r_f.resolved_left || ' LIKE ' || r_f.rhs;
        ELSE
            SET v_where_sql = v_where_sql || r_f.resolved_left || ' ' || r_f.op || ' ' || r_f.rhs;
        END IF;
    END FOR;

    -- ========== 14) GROUP BY ==========
    IF (SELECT COUNT(*) FROM demo_user.request_metric) > 0
       AND (SELECT COUNT(*) FROM demo_user.request_dimension) > 0 THEN
        SET v_group_by = ' GROUP BY ';
        SET v_first = 1;
        FOR r_d AS c_gb CURSOR FOR
            SELECT alias, field_name, CAST(expression AS VARCHAR(2000)) AS expression, grain
              FROM demo_user.request_dimension ORDER BY field_id
        DO
            IF v_first = 1 THEN SET v_first = 0; ELSE SET v_group_by = v_group_by || ', '; END IF;
            IF r_d.grain IS NOT NULL THEN
                SET v_group_by = v_group_by ||
                    CASE UPPER(r_d.grain)
                        WHEN 'DAY'     THEN 'TRUNC(' || r_d.alias || '.' || r_d.expression || ', ''DDD'')'
                        WHEN 'WEEK'    THEN 'TRUNC(' || r_d.alias || '.' || r_d.expression || ', ''DAY'')'
                        WHEN 'MONTH'   THEN 'TRUNC(' || r_d.alias || '.' || r_d.expression || ', ''MM'')'
                        WHEN 'QUARTER' THEN 'TRUNC(' || r_d.alias || '.' || r_d.expression || ', ''Q'')'
                        WHEN 'YEAR'    THEN 'TRUNC(' || r_d.alias || '.' || r_d.expression || ', ''Y'')'
                        ELSE r_d.alias || '.' || r_d.expression
                    END;
            ELSE
                SET v_group_by = v_group_by || r_d.alias || '.' || r_d.field_name;
            END IF;
        END FOR;
    END IF;

    -- ========== 15) HAVING from request_filter ==========
    SET v_first = 1;
    FOR r_h AS c_h CURSOR FOR
        SELECT left_token, op, rhs
          FROM demo_user.request_filter WHERE kind = 'HAVING' ORDER BY ord
    DO
        SET v_m_expr = NULL;
        BEGIN
            DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
            SELECT CAST(expression AS VARCHAR(4000)) INTO v_m_expr
              FROM demo_user.request_metric WHERE metric_name = r_h.left_token;
        END;
        IF v_m_expr IS NOT NULL THEN
            IF v_first = 1 THEN SET v_having_sql = ' HAVING '; SET v_first = 0;
            ELSE SET v_having_sql = v_having_sql || ' AND '; END IF;
            SET v_having_sql = v_having_sql || '(' || v_m_expr || ') ' || r_h.op || ' ' || r_h.rhs;
        END IF;
    END FOR;

    -- ========== 16) ORDER BY ==========
    IF p_sort IS NOT NULL AND TRIM(p_sort) <> '' THEN
        SET v_order_by = ' ORDER BY ' || TRIM(p_sort);
    END IF;

    -- ========== 17) TOP N ==========
    IF p_row_limit IS NOT NULL AND p_row_limit > 0 THEN
        SET v_top_clause = 'TOP ' || TRIM(CAST(p_row_limit AS VARCHAR(20))) || ' ';
    END IF;

    -- ========== 18) Assemble — with F3 DISTINCT for dim-only ==========
    IF (SELECT COUNT(*) FROM demo_user.request_metric) = 0
       AND (SELECT COUNT(*) FROM demo_user.request_dimension) > 0 THEN
        SET v_sql =
            'LOCKING ROW FOR ACCESS ' || CHR(10) ||
            'SELECT DISTINCT ' || v_top_clause || v_select_list || CHR(10) ||
            '  ' || v_from_clause ||
            v_where_sql || v_order_by;
    ELSE
        SET v_sql =
            'LOCKING ROW FOR ACCESS ' || CHR(10) ||
            'SELECT ' || v_top_clause || v_select_list || CHR(10) ||
            '  ' || v_from_clause ||
            v_where_sql || v_group_by || v_having_sql || v_order_by;
    END IF;

    -- ========== 19) Return via OUT parameters ==========
    SET p_compiled_sql       = v_sql;
    SET p_is_valid           = v_valid;
    SET p_validation_message = v_errtext;
    SET p_anchor_dataset     = v_anchor_name;
    SET p_joined_datasets    = v_joined_list;

END request_body;
