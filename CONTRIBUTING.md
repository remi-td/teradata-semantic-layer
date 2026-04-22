# Contributing

Thanks for your interest in contributing to the Teradata Semantic
Catalog. This doc is short on purpose — the codebase itself is the
spec.

## Ground rules

- **The pure-Python pipeline is the product.** Compiler lives in
  `src/semantic_catalog/compiler/`, importer in
  `src/semantic_catalog/importer/`, exporter in
  `src/semantic_catalog/exporter/`. Changes that require a stored
  procedure to compile a request will not be merged.
- **YAML regression cases are the truth.** New compiler features ship
  with at least one case under `tests/cases/` exercising the new SQL
  shape. Bug fixes ship with a case that fails before the fix.
- **No new SQL files in `sql_bundle/`** unless they are pure DDL or
  simple read-only macros. The installer explicitly drops the old
  `sp_semantic_request` / `sp_semantic_import` surface; don't re-add a
  SQL compiler.

## Local setup

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

export DATABASE_URI="teradata://<user>:<pw>@<host>:1025/<db>"
semantic-catalog ping
pytest
```

Tests that require a live database are marked `@pytest.mark.live` and
auto-skip when `DATABASE_URI` is unset or unreachable. The offline
suite (fake catalog) should stay green on every branch.

## Submitting a change

1. Fork, branch from `master`.
2. Keep the commit message focused on the **why**. The diff already
   shows the **what**.
3. Include test updates in the same commit as the code change.
4. Open a PR with a short "before / after" description. Attach output
   of the regression case if the change affects compiled SQL.

## Style

- Python: `ruff` is pre-configured (`line-length = 100`). No hard
  opinion beyond that.
- SQL: `UPPERCASE` keywords, `snake_case` identifiers, physical names
  matching the Teradata dictionary casing (`DataBaseName`, `TableName`,
  `ColumnName`).

## Reporting issues

- File an issue at https://github.com/remi-td/semantic-catalog/issues.
- For compiler bugs, include the request JSON, the compiled SQL, and
  (if possible) the catalog state (`/api/export/osi/<model>`).

## Security

For suspected security issues (injection, privilege escalation, etc.),
please email the maintainer directly rather than filing a public
issue. The repo ships a hardened default (bearer auth, regex-gated
`RAW` filters, read-only `EXPLAIN`) but the attack surface is still
growing.
