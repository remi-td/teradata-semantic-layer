"""Resolver v1 tests — token + catalog → LogicalPlan, no DB, no joins.

Joins (BFS + chasm) come in task #23; these tests assert the resolver's
contract up to that boundary: metrics composed, dims bound with roles
and grain, filters encoded, required datasets collected, anchor chosen.
"""
from __future__ import annotations

import pytest

from semantic_catalog.api.models import QueryFilter, QueryRequest, QuerySort
from semantic_catalog.compiler import (
    AmbiguousPathError,
    InMemoryCatalog,
    Resolver,
    UnknownEntityError,
    UnknownModelError,
)
from semantic_catalog.compiler.errors import CompileError


# -------------------------------------------------------- catalog fixtures

def _tpch_catalog() -> tuple[InMemoryCatalog, dict]:
    cat = InMemoryCatalog()
    mid = cat.add_model("tpch_orders")

    lineitem = cat.add_dataset(mid, "lineitem", database="tpch", table="lineitem")
    orders   = cat.add_dataset(mid, "orders",   database="tpch", table="orders")
    customer = cat.add_dataset(mid, "customer", database="tpch", table="customer")

    l_orderkey   = cat.add_field(lineitem, "l_orderkey")
    l_price      = cat.add_field(lineitem, "l_extendedprice")
    l_disc       = cat.add_field(lineitem, "l_discount")
    l_shipdate   = cat.add_field(lineitem, "l_shipdate", is_time=True)
    o_orderkey   = cat.add_field(orders,   "o_orderkey")
    o_custkey    = cat.add_field(orders,   "o_custkey")
    o_orderstatus= cat.add_field(orders,   "o_orderstatus")
    c_custkey    = cat.add_field(customer, "c_custkey")
    c_name       = cat.add_field(customer, "c_name")
    c_mktsegment = cat.add_field(customer, "c_mktsegment")

    revenue = cat.add_metric(
        mid, "revenue",
        expression="SUM(lineitem.l_extendedprice * (1 - lineitem.l_discount))",
        primary_dataset_id=lineitem.dataset_id,
        field_refs=[l_price.field_id, l_disc.field_id],
    )
    count_orders = cat.add_metric(
        mid, "count_orders",
        expression="COUNT(orders.o_orderkey)",
        primary_dataset_id=orders.dataset_id,
        field_refs=[o_orderkey.field_id],
    )

    cat.add_relationship(
        mid, name="lineitem_to_orders",
        from_ds=lineitem, to_ds=orders,
        cardinality="MANY_TO_ONE",
        columns=[(l_orderkey, o_orderkey)],
    )
    cat.add_relationship(
        mid, name="orders_to_customer",
        from_ds=orders, to_ds=customer,
        cardinality="MANY_TO_ONE",
        columns=[(o_custkey, c_custkey)],
    )

    return cat, {
        "model_id": mid, "lineitem": lineitem, "orders": orders, "customer": customer,
        "revenue": revenue, "count_orders": count_orders,
    }


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
    total = cat.add_metric(
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


# --------------------------------------------------------------- tests

def test_unknown_model_raises() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(model="nonexistent", metrics=["revenue"])
    with pytest.raises(UnknownModelError):
        r.resolve(req)


def test_unknown_metric_raises() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(model="tpch_orders", metrics=["nonexistent_metric"])
    with pytest.raises(UnknownEntityError):
        r.resolve(req)


def test_simple_metric_plus_dim_picks_anchor_from_primary() -> None:
    cat, fx = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders",
        metrics=["revenue"],
        dimensions=["customer.c_mktsegment"],
    )
    plan = r.resolve(req)
    assert plan.anchor.dataset_name == "lineitem"
    assert [m.metric_name for m in plan.metrics] == ["revenue"]
    assert plan.metrics[0].expression.startswith("SUM(lineitem.l_extendedprice")
    assert [d.field.field_name for d in plan.dimensions] == ["c_mktsegment"]
    assert plan.dimensions[0].dataset_alias == "customer"
    # required datasets: lineitem (anchor) + customer (dim)
    names = [ds.dataset_name for ds in plan.required_datasets]
    assert "lineitem" in names and "customer" in names


def test_time_grain_suffix_is_parsed_and_stored() -> None:
    cat, fx = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders",
        metrics=["revenue"],
        dimensions=["lineitem.l_shipdate:MONTH"],
    )
    plan = r.resolve(req)
    dim = plan.dimensions[0]
    assert dim.grain == "MONTH"
    assert dim.column_alias == "l_shipdate_month"


def test_unknown_grain_rejected() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders", metrics=["revenue"],
        dimensions=["lineitem.l_shipdate:DECADE"],
    )
    with pytest.raises(CompileError):
        r.resolve(req)


def test_role_playing_dim_resolves_role_and_sets_alias() -> None:
    cat, fx = _tpcds_role_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpcds_retail",
        metrics=["total_revenue"],
        dimensions=["sold_date.d_year"],
    )
    plan = r.resolve(req)
    dim = plan.dimensions[0]
    assert dim.dataset_alias == "sold_date"
    assert dim.role_edge_id is not None
    assert dim.column_alias == "sold_date_d_year"
    names_aliases = [(d.dataset_name, d.alias) for d in plan.required_datasets]
    assert ("store_sales", "store_sales") in names_aliases
    assert ("date_dim", "sold_date") in names_aliases


def test_two_role_dims_tracked_as_separate_aliases() -> None:
    cat, fx = _tpcds_role_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpcds_retail",
        metrics=["total_revenue"],
        dimensions=["sold_date.d_year", "ship_date.d_year"],
    )
    plan = r.resolve(req)
    aliases = {d.alias for d in plan.required_datasets if d.dataset_name == "date_dim"}
    assert aliases == {"sold_date", "ship_date"}


def test_ambiguous_dim_without_role_raises() -> None:
    """When date_dim has two incoming relationships, an unprefixed
    ``date_dim.d_year`` dim is ambiguous."""
    cat, _ = _tpcds_role_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpcds_retail",
        metrics=["total_revenue"],
        dimensions=["date_dim.d_year"],
    )
    with pytest.raises(AmbiguousPathError) as exc:
        r.resolve(req)
    assert sorted(exc.value.roles) == ["ship_date", "sold_date"]


def test_where_filter_is_encoded_and_required_ds_added() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders",
        metrics=["revenue"],
        dimensions=["customer.c_mktsegment"],
        where=[QueryFilter(field="orders.o_orderstatus", op="=", value="O")],
    )
    plan = r.resolve(req)
    assert len(plan.filters) == 1
    f = plan.filters[0]
    assert f.kind == "WHERE" and f.lhs == "orders.o_orderstatus"
    assert f.op == "=" and f.rhs == "'O'"
    assert any(d.dataset_name == "orders" for d in plan.required_datasets)


def test_where_in_filter_encodes_values() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders", metrics=["revenue"], dimensions=["customer.c_mktsegment"],
        where=[QueryFilter(field="orders.o_orderstatus", op="IN",
                           values=["O", "F", "P"])],
    )
    plan = r.resolve(req)
    assert plan.filters[0].rhs == "('O','F','P')"


def test_having_filter_validated_against_requested_metrics() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders",
        metrics=["revenue"],
        dimensions=["customer.c_mktsegment"],
        having=[QueryFilter(metric="revenue", op=">", value=1000, type="NUMBER")],
    )
    plan = r.resolve(req)
    h = [f for f in plan.filters if f.kind == "HAVING"]
    assert len(h) == 1
    assert h[0].lhs == "revenue" and h[0].op == ">" and h[0].rhs == "1000"


def test_having_filter_on_unknown_metric_raises() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders",
        metrics=["revenue"],
        dimensions=["customer.c_mktsegment"],
        having=[QueryFilter(metric="customer_count", op=">", value=10)],
    )
    with pytest.raises(UnknownEntityError):
        r.resolve(req)


def test_where_without_dataset_prefix_raises() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders", metrics=["revenue"],
        where=[QueryFilter(field="c_mktsegment", op="=", value="BUILDING")],
    )
    with pytest.raises(CompileError):
        r.resolve(req)


def test_chasm_warning_emitted_for_two_grains() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    req = QueryRequest(
        model="tpch_orders",
        metrics=["revenue", "count_orders"],
        dimensions=["customer.c_mktsegment"],
    )
    plan = r.resolve(req)
    assert plan.grain_count == 2
    assert plan.chasm_warning and "CHASM_WARNING" in plan.chasm_warning


# -------------------------------------------- filtered-metric composition

def _filtered_catalog() -> tuple[InMemoryCatalog, dict]:
    cat = InMemoryCatalog()
    mid = cat.add_model("school_gradebook")
    assessment = cat.add_dataset(mid, "assessment", database="demo_user", table="gb_assessment")
    atype = cat.add_dataset(mid, "assessment_type",
                            database="demo_user", table="gb_assessment_type")
    score = cat.add_field(assessment, "score")
    aid = cat.add_field(assessment, "assessment_id")
    cat1 = cat.add_field(atype, "category_lvl1")
    score_avg = cat.add_base_metric(
        mid, "score_avg",
        aggregate_fn="AVG", aggregate_arg="assessment.score",
        primary_dataset_id=assessment.dataset_id,
        field_refs=[score.field_id],
    )
    assessment_count = cat.add_base_metric(
        mid, "assessment_count",
        aggregate_fn="COUNT", aggregate_arg="assessment.assessment_id",
        primary_dataset_id=assessment.dataset_id,
        field_refs=[aid.field_id],
    )
    exam_score_avg = cat.add_filtered_metric(
        mid, "exam_score_avg", base=score_avg,
        filters=[(atype, cat1, "=", "'EX'")],
    )
    exam_count = cat.add_filtered_metric(
        mid, "exam_count", base=assessment_count,
        filters=[(atype, cat1, "=", "'EX'")],
    )
    return cat, {
        "model_id": mid, "assessment": assessment, "atype": atype,
        "score_avg": score_avg, "exam_score_avg": exam_score_avg,
        "exam_count": exam_count,
    }


def test_filtered_metric_avg_uses_else_null() -> None:
    cat, fx = _filtered_catalog()
    r = Resolver(cat)
    req = QueryRequest(model="school_gradebook", metrics=["exam_score_avg"])
    plan = r.resolve(req)
    m = plan.metrics[0]
    # ELSE clause absent (implicit NULL) for AVG
    assert m.expression == (
        "AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' "
        "THEN assessment.score END)"
    )
    # Filter dataset is required (assessment_type)
    names = [ds.dataset_name for ds in plan.required_datasets]
    assert "assessment_type" in names and "assessment" in names


def test_filtered_metric_count_uses_else_null() -> None:
    cat, fx = _filtered_catalog()
    r = Resolver(cat)
    req = QueryRequest(model="school_gradebook", metrics=["exam_count"])
    plan = r.resolve(req)
    m = plan.metrics[0]
    assert m.expression == (
        "COUNT(CASE WHEN assessment_type.category_lvl1 = 'EX' "
        "THEN assessment.assessment_id END)"
    )


def test_filtered_metric_sum_uses_else_zero() -> None:
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    d = cat.add_dataset(mid, "t", database="db", table="t")
    f_amt = cat.add_field(d, "amt")
    f_cat = cat.add_field(d, "cat")
    base = cat.add_base_metric(mid, "total", aggregate_fn="SUM",
                               aggregate_arg="t.amt",
                               primary_dataset_id=d.dataset_id,
                               field_refs=[f_amt.field_id])
    cat.add_filtered_metric(mid, "a_total", base=base,
                            filters=[(d, f_cat, "=", "'A'")])
    r = Resolver(cat)
    req = QueryRequest(model="m", metrics=["a_total"])
    plan = r.resolve(req)
    assert plan.metrics[0].expression == (
        "SUM(CASE WHEN t.cat = 'A' THEN t.amt ELSE 0 END)"
    )


def test_filtered_metric_multi_filter_joins_with_AND() -> None:
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    d = cat.add_dataset(mid, "t", database="db", table="t")
    amt = cat.add_field(d, "amt")
    cat1 = cat.add_field(d, "c1")
    cat2 = cat.add_field(d, "c2")
    base = cat.add_base_metric(mid, "total", aggregate_fn="SUM",
                               aggregate_arg="t.amt",
                               primary_dataset_id=d.dataset_id,
                               field_refs=[amt.field_id])
    cat.add_filtered_metric(mid, "ab_total", base=base,
                            filters=[(d, cat1, "=", "'A'"),
                                     (d, cat2, "=", "'B'")])
    r = Resolver(cat)
    plan = r.resolve(QueryRequest(model="m", metrics=["ab_total"]))
    assert plan.metrics[0].expression == (
        "SUM(CASE WHEN t.c1 = 'A' AND t.c2 = 'B' THEN t.amt ELSE 0 END)"
    )


# ----- structured-error and prefix-acceptance tests --------------------


def test_unknown_model_attaches_available_and_suggestions() -> None:
    """Agents recover from typos via details.suggestions (fuzzy match)
    and details.available_models (full list as fallback)."""
    cat, _ = _tpch_catalog()
    cat.add_model("tpcds_retail")
    r = Resolver(cat)
    with pytest.raises(UnknownModelError) as exc:
        r.resolve(QueryRequest(model="tpch_order", metrics=["revenue"]))
    details = exc.value.details
    assert "tpch_orders" in details["available_models"]
    assert "tpcds_retail" in details["available_models"]
    # Fuzzy match returns the close one.
    assert "tpch_orders" in details["suggestions"]


def test_unknown_metric_attaches_suggestions() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    with pytest.raises(UnknownEntityError) as exc:
        r.resolve(QueryRequest(model="tpch_orders", metrics=["revenuee"]))
    details = exc.value.details
    assert details.get("kind") == "metric"
    assert "revenue" in details["suggestions"]


def test_unknown_dim_attaches_suggestions() -> None:
    cat, _ = _tpch_catalog()
    r = Resolver(cat)
    with pytest.raises(UnknownEntityError) as exc:
        r.resolve(QueryRequest(
            model="tpch_orders", metrics=["revenue"],
            dimensions=["customer.c_mktsegmnt"],  # typo
        ))
    details = exc.value.details
    assert details.get("kind") == "dimension"
    # We expect at least one near-match. With suggestions populated from
    # the dataset-scoped token list, the right form must show up.
    sugg = details["suggestions"]
    assert any("c_mktsegment" in s for s in sugg)


def test_ambiguous_path_provides_ready_to_retry_tokens() -> None:
    """AMBIGUOUS_PATH details.suggestions must list exact compile tokens
    (role.field), not just role names. Closes the gap the diagnostic
    report flagged."""
    cat, _ = _tpcds_role_catalog()
    r = Resolver(cat)
    with pytest.raises(AmbiguousPathError) as exc:
        r.resolve(QueryRequest(
            model="tpcds_retail",
            metrics=["total_revenue"],
            dimensions=["date_dim.d_year"],
        ))
    details = exc.value.details
    assert sorted(details["suggestions"]) == [
        "ship_date.d_year", "sold_date.d_year",
    ]
    assert details["target"] == "date_dim"


def test_relationship_name_prefix_resolves_when_role_name_unset() -> None:
    """Seed data sometimes leaves role_name NULL, populating only
    relationship_name. The parser must accept either — matching what
    AMBIGUOUS_PATH advertises and the GUI / agent will retry with."""
    cat = InMemoryCatalog()
    mid = cat.add_model("rel_name_only")
    fact = cat.add_dataset(mid, "fact")
    dim = cat.add_dataset(mid, "dim")
    pk = cat.add_field(fact, "fk")
    dk = cat.add_field(dim,  "pk")
    val = cat.add_field(dim, "v")
    cat.add_metric(mid, "n", expression="COUNT(*)",
                   primary_dataset_id=fact.dataset_id, field_refs=[pk.field_id])
    # Note: role_name=None — only relationship_name is set.
    cat.add_relationship(mid, name="fact_to_dim",
                         from_ds=fact, to_ds=dim,
                         columns=[(pk, dk)])
    r = Resolver(cat)
    # Using the relationship_name as the prefix must resolve.
    plan = r.resolve(QueryRequest(
        model="rel_name_only", metrics=["n"],
        dimensions=["fact_to_dim.v"],
    ))
    assert plan.dimensions[0].dataset_alias == "fact_to_dim"
    assert plan.dimensions[0].role_edge_id is not None


def test_dimension_dict_via_field_is_coerced_to_role_field() -> None:
    """The {field, via} object form (a common agent shape) is normalised
    to the role.field token the parser accepts. Plain strings still
    pass through unchanged."""
    from semantic_catalog.compiler.request import from_mapping

    req = from_mapping({
        "model": "m",
        "metrics": ["x"],
        "dimensions": [
            "supplier.s_name",
            {"field": "p_brand", "via": "lineitem_to_part"},
            {"field": "alone"},
            {"name": "p_brand", "role": "lineitem_to_part"},
            {"field": "p_brand", "through": "lineitem_to_part"},
        ],
    })
    assert req.dimensions == [
        "supplier.s_name",
        "lineitem_to_part.p_brand",
        "alone",
        "lineitem_to_part.p_brand",
        "lineitem_to_part.p_brand",
    ]


def test_dimension_unsupported_dict_shape_raises_value_error() -> None:
    from semantic_catalog.compiler.request import from_mapping
    with pytest.raises(ValueError) as exc:
        from_mapping({
            "model": "m", "metrics": ["x"],
            "dimensions": [{"unknown": "shape"}],
        })
    assert "dimension" in str(exc.value).lower()


def test_metric_dict_form_is_coerced() -> None:
    from semantic_catalog.compiler.request import from_mapping
    req = from_mapping({
        "model": "m",
        "metrics": [{"field": "revenue"}],
        "dimensions": [],
    })
    assert req.metrics == ["revenue"]


# -------- transitive role tests ------------------------------------------

def _tpch_nation_region_catalog() -> tuple[InMemoryCatalog, dict]:
    """lineitem → orders → customer → nation → region
    customer→nation has role_name='customer_nation'.
    nation→region has no role (unambiguous).
    Tests: customer_nation.r_name should resolve via the transitive walk.
    """
    cat = InMemoryCatalog()
    mid = cat.add_model("tpch_orders")
    lineitem = cat.add_dataset(mid, "lineitem", database="tpch", table="lineitem")
    orders   = cat.add_dataset(mid, "orders",   database="tpch", table="orders")
    customer = cat.add_dataset(mid, "customer", database="tpch", table="customer")
    nation   = cat.add_dataset(mid, "nation",   database="tpch", table="nation")
    region   = cat.add_dataset(mid, "region",   database="tpch", table="region")

    l_orderkey  = cat.add_field(lineitem, "l_orderkey")
    l_extprice  = cat.add_field(lineitem, "l_extendedprice")
    o_orderkey  = cat.add_field(orders,   "o_orderkey")
    o_custkey   = cat.add_field(orders,   "o_custkey")
    c_custkey   = cat.add_field(customer, "c_custkey")
    c_nationkey = cat.add_field(customer, "c_nationkey")
    n_nationkey = cat.add_field(nation,   "n_nationkey")
    n_name      = cat.add_field(nation,   "n_name")
    n_regionkey = cat.add_field(nation,   "n_regionkey")
    r_regionkey = cat.add_field(region,   "r_regionkey")
    r_name      = cat.add_field(region,   "r_name")

    revenue = cat.add_metric(
        mid, "revenue",
        expression="SUM(lineitem.l_extendedprice)",
        primary_dataset_id=lineitem.dataset_id,
        field_refs=[l_extprice.field_id],
    )

    cat.add_relationship(mid, name="lineitem_to_orders",
        from_ds=lineitem, to_ds=orders, cardinality="MANY_TO_ONE",
        columns=[(l_orderkey, o_orderkey)])
    cat.add_relationship(mid, name="orders_to_customer",
        from_ds=orders, to_ds=customer, cardinality="MANY_TO_ONE",
        columns=[(o_custkey, c_custkey)])
    cat.add_relationship(mid, name="customer_to_nation",
        from_ds=customer, to_ds=nation, cardinality="MANY_TO_ONE",
        role_name="customer_nation",
        columns=[(c_nationkey, n_nationkey)])
    cat.add_relationship(mid, name="nation_to_region",
        from_ds=nation, to_ds=region, cardinality="MANY_TO_ONE",
        columns=[(n_regionkey, r_regionkey)])

    return cat, {
        "model_id": mid,
        "lineitem": lineitem, "nation": nation, "region": region,
        "revenue": revenue, "r_name": r_name, "n_name": n_name,
    }


def test_transitive_role_resolves_downstream_field() -> None:
    """customer_nation.r_name should resolve r_name on region via nation→region."""
    cat, ids = _tpch_nation_region_catalog()
    r = Resolver(cat)
    plan = r.resolve(QueryRequest(
        model="tpch_orders",
        metrics=["revenue"],
        dimensions=["customer_nation.r_name"],
    ))
    assert plan.unresolved == []
    assert len(plan.dimensions) == 1
    dim = plan.dimensions[0]
    assert dim.field.field_name == "r_name"
    assert dim.dataset_alias == "customer_nation_region"
    assert dim.role_edge_id is not None
    assert dim.column_alias == "customer_nation_r_name"


def test_transitive_role_direct_field_still_works() -> None:
    """customer_nation.n_name should still resolve directly on nation."""
    cat, _ = _tpch_nation_region_catalog()
    r = Resolver(cat)
    plan = r.resolve(QueryRequest(
        model="tpch_orders",
        metrics=["revenue"],
        dimensions=["customer_nation.n_name"],
    ))
    assert len(plan.dimensions) == 1
    assert plan.dimensions[0].field.field_name == "n_name"
    assert plan.dimensions[0].dataset_alias == "customer_nation"


def test_transitive_role_adds_intermediate_to_required() -> None:
    """nation must appear in the required set when customer_nation.r_name is used."""
    cat, _ = _tpch_nation_region_catalog()
    r = Resolver(cat)
    plan = r.resolve(QueryRequest(
        model="tpch_orders",
        metrics=["revenue"],
        dimensions=["customer_nation.r_name"],
    ))
    req_names = {ds.dataset_name for ds in plan.required_datasets}
    assert "nation" in req_names
    assert "region" in req_names


def test_transitive_role_unknown_field_raises() -> None:
    """A field that doesn't exist anywhere raises UnknownEntityError, not a transitive hit."""
    cat, _ = _tpch_nation_region_catalog()
    r = Resolver(cat)
    with pytest.raises(UnknownEntityError):
        r.resolve(QueryRequest(
            model="tpch_orders",
            metrics=["revenue"],
            dimensions=["customer_nation.no_such_field"],
        ))
