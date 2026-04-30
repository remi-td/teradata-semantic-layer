# Lite deployment

A **server-less** way to expose the Teradata Semantic Catalog to AI
agents. No FastAPI process, no GUI, no Python compiler — just the
catalog tables and two Teradata-resident macros, surfaced as custom
tools on the open-source [Teradata MCP Server Community
Edition](https://github.com/Teradata/teradata-mcp-server).

## What you get

| Tool                  | Backed by                         | What an agent can do                              |
|-----------------------|-----------------------------------|---------------------------------------------------|
| `semantic_search`     | macro `m_semantic_search`         | Find metrics / datasets / fields by business term |
| `semantic_describe`   | macro `m_semantic_describe`       | Get expressions, AI context, joins, format spec   |

What lite does **not** include:

- ❌ Query compilation. The agent has to write the SQL itself
  (using the metric expressions and relationships it discovers via
  `describe`).
- ❌ Compile-time validation, EXPLAIN, chasm-trap detection.
- ❌ Row-level security WHERE injection (driven by the Python
  compiler today).
- ❌ Authoring as an MCP tool. Models are loaded with the offline
  `semantic-catalog import` CLI (one-shot, no daemon).
- ❌ OSI export as an MCP tool. Use the offline `semantic-catalog
  export` CLI instead — Teradata MCP Server CE can't surface
  dynamic-result-set procedures, so the SP-based path was dropped in
  favour of a single Python-only exporter shared with the full
  deployment.
- ❌ Web GUI. Use any SQL client.

If you need any of the above as live tools, run the full deployment:
`semantic-catalog serve`.

## Install

```bash
# 1. Deploy the catalog tables and macros into Teradata.
pip install git+https://github.com/remi-td/teradata-semantic-layer.git   # one-shot tool, only needed for install
export DATABASE_URI="teradata://user:pw@host:1025/<your_db>"
semantic-catalog install                        # idempotent

# 2. Load whatever semantic model(s) you want catalogued.
semantic-catalog install-example tpch_orders    # bundled example, or:
semantic-catalog import path/to/your_model.yaml # one-shot, no server needed
# semantic-catalog import path/to/your_model.yaml --dry-run   # validate only

# 3. Drop this manifest into the directory you'll point Teradata MCP
#    Server CE at via --config_dir. The filename's `_objects.yml` suffix
#    is required: the CE server only globs files matching `*_objects.yml`.
cp agentic/lite/semantic_catalog_objects.yml /path/to/mcp-config-dir/

#    EDIT the manifest: replace 'demo_user' with the database you installed
#    the catalog into (it must match the database in DATABASE_URI above).

# 4. Start the MCP server, pointing at that directory. The two tools
#    register automatically at startup.
teradata-mcp-server --config_dir /path/to/mcp-config-dir
```

After that, **the Python toolchain is not on the runtime path.** Agents
talk to the Teradata MCP Server CE; the server hits the macros directly
via its Teradata connection. You only need the `semantic-catalog`
package on the workstation that loads / dumps models — not on the
runtime host.

## Authoring / updating the model after install

Lite is read-mostly at runtime. To change the model:

- **Recommended:** re-run `semantic-catalog import your_model.yaml`
  from a workstation. The CLI runs the same one-transaction importer
  the full server uses; add `--dry-run` to validate first.
- **Hand-SQL:** the catalog is just tables. Insert into
  `SEMANTIC_MODEL`, `DATASET`, `FIELD`, `METRIC`, `RELATIONSHIP`,
  `REL_COLUMN_MAP`, `AI_CONTEXT` directly. See
  [`docs/developer/semantic-catalog-design.md`](../../docs/developer/semantic-catalog-design.md)
  for the schema.

There is deliberately **no `sp_semantic_add` family** — the existing
Python importer is the maintained authoring path, and re-implementing
it as 13 stored procedures would create drift between the two
codepaths. If you want agent-driven authoring, run the full deployment.

## Exporting a model to OSI YAML

```bash
semantic-catalog export tpch_orders                       # to stdout
semantic-catalog export tpch_orders -o tpch_orders.yaml   # to file
```

The CLI uses the same Python exporter as the full server's
`/api/export/osi` endpoint, so the output is byte-for-byte identical
across both deployment modes.

## Trade-offs vs. full deployment

|                             | Lite                               | Full                                 |
|-----------------------------|------------------------------------|--------------------------------------|
| Runtime processes           | None on the app side               | One Python process per host          |
| Discovery (search/describe) | ✅ via Teradata MCP Server CE       | ✅ via embedded MCP                  |
| OSI export                  | ✅ offline via `export` CLI         | ✅ via Python (MCP tool + REST)      |
| SQL compilation             | ❌ — agent writes SQL itself        | ✅ governed Teradata SQL              |
| Compile-time validation     | ❌                                  | ✅ EXPLAIN, chasm-trap, unresolved   |
| Row-level security          | ❌                                  | ✅ `X-Semantic-Groups` + policies    |
| Authoring at runtime        | ❌ (offline `import` CLI only)      | ✅ `/api/import`                      |
| Web GUI                     | ❌                                  | ✅ Cytoscape + query builder         |

Both modes share **the same database schema**. There is no
"lite-flavoured" catalog — the only difference is which Python
processes (if any) sit between the agent and the catalog tables.

## Trouble-shooting

- **`Object 'm_semantic_search' does not exist`**: the manifest's
  database prefix doesn't match where the catalog was installed. Edit
  `agentic/lite/semantic_catalog_objects.yml` and replace `demo_user`.
- **Tools never show up in `tools/list`**: the server only discovers
  manifests whose filename ends in `_objects.yml` (CE convention).
  Don't rename the file when copying it.
- **Every call returns `This text() construct doesn't define a bound
  parameter named '...'`**: the manifest was hand-edited to use
  `%(name)s` placeholders. CE binds via SQLAlchemy `text()`, which only
  honours `:name`. Restore the `:term`/`:model`/`:entity_type`/etc.
  placeholders in `semantic_catalog_objects.yml`.
- **Empty `semantic_search` results across the board**: confirm at
  least one model is loaded — `SELECT model_name FROM <db>.SEMANTIC_MODEL`.
