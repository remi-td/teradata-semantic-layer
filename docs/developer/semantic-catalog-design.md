# Teradata Semantic Catalog
## Conceptual Model, Ontology, and Logical Design — v0.2

---

## Part 1: Design principles

1. **Start simple, add richness.** A semantic model can begin as a single dataset (a cube) with dimensions and measures defined on it. Over time, additional datasets, relationships, keys, and metadata are added. Nothing is ever required upfront beyond a dataset with fields.

2. **Field is the atomic unit.** Every column, expression, dimension, key, and measure in the system is a field. A field belongs to a dataset. Its role — key, dimension, measure ingredient — is determined by how it participates in other structures and how it is used in context.

3. **A cube is a dataset.** There is no separate "cube" entity. A cube is simply a dataset (backed by a table, view, or SQL query) where the consumer interacts with it as a flat result set. If the underlying relational structure is known, it is modeled as additional datasets and relationships alongside the cube. The consumer chooses which level to use.

4. **Metrics are model-level citizens.** Metrics are aggregate expressions that can span multiple datasets. They reference fields. The same field can be used in a metric expression (as the thing being aggregated) and as a dimension (as the thing being grouped by) simultaneously.

5. **Physical mapping is referential, not defining.** Datasets map to physical objects in `dbc.TablesV` (database_name + table_name) or to a SQL query. Fields map to physical columns in `dbc.ColumnsV`. But the same physical column can back multiple semantic fields with different expressions. The physical reference is a foreign key, not the identity.

6. **Two dialects: Teradata and ANSI_SQL.** Multi-dialect expressions are supported for interoperability, but limited to what matters: Teradata-native SQL and ANSI SQL for OSI projection.

7. **Metadata is pervasive and uniform.** AI context, format specs, security policies, and vendor extensions all attach to entities using the same polymorphic pattern. There is no separate "tier" for consumption vs. annotation — these are all just metadata on the model.

---

## Part 2: Ontology

### Core entities

**Semantic model**
A named container grouping all semantic objects into a coherent unit of business meaning. A system may contain multiple semantic models (e.g., "retail_analytics", "finance"). Everything belongs to a model.

**Dataset**
A logical business entity grounded in a physical data source. A dataset can be:
- A physical table or view (referenced by database_name + table_name)
- A SQL query (stored as a query string)
- Both (a table/view that also has a query string for documentation or alternative access)

A dataset that represents a cube is just a dataset. The difference is not structural — it is the level of definition around it. A cube typically has dimensions and measures defined on its fields but may lack decomposed relationships to other datasets. As the model matures, the cube's underlying entities may be added as separate datasets with explicit relationships, giving consumers the choice between the pre-canned cube and custom queries over the relational model.

A dataset has a granularity — what a single row represents. This is documented as text, not enforced structurally.

**Field**
The atomic unit. A named, typed, expression-backed attribute belonging to a dataset. A field has:
- An expression (Teradata SQL, scalar — can be a simple column reference or a computed expression)
- An optional physical mapping (database_name + table_name + column_name referencing dbc.ColumnsV)
- Flags: is_dimension, is_time_dimension
- A field_type_code: A (attribute) or K (key) indicating primary role

A field's role is not exclusive. The same field can simultaneously:
- Be a primary key (participates in DATASET_KEY)
- Be a dimension (is_dimension = 1, used in GROUP BY)
- Be referenced by a metric (appears in METRIC_FIELD_REF as a MEASURE or GROUP_BY)
- Be a join column (appears in REL_COLUMN_MAP)

Example: "age" can be used as a dimension ("average spending by age") and as a measure ingredient ("average age for customers spending > $1000") depending on which metric references it and how.

**Metric**
An aggregate expression producing a business measure. Metrics belong to a semantic model (not a single dataset) because they can span multiple datasets. A metric:
- References fields from one or more datasets in its expression
- Has a type: SIMPLE, RATIO, CUMULATIVE, DERIVED
- Can be composed from other metrics (DERIVED type)
- Has multi-dialect expressions (Teradata + ANSI_SQL)

**Relationship**
An explicit join path between two datasets. Defined by:
- from_dataset (many-side) and to_dataset (one-side)
- Column-pair mappings (from_field → to_field) via REL_COLUMN_MAP
- Cardinality (many_to_one, one_to_one, one_to_many, many_to_many)
- Join type hint (INNER, LEFT OUTER, etc.)
- Optional SCD2 temporal join metadata

Relationships are optional. A dataset (cube) can exist without any relationships. When relationships are added, they enable query generation engines to resolve join paths selectively.

**Dataset key**
Records which fields participate in a dataset's primary key or unique keys. Supports composite keys. Dataset keys are optional — a cube may not have meaningful keys defined (only its dimensions collectively identify a row).

### Metadata (uniform, attachable to any entity)

**AI context**
Agent-facing metadata: instructions, synonyms, examples, display_name. Attaches to any entity via (entity_type, entity_id).

**Format specification**
Display formatting: number, currency, percentage, date — with currency code, decimal places, abbreviation, date format. Attaches to fields, metrics, or view members.

**Security policy**
Access control rules: row-level filters and member-level include/exclude lists, scoped by user group. Attaches to semantic models or datasets.

**Custom extension**
Vendor-specific JSON metadata. Attaches to any entity. Vendor names: TERADATA, COMMON.

### Presentation

**Semantic view**
A curated projection over one or more datasets, exposing a subset of dimensions and measures to consumers. A view:
- References a primary dataset (the "fact" table or cube)
- Selects which fields and metrics to expose as view members
- Can apply filters and security policies
- Carries its own AI context

A semantic view is metadata on the model, not a separate tier. It is the mechanism by which different audiences see different slices of the same model. A cube that is directly consumed (without further curation) simply has a view that exposes all its fields and metrics.

Multiple views can coexist: a pre-canned cube view alongside custom views that leverage the decomposed relational model. The consumer chooses.

**View member**
An entry in a semantic view that exposes a specific field or metric. View members can:
- Alias the underlying name
- Override display formatting
- Control visibility (public/hidden)
- Define an inline expression (for cases where the underlying field/metric hasn't been formally created yet)

---

## Part 3: Logical model

### Entity list

| Entity | Primary key | Natural key | Parent(s) |
|---|---|---|---|
| SEMANTIC_MODEL | model_id | model_name | — |
| DATASET | dataset_id | (model_id, dataset_name) | SEMANTIC_MODEL |
| FIELD | field_id | (dataset_id, field_name) | DATASET |
| DATASET_KEY | (dataset_id, key_type, key_ordinal, column_position) | same | DATASET, FIELD |
| RELATIONSHIP | relationship_id | (from_dataset_id, to_dataset_id) | DATASET (twice) |
| REL_COLUMN_MAP | (relationship_id, column_position) | same | RELATIONSHIP, FIELD (twice) |
| METRIC | metric_id | (model_id, metric_name) | SEMANTIC_MODEL, DATASET (optional) |
| METRIC_EXPRESSION | (metric_id, dialect) | same | METRIC |
| METRIC_FIELD_REF | (metric_id, field_id) | same | METRIC, FIELD |
| SEMANTIC_VIEW | view_id | (model_id, view_name) | SEMANTIC_MODEL |
| VIEW_MEMBER | (view_id, member_ordinal) | (view_id, member_name) | SEMANTIC_VIEW, FIELD or METRIC |
| AI_CONTEXT | (entity_type, entity_id) | same | polymorphic |
| FORMAT_SPEC | (entity_type, entity_id) | same | polymorphic |
| SECURITY_POLICY | (entity_type, entity_id, policy_ordinal) | same | polymorphic |
| CUSTOM_EXTENSION | (entity_type, entity_id, vendor_name) | same | polymorphic |

### Entity detail

#### SEMANTIC_MODEL
```
model_id            INTEGER         PK (surrogate)
model_name          VARCHAR(200)    NK, unique
description         VARCHAR(10000)
owner_user          VARCHAR(128)
owner_group         VARCHAR(128)
is_active           BYTEINT         default 1
created_ts          TIMESTAMP(6)
updated_ts          TIMESTAMP(6)
```

#### DATASET
```
dataset_id          INTEGER         PK (surrogate)
model_id            INTEGER         FK → SEMANTIC_MODEL, part of NK
dataset_name        VARCHAR(200)    part of NK
description         VARCHAR(10000)
granularity_desc    VARCHAR(1000)   what one row represents (text)
-- Physical mapping (FK to dbc.TablesV — not the identity, just a reference)
DataBaseName        VARCHAR(128)    nullable (matches dbc.TablesV.DataBaseName)
TableName           VARCHAR(128)    nullable (matches dbc.TablesV.TableName)
-- Alternative or complementary: SQL query as source
source_query        CLOB            nullable (populated when dataset is defined by a query)
created_ts          TIMESTAMP(6)
updated_ts          TIMESTAMP(6)
```
A dataset has either DataBaseName + TableName, or source_query, or both. Table kind (T, V, O, etc.) and other catalog metadata are not stored here — they are looked up from dbc.TablesV at runtime via the FK.

Note: dbc.TablesV spells it `DataBaseName` (capital B). dbc.ColumnsV spells it `DatabaseName` (lowercase b). We use each view's actual spelling in the corresponding entity.

#### FIELD
```
field_id            INTEGER         PK (surrogate)
dataset_id          INTEGER         FK → DATASET, part of NK
field_name          VARCHAR(200)    part of NK
field_type_code     CHAR(1)         'A' (attribute) or 'K' (key) — primary role
expression          VARCHAR(10000)  Teradata SQL (scalar)
description         VARCHAR(10000)
label               VARCHAR(500)    display label
is_dimension        BYTEINT         1 = can be used for grouping/filtering
is_time_dimension   BYTEINT         1 = time-based dimension
data_type           VARCHAR(200)    logical type (INTEGER, DECIMAL(15,2), VARCHAR(100), etc.)
-- Physical mapping (FK to dbc.ColumnsV — not the identity)
-- DatabaseName and TableName are inherited from the parent DATASET
ColumnName          VARCHAR(128)    nullable (matches dbc.ColumnsV.ColumnName)
-- Presentation
field_order         SMALLINT        display ordering
created_ts          TIMESTAMP(6)
updated_ts          TIMESTAMP(6)
```
ColumnName is nullable because a field can be a computed expression that doesn't map to a single physical column (e.g., `first_name || ' ' || last_name`).
The same physical ColumnName can appear in multiple fields with different expressions.
DatabaseName and TableName for the column lookup are inherited from the parent DATASET — no need to repeat them here.

#### DATASET_KEY
```
dataset_id          INTEGER         FK → DATASET, part of PK
key_type            VARCHAR(10)     'PK' or 'UK', part of PK
key_ordinal         SMALLINT        distinguishes multiple UKs, part of PK
field_id            INTEGER         FK → FIELD
column_position     SMALLINT        position in composite key, part of PK
```

#### RELATIONSHIP
```
relationship_id     INTEGER         PK (surrogate)
from_dataset_id     INTEGER         FK → DATASET (many-side), part of NK
to_dataset_id       INTEGER         FK → DATASET (one-side), part of NK
relationship_name   VARCHAR(200)
description         VARCHAR(10000)
cardinality         VARCHAR(20)     MANY_TO_ONE, ONE_TO_ONE, ONE_TO_MANY, MANY_TO_MANY
join_type_hint      VARCHAR(20)     INNER, LEFT_OUTER, FULL_OUTER
-- SCD2 support
is_scd2             BYTEINT         1 = temporal join
scd2_effective_col  VARCHAR(200)    effective date column (if SCD2)
scd2_expiry_col     VARCHAR(200)    expiry date column (if SCD2)
created_ts          TIMESTAMP(6)
```

#### REL_COLUMN_MAP
```
relationship_id     INTEGER         FK → RELATIONSHIP, part of PK
column_position     SMALLINT        part of PK
from_field_id       INTEGER         FK → FIELD (many-side column)
to_field_id         INTEGER         FK → FIELD (one-side column)
```

#### METRIC
```
metric_id           INTEGER         PK (surrogate)
model_id            INTEGER         FK → SEMANTIC_MODEL, part of NK
metric_name         VARCHAR(200)    part of NK
description         VARCHAR(10000)
primary_dataset_id  INTEGER         FK → DATASET (optional, NULL for cross-dataset)
metric_type         VARCHAR(20)     SIMPLE, RATIO, CUMULATIVE, DERIVED
is_additive         BYTEINT         1 = can be summed across groups
is_certified        BYTEINT         1 = reviewed and approved
owner_team          VARCHAR(200)
default_time_grain  VARCHAR(20)     DAY, WEEK, MONTH, QUARTER, YEAR
created_ts          TIMESTAMP(6)
updated_ts          TIMESTAMP(6)
```

#### METRIC_EXPRESSION
```
metric_id           INTEGER         FK → METRIC, part of PK
dialect             VARCHAR(50)     'TERADATA' or 'ANSI_SQL', part of PK
expression          VARCHAR(32000)  aggregate SQL
```

#### METRIC_FIELD_REF
```
metric_id           INTEGER         FK → METRIC, part of PK
field_id            INTEGER         FK → FIELD, part of PK
dep_role            VARCHAR(20)     MEASURE, FILTER, GROUP_BY
```

#### SEMANTIC_VIEW
```
view_id             INTEGER         PK (surrogate)
model_id            INTEGER         FK → SEMANTIC_MODEL, part of NK
view_name           VARCHAR(200)    part of NK
description         VARCHAR(10000)
primary_dataset_id  INTEGER         FK → DATASET (the main dataset this view projects)
timeseries_field    VARCHAR(200)    default time dimension name
is_certified        BYTEINT         1 = production-certified
is_public           BYTEINT         1 = visible to consumers
owner_user          VARCHAR(128)
created_ts          TIMESTAMP(6)
updated_ts          TIMESTAMP(6)
```

#### VIEW_MEMBER
```
view_id             INTEGER         FK → SEMANTIC_VIEW, part of PK
member_ordinal      SMALLINT        part of PK
member_name         VARCHAR(200)    exposed name
member_type         VARCHAR(20)     DIMENSION, MEASURE, TIME_DIMENSION
-- Links to underlying objects (at least one should be populated):
field_id            INTEGER         FK → FIELD (nullable)
metric_id           INTEGER         FK → METRIC (nullable)
-- Fallback for not-yet-decomposed fields:
inline_expression   VARCHAR(10000)  scalar or aggregate SQL (nullable)
-- Presentation
display_name        VARCHAR(500)
is_public           BYTEINT         1 = visible, 0 = hidden
member_order        SMALLINT        display ordering
```

#### AI_CONTEXT (polymorphic)
```
entity_type         VARCHAR(20)     part of PK
entity_id           INTEGER         part of PK
instructions        VARCHAR(10000)
synonyms            JSON(8000)      ["total sales", "revenue"]
examples            JSON(8000)      ["Show revenue by region"]
display_name        VARCHAR(500)
```
entity_type: MODEL, DATASET, FIELD, METRIC, VIEW, VIEW_MEMBER

#### FORMAT_SPEC (polymorphic)
```
entity_type         VARCHAR(20)     part of PK
entity_id           INTEGER         part of PK
format_type         VARCHAR(20)     NUMBER, CURRENCY, PERCENTAGE, DATE, TEXT
currency_code       VARCHAR(10)
decimal_places      SMALLINT
abbreviation        VARCHAR(20)     COMPACT, FULL, NONE
date_format         VARCHAR(50)
custom_format       VARCHAR(200)
```
entity_type: FIELD, METRIC, VIEW_MEMBER

#### SECURITY_POLICY (polymorphic)
```
entity_type         VARCHAR(20)     part of PK
entity_id           INTEGER         part of PK
policy_ordinal      SMALLINT        part of PK
policy_type         VARCHAR(20)     ROW_FILTER, MEMBER_INCLUDE, MEMBER_EXCLUDE
group_name          VARCHAR(200)
policy_expression   VARCHAR(10000)
```
entity_type: MODEL, DATASET, VIEW

#### CUSTOM_EXTENSION (polymorphic)
```
entity_type         VARCHAR(20)     part of PK
entity_id           INTEGER         part of PK
vendor_name         VARCHAR(50)     TERADATA or COMMON, part of PK
extension_data      JSON(64000)
```
entity_type: MODEL, DATASET, FIELD, METRIC, VIEW, RELATIONSHIP

---

## Part 4: Key design decisions

### A cube is a dataset
There is no separate cube entity. A cube is a dataset — it may be backed by a SQL query (source_query) or by a table/view (td_database_name + td_table_name). The only difference between a "cube" and a "decomposed entity" is whether relationships to other datasets exist. A cube with no relationships is self-contained. A cube with relationships lets query engines generate custom join paths.

Both forms coexist in the same model. A consumer can query the cube directly (pre-canned flat dataset) or traverse the relational model (custom query). The semantic view layer lets you expose either or both.

### Physical mapping is referential
DataBaseName and TableName on DATASET, and ColumnName on FIELD, are references to Teradata catalog objects (dbc.TablesV, dbc.ColumnsV). They use the same VARCHAR(128) type as the dbc views. They are not the identity of the semantic entity. The same physical column can back multiple semantic fields:
- "customer_age" field with expression `age` and is_dimension = 1
- Another metric references the same column via `AVG(age)` in its expression

The field inherits DataBaseName and TableName from its parent dataset — there is no need to repeat them on the field entity.

Note on dbc naming: dbc.TablesV uses `DataBaseName` (capital B in Base) while dbc.ColumnsV uses `DatabaseName` (lowercase b). This is a genuine inconsistency in the Teradata data dictionary. We use each view's actual spelling in the corresponding entity.

### Fields participate in everything
A field's role is emergent, not assigned. The field_type_code (A or K) is the primary role, but actual usage is determined by participation:
- In DATASET_KEY → it's a key
- In REL_COLUMN_MAP → it's a join column
- In METRIC_FIELD_REF → it's a measure ingredient
- has is_dimension = 1 → it's a dimension
- Any combination of the above → all at once

### Source flexibility
A dataset can have:
- Only td_database_name + td_table_name (physical table/view)
- Only source_query (SQL query)
- Both (table reference plus a query that may add computed columns, filters, or joins)

This is independent of whether the dataset has relationships defined. A query-based dataset can have relationships (the query identifies the base entity, relationships connect it to other datasets). A table-based dataset can be a flat cube with no relationships.

### Security is metadata
Security policies attach to models, datasets, or views using the same polymorphic pattern as AI context and format specs. There is no separate "consumption tier" — views are part of the model, and security is metadata on the model.

### View members bridge decomposed and non-decomposed
A view member has three possible backing references:
- field_id → links to a decomposed FIELD entity
- metric_id → links to a decomposed METRIC entity
- inline_expression → a raw SQL expression for fields/metrics not yet formally created

As the model matures, inline expressions are replaced by proper field_id/metric_id links. The inline_expression is kept as documentation.

---

## Part 5: Projection to other formats

| Target | How it maps |
|---|---|
| **OSI** | SEMANTIC_MODEL → semantic_model. DATASET → datasets. FIELD → fields. RELATIONSHIP → relationships. METRIC → metrics. METRIC_EXPRESSION(dialect=ANSI_SQL) → expression. AI_CONTEXT → ai_context. CUSTOM_EXTENSION → custom_extensions. |
| **Cube** | DATASET → cube. FIELD(is_dimension=1) → dimensions. METRIC → measures. RELATIONSHIP → joins. SEMANTIC_VIEW → view. VIEW_MEMBER → includes. |
| **Databricks MV** | SEMANTIC_VIEW → CREATE VIEW WITH METRICS. DATASET → source. VIEW_MEMBER(DIMENSION) → dimensions. VIEW_MEMBER(MEASURE) → measures. RELATIONSHIP → joins. AI_CONTEXT → display_name/synonyms. FORMAT_SPEC → format. |
| **MetricFlow** | DATASET → semantic_models. FIELD(type=K) → entities. FIELD(is_dimension=1) → dimensions. METRIC decomposed into measures + metrics. RELATIONSHIP → implicit via entity types. |
