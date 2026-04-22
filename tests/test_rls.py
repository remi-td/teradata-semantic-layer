"""RLS (row-level-security) integration: CompileRequest.policy_fragments
injected by the API layer from SECURITY_POLICY.

Covers the compiler end of the hook and the InMemoryCatalog fake. The
HTTP-layer wiring (``X-Semantic-Groups`` header → catalog lookup →
``policy_fragments``) is exercised by test_api_fake via FakePool.
"""
from __future__ import annotations

from semantic_catalog.compiler import InMemoryCatalog, compile, render
from semantic_catalog.compiler.request import CompileRequest


def _cat() -> tuple[InMemoryCatalog, int]:
    cat = InMemoryCatalog()
    mid = cat.add_model("rls_demo")
    fact = cat.add_dataset(mid, "events", database="ops", table="events")
    amount = cat.add_field(fact, "amount")
    le = cat.add_field(fact, "CO_LE")
    cat.add_metric(
        mid, "amount_sum",
        expression="SUM(events.amount)",
        primary_dataset_id=fact.dataset_id,
        field_refs=[amount.field_id],
    )
    return cat, mid


def test_compile_without_policy_fragments_emits_unfiltered_sql():
    cat, _ = _cat()
    plan = compile(CompileRequest(model="rls_demo", metrics=["amount_sum"]), cat)
    sql = render(plan, pretty=False)
    assert "WHERE" not in sql.upper().split("GROUP BY")[0]  # no WHERE clause


def test_compile_with_single_policy_fragment_injects_where():
    cat, _ = _cat()
    req = CompileRequest(
        model="rls_demo",
        metrics=["amount_sum"],
        policy_fragments=["events.CO_LE IN ('100', '200')"],
    )
    plan = compile(req, cat)
    sql = render(plan, pretty=False)
    assert "events.CO_LE IN ('100', '200')" in sql


def test_compile_with_multiple_fragments_AND_joins_them():
    cat, _ = _cat()
    req = CompileRequest(
        model="rls_demo",
        metrics=["amount_sum"],
        policy_fragments=[
            "events.CO_LE IN ('100')",
            "events.region = 'US'",
        ],
    )
    plan = compile(req, cat)
    sql = render(plan, pretty=False)
    # Both fragments must appear; sqlglot AND-joins successive WHERE calls.
    assert "events.CO_LE IN ('100')" in sql
    assert "events.region = 'US'" in sql


def test_compile_with_user_where_plus_policy_fragment_emits_both():
    cat, _ = _cat()
    # Simulate the API-layer flow: user-supplied WHERE plus operator
    # policy. Both end up in the WHERE clause.
    from semantic_catalog.compiler.request import CompileFilter
    req = CompileRequest(
        model="rls_demo",
        metrics=["amount_sum"],
        where=[CompileFilter(field="events.amount", op=">", value=0, type="NUMBER")],
        policy_fragments=["events.CO_LE IN ('100', '200')"],
    )
    plan = compile(req, cat)
    sql = render(plan, pretty=False)
    assert "events.amount > 0" in sql
    assert "events.CO_LE IN ('100', '200')" in sql


def test_load_row_filters_matches_groups():
    cat, mid = _cat()
    cat.add_row_filter(mid, "events.CO_LE IN ('100')", group_name="branch_100")
    cat.add_row_filter(mid, "events.CO_LE IN ('200')", group_name="branch_200")
    cat.add_row_filter(mid, "events.is_deleted = 0")  # global (group_name=None)

    # No groups: only the global policy applies.
    assert cat.load_row_filters(mid, []) == ["events.is_deleted = 0"]

    # One group: global + that group's policy.
    assert set(cat.load_row_filters(mid, ["branch_100"])) == {
        "events.CO_LE IN ('100')",
        "events.is_deleted = 0",
    }

    # Multiple groups: union.
    assert set(cat.load_row_filters(mid, ["branch_100", "branch_200"])) == {
        "events.CO_LE IN ('100')",
        "events.CO_LE IN ('200')",
        "events.is_deleted = 0",
    }


def test_empty_fragment_strings_are_ignored():
    cat, _ = _cat()
    req = CompileRequest(
        model="rls_demo",
        metrics=["amount_sum"],
        policy_fragments=["", "   ", None],  # type: ignore[list-item]
    )
    plan = compile(req, cat)
    sql = render(plan, pretty=False)
    assert "WHERE" not in sql.upper().split("GROUP BY")[0]
