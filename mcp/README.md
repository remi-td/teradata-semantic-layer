# Teradata Semantic Layer — MCP Server Configuration

This directory is a **drop-in config directory for the Teradata MCP server**
(<https://github.com/Teradata/teradata-mcp-server>). It exposes every
semantic-catalog operation as a custom MCP tool and ships three ready-to-use
profiles so you can spin up agents of different trust levels in one command.

---

## What you get

```
mcp/
├── README.md                        ← this file
├── profiles.yml                     ← three personas (admin / analyst / guided)
├── semantic_tools.yml               ← core 4 tools: list, search, describe, answer
├── semantic_admin_tools.yml         ← admin-only: import, export_osi
├── semantic_prompts.yml             ← persona briefings + glossary
└── sql/
    └── 70_sp_semantic_answer.sql    ← atomic compile+execute wrapper SP
```

### Personas

| Profile            | Browse | Compile | Execute (compiled) | Free-form SQL    | Write catalog | Export |
|--------------------|:------:|:-------:|:------------------:|:----------------:|:-------------:|:------:|
| `semantic_guided`  | ✅     | ✅      | ✅ (`sem_answer`)  | ❌               | ❌            | ❌     |
| `semantic_analyst` | ✅     | ✅      | ✅                 | ✅ (read-only)   | ❌            | ❌     |
| `semantic_admin`   | ✅     | ✅      | ✅                 | ✅ (read+write)  | ✅            | ✅     |

- **`semantic_guided`** — locked-down chat-with-your-metrics agent. Only the
  four core sem_* tools. No free-form SQL, no export, no authoring.
- **`semantic_analyst`** — power analyst / data scientist. Uses the
  semantic layer for governed answers AND has free-form **read** access
  via `base_*`. `base_writeQuery` / `base_dynamicQuery` are excluded.
- **`semantic_admin`** — catalog steward / DBA. Full authoring
  (`sem_import`), export (`sem_export_*`), plus every `base_*`, `dba_*`,
  `sec_*`, `qlty_*` tool.

### Tool inventory (6 total)

**Core — every persona (4):**

| Tool          | Purpose                                                              |
|---------------|----------------------------------------------------------------------|
| `sem_list`    | enumerate entities by `kind` (MODEL / DATASET / FIELD / METRIC / VIEW / VIEW_MEMBER / RELATIONSHIP) — one tool for every level of the hierarchy |
| `sem_search`  | fuzzy keyword search across names, synonyms, descriptions             |
| `sem_describe`| pivoted attribute list for one entity (the deepest discovery tool)    |
| `sem_answer`  | compile + execute a semantic request; `dry_run=1` returns the SQL + plan without running it |

**Admin-only (2):**

| Tool              | Purpose                                                          |
|-------------------|------------------------------------------------------------------|
| `sem_import`      | create one catalog entity (any kind) from a JSON payload         |
| `sem_export_osi`  | OSI 0.1.1 YAML dump of a whole model                             |

---

## Setup (one-time)

### 1. Deploy the catalog

You must have the base semantic-catalog schema installed already. From the
repo root:

```bash
export DATABASE_URI="teradata://<user>:<password>@<host>/demo_user"
semantic-catalog deploy --mode split          # base catalog + samples
```

### 2. Deploy the MCP-specific wrapper SP

`sem_answer` (the atomic compile-and-execute tool used by
`semantic_guided`) relies on `demo_user.sp_semantic_answer`. Deploy it:

```bash
semantic-catalog deploy --mode whole --include mcp/sql/70_sp_semantic_answer
# or, equivalently:
bteq < mcp/sql/70_sp_semantic_answer.sql
```

Verify:

```sql
HELP PROCEDURE demo_user.sp_semantic_answer;
CALL demo_user.sp_semantic_answer('tpch_osi','revenue','','','','',5);
```

### 3. Install the Teradata MCP server

```bash
pip install teradata-mcp-server        # from PyPI
# or
uv tool install teradata-mcp-server    # if you use uv
```

### 4. Point the server at this config directory

```bash
export DATABASE_URI="teradatasql://<user>:<password>@<host>/demo_user"
export CONFIG_DIR="$PWD/mcp"          # absolute path to THIS directory
# pick ONE persona:
teradata-mcp-server --profile semantic_guided
```

That's it. The server loads every `*.yml` in `$CONFIG_DIR`, filters them
through the selected profile's regex, and exposes the surviving tools via
MCP (stdio by default, SSE / streamable-HTTP available via flags — see the
upstream docs).

---

## Running the three personas

Same config dir, different `--profile`:

```bash
# A chat-with-your-metrics bot you can safely hand to anyone:
teradata-mcp-server --profile semantic_guided

# A data-scientist agent that can also poke around the DB:
teradata-mcp-server --profile semantic_analyst

# A semantic-layer curator / developer agent:
teradata-mcp-server --profile semantic_admin
```

### Wiring it into Claude Desktop / a Claude API client

`claude_desktop_config.json`:

```jsonc
{
  "mcpServers": {
    "td-semantic-guided": {
      "command": "teradata-mcp-server",
      "args": ["--profile", "semantic_guided"],
      "env": {
        "DATABASE_URI": "teradatasql://user:pw@host/demo_user",
        "CONFIG_DIR":   "/absolute/path/to/semantic-layer/mcp"
      }
    },
    "td-semantic-analyst": {
      "command": "teradata-mcp-server",
      "args": ["--profile", "semantic_analyst"],
      "env": {
        "DATABASE_URI": "teradatasql://user:pw@host/demo_user",
        "CONFIG_DIR":   "/absolute/path/to/semantic-layer/mcp"
      }
    }
  }
}
```

Add one block per persona you want to expose; Claude will show them as
separate servers.

---

## How the agent uses the tools

**Typical flow for a `semantic_guided` chat agent answering
*"How much revenue did AUTOMOBILE customers generate in 2023?"*:**

1. `sem_list(kind='MODEL')` → `tpch_osi`, `tpch_orders`, `exec_dashboard`
2. `sem_search(term='revenue')` → hit on metric `revenue` in `tpch_osi`
3. `sem_describe(entity_type='METRIC', entity_name='revenue',
    model='tpch_osi')` → confirms the definition + primary dataset
4. `sem_list(kind='FIELD', model='tpch_osi', parent='customer')` →
    `c_mktsegment` is a dimension
5. `sem_answer(model='tpch_osi', metrics='revenue',
    dimensions='customer.c_mktsegment',
    where_filters="customer.c_mktsegment|=|'AUTOMOBILE'", row_limit=1)`
    → returns the answer row.

For `semantic_analyst`, step 5 can alternatively be
`sem_answer(..., dry_run=1)` to see the compiled SQL, then
`base_readQuery(sql=<tweaked SQL>)` to run a modified version.

---

## Customising

### Change the catalog schema

All tools accept a `catalog_db` parameter (default `demo_user`). Either
pass it explicitly per call, or edit each YAML's `default:` line once.

### Add a new tool

Create a `*.yml` in this directory. Minimal shape:

```yaml
my_new_tool:
  type: tool
  description: "what it does"
  sql: "SELECT foo FROM bar WHERE baz = :baz"
  parameters:
    baz:
      description: "filter value"
```

If the name starts with `sem_`, it will be auto-picked up by the three
profiles shipped here. For a different prefix, extend the relevant
`tool:` regex list in `profiles.yml`.

### Add a new persona

Append to `profiles.yml`:

```yaml
my_persona:
  tool:
    - ^sem_(list|search|describe|get|answer)$   # restrict as needed
  prompt:
    - ^sem_discovery_.*
```

Then `teradata-mcp-server --profile my_persona`.

---

## Troubleshooting

- **`EXEC demo_user.m_semantic_search(...)` fails with permission error.**
  The macro lives in `demo_user`. Either grant EXECUTE to the MCP session
  user or set `catalog_db` to a schema the session can reach.
- **`sem_answer` returns `status='ERROR'` with message "no metrics and no
  dimensions".** You passed `metrics=""` and `dimensions=""`. Every
  request needs at least one of each.
- **`sem_import` reports `ERROR: parent not found`.** You skipped a
  topological step. Create the parent (e.g. the DATASET before its
  FIELDs) and retry.
- **Server logs: `Type tool for custom object ... is undefined`.** The
  YAML under that name is missing `type: tool`. Every definition must
  start with one of `type: tool | cube | prompt | glossary`.
- **Generated SQL looks right but fails at execute time on the `tpch_*`
  physical tables.** The sandbox may not have the TPC-H schema
  deployed. Run `sql/40_sample_tpch_ddl.sql` + `sql/41_sample_tpch_data.sql`
  from the repo root, or retarget the catalog to existing tables via
  `sql/42_retarget_catalog.sql`.

---

## Design notes

- **Why a wrapper SP for `sem_answer`?** The MCP server executes every
  custom tool via a single-statement SQLAlchemy `text()` call routed
  through `handle_base_readQuery`. The catalog's compiler (`sp_semantic_request`)
  returns its plan via OUT parameters; the MCP executor expects row
  results. `sp_semantic_answer` (in `sql/70_sp_semantic_answer.sql`)
  wraps compile + execute in one `CALL`, returns rows via
  `DYNAMIC RESULT SETS 1`, and — critically — lets the `semantic_guided`
  persona execute compiled SQL **without ever being granted free-form
  SQL access**.
- **Why `{catalog_db}` as format-string, but `:param` for values?** The
  server's handler detects `{foo}` placeholders and does identifier
  substitution before SQLAlchemy binds values. Schema names can't be
  bind parameters in any DBMS, so this is the canonical workaround.
- **Concurrency.** The compiler uses GLOBAL TEMPORARY staging tables, so
  each session has its own scratchpad; concurrent callers never see each
  other's rows. Results come back as OUT parameters on the CALL itself,
  not from any shared table — no locking, no session-id filter needed.
