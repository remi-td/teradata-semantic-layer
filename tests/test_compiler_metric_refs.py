"""Phase 2 — metric-in-metric reference tests.

Covers the ${metric_name} placeholder syntax: resolver substitutes
referenced metrics' expressions recursively, wraps in parens for
precedence safety, detects cycles and cross-grain composition, and
respects the max-depth guard.
"""
from __future__ import annotations

import pytest

from semantic_catalog.api.models import QueryRequest
from semantic_catalog.compiler import (
    InMemoryCatalog,
    Resolver,
    UnknownEntityError,
    compile,
    render,
)
from semantic_catalog.compiler.errors import CompileError, CycleError


def _ratio_catalog() -> tuple[InMemoryCatalog, dict]:
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    d = cat.add_dataset(mid, "fact", database="db", table="fact")
    rev = cat.add_field(d, "revenue")
    cost = cat.add_field(d, "cost")
    rev_metric = cat.add_metric(
        mid, "revenue",
        expression="SUM(fact.revenue)",
        primary_dataset_id=d.dataset_id,
        field_refs=[rev.field_id],
    )
    cost_metric = cat.add_metric(
        mid, "cost",
        expression="SUM(fact.cost)",
        primary_dataset_id=d.dataset_id,
        field_refs=[cost.field_id],
    )
    profit_metric = cat.add_metric(
        mid, "profit",
        expression="${revenue} - ${cost}",
        primary_dataset_id=d.dataset_id,
    )
    margin_metric = cat.add_metric(
        mid, "margin",
        expression="${profit} / ${revenue}",
        primary_dataset_id=d.dataset_id,
    )
    return cat, {
        "model_id": mid, "fact": d,
        "revenue": rev_metric, "cost": cost_metric,
        "profit": profit_metric, "margin": margin_metric,
    }


def test_simple_metric_ref_substitutes_with_parens() -> None:
    cat, _ = _ratio_catalog()
    plan = Resolver(cat).resolve(QueryRequest(model="m", metrics=["profit"]))
    assert plan.metrics[0].expression == "(SUM(fact.revenue)) - (SUM(fact.cost))"


def test_nested_metric_refs_resolve_recursively() -> None:
    """margin = ${profit}/${revenue}, profit = ${revenue}-${cost}.
    The margin's profit ref must itself be expanded."""
    cat, _ = _ratio_catalog()
    plan = Resolver(cat).resolve(QueryRequest(model="m", metrics=["margin"]))
    expr = plan.metrics[0].expression
    assert expr == "((SUM(fact.revenue)) - (SUM(fact.cost))) / (SUM(fact.revenue))"


def test_self_cycle_detected() -> None:
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    d = cat.add_dataset(mid, "t", database="db", table="t")
    cat.add_field(d, "x")
    cat.add_metric(mid, "a", expression="${a} + 1", primary_dataset_id=d.dataset_id)
    with pytest.raises(CycleError) as exc:
        Resolver(cat).resolve(QueryRequest(model="m", metrics=["a"]))
    assert "a" in exc.value.chain


def test_mutual_cycle_detected() -> None:
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    d = cat.add_dataset(mid, "t", database="db", table="t")
    cat.add_field(d, "x")
    cat.add_metric(mid, "a", expression="${b} + 1", primary_dataset_id=d.dataset_id)
    cat.add_metric(mid, "b", expression="${a} + 1", primary_dataset_id=d.dataset_id)
    with pytest.raises(CycleError) as exc:
        Resolver(cat).resolve(QueryRequest(model="m", metrics=["a"]))
    # Chain must include both a and b
    assert set(exc.value.chain).issuperset({"a", "b"})


def test_unknown_metric_ref_raises() -> None:
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    d = cat.add_dataset(mid, "t", database="db", table="t")
    cat.add_field(d, "x")
    cat.add_metric(mid, "a", expression="${missing_metric} + 1",
                   primary_dataset_id=d.dataset_id)
    with pytest.raises(UnknownEntityError):
        Resolver(cat).resolve(QueryRequest(model="m", metrics=["a"]))


def test_deep_chain_within_limit_resolves() -> None:
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    d = cat.add_dataset(mid, "t", database="db", table="t")
    cat.add_field(d, "x")
    # Build a 5-deep chain: a5 -> a4 -> a3 -> a2 -> a1
    cat.add_metric(mid, "a1", expression="SUM(t.x)", primary_dataset_id=d.dataset_id)
    for i in range(2, 6):
        cat.add_metric(mid, f"a{i}", expression="${a" + str(i - 1) + "}",
                       primary_dataset_id=d.dataset_id)
    plan = Resolver(cat).resolve(QueryRequest(model="m", metrics=["a5"]))
    # Each hop wraps in parens
    assert plan.metrics[0].expression == "((((SUM(t.x)))))"


def test_depth_limit_enforced() -> None:
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    d = cat.add_dataset(mid, "t", database="db", table="t")
    cat.add_field(d, "x")
    cat.add_metric(mid, "a1", expression="SUM(t.x)", primary_dataset_id=d.dataset_id)
    # 15-deep chain — exceeds _MAX_METRIC_REF_DEPTH (8)
    for i in range(2, 16):
        cat.add_metric(mid, f"a{i}", expression="${a" + str(i - 1) + "}",
                       primary_dataset_id=d.dataset_id)
    with pytest.raises(CompileError) as exc:
        Resolver(cat).resolve(QueryRequest(model="m", metrics=["a15"]))
    assert "max depth" in str(exc.value).lower()


def test_cross_grain_composition_rejected() -> None:
    """A composed metric that references two metrics on different
    primary datasets is a chasm trap — reject at compile time."""
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    fact_a = cat.add_dataset(mid, "fa", database="db", table="fa")
    fact_b = cat.add_dataset(mid, "fb", database="db", table="fb")
    cat.add_field(fact_a, "x")
    cat.add_field(fact_b, "y")
    cat.add_metric(mid, "ma", expression="SUM(fa.x)",
                   primary_dataset_id=fact_a.dataset_id)
    cat.add_metric(mid, "mb", expression="SUM(fb.y)",
                   primary_dataset_id=fact_b.dataset_id)
    # Composed metric has NO declared primary_dataset_id — resolver
    # must unify from sub-refs and reject because they span grains.
    cat.add_metric(mid, "mix", expression="${ma} + ${mb}",
                   primary_dataset_id=None)
    with pytest.raises(CompileError) as exc:
        Resolver(cat).resolve(QueryRequest(model="m", metrics=["mix"]))
    assert "chasm" in str(exc.value).lower() or "grain" in str(exc.value).lower()


def test_compose_filtered_and_ref_together() -> None:
    """A ratio metric can reference two filtered metrics (same grain)."""
    cat = InMemoryCatalog()
    mid = cat.add_model("m")
    assess = cat.add_dataset(mid, "assessment", database="db", table="a")
    atype = cat.add_dataset(mid, "assessment_type", database="db", table="at")
    score = cat.add_field(assess, "score")
    aid = cat.add_field(assess, "assessment_id")
    atype_code = cat.add_field(atype, "type_code")
    a_type_code = cat.add_field(assess, "type_code")
    cat1 = cat.add_field(atype, "category_lvl1")
    cat.add_relationship(mid, name="a_to_type", from_ds=assess, to_ds=atype,
                         cardinality="MANY_TO_ONE",
                         columns=[(a_type_code, atype_code)])
    score_avg = cat.add_base_metric(
        mid, "score_avg", aggregate_fn="AVG",
        aggregate_arg="assessment.score",
        primary_dataset_id=assess.dataset_id,
        field_refs=[score.field_id],
    )
    assessment_count = cat.add_base_metric(
        mid, "assessment_count", aggregate_fn="COUNT",
        aggregate_arg="assessment.assessment_id",
        primary_dataset_id=assess.dataset_id,
        field_refs=[aid.field_id],
    )
    exam_avg = cat.add_filtered_metric(
        mid, "exam_score_avg", base=score_avg,
        filters=[(atype, cat1, "=", "'EX'")],
    )
    exam_count = cat.add_filtered_metric(
        mid, "exam_count", base=assessment_count,
        filters=[(atype, cat1, "=", "'EX'")],
    )
    # Ratio metric composing two filtered rollups.
    cat.add_metric(
        mid, "exam_avg_div_count",
        expression="${exam_score_avg} / ${exam_count}",
        primary_dataset_id=assess.dataset_id,
    )
    plan = compile(
        QueryRequest(model="m", metrics=["exam_avg_div_count"]),
        cat,
    )
    expr = plan.metrics[0].expression
    assert expr == (
        "(AVG(CASE WHEN assessment_type.category_lvl1 = 'EX' "
        "THEN assessment.score END)) "
        "/ (COUNT(CASE WHEN assessment_type.category_lvl1 = 'EX' "
        "THEN assessment.assessment_id END))"
    )
    # The filter dataset is auto-included
    names = [ds.dataset_name for ds in plan.required_datasets]
    assert "assessment_type" in names and "assessment" in names


def test_compile_then_render_metric_ref_emits_composed_sql() -> None:
    cat, _ = _ratio_catalog()
    plan = compile(
        QueryRequest(model="m", metrics=["margin"]),
        cat,
    )
    sql = render(plan, pretty=False)
    # Final SQL must contain the fully-substituted expression
    assert (
        "((SUM(fact.revenue)) - (SUM(fact.cost))) / (SUM(fact.revenue)) AS margin"
    ) in sql
