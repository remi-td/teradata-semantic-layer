-- =========================================================================
-- Table-level and column-level comments for agent discoverability.
-- =========================================================================

-- Enum tables
COMMENT ON TABLE demo_user.DIALECT_ENUM AS 'Supported SQL dialects for metric expressions (TERADATA, ANSI_SQL).';
COMMENT ON TABLE demo_user.VENDOR_ENUM AS 'Vendor namespaces for custom extension payloads.';
COMMENT ON TABLE demo_user.FIELD_TYPE_ENUM AS 'Primary role codes for FIELD: A=attribute, K=key.';
COMMENT ON TABLE demo_user.METRIC_TYPE_ENUM AS 'Metric type vocabulary: SIMPLE, RATIO, CUMULATIVE, DERIVED.';
COMMENT ON TABLE demo_user.CARDINALITY_ENUM AS 'Relationship cardinality codes.';

-- SEMANTIC_MODEL
COMMENT ON TABLE demo_user.SEMANTIC_MODEL AS 'Top-level container for a coherent body of semantic metadata (one business domain per row).';
COMMENT ON COLUMN demo_user.SEMANTIC_MODEL.model_id AS 'Surrogate primary key.';
COMMENT ON COLUMN demo_user.SEMANTIC_MODEL.model_name AS 'Business name of the semantic model (unique).';
COMMENT ON COLUMN demo_user.SEMANTIC_MODEL.description AS 'Human-readable description of the scope and intent of this model.';
COMMENT ON COLUMN demo_user.SEMANTIC_MODEL.owner_user AS 'Primary owner (Teradata user name).';
COMMENT ON COLUMN demo_user.SEMANTIC_MODEL.owner_group AS 'Owning team or role.';
COMMENT ON COLUMN demo_user.SEMANTIC_MODEL.is_active AS '1 = active and discoverable, 0 = archived.';
COMMENT ON COLUMN demo_user.SEMANTIC_MODEL.created_ts AS 'Creation audit timestamp.';
COMMENT ON COLUMN demo_user.SEMANTIC_MODEL.updated_ts AS 'Last-update audit timestamp.';

-- DATASET
COMMENT ON TABLE demo_user.DATASET AS 'Logical business entity backed by a physical table/view or SQL query. Also represents a cube.';
COMMENT ON COLUMN demo_user.DATASET.dataset_id AS 'Surrogate primary key.';
COMMENT ON COLUMN demo_user.DATASET.model_id AS 'FK to SEMANTIC_MODEL — the model this dataset belongs to.';
COMMENT ON COLUMN demo_user.DATASET.dataset_name AS 'Business name of the dataset, unique within its model.';
COMMENT ON COLUMN demo_user.DATASET.description AS 'Human-readable description.';
COMMENT ON COLUMN demo_user.DATASET.granularity_desc AS 'What a single row represents (grain), e.g. one customer per row.';
COMMENT ON COLUMN demo_user.DATASET.DataBaseName AS 'Optional reference to dbc.TablesV.DataBaseName (physical mapping).';
COMMENT ON COLUMN demo_user.DATASET.TableName AS 'Optional reference to dbc.TablesV.TableName (physical mapping).';
COMMENT ON COLUMN demo_user.DATASET.source_query AS 'Optional SQL query that defines the dataset when there is no single base table.';
COMMENT ON COLUMN demo_user.DATASET.created_ts AS 'Creation audit timestamp.';
COMMENT ON COLUMN demo_user.DATASET.updated_ts AS 'Last-update audit timestamp.';

-- FIELD
COMMENT ON TABLE demo_user.FIELD AS 'Atomic column-or-expression belonging to a DATASET. Role emerges from participation.';
COMMENT ON COLUMN demo_user.FIELD.field_id AS 'Surrogate primary key.';
COMMENT ON COLUMN demo_user.FIELD.dataset_id AS 'FK to DATASET — the dataset this field belongs to.';
COMMENT ON COLUMN demo_user.FIELD.field_name AS 'Business name of the field, unique within its dataset.';
COMMENT ON COLUMN demo_user.FIELD.field_type_code AS 'Primary role: A (attribute) or K (key).';
COMMENT ON COLUMN demo_user.FIELD.expression AS 'Teradata SQL scalar expression (simple column reference or computed).';
COMMENT ON COLUMN demo_user.FIELD.description AS 'Human-readable description.';
COMMENT ON COLUMN demo_user.FIELD.label AS 'Display label for BI/agents.';
COMMENT ON COLUMN demo_user.FIELD.is_dimension AS '1 = usable for GROUP BY / filtering.';
COMMENT ON COLUMN demo_user.FIELD.is_time_dimension AS '1 = time-valued dimension (date/timestamp/year/month).';
COMMENT ON COLUMN demo_user.FIELD.data_type AS 'Logical type (INTEGER, DECIMAL(15,2), VARCHAR(100), DATE, ...).';
COMMENT ON COLUMN demo_user.FIELD.ColumnName AS 'Optional reference to dbc.ColumnsV.ColumnName; NULL for computed expressions.';
COMMENT ON COLUMN demo_user.FIELD.field_order AS 'Display ordering within the dataset.';

-- DATASET_KEY
COMMENT ON TABLE demo_user.DATASET_KEY AS 'Records which fields form a primary or unique key for a dataset (supports composite keys).';
COMMENT ON COLUMN demo_user.DATASET_KEY.dataset_id AS 'FK to DATASET.';
COMMENT ON COLUMN demo_user.DATASET_KEY.key_type AS 'Key kind: PK (primary) or UK (unique).';
COMMENT ON COLUMN demo_user.DATASET_KEY.key_ordinal AS 'Distinguishes multiple UKs on the same dataset (0 for PK).';
COMMENT ON COLUMN demo_user.DATASET_KEY.column_position AS 'Position within a composite key (1-based).';
COMMENT ON COLUMN demo_user.DATASET_KEY.field_id AS 'FK to FIELD — the field participating in this key.';

-- RELATIONSHIP
COMMENT ON TABLE demo_user.RELATIONSHIP AS 'Join path between two datasets (from_dataset = many side, to_dataset = one side).';
COMMENT ON COLUMN demo_user.RELATIONSHIP.relationship_id AS 'Surrogate primary key.';
COMMENT ON COLUMN demo_user.RELATIONSHIP.from_dataset_id AS 'FK to DATASET — many side of the join.';
COMMENT ON COLUMN demo_user.RELATIONSHIP.to_dataset_id AS 'FK to DATASET — one side of the join.';
COMMENT ON COLUMN demo_user.RELATIONSHIP.relationship_name AS 'Business name for this join path (e.g. lineitem_to_orders).';
COMMENT ON COLUMN demo_user.RELATIONSHIP.description AS 'Human-readable description.';
COMMENT ON COLUMN demo_user.RELATIONSHIP.cardinality AS 'MANY_TO_ONE | ONE_TO_ONE | ONE_TO_MANY | MANY_TO_MANY.';
COMMENT ON COLUMN demo_user.RELATIONSHIP.join_type_hint AS 'Preferred join type: INNER | LEFT_OUTER | FULL_OUTER.';
COMMENT ON COLUMN demo_user.RELATIONSHIP.role_name AS 'Optional alias for this edge; set when two edges share the same (from, to) and must be disambiguated in queries (role-playing dim).';
COMMENT ON COLUMN demo_user.RELATIONSHIP.is_scd2 AS '1 = temporal/SCD2 join.';
COMMENT ON COLUMN demo_user.RELATIONSHIP.scd2_effective_col AS 'Effective-date column on the one side.';
COMMENT ON COLUMN demo_user.RELATIONSHIP.scd2_expiry_col AS 'Expiry-date column on the one side.';

-- REL_COLUMN_MAP
COMMENT ON TABLE demo_user.REL_COLUMN_MAP AS 'Column pair mapping for a RELATIONSHIP. One row per field pair in a (composite) join.';
COMMENT ON COLUMN demo_user.REL_COLUMN_MAP.relationship_id AS 'FK to RELATIONSHIP.';
COMMENT ON COLUMN demo_user.REL_COLUMN_MAP.column_position AS 'Position within a composite join key (1-based).';
COMMENT ON COLUMN demo_user.REL_COLUMN_MAP.from_field_id AS 'FK to FIELD on the many side.';
COMMENT ON COLUMN demo_user.REL_COLUMN_MAP.to_field_id AS 'FK to FIELD on the one side.';

-- METRIC
COMMENT ON TABLE demo_user.METRIC AS 'Aggregate expression producing a business measure; belongs to a semantic model.';
COMMENT ON COLUMN demo_user.METRIC.metric_id AS 'Surrogate primary key.';
COMMENT ON COLUMN demo_user.METRIC.model_id AS 'FK to SEMANTIC_MODEL.';
COMMENT ON COLUMN demo_user.METRIC.metric_name AS 'Business name of the metric (unique within its model).';
COMMENT ON COLUMN demo_user.METRIC.description AS 'Human-readable description including computation intent.';
COMMENT ON COLUMN demo_user.METRIC.primary_dataset_id AS 'Optional FK to DATASET — the anchor dataset for FROM clause assembly.';
COMMENT ON COLUMN demo_user.METRIC.metric_type AS 'SIMPLE | RATIO | CUMULATIVE | DERIVED.';
COMMENT ON COLUMN demo_user.METRIC.is_additive AS '1 = can be summed across groups without double counting.';
COMMENT ON COLUMN demo_user.METRIC.is_certified AS '1 = reviewed and approved for production use.';
COMMENT ON COLUMN demo_user.METRIC.owner_team AS 'Team or role that owns the metric definition.';
COMMENT ON COLUMN demo_user.METRIC.default_time_grain AS 'Default time grain: DAY | WEEK | MONTH | QUARTER | YEAR.';
COMMENT ON COLUMN demo_user.METRIC.base_metric_id AS 'Optional FK to another METRIC. When set, this metric is a filtered rollup of the base: compiler wraps base aggregate_arg in CASE WHEN <filters> THEN arg ELSE default END.';
COMMENT ON COLUMN demo_user.METRIC.aggregate_fn AS 'Optional aggregate function (SUM, AVG, MIN, MAX, COUNT, COUNT_DISTINCT). Populated for metrics that can serve as a filtered-metric base; NULL for derived/ratio metrics that rely solely on METRIC_EXPRESSION.';
COMMENT ON COLUMN demo_user.METRIC.aggregate_arg AS 'Argument expression to aggregate_fn (e.g. "fact.amount" for SUM(fact.amount)). Compiler references this when composing filtered variants.';

-- METRIC_EXPRESSION
COMMENT ON TABLE demo_user.METRIC_EXPRESSION AS 'Multi-dialect SQL expression body for a metric (one row per dialect).';
COMMENT ON COLUMN demo_user.METRIC_EXPRESSION.metric_id AS 'FK to METRIC.';
COMMENT ON COLUMN demo_user.METRIC_EXPRESSION.dialect AS 'TERADATA | ANSI_SQL.';
COMMENT ON COLUMN demo_user.METRIC_EXPRESSION.expression AS 'Aggregate SQL expression; field references use dataset.field notation.';

-- METRIC_FIELD_REF
COMMENT ON TABLE demo_user.METRIC_FIELD_REF AS 'Records which fields a metric consumes and in what role.';
COMMENT ON COLUMN demo_user.METRIC_FIELD_REF.metric_id AS 'FK to METRIC.';
COMMENT ON COLUMN demo_user.METRIC_FIELD_REF.field_id AS 'FK to FIELD.';
COMMENT ON COLUMN demo_user.METRIC_FIELD_REF.dep_role AS 'MEASURE (aggregated) | FILTER (WHERE) | GROUP_BY.';

-- METRIC_FILTER
COMMENT ON TABLE demo_user.METRIC_FILTER AS 'Predicates composing a filtered-rollup metric: compiler joins these with AND inside a CASE WHEN wrapper around the base metric aggregate_arg.';
COMMENT ON COLUMN demo_user.METRIC_FILTER.metric_id AS 'FK to METRIC (the filtered variant).';
COMMENT ON COLUMN demo_user.METRIC_FILTER.filter_ord AS 'Stable ordering for composite filters; ordinal in the AND chain.';
COMMENT ON COLUMN demo_user.METRIC_FILTER.field_id AS 'FK to FIELD — the column to filter on. Dataset containing this field is auto-joined by the compiler.';
COMMENT ON COLUMN demo_user.METRIC_FILTER.op AS 'Operator: = | <> | IN | LIKE | < | <= | > | >=.';
COMMENT ON COLUMN demo_user.METRIC_FILTER.filter_value AS 'Literal value; strings must already be quoted, IN-lists must include parens.';

-- FIELD_HIERARCHY
COMMENT ON TABLE demo_user.FIELD_HIERARCHY AS 'Named ordered chain of FIELDs representing a drill-up/drill-down path. Metadata only; the compiler does not rewrite queries based on it.';
COMMENT ON COLUMN demo_user.FIELD_HIERARCHY.hierarchy_id AS 'Surrogate primary key.';
COMMENT ON COLUMN demo_user.FIELD_HIERARCHY.model_id AS 'FK to SEMANTIC_MODEL.';
COMMENT ON COLUMN demo_user.FIELD_HIERARCHY.hierarchy_name AS 'Business name (e.g. "product_hierarchy"). Unique within model.';
COMMENT ON COLUMN demo_user.FIELD_HIERARCHY.description AS 'Purpose of the hierarchy.';

-- FIELD_HIERARCHY_LEVEL
COMMENT ON TABLE demo_user.FIELD_HIERARCHY_LEVEL AS 'Levels of a FIELD_HIERARCHY, ordered from top (most aggregated) to leaf.';
COMMENT ON COLUMN demo_user.FIELD_HIERARCHY_LEVEL.hierarchy_id AS 'FK to FIELD_HIERARCHY.';
COMMENT ON COLUMN demo_user.FIELD_HIERARCHY_LEVEL.level_ord AS '1 = top (most aggregated); monotonically increasing down the hierarchy.';
COMMENT ON COLUMN demo_user.FIELD_HIERARCHY_LEVEL.field_id AS 'FK to FIELD participating at this level.';
COMMENT ON COLUMN demo_user.FIELD_HIERARCHY_LEVEL.level_name AS 'Business label for this level (e.g. "Country", "Region").';

-- SEMANTIC_VIEW
COMMENT ON TABLE demo_user.SEMANTIC_VIEW AS 'Curated projection over a model — exposes a chosen subset of dimensions and metrics.';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.view_id AS 'Surrogate primary key.';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.model_id AS 'FK to SEMANTIC_MODEL.';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.view_name AS 'Business name of the view (unique within model).';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.description AS 'Human-readable description.';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.primary_dataset_id AS 'Anchor dataset (typically the fact or cube).';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.timeseries_field AS 'Default time dimension field name for BI consumers.';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.is_certified AS '1 = production-certified.';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.is_public AS '1 = visible to consumers.';
COMMENT ON COLUMN demo_user.SEMANTIC_VIEW.owner_user AS 'Primary owner (Teradata user).';

-- VIEW_MEMBER
COMMENT ON TABLE demo_user.VIEW_MEMBER AS 'Exposed member (dimension or measure) of a SEMANTIC_VIEW.';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.view_id AS 'FK to SEMANTIC_VIEW.';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.member_ordinal AS 'Position within the view.';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.member_name AS 'Exposed name (may alias the underlying field/metric).';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.member_type AS 'DIMENSION | MEASURE | TIME_DIMENSION.';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.field_id AS 'Optional FK to FIELD (for dimensions).';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.metric_id AS 'Optional FK to METRIC (for measures).';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.inline_expression AS 'Raw SQL expression when the underlying field/metric is not yet decomposed.';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.display_name AS 'Override display label.';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.is_public AS '1 = visible, 0 = hidden.';
COMMENT ON COLUMN demo_user.VIEW_MEMBER.member_order AS 'Display order.';

-- AI_CONTEXT
COMMENT ON TABLE demo_user.AI_CONTEXT AS 'Polymorphic agent-facing metadata: instructions, synonyms, examples, display_name.';
COMMENT ON COLUMN demo_user.AI_CONTEXT.entity_type AS 'MODEL | DATASET | FIELD | METRIC | VIEW | VIEW_MEMBER.';
COMMENT ON COLUMN demo_user.AI_CONTEXT.entity_id AS 'Surrogate ID of the referenced entity.';
COMMENT ON COLUMN demo_user.AI_CONTEXT.instructions AS 'Free-form agent guidance about how/when to use this entity.';
COMMENT ON COLUMN demo_user.AI_CONTEXT.synonyms AS 'JSON array of alternative names (e.g. ["total sales","revenue"]).';
COMMENT ON COLUMN demo_user.AI_CONTEXT.examples AS 'JSON array of example natural-language questions.';
COMMENT ON COLUMN demo_user.AI_CONTEXT.display_name AS 'User-facing display name.';

-- FORMAT_SPEC
COMMENT ON TABLE demo_user.FORMAT_SPEC AS 'Polymorphic display formatting for fields, metrics, and view members.';
COMMENT ON COLUMN demo_user.FORMAT_SPEC.entity_type AS 'FIELD | METRIC | VIEW_MEMBER.';
COMMENT ON COLUMN demo_user.FORMAT_SPEC.entity_id AS 'Surrogate ID of the referenced entity.';
COMMENT ON COLUMN demo_user.FORMAT_SPEC.format_type AS 'NUMBER | CURRENCY | PERCENTAGE | DATE | TEXT.';
COMMENT ON COLUMN demo_user.FORMAT_SPEC.currency_code AS 'ISO 4217 code when format_type=CURRENCY.';
COMMENT ON COLUMN demo_user.FORMAT_SPEC.decimal_places AS 'Decimal digits.';
COMMENT ON COLUMN demo_user.FORMAT_SPEC.abbreviation AS 'COMPACT | FULL | NONE.';
COMMENT ON COLUMN demo_user.FORMAT_SPEC.date_format AS 'Date format pattern (e.g. YYYY-MM-DD).';
COMMENT ON COLUMN demo_user.FORMAT_SPEC.custom_format AS 'Arbitrary format string fallback.';

-- SECURITY_POLICY
COMMENT ON TABLE demo_user.SECURITY_POLICY AS 'Polymorphic access-control policies scoped by group (row filter / member include / member exclude).';
COMMENT ON COLUMN demo_user.SECURITY_POLICY.entity_type AS 'MODEL | DATASET | VIEW.';
COMMENT ON COLUMN demo_user.SECURITY_POLICY.entity_id AS 'Surrogate ID of the referenced entity.';
COMMENT ON COLUMN demo_user.SECURITY_POLICY.policy_ordinal AS 'Distinguishes multiple policies on the same entity.';
COMMENT ON COLUMN demo_user.SECURITY_POLICY.policy_type AS 'ROW_FILTER | MEMBER_INCLUDE | MEMBER_EXCLUDE.';
COMMENT ON COLUMN demo_user.SECURITY_POLICY.group_name AS 'Group this policy applies to.';
COMMENT ON COLUMN demo_user.SECURITY_POLICY.policy_expression AS 'Row filter (WHERE fragment) or comma-separated member list.';

-- CUSTOM_EXTENSION
COMMENT ON TABLE demo_user.CUSTOM_EXTENSION AS 'Polymorphic vendor-specific JSON extension payload.';
COMMENT ON COLUMN demo_user.CUSTOM_EXTENSION.entity_type AS 'MODEL | DATASET | FIELD | METRIC | VIEW | RELATIONSHIP.';
COMMENT ON COLUMN demo_user.CUSTOM_EXTENSION.entity_id AS 'Surrogate ID of the referenced entity.';
COMMENT ON COLUMN demo_user.CUSTOM_EXTENSION.vendor_name AS 'TERADATA | COMMON | <other vendor>.';
COMMENT ON COLUMN demo_user.CUSTOM_EXTENSION.extension_data AS 'Vendor-specific JSON payload.';
