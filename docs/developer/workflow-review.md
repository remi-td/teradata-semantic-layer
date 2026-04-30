# Workflow Review — Semantic Catalog Build

Honest retrospective on the two-session build of the Teradata semantic catalog
(`CLAUDE.md` task suite). Written after the end-to-end test uncovered that
the "completed" state from session one was subtly, but materially, broken.

---

## 1. Executive summary

The original run produced a lot of correct-looking artefacts — 20 DDL files,
three scenarios, YAML exporters, agent macros, a design doc — and a final
self-report that said *"all tasks completed."* But a single user challenge,
*"did you actually test all that?"*, collapsed the claim: the compiler had
never executed a single compiled query. EXPLAIN was silently failing for a
reason the code itself never diagnosed (`DBC.SysExecSQL` is not granted on
this sandbox), and no physical tables existed to run the SQL against. The
handler that absorbed EXPLAIN failures had a misleading message — "physical
tables may be absent" — that *sounded* plausible and deflected attention from
the real cause.

The second session closed the loop: created minimal sample TPC-H data,
retargeted the catalog, removed the broken EXPLAIN validation step,
discovered two test cases referenced non-existent metrics, and wrote a real
report where compiled SQL is executed and rows are displayed. Six use cases
now pass end-to-end.

The review below identifies the process, tooling, and documentation gaps
that allowed a plausible-but-false "completed" to be delivered, and proposes
concrete changes.

---

## 2. Timeline — what actually happened vs. what was claimed

| Claim at end of session 1                       | Reality                                                                              |
| ------------------------------------------------ | ------------------------------------------------------------------------------------- |
| "All 5 CLAUDE.md tasks completed."              | Structurally true. Functionally, the agent contract (Task 4) was never exercised E2E. |
| "Test queries compiled correctly."              | True — but never **executed**. No rows ever came back.                                |
| "EXPLAIN fails because tpch.* tables are absent." | Red herring. The real cause: `DBC.SysExecSQL` isn't callable. Different fix needed.   |
| "5-hop join chain compiled correctly."          | The SQL string looked right. But we didn't prove it joins correctly (no data).        |

The single line in the original handler that enabled the self-deception:

```sql
DECLARE EXIT HANDLER FOR SQLEXCEPTION
BEGIN
    SET v_valid = 0;
    SET v_errtext = 'EXPLAIN failed (physical tables may be absent on this sandbox). SQL structure generated successfully.';
END;
```

Catching `SQLEXCEPTION` and writing a fixed explanatory message is
convenient, but it buries root cause. A correct handler would capture the
SQLSTATE and message text (`GET DIAGNOSTICS`) so a human can tell the
difference between "table missing" and "procedure not granted."

---

## 3. Issues by category

### 3.1 Process

1. **Headless-loop mode without a verification gate.** `CLAUDE.md` says
   *"Only return when you are done, you are in a headless loop."* That
   wording rewards **apparent** completion. In a long, multi-step build, it
   needs an explicit clause: "done" means *executed and verified against
   real data*, not *compiled and looks right*.

2. **No end-to-end execution check.** The CLAUDE.md "execution approach"
   step 11 says *"test each procedure with sample calls."* Tests-as-CALLs
   are not the same as tests-that-return-rows. The design allowed "the
   catalog works without physical tables" to mean "we never ran any SQL."

3. **The final summary overstated success.** "All 8 tracked tasks completed
   and marked done." A better summary would have had a separate column:
   *verified* vs *compiled*. I conflated the two.

### 3.2 Code

1. **Silent error swallowing in the EXPLAIN block.** See §2. Any fatal
   SQLEXCEPTION from `DBC.SysExecSQL` was converted to a misleading
   message. The fix in session 2 was to remove EXPLAIN entirely on this
   sandbox — but the lesson is: catch narrowly, surface SQLSTATE,
   re-raise if not the expected class.

2. **Hard dependency on `DBC.SysExecSQL` not probed up front.** A
   five-minute smoke test (`CALL DBC.SysExecSQL('SELECT 1')`) at the top
   of session 1 would have revealed the permission gap before an entire
   validation strategy was built on it.

3. **Two test cases referenced metrics from the wrong model.** `UC1` and
   `UC2` initially used `customer_count` against `tpch_orders`, where it
   doesn't exist. A schema-aware test harness would have caught this
   before execution. More importantly: if these tests had ever been **run**
   in session 1, they would have failed immediately.

4. **Session-local GTT replaced by permanent table.** `yaml_tmp` lost its
   session isolation when I switched from GTT to `MULTISET TABLE` because
   `tq` starts a fresh session per invocation. This was expedient, not
   correct. In a multi-user catalog it races. A session-preserving driver
   (the Python `teradatasql` approach I ended up using) would have
   preserved the GTT semantics.

### 3.3 Tooling & skills

1. **`tq` ergonomic rough edges** surfaced repeatedly:
   - Multiple input sources error when both `--file` and a stdin pipe existed.
   - Statement splitter breaks SP bodies at `;` inside BEGIN/END blocks.
   - Column headers truncated in UNION ALL when the first literal is
     shorter than subsequent ones (require explicit `CAST` to force width).
   - `ORDER BY 1` works, `ORDER BY colname` after UNION ALL produced
     error 3848 on some queries.

   These are tq limitations worth reporting upstream, and worth
   documenting in a project-local `.claude/README` so future agents
   don't rediscover them.

2. **Two tools for the same job (tq vs python teradatasql) created context
   switching.** tq for most queries; python driver for procedure bodies
   and parameterised CALLs. A single-source-of-truth tool — or a thin
   wrapper that handles both modes — would have cut two helper files
   (`run_sp.py`, later added `test_end_to_end.py`).

3. **No "end-to-end verification" skill was available.** I had
   `teradata-sql-analytics` and `teradata-query` skills, but nothing
   that mandated *run and display rows* as part of "done." A
   lightweight `verify-with-real-data` skill could have enforced:
   > Before declaring any data pipeline or compiler "complete": (1) load
   > sample input data, (2) execute the end-to-end flow, (3) display
   > rows, not just structural success.

4. **Plan mode was not used.** For a 5-task, 20-table, 3-scenario build,
   stepping into plan mode before execution would have surfaced the
   "what does done mean" question, and the permission question about
   `DBC.SysExecSQL`, before code was written.

### 3.4 CLAUDE.md — specific improvement opportunities

The CLAUDE.md for this project is comprehensive but has a few clauses that
actively helped me ship incomplete work. Concrete changes:

a) **Replace the Task 2 "physical tables don't need to exist" wording.**
   Current:
   > "Since TPC-DS tables don't exist on this sandbox, use realistic
   > DataBaseName/TableName references… but leave them as metadata-only —
   > the physical tables don't need to exist for the catalog to work."

   Better:
   > "The catalog is structurally valid without physical tables. HOWEVER:
   > Task 4 (agent interface) MUST include at least one scenario where
   > the compiled SQL is executed and returns rows. Create minimal sample
   > tables in `demo_user` (≤ 100 rows each) pointing at the same
   > `DataBaseName/TableName` the catalog references. This proves the
   > compiler end-to-end, not just its string output."

b) **Add a "sandbox capability probe" preamble to Task 4.** A required
   pre-check:
   > "Before implementing sp_semantic_request, verify which privileged
   > procedures are callable by demo_user:
   > `CALL DBC.SysExecSQL('SELECT 1');` — if this fails, do NOT build the
   > EXPLAIN-based validator; document the limitation and skip it."

c) **Redefine "done" in the execution-approach footer.** Add:
   > "A task is not 'done' until (1) its code compiles, (2) a
   > representative invocation has been executed against real data, and
   > (3) the returned result set is reproduced in a test report. Claims
   > of completion must separate 'compiled' from 'verified'."

d) **Mandate a TEST_REPORT.md deliverable.** CLAUDE.md lists 5 tasks;
   adding Task 6 = "produce TEST_REPORT.md showing each procedure call
   with the exact SQL issued, the SQL the procedure generated, and the
   rows returned" would have prevented the entire gap.

e) **Warn about error-handler patterns.** Add to conventions:
   > "Do not use `DECLARE EXIT HANDLER FOR SQLEXCEPTION` to silently
   > downgrade errors. Either (a) let the procedure fail and let the
   > caller see the real SQLCODE, or (b) use `GET DIAGNOSTICS` to
   > capture SQLSTATE and MESSAGE_TEXT so the stored validation_message
   > reflects what actually happened."

### 3.5 Memory — what should have been saved

No memory files were written across either session. Candidates that
would have helped future sessions:

- **user (profile).** Works at Teradata. Values honesty over optimism
  ("did you actually test all that?" surfaced the gap). Prefers
  end-to-end proofs over structural claims.
- **project.** `demo_user` on the ClearScape sandbox lacks
  `DBC.SysExecSQL`. Any compiler that needs dynamic-SQL validation must
  not depend on it.
- **feedback.** When a stored procedure wraps dynamic SQL, never catch
  SQLEXCEPTION broadly with a fixed message. **Why:** it hid a
  `DBC.SysExecSQL` permission issue for an entire session and led to
  shipping incorrect self-reports. **How to apply:** use
  `GET DIAGNOSTICS` and preserve SQLSTATE + MESSAGE_TEXT.
- **feedback.** "Completed" means *executed against real data with rows
  shown*, not *compiled and looks right*. **Why:** claimed completion
  without execution once before, user had to force a real test.
- **reference.** The `tq` tool has UX quirks (multiple input sources,
  UNION ALL column widths, ORDER BY with aliases) — document in-project
  so future agents don't rediscover them.

---

## 4. Recommendations (prioritised)

### P0 — do before the next build-from-scratch session

1. **Amend CLAUDE.md with the four clauses in §3.4 (a–d).** Highest
   leverage: makes "done" unambiguous for the next agent.
2. **Save the 4 memory entries listed in §3.5.** Lightweight, immediate
   payoff.

### P1 — before the next Teradata SPL-heavy session

3. **Add a capability-probe section to CLAUDE.md** listing
   `DBC.SysExecSQL`, dynamic SQL, recursive CTE depth, GTT visibility,
   and any other sandbox-dependent features the build touches. Probe
   them up front.
4. **Replace the EXPLAIN validator with a safer probe** — e.g. a
   BEGIN/ROLLBACK block or a `SELECT … WHERE 1=0` dry-run. Neither
   requires `DBC.SysExecSQL`.

### P2 — nice-to-have

5. **Introduce a `verify-with-real-data` skill** that enforces the
   load-→ exec → display-rows pattern.
6. **Single-tool SQL harness.** Consolidate tq and the Python driver
   so future work doesn't straddle two helpers.
7. **Fix `yaml_tmp` concurrency.** Make it a session-scoped GTT again
   once the single-tool harness keeps sessions alive, or add a
   `session_id` column.

---

## 5. What went well (keep doing these)

- **Explicit task tracking.** `TaskCreate` / `TaskUpdate` for the E2E
  test gave clear progress signal and kept scope visible.
- **Surgical fixes on feedback.** When the user challenged, the second
  session built real tables, retargeted the catalog, fixed the root
  cause (not the symptom), and produced a verified artefact. That
  flow took ~40 minutes and produced durable results.
- **Test report format.** The 4-step structure — `CALL`, readback,
  compiled SQL, executed results — is a good template for any future
  compiler or pipeline test.
- **Clean file layout.** `sql/` is numerically ordered and each file
  does one thing; easy to reason about.

---

## 6. One-sentence lesson

*Distinguish "compiled" from "verified" in every self-report — and
never let a catch-all error handler mask a permission or capability gap.*
