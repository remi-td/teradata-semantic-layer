"""Join resolver — BFS from anchor to required datasets, plus bridging.

Ports the algorithm from ``sp_semantic_request`` section 8. Two nested
loops:

  expansion  drain any required dataset that is adjacent to the current
             plan. Role-played aliases are constrained to the specific
             relationship whose ``role_name`` matches the alias.

  bridging   when expansion stalls but required datasets remain, add one
             intermediate dataset that is frontier-adjacent and
             itself adjacent to an out-of-plan required. Loop at most
             ``MAX_BRIDGE_ITERATIONS`` times.

The resolver renders each step's SQL fragment (FROM <src> for step 0,
``INNER JOIN <src> ON <cond>`` for later steps) so the plan becomes
self-contained for the renderer.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List, Optional, Set, Tuple

from .catalog import CatalogDAO, RelationshipRow
from .errors import UnresolvedJoinError
from .logical import DatasetRef, JoinStep, LogicalPlan


MAX_BRIDGE_ITERATIONS = 10


# --------------------------------------------------------------- helpers

def _source_sql(ds: DatasetRef) -> str:
    """Render the FROM-clause source for a dataset: physical, cube, or
    catalog-only. Alias is appended by the caller-step."""
    if ds.source_query and not ds.database_name:
        return f"({ds.source_query}) AS {ds.alias}"
    if ds.database_name and ds.table_name:
        return f"{ds.database_name.strip()}.{ds.table_name.strip()} AS {ds.alias}"
    return f"{ds.dataset_name} AS {ds.alias}"


def _build_role_map(relationships: List[RelationshipRow]) -> Dict[str, int]:
    """alias ↔ role_name.  When a required dataset's alias appears here,
    the BFS must reach it through the referenced relationship."""
    return {r.role_name: r.relationship_id for r in relationships if r.role_name}


# --------------------------------------------------------------- resolver

@dataclass
class _PlanNode:
    dataset: DatasetRef
    in_plan: bool = False
    role_edge_id: Optional[int] = None    # which relationship must be used to enter
    entry_from_alias: Optional[str] = None  # which in-plan alias must be the source


class JoinResolver:
    """One instance per compile. Not thread-safe; don't share across requests."""

    def __init__(self, catalog: CatalogDAO, model_id: int):
        self.catalog = catalog
        self.model_id = model_id
        self.relationships = catalog.load_relationships(model_id)
        self.role_map = _build_role_map(self.relationships)

        self._edges_by_from: Dict[int, List[RelationshipRow]] = defaultdict(list)
        self._edges_by_to: Dict[int, List[RelationshipRow]] = defaultdict(list)
        for r in self.relationships:
            self._edges_by_from[r.from_dataset_id].append(r)
            self._edges_by_to[r.to_dataset_id].append(r)

    # -------- public -----------

    def resolve(self, plan: LogicalPlan) -> None:
        """Populate ``plan.join_steps`` and ``plan.unresolved`` in place."""
        nodes = self._build_nodes(plan)
        anchor_key = self._anchor_key(plan, nodes)
        nodes[anchor_key].in_plan = True

        join_steps: List[JoinStep] = [
            JoinStep(step_ordinal=0, relationship_id=None, from_dataset_id=None,
                     to_dataset_id=plan.anchor.dataset_id,
                     join_sql=f"FROM {_source_sql(plan.anchor)}")
        ]

        next_step = 1
        for _iter in range(MAX_BRIDGE_ITERATIONS + 1):
            next_step = self._drain_expansion(nodes, join_steps, next_step)
            unresolved = [k for k, n in nodes.items() if not n.in_plan]
            if not unresolved:
                break
            if not self._add_bridge(nodes, plan):
                break

        plan.join_steps = join_steps
        plan.unresolved = [f"{n.dataset.dataset_name} AS {n.dataset.alias}"
                           if n.dataset.alias != n.dataset.dataset_name
                           else n.dataset.dataset_name
                           for n in nodes.values() if not n.in_plan]

    # -------- internals ---------

    def _build_nodes(self, plan: LogicalPlan) -> Dict[Tuple[int, str], _PlanNode]:
        nodes: Dict[Tuple[int, str], _PlanNode] = {}
        for ds in plan.required_datasets:
            key = (ds.dataset_id, ds.alias)
            # Prefer explicit constraints stored on DatasetRef (set by the resolver
            # for transitively-reached datasets).  Fall back to role_map for
            # directly role-played aliases (e.g. customer_nation).
            role_rel_id = ds.role_edge_id if ds.role_edge_id is not None \
                else self.role_map.get(ds.alias)
            nodes[key] = _PlanNode(
                dataset=ds,
                role_edge_id=role_rel_id,
                entry_from_alias=ds.entry_from_alias,
            )
        # Ensure anchor is present
        anchor_key = (plan.anchor.dataset_id, plan.anchor.alias)
        if anchor_key not in nodes:
            nodes[anchor_key] = _PlanNode(dataset=plan.anchor)
        return nodes

    def _anchor_key(self, plan: LogicalPlan,
                    nodes: Dict[Tuple[int, str], _PlanNode]) -> Tuple[int, str]:
        return (plan.anchor.dataset_id, plan.anchor.alias)

    def _drain_expansion(self, nodes: Dict[Tuple[int, str], _PlanNode],
                         join_steps: List[JoinStep], next_step: int) -> int:
        """Keep pulling out-of-plan nodes in until no adjacent edge remains."""
        progress = True
        while progress:
            progress = False
            cand = self._pick_candidate(nodes)
            if cand is None:
                break
            (in_key, out_key, rel, reverse) = cand
            in_node = nodes[in_key]
            out_node = nodes[out_key]
            join_sql = self._render_join(in_node, out_node, rel, reverse=reverse)
            join_steps.append(JoinStep(
                step_ordinal=next_step,
                relationship_id=rel.relationship_id,
                from_dataset_id=in_node.dataset.dataset_id,
                to_dataset_id=out_node.dataset.dataset_id,
                join_sql=join_sql,
            ))
            out_node.in_plan = True
            next_step += 1
            progress = True
        return next_step

    def _pick_candidate(self, nodes: Dict[Tuple[int, str], _PlanNode]):
        """Find the next best edge to expand.

        Ordering: prefer MANY_TO_ONE forward edges (fact → dim); then
        MANY_TO_ONE reverse; then other forward; then other reverse.
        Deterministic tiebreaker on (candidate dataset_id, relationship_id).
        """
        in_plan = {k: n for k, n in nodes.items() if n.in_plan}
        out_plan = {k: n for k, n in nodes.items() if not n.in_plan}

        best_tuple: Optional[Tuple[int, int, int]] = None  # (pref, out_ds_id, rel_id)
        best_edge: Optional[Tuple[Tuple[int, str], Tuple[int, str],
                                  RelationshipRow, bool]] = None

        def _pref(r: RelationshipRow, reverse: bool) -> int:
            if r.cardinality == "MANY_TO_ONE" and not reverse:
                return 0
            if r.cardinality == "MANY_TO_ONE" and reverse:
                return 1
            if not reverse:
                return 2
            return 3

        def _consider(in_key, out_key, r: RelationshipRow, reverse: bool) -> None:
            nonlocal best_tuple, best_edge
            score = (_pref(r, reverse), nodes[out_key].dataset.dataset_id, r.relationship_id)
            if best_tuple is None or score < best_tuple:
                best_tuple = score
                best_edge = (in_key, out_key, r, reverse)

        for in_key, in_node in in_plan.items():
            for r in self._edges_by_from[in_node.dataset.dataset_id]:
                for out_key, out_node in out_plan.items():
                    if out_node.dataset.dataset_id != r.to_dataset_id:
                        continue
                    if not self._edge_allowed(r, in_node, out_node, reverse=False):
                        continue
                    _consider(in_key, out_key, r, False)

            for r in self._edges_by_to[in_node.dataset.dataset_id]:
                for out_key, out_node in out_plan.items():
                    if out_node.dataset.dataset_id != r.from_dataset_id:
                        continue
                    if not self._edge_allowed(r, in_node, out_node, reverse=True):
                        continue
                    _consider(in_key, out_key, r, True)

        return best_edge

    def _edge_allowed(self, r: RelationshipRow,
                      in_node: _PlanNode, out_node: _PlanNode,
                      *, reverse: bool) -> bool:
        """Role-constraint checks for the edge entering *out_node*.

        1. *out_node* pin: if the node being joined to is pinned to a specific
           relationship, the edge must match.
        2. *out_node* source: if the node being joined to requires a specific
           source alias (set for transitive datasets like ``supplier_nation_region``),
           the in-plan node's alias must match.
        3. *in_node* reverse guard: a role-pinned node must not be traversed
           BACKWARDS via a different relationship — that would route through the
           wrong role (e.g. reaching ``customer`` from ``supplier_nation`` by
           reversing ``customer_to_nation``).  Forward expansion is unrestricted.
        """
        if out_node.role_edge_id is not None and out_node.role_edge_id != r.relationship_id:
            return False
        if (out_node.entry_from_alias is not None
                and in_node.dataset.alias != out_node.entry_from_alias):
            return False
        if (reverse
                and in_node.role_edge_id is not None
                and in_node.role_edge_id != r.relationship_id):
            return False
        return True

    def _render_join(self, in_node: _PlanNode, out_node: _PlanNode,
                     rel: RelationshipRow, *, reverse: bool) -> str:
        cols = self.catalog.load_rel_columns(rel.relationship_id)
        preds: List[str] = []
        for col in sorted(cols, key=lambda c: c.column_position):
            if not reverse:
                # forward: in-plan = FROM side, candidate = TO side
                preds.append(f"{in_node.dataset.alias}.{col.from_field_name} = "
                             f"{out_node.dataset.alias}.{col.to_field_name}")
            else:
                # reverse: candidate = FROM side, in-plan = TO side
                preds.append(f"{out_node.dataset.alias}.{col.from_field_name} = "
                             f"{in_node.dataset.alias}.{col.to_field_name}")
        on_sql = " AND ".join(preds)
        return f"INNER JOIN {_source_sql(out_node.dataset)} ON {on_sql}"

    def _add_bridge(self, nodes: Dict[Tuple[int, str], _PlanNode],
                    plan: LogicalPlan) -> bool:
        """Insert one frontier-adjacent intermediate dataset into the plan.

        Returns True when progress was made (a bridge was added),
        False when no candidate exists.
        """
        in_plan_ids = {n.dataset.dataset_id for n in nodes.values() if n.in_plan}
        out_plan_ids = {n.dataset.dataset_id for n in nodes.values() if not n.in_plan}
        if not out_plan_ids:
            return False

        # Candidate = any dataset in the model NOT already in `nodes`,
        # adjacent to an in-plan node AND adjacent to ≥1 out-of-plan node.
        present_keys = set(nodes.keys())

        adj: Dict[int, Set[int]] = defaultdict(set)
        for r in self.relationships:
            adj[r.from_dataset_id].add(r.to_dataset_id)
            adj[r.to_dataset_id].add(r.from_dataset_id)

        best_bridge: Optional[int] = None
        best_out_count = -1
        for ds in self.catalog.load_datasets(self.model_id):
            if ds.dataset_id in {k[0] for k in present_keys}:
                continue
            nbrs = adj.get(ds.dataset_id, set())
            if not (nbrs & in_plan_ids):
                continue
            # Matches sp_semantic_request: bridges can step toward the
            # out-of-plan frontier even when they are not directly
            # adjacent to any out-of-plan required. Prefer those that
            # *are* adjacent (higher out_count); fall back to any
            # frontier-adjacent dataset so multi-hop chains resolve in
            # multiple outer iterations.
            out_count = len(nbrs & out_plan_ids)
            if out_count > best_out_count or (out_count == best_out_count
                                              and (best_bridge is None
                                                   or ds.dataset_id < best_bridge)):
                best_bridge = ds.dataset_id
                best_out_count = out_count

        if best_bridge is None:
            return False

        bridge_ds = self.catalog.load_dataset(best_bridge)
        if bridge_ds is None:
            return False
        # Use alias = dataset_name for bridges (never role-played).
        copy = DatasetRef(
            dataset_id=bridge_ds.dataset_id, dataset_name=bridge_ds.dataset_name,
            database_name=bridge_ds.database_name, table_name=bridge_ds.table_name,
            source_query=bridge_ds.source_query, alias=bridge_ds.dataset_name,
        )
        nodes[(copy.dataset_id, copy.alias)] = _PlanNode(dataset=copy)
        plan.required_datasets.append(copy)
        return True
