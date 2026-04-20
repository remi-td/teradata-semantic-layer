# Examples

Demo scenarios that showcase the semantic catalog. These are **not** part of
the core product — install them only if you want the sample data and models
used throughout the docs.

## Layout

```
examples/
├── tpch_physical/   TPC-H sample tables (shared prereq for tpch_osi + tpch_orders)
├── tpch_osi/        Scenario A: OSI-style entity-first model (model: tpch_osi)
├── tpch_orders/     Scenario B: Honeydew-style supply-chain model with
│                    role-playing dims (model: tpch_orders)
└── exec_dashboard/  Scenario C: cube-first single-dataset model (model: exec_dashboard)
```

Each directory holds:

- The scenario's `.sql` files (catalog inserts, physical DDL where relevant).
- A `teardown.sql` that removes everything the scenario added.

## Install

The core catalog must already be deployed (`semantic-catalog install`).
Then:

```bash
# TPC-H physical tables are a shared prerequisite for the two TPC-H catalog
# scenarios. Install them once.
semantic-catalog install-example tpch_physical

semantic-catalog install-example tpch_osi
semantic-catalog install-example tpch_orders
semantic-catalog install-example exec_dashboard   # no physical prereq
```

## Uninstall

```bash
semantic-catalog uninstall-example tpch_orders
semantic-catalog uninstall-example tpch_osi
semantic-catalog uninstall-example exec_dashboard

# Drop the physical tables last, once no catalog scenario references them.
semantic-catalog uninstall-example tpch_physical
```

Teardowns are idempotent (tolerate "object does not exist" errors).

## What to run in your own project

You do not need these examples to use the catalog. For a real deployment:

1. `semantic-catalog install` — deploy the core DDL and stored procedures.
2. Load your own metadata via `POST /api/import` (GUI) or the
   `sp_semantic_import` stored procedure.

Use these examples as reference payloads when you're writing your own.
