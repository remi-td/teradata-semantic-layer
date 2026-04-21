"""Join resolver + end-to-end compile() tests.

Covers:
  * Anchor-only emits step 0 FROM
  * 1-hop forward join
  * 2-hop with auto-bridging (lineitem → customer via orders)
  * Role-played single + double roles resolve to the right edges
  * Unresolved datasets surface in plan.unresolved without crashing
  * compile() round-trip: resolver + joins + render → SQL string whose
    shape matches what the SP engine would emit
"""
from __future__ import annotations

from semantic_catalog.api.models import QueryFilter, QueryRequest, QuerySort
from semantic_catalog.compiler import (
    InMemoryCatalog,
    compile,
    render,
)


# reuse fixture shape from test_compiler_resolver.py to avoid coupling
def _tpch_catalog() -> tuple[InMemoryCatalog, dict]:
    cat = InMemoryCatalog()
    mid = cat.add_model("tpch_orders")
    lineitem = cat.add_dataset(mid, "lineitem", database="tpch", table="lineitem")
    orders   = cat.add_dataset(mid, "orders",   database="tpch", table="orders")
    customer = cat.add_dataset(mid, "customer", database="tpch", table="customer")
    l_orderkey = cat.add_field(lineitem, "l_orderkey")
    l_price    = cat.add_field(lineitem, "l_extendedprice")
    l_disc     = cat.add_field(lineitem, "l_discount")
    l_shipdate = cat.add_field(lineitem, "l_shipdate", is_time=True)
    o_orderkey = cat.add_field(orders,   "o_orderkey")
    o_custkey  = cat.add_field(orders,   "o_custkey")
    o_orderstatus = cat.add_field(orders, "o_orderstatus")
    c_custkey  = cat.add_field(customer, "c_custkey")
    c_name     = cat.add_field(customer, "c_name")
    c_mktsegment = cat.add_field(customer, "c_mktsegment")
    cat.add_metric(
        mid, "revenue",
        expression="SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))",
        primary_dataset_id=lineitem.dataset_id,
        field_refs=[l_price.field_id, l_disc.field_id],
    )
    cat.add_metric(
        mid, "count_orders",
        expression="COUNT(orders.o_orderkey)",
        primary_dataset_id=orders.dataset_id,
        field_refs=[o_orderkey.field_id],
    )
    cat.add_relationship(
        mid, name="lineitem_to_orders", from_ds=lineitem, to_ds=orders,
        cardinality="MANY_TO_ONE", columns=[(l_orderkey, o_orderkey)],
    )
    cat.add_relationship(
        mid, name="orders_to_customer", from_ds=orders, to_ds=customer,
        cardinality="MANY_TO_ONE", columns=[(o_custkey, c_custkey)],
    )
    return cat, {"model_id": mid, "lineitem": lineitem, "orders": orders,
                 "customer": customer}


def _tpcds_role_catalog() -> tuple[InMemoryCatalog, dict]:
    cat = InMemoryCatalog()
    mid = cat.add_model("tpcds_retail")
    fact = cat.add_dataset(mid, "store_sales", database="tpcds", table="store_sales")
    date_dim = cat.add_dataset(mid, "date_dim", database="tpcds", table="date_dim")
    sold_sk = cat.add_field(fact, "ss_sold_date_sk")
    ship_sk = cat.add_field(fact, "ss_ship_date_sk")
    ext_sales = cat.add_field(fact, "ss_ext_sales_price")
    d_date_sk = cat.add_field(date_dim, "d_date_sk")
    d_year = cat.add_field(date_dim, "d_year")
    cat.add_metric(
        mid, "total_revenue",
        expression="SUM(store_sales.ss_ext_sales_price)",
        primary_dataset_id=fact.dataset_id,
        field_refs=[ext_sales.field_id],
    )
    cat.add_relationship(
        mid, name="sold_date", from_ds=fact, to_ds=date_dim,
        cardinality="MANY_TO_ONE", role_name="sold_date",
        columns=[(sold_sk, d_date_sk)],
    )
    cat.add_relationship(
        mid, name="ship_date", from_ds=fact, to_ds=date_dim,
        cardinality="MANY_TO_ONE", role_name="ship_date",
        columns=[(ship_sk, d_date_sk)],
    )
    return cat, {"model_id": mid, "fact": fact, "date_dim": date_dim}


# --------------------------------------------------- joins unit tests

def test_anchor_only_emits_step_zero() -> None:
    cat, _ = _tpch_catalog()
    plan = compile(QueryRequest(model="tpch_orders", metrics=["revenue"]), cat)
    steps = plan.join_steps
    assert len(steps) == 1
    assert steps[0].step_ordinal == 0
    assert steps[0].join_sql == "FROM tpch.lineitem AS lineitem"
    assert plan.unresolved == []


def test_one_hop_forward_join() -> None:
    cat, _ = _tpch_catalog()
    plan = compile(
        QueryRequest(
            model="tpch_orders",
            metrics=["revenue"],
            where=[QueryFilter(field="orders.o_orderstatus", op="=", value="O")],
        ),
        cat,
    )
    assert len(plan.join_steps) == 2
    j = plan.join_steps[1]
    assert j.step_ordinal == 1
    assert ("INNER JOIN tpch.orders AS orders "
            "ON lineitem.l_orderkey = orders.o_orderkey") == j.join_sql
    assert plan.unresolved == []


def test_two_hop_with_bridge_inserts_orders() -> None:
    cat, _ = _tpch_catalog()
    plan = compile(
        QueryRequest(
            model="tpch_orders",
            metrics=["revenue"],
            dimensions=["customer.c_mktsegment"],
        ),
        cat,
    )
    assert plan.unresolved == []
    # Expect: FROM lineitem, JOIN orders (bridge), JOIN customer
    join_sqls = [s.join_sql for s in plan.join_steps]
    assert join_sqls[0] == "FROM tpch.lineitem AS lineitem"
    assert any("INNER JOIN tpch.orders" in s for s in join_sqls[1:])
    assert any("INNER JOIN tpch.customer" in s for s in join_sqls[1:])


def test_role_played_dim_selects_correct_edge() -> None:
    cat, _ = _tpcds_role_catalog()
    plan = compile(
        QueryRequest(
            model="tpcds_retail",
            metrics=["total_revenue"],
            dimensions=["sold_date.d_year"],
        ),
        cat,
    )
    join = next(s for s in plan.join_steps if s.step_ordinal > 0)
    # Alias must be ``sold_date`` — and the ON clause must reference ss_sold_date_sk
    assert "AS sold_date" in join.join_sql
    assert "ss_sold_date_sk" in join.join_sql
    assert "ss_ship_date_sk" not in join.join_sql


def test_two_role_dims_emit_both_joins() -> None:
    cat, _ = _tpcds_role_catalog()
    plan = compile(
        QueryRequest(
            model="tpcds_retail",
            metrics=["total_revenue"],
            dimensions=["sold_date.d_year", "ship_date.d_year"],
        ),
        cat,
    )
    assert plan.unresolved == []
    join_sqls = " ".join(s.join_sql for s in plan.join_steps if s.step_ordinal > 0)
    assert "AS sold_date" in join_sqls and "AS ship_date" in join_sqls
    assert "ss_sold_date_sk" in join_sqls and "ss_ship_date_sk" in join_sqls


def test_unresolved_datasets_surface_when_no_path() -> None:
    """A dangling dataset with no relationship to the rest of the model
    is surfaced in plan.unresolved without raising."""
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    a = cat.add_dataset(mid, "a", database="db", table="a")
    b = cat.add_dataset(mid, "b", database="db", table="b")
    dangling = cat.add_dataset(mid, "c", database="db", table="c")
    cat.add_field(a, "k")
    cat.add_field(b, "k")
    c_x = cat.add_field(dangling, "x")
    cat.add_metric(mid, "mk", expression="COUNT(a.k)",
                   primary_dataset_id=a.dataset_id)
    cat.add_relationship(mid, name="a_to_b", from_ds=a, to_ds=b,
                         cardinality="MANY_TO_ONE",
                         columns=[(cat.fields[(a.dataset_id, "k")],
                                   cat.fields[(b.dataset_id, "k")])])
    plan = compile(
        QueryRequest(model="m", metrics=["mk"], dimensions=["c.x"]),
        cat,
    )
    assert plan.unresolved == ["c"]


# ---------------------------------------------- end-to-end render tests

def test_compile_then_render_simple_metric_and_dim() -> None:
    cat, _ = _tpch_catalog()
    plan = compile(
        QueryRequest(
            model="tpch_orders",
            metrics=["revenue"],
            dimensions=["customer.c_mktsegment"],
        ),
        cat,
    )
    sql = render(plan, pretty=False)
    assert "LOCKING ROW FOR ACCESS" in sql
    assert "SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount)) AS revenue" in sql
    assert "customer.c_mktsegment AS c_mktsegment" in sql
    assert "INNER JOIN tpch.orders AS orders" in sql
    assert "INNER JOIN tpch.customer AS customer" in sql
    assert "GROUP BY customer.c_mktsegment" in sql


def test_compile_then_render_dim_only_uses_distinct() -> None:
    cat, _ = _tpch_catalog()
    plan = compile(
        QueryRequest(
            model="tpch_orders",
            dimensions=["customer.c_mktsegment"],
        ),
        cat,
    )
    sql = render(plan, pretty=False)
    assert "SELECT DISTINCT" in sql
    assert "GROUP BY" not in sql


def test_compile_then_render_having_substitutes_metric_expr() -> None:
    cat, _ = _tpch_catalog()
    plan = compile(
        QueryRequest(
            model="tpch_orders",
            metrics=["revenue"],
            dimensions=["customer.c_mktsegment"],
            having=[QueryFilter(metric="revenue", op=">", value=1000, type="NUMBER")],
        ),
        cat,
    )
    sql = render(plan, pretty=False)
    assert ("HAVING (SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))) > 1000"
            in sql)


def test_compile_then_render_order_by_and_top() -> None:
    cat, _ = _tpch_catalog()
    plan = compile(
        QueryRequest(
            model="tpch_orders",
            metrics=["revenue"],
            dimensions=["customer.c_mktsegment"],
            sort=[QuerySort(field="revenue", direction="desc")],
            limit=10,
        ),
        cat,
    )
    sql = render(plan, pretty=False)
    assert "ORDER BY revenue DESC" in sql
    assert "TOP 10" in sql
    assert "LIMIT" not in sql


def test_compile_then_render_filtered_metric_builds_case_when() -> None:
    """End-to-end filtered metric: compile + render should produce the
    CASE WHEN form identical to the SP for FM01 (school_gradebook)."""
    cat = InMemoryCatalog()
    mid = cat.add_model("school_gradebook")
    assess = cat.add_dataset(mid, "assessment",
                             database="demo_user", table="gb_assessment")
    atype = cat.add_dataset(mid, "assessment_type",
                            database="demo_user", table="gb_assessment_type")
    student = cat.add_dataset(mid, "student",
                              database="demo_user", table="gb_student")
    a_type_code = cat.add_field(assess, "type_code")
    a_student_id = cat.add_field(assess, "student_id")
    a_score = cat.add_field(assess, "score")
    t_type_code = cat.add_field(atype, "type_code")
    t_lvl1 = cat.add_field(atype, "category_lvl1")
    s_student_id = cat.add_field(student, "student_id")
    s_major = cat.add_field(student, "major")
    cat.add_relationship(mid, name="a_to_student", from_ds=assess, to_ds=student,
                         cardinality="MANY_TO_ONE",
                         columns=[(a_student_id, s_student_id)])
    cat.add_relationship(mid, name="a_to_type", from_ds=assess, to_ds=atype,
                         cardinality="MANY_TO_ONE",
                         columns=[(a_type_code, t_type_code)])
    score_avg = cat.add_base_metric(
        mid, "score_avg",
        aggregate_fn="AVG", aggregate_arg="assessment.score",
        primary_dataset_id=assess.dataset_id,
        field_refs=[a_score.field_id],
    )
    cat.add_filtered_metric(
        mid, "exam_score_avg", base=score_avg,
        filters=[(atype, t_lvl1, "=", "'EX'")],
    )
    plan = compile(
        QueryRequest(
            model="school_gradebook",
            metrics=["score_avg", "exam_score_avg"],
            dimensions=["student.major"],
        ),
        cat,
    )
    sql = render(plan, pretty=False)
    assert "AVG(assessment.score) AS score_avg" in sql
    assert ("AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' "
            "THEN assessment.score END) AS exam_score_avg") in sql
    assert "INNER JOIN demo_user.gb_student AS student" in sql
    assert "INNER JOIN demo_user.gb_assessment_type AS assessment_type" in sql
    assert "GROUP BY student.major" in sql
