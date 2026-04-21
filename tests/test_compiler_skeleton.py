"""Compiler skeleton tests — no database, no resolver, just the render layer.

Proves that:
  1. sqlglot is installed and picks up the Teradata dialect.
  2. LogicalPlan dataclasses are constructable by hand.
  3. render() emits Teradata-correct SQL:
       - TOP N (not LIMIT) for row limits
       - dataset-qualified columns
       - aliased FROM clauses
       - multi-step joins parsed through sqlglot
"""
from __future__ import annotations

from semantic_catalog.compiler import (
    DatasetRef,
    FieldRef,
    JoinStep,
    LogicalPlan,
    MetricRef,
    ResolvedDim,
    render,
)


def _anchor() -> DatasetRef:
    return DatasetRef(
        dataset_id=1,
        dataset_name="lineitem",
        database_name="tpch",
        table_name="lineitem",
    )


def test_render_emits_top_not_limit_for_teradata() -> None:
    plan = LogicalPlan(
        model_id=1,
        model_name="tpch_orders",
        anchor=_anchor(),
        required_datasets=[_anchor()],
        dimensions=[
            ResolvedDim(
                field=FieldRef(field_id=10, dataset_id=1, field_name="l_returnflag",
                               expression="l_returnflag"),
                dataset_alias="lineitem",
            )
        ],
        limit=100,
    )
    sql = render(plan, pretty=False)
    assert "TOP 100" in sql, sql
    assert "LIMIT" not in sql, sql
    assert "lineitem.l_returnflag" in sql, sql
    assert "tpch.lineitem AS lineitem" in sql, sql


def test_render_with_metric_and_multiple_dims() -> None:
    anchor = _anchor()
    plan = LogicalPlan(
        model_id=1,
        model_name="tpch_orders",
        anchor=anchor,
        required_datasets=[anchor],
        dimensions=[
            ResolvedDim(
                field=FieldRef(field_id=10, dataset_id=1, field_name="l_returnflag",
                               expression="l_returnflag"),
                dataset_alias="lineitem",
            ),
            ResolvedDim(
                field=FieldRef(field_id=11, dataset_id=1, field_name="l_linestatus",
                               expression="l_linestatus"),
                dataset_alias="lineitem",
            ),
        ],
        metrics=[
            MetricRef(metric_id=5, metric_name="revenue",
                      expression="SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))",
                      primary_dataset_id=1)
        ],
    )
    sql = render(plan, pretty=False)
    assert "l_returnflag AS l_returnflag" in sql
    assert "l_linestatus AS l_linestatus" in sql
    assert "SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue" in sql


def test_render_with_join_step() -> None:
    anchor = _anchor()
    customer = DatasetRef(
        dataset_id=2,
        dataset_name="customer",
        database_name="tpch",
        table_name="customer",
    )
    orders = DatasetRef(
        dataset_id=3,
        dataset_name="orders",
        database_name="tpch",
        table_name="orders",
    )
    plan = LogicalPlan(
        model_id=1,
        model_name="tpch_orders",
        anchor=anchor,
        required_datasets=[anchor, orders, customer],
        dimensions=[
            ResolvedDim(
                field=FieldRef(field_id=30, dataset_id=2, field_name="c_name",
                               expression="c_name"),
                dataset_alias="customer",
            )
        ],
        join_steps=[
            JoinStep(step_ordinal=0, relationship_id=None, from_dataset_id=None,
                     to_dataset_id=1, join_sql="FROM tpch.lineitem AS lineitem"),
            JoinStep(step_ordinal=1, relationship_id=100, from_dataset_id=1,
                     to_dataset_id=3,
                     join_sql=("INNER JOIN tpch.orders AS orders "
                               "ON lineitem.l_orderkey = orders.o_orderkey")),
            JoinStep(step_ordinal=2, relationship_id=101, from_dataset_id=3,
                     to_dataset_id=2,
                     join_sql=("INNER JOIN tpch.customer AS customer "
                               "ON orders.o_custkey = customer.c_custkey")),
        ],
    )
    sql = render(plan, pretty=False)
    assert "tpch.lineitem AS lineitem" in sql
    assert "INNER JOIN tpch.orders AS orders ON lineitem.l_orderkey = orders.o_orderkey" in sql
    assert "INNER JOIN tpch.customer AS customer ON orders.o_custkey = customer.c_custkey" in sql
    assert "customer.c_name" in sql


def test_render_cube_dataset_wraps_source_query() -> None:
    cube = DatasetRef(
        dataset_id=7,
        dataset_name="sales_cube",
        database_name=None,
        table_name=None,
        source_query="SELECT 1 AS x, 2 AS y FROM some.table",
    )
    plan = LogicalPlan(
        model_id=99,
        model_name="exec_dashboard",
        anchor=cube,
        required_datasets=[cube],
        dimensions=[
            ResolvedDim(
                field=FieldRef(field_id=70, dataset_id=7, field_name="x", expression="x"),
                dataset_alias="sales_cube",
            )
        ],
    )
    sql = render(plan, pretty=False)
    assert "(SELECT 1 AS x, 2 AS y FROM some.table) AS sales_cube" in sql \
        or "(SELECT\n  1 AS x,\n  2 AS y\n  FROM some.table) AS sales_cube" in sql \
        or "FROM (SELECT" in sql  # sqlglot may reflow
    assert "sales_cube.x AS x" in sql


def test_render_dim_with_year_grain_wraps_trunc() -> None:
    anchor = _anchor()
    plan = LogicalPlan(
        model_id=1,
        model_name="tpch_orders",
        anchor=anchor,
        required_datasets=[anchor],
        dimensions=[
            ResolvedDim(
                field=FieldRef(field_id=50, dataset_id=1, field_name="l_shipdate",
                               expression="l_shipdate", is_time_dimension=True),
                dataset_alias="lineitem",
                grain="YEAR",
            )
        ],
    )
    sql = render(plan, pretty=False)
    assert "TRUNC(lineitem.l_shipdate, 'Y')" in sql
    assert "AS l_shipdate_year" in sql


def test_render_role_played_dim_uses_role_alias() -> None:
    fact = DatasetRef(dataset_id=1, dataset_name="store_sales",
                      database_name="tpcds", table_name="store_sales")
    sold_date = DatasetRef(dataset_id=5, dataset_name="date_dim",
                           database_name="tpcds", table_name="date_dim",
                           alias="sold_date")
    plan = LogicalPlan(
        model_id=1,
        model_name="tpcds_retail",
        anchor=fact,
        required_datasets=[fact, sold_date],
        dimensions=[
            ResolvedDim(
                field=FieldRef(field_id=60, dataset_id=5, field_name="d_year",
                               expression="d_year"),
                dataset_alias="sold_date",
                role_edge_id=42,
                column_alias="sold_date_d_year",
            )
        ],
        join_steps=[
            JoinStep(step_ordinal=0, relationship_id=None, from_dataset_id=None,
                     to_dataset_id=1, join_sql="FROM tpcds.store_sales AS store_sales"),
            JoinStep(step_ordinal=1, relationship_id=42, from_dataset_id=1,
                     to_dataset_id=5,
                     join_sql=("INNER JOIN tpcds.date_dim AS sold_date "
                               "ON store_sales.ss_sold_date_sk = sold_date.d_date_sk")),
        ],
    )
    sql = render(plan, pretty=False)
    assert "sold_date.d_year AS sold_date_d_year" in sql
    assert "tpcds.date_dim AS sold_date" in sql


def test_joined_datasets_reports_aliases() -> None:
    fact = DatasetRef(dataset_id=1, dataset_name="store_sales",
                      database_name="tpcds", table_name="store_sales")
    sold = DatasetRef(dataset_id=5, dataset_name="date_dim",
                      database_name="tpcds", table_name="date_dim",
                      alias="sold_date")
    ship = DatasetRef(dataset_id=5, dataset_name="date_dim",
                      database_name="tpcds", table_name="date_dim",
                      alias="ship_date")
    plan = LogicalPlan(
        model_id=1, model_name="tpcds_retail", anchor=fact,
        required_datasets=[fact, sold, ship],
    )
    assert plan.joined_datasets == [
        "store_sales",
        "date_dim AS sold_date",
        "date_dim AS ship_date",
    ]
