"""CLI entrypoint.

Commands::

    semantic-catalog serve [--host HOST] [--port PORT] [--reload]
    semantic-catalog ping
    semantic-catalog install [--force] [--with-sample [NAME]]
    semantic-catalog uninstall
    semantic-catalog install-example <name>
    semantic-catalog uninstall-example <name>
    semantic-catalog import <file> [--model NAME] [--dry-run]
    semantic-catalog export <model> [--output FILE]
    semantic-catalog deploy [--sql-dir DIR] [--include FILENAME...]   # low-level escape hatch
"""
from __future__ import annotations

import argparse
import logging
import os
import re
import sys
from pathlib import Path

from .config import load_settings


def _render_sql(text: str, catalog_db: str) -> str:
    """Substitute the placeholder schema 'demo_user' with the active catalog DB.

    All SQL files use 'demo_user' as the schema placeholder so they remain
    readable standalone. At install time we swap it for whatever database the
    caller configured (via DATABASE_URI). Word-boundary replace, so any
    user data that coincidentally contains the substring 'demo_user' is
    left alone.
    """
    if catalog_db == "demo_user":
        return text
    return re.sub(r"\bdemo_user\b", catalog_db, text)


def _cmd_serve(args: argparse.Namespace) -> int:
    import uvicorn

    # Ensure configuration is loadable before we launch uvicorn, so errors
    # surface immediately with a friendly message.
    try:
        settings = load_settings()
    except Exception as e:  # noqa: BLE001
        print(f"[error] could not load settings: {e}", file=sys.stderr)
        return 2

    host = args.host or settings.bind_host
    port = args.port or settings.bind_port
    print(f"semantic-catalog serving at http://{host}:{port}  (db={settings.host})")
    uvicorn.run(
        "semantic_catalog.server:app",
        host=host,
        port=port,
        reload=args.reload,
        log_level=args.log_level,
    )
    return 0


def _cmd_ping(args: argparse.Namespace) -> int:
    from .db import get_pool
    try:
        settings = load_settings()
        with get_pool().cursor() as cur:
            cur.execute("SELECT CURRENT_TIMESTAMP, USER")
            row = cur.fetchone()
        print(f"connected to {settings.host} as {row[1]} @ {row[0]}")
        return 0
    except Exception as e:  # noqa: BLE001
        print(f"ping failed: {e}", file=sys.stderr)
        return 1


def _cmd_deploy(args: argparse.Namespace) -> int:
    """Execute .sql files against the database, in file-name order.

    The catalog ships its DDL/DML as *.sql files — each file is submitted
    as one statement (so it can contain a CREATE PROCEDURE body). For
    multi-statement files we rely on each statement ending with ``;`` on
    its own line with a blank line separator.
    """
    import teradatasql
    settings = load_settings()
    sql_dir = Path(args.sql_dir or _default_sql_dir()).resolve()
    if not sql_dir.is_dir():
        print(f"[error] sql directory not found: {sql_dir}", file=sys.stderr)
        return 2
    files = sorted(p for p in sql_dir.glob("*.sql") if p.is_file())
    if args.include:
        wanted = set(args.include)
        files = [f for f in files if f.name in wanted or f.stem in wanted]
    if not files:
        print(f"[info] no .sql files to run in {sql_dir}")
        return 0

    conn = teradatasql.connect(**settings.driver_kwargs())
    cur = conn.cursor()
    failures = 0
    for f in files:
        print(f"=> {f.name}")
        try:
            text = _render_sql(f.read_text(), settings.catalog_db)
            _submit_sql_file(cur, text, mode=args.mode)
            print(f"   ok")
        except Exception as e:  # noqa: BLE001
            failures += 1
            print(f"   FAILED: {e}", file=sys.stderr)
            if args.stop_on_error:
                break
    cur.close()
    conn.close()
    if failures:
        print(f"[done] {failures} failures", file=sys.stderr)
        return 1
    print("[done] deployment complete")
    return 0


def _submit_sql_file(cur, text: str, *, mode: str) -> None:
    """Feed a .sql file to the Teradata driver.

    ``mode``:
      - ``whole``:            submit the file as a single statement (for CREATE PROCEDURE).
      - ``split``:            split on blank lines + trailing ``;`` (plain DDL/DML).
      - ``split-tolerant``:   same as split, but logs and continues on per-statement errors.
    """
    text = text.lstrip()
    if mode == "whole":
        # The teradatasql driver decides whether to treat the request as a
        # single statement or a multi-statement batch by inspecting the
        # leading keyword. Leading comments/blank lines prevent it from
        # recognising CREATE/REPLACE PROCEDURE bodies — strip them so the
        # driver sees the DDL as the first token.
        lines = text.splitlines()
        while lines and (not lines[0].strip() or lines[0].lstrip().startswith("--")):
            lines.pop(0)
        cur.execute("\n".join(lines).rstrip())
        return
    # Split by lines ending with ';' followed by a blank line OR end-of-file.
    stmts = []
    buf: list[str] = []
    for line in text.splitlines():
        if line.strip().startswith("--"):
            continue
        buf.append(line)
        if line.rstrip().endswith(";"):
            stmts.append("\n".join(buf).strip())
            buf = []
    if buf:
        remainder = "\n".join(buf).strip()
        if remainder:
            stmts.append(remainder)
    for s in stmts:
        s2 = s.rstrip(";").strip()
        if not s2:
            continue
        try:
            cur.execute(s2)
        except Exception as e:  # noqa: BLE001
            if mode == "split-tolerant":
                # Common idempotent case: 3807 'object does not exist' on DROP.
                print(f"   [warn] {str(e).splitlines()[0][:200]}", file=sys.stderr)
                continue
            raise


def _default_sql_dir() -> str:
    # Prefer the bundled SQL, fall back to repo-level sql/ when dev-installed.
    pkg_sql = Path(__file__).parent / "sql_bundle"
    if pkg_sql.is_dir() and any(pkg_sql.glob("*.sql")):
        return str(pkg_sql)
    # Running from source tree.
    repo_sql = Path(__file__).parent.parent.parent / "sql"
    return str(repo_sql)


def _examples_dir() -> Path:
    """Locate the examples directory.

    Prefer the package-bundled ``examples_bundle/`` (shipped in the wheel,
    currently containing only ``tpch_orders``). Fall back to the repo-root
    ``examples/`` when running from a source checkout — that has the full
    set of demos (school_gradebook, exec_dashboard, tpch_*).
    """
    bundled = Path(__file__).parent / "examples_bundle"
    if bundled.is_dir() and any(bundled.iterdir()):
        return bundled
    repo_root = Path(__file__).parent.parent.parent
    return repo_root / "examples"


def _catalog_already_installed(cur, db: str) -> bool:
    """Return True if the semantic catalog is already deployed in ``db``.

    Uses ``SEMANTIC_MODEL`` as the sentinel — it's the root catalog table
    and is present in every successful install. dbc.TablesV stores the
    database name in mixed case (``DataBaseName``) but compares
    case-insensitively in Teradata, so an upper-cased lookup is fine.
    """
    try:
        cur.execute(
            "SELECT 1 FROM dbc.TablesV "
            "WHERE DataBaseName = ? AND TableName = 'SEMANTIC_MODEL'",
            (db,),
        )
        return cur.fetchone() is not None
    except Exception:  # noqa: BLE001
        # If the user lacks SELECT on dbc.TablesV (rare), fall back to a
        # direct probe — a SELECT against the table itself either succeeds
        # or fails with 3807 "object does not exist".
        try:
            cur.execute(f"SELECT 1 FROM {db}.SEMANTIC_MODEL WHERE 1=0")
            return True
        except Exception:  # noqa: BLE001
            return False


# Files shipped in sql/ (and sql_bundle/) — the core product. Order matters.
# 'split'           = multi-statement DDL.
# 'whole'           = single procedure/macro body (semicolons inside the body).
# 'split-tolerant'  = multi-statement DDL, swallow per-statement errors (for
#                     GTT re-creation: Teradata refuses DROP TABLE on a GTT
#                     that any session has materialised, so we treat an
#                     already-existing GTT as idempotent).
# Install sequence. Post-v0.4 cleanup: the SQL compiler
# (``33_sp_semantic_request``) and SQL importer (``60_sp_semantic_import``)
# are superseded by the pure-Python compiler/importer in
# ``semantic_catalog.compiler`` / ``semantic_catalog.importer`` and are no
# longer deployed. The search + describe macros stay because the GUI and
# agents call them directly.
_CORE_SEQUENCE: list[tuple[str, str]] = [
    ("split", "01_ddl_enums"),
    ("split", "02_ddl_core"),
    ("split", "03_ddl_relationships"),
    ("split", "04_ddl_metrics"),
    ("split", "05_ddl_views"),
    ("split", "05a_ddl_hierarchies"),
    ("split", "06_ddl_metadata"),
    ("split", "07_comments"),
    ("split", "08_collect_stats"),
    ("split", "09_seed_enums"),
    ("whole", "30_sp_semantic_search"),
    ("whole", "31_sp_semantic_describe"),
]


def _run_file(
    cur, sql_dir: Path, stem: str, *, mode: str, catalog_db: str,
    tolerate_errors: bool = False,
) -> int:
    """Execute a single .sql file. Returns the number of failures (0 or 1)."""
    path = sql_dir / f"{stem}.sql"
    if not path.is_file():
        path = sql_dir / stem  # allow callers to pass the full filename
    if not path.is_file():
        print(f"   FAILED: file not found: {stem}", file=sys.stderr)
        return 1
    print(f"=> {path.name} ({mode})")
    try:
        text = _render_sql(path.read_text(), catalog_db)
        _submit_sql_file_tolerant(cur, text, mode=mode, tolerate_errors=tolerate_errors)
        print("   ok")
        return 0
    except Exception as e:  # noqa: BLE001
        print(f"   FAILED: {e}", file=sys.stderr)
        return 1


def _submit_sql_file_tolerant(cur, text: str, *, mode: str, tolerate_errors: bool) -> None:
    """Like _submit_sql_file but optionally swallows per-statement errors.

    Used for DROP scripts where 'object does not exist' (Teradata error 3807)
    is the expected idempotent outcome.
    """
    if not tolerate_errors:
        _submit_sql_file(cur, text, mode=mode)
        return
    # In tolerant mode we always want per-statement submission so that one
    # failure doesn't abort the rest.
    _submit_sql_file(cur, text, mode="split-tolerant")


def _detect_mode(text: str) -> str:
    """Decide 'whole' vs 'split' by inspecting the first non-comment line."""
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        up = s.upper()
        if up.startswith(("REPLACE PROCEDURE", "CREATE PROCEDURE",
                          "REPLACE MACRO", "CREATE MACRO")):
            return "whole"
        return "split"
    return "split"


def _cmd_install(args: argparse.Namespace) -> int:
    """Deploy the core catalog (DDL + macros + idempotent schema extensions).

    With ``--with-sample NAME`` (or the alias ``--with-sample`` without a
    name, which defaults to ``tpch_orders`` — the only example bundled in
    the wheel), also deploys the matching example after the core catalog
    lands so the GUI isn't empty on first run.
    """
    import teradatasql
    from .config import load_settings
    settings = load_settings()
    sql_dir = Path(_default_sql_dir()).resolve()
    if not sql_dir.is_dir():
        print(f"[error] sql directory not found: {sql_dir}", file=sys.stderr)
        return 2

    conn = teradatasql.connect(**settings.driver_kwargs())
    cur = conn.cursor()
    failures = 0

    # `--fresh` was the original flag name; keep it as a deprecated alias.
    force = bool(getattr(args, "force", False) or getattr(args, "fresh", False))
    if getattr(args, "fresh", False) and not getattr(args, "force", False):
        print("[install] --fresh is deprecated, use --force", file=sys.stderr)

    already = _catalog_already_installed(cur, settings.catalog_db)
    if already and not force:
        print(
            f"[error] Semantic layer already installed in database "
            f"'{settings.catalog_db}'.\n"
            f"        If you really want to reinstall, use --force — "
            f"THIS WILL DROP ALL YOUR DATA.",
            file=sys.stderr,
        )
        cur.close()
        conn.close()
        return 1

    if force and already:
        print("[install] --force: dropping existing catalog objects first")
        failures += _run_file(cur, sql_dir, "00_drop_all", mode="split",
                              catalog_db=settings.catalog_db, tolerate_errors=True)
    elif force:
        # `--force` on a clean DB is a no-op for the drop step; still print
        # for transparency so users know the flag was honored.
        print("[install] --force: no existing catalog detected, fresh install")

    for mode, stem in _CORE_SEQUENCE:
        failures += _run_file(cur, sql_dir, stem, mode=mode,
                              catalog_db=settings.catalog_db)
        if failures and args.stop_on_error:
            break

    sample = getattr(args, "with_sample", None)
    sample_deployed = False
    if sample and not failures:
        ex_dir = _examples_dir() / sample
        if not ex_dir.is_dir():
            print(f"[install] --with-sample {sample}: example not found at "
                  f"{ex_dir} — skipping", file=sys.stderr)
        else:
            print(f"[install] --with-sample: deploying example '{sample}'")
            files = sorted(p for p in ex_dir.glob("*.sql")
                           if p.is_file() and p.name != "teardown.sql")
            sample_failed = False
            for f in files:
                text = _render_sql(f.read_text(), settings.catalog_db)
                mode = _detect_mode(text)
                print(f"=> {sample}/{f.name} ({mode})")
                try:
                    _submit_sql_file(cur, text, mode=mode)
                    print("   ok")
                except Exception as e:  # noqa: BLE001
                    failures += 1
                    sample_failed = True
                    print(f"   FAILED: {e}", file=sys.stderr)
                    if args.stop_on_error:
                        break
            sample_deployed = not sample_failed

    cur.close()
    conn.close()
    if failures:
        print(f"[install] {failures} failure(s)", file=sys.stderr)
        return 1
    print("[install] core catalog deployed"
          + (f" (+ sample: {sample})" if sample_deployed else ""))
    return 0


def _cmd_uninstall(args: argparse.Namespace) -> int:
    """Drop every core catalog object."""
    import teradatasql
    from .config import load_settings
    settings = load_settings()
    sql_dir = Path(_default_sql_dir()).resolve()
    conn = teradatasql.connect(**settings.driver_kwargs())
    cur = conn.cursor()
    failures = _run_file(cur, sql_dir, "00_drop_all", mode="split",
                         catalog_db=settings.catalog_db, tolerate_errors=True)
    cur.close()
    conn.close()
    if failures:
        print("[uninstall] completed with non-fatal errors", file=sys.stderr)
    else:
        print("[uninstall] core catalog removed")
    return 0


def _cmd_install_example(args: argparse.Namespace) -> int:
    """Deploy every .sql file under examples/<name>/ in filename order."""
    import teradatasql
    from .config import load_settings
    settings = load_settings()
    ex_dir = _examples_dir() / args.name
    if not ex_dir.is_dir():
        print(f"[error] unknown example: {args.name} (looked in {ex_dir})", file=sys.stderr)
        return 2
    files = sorted(p for p in ex_dir.glob("*.sql")
                   if p.is_file() and p.name != "teardown.sql")
    if not files:
        print(f"[info] no installable .sql files in {ex_dir}")
        return 0

    conn = teradatasql.connect(**settings.driver_kwargs())
    cur = conn.cursor()
    failures = 0
    for f in files:
        text = _render_sql(f.read_text(), settings.catalog_db)
        mode = _detect_mode(text)
        print(f"=> {args.name}/{f.name} ({mode})")
        try:
            _submit_sql_file(cur, text, mode=mode)
            print("   ok")
        except Exception as e:  # noqa: BLE001
            failures += 1
            print(f"   FAILED: {e}", file=sys.stderr)
            if args.stop_on_error:
                break
    cur.close()
    conn.close()
    if failures:
        print(f"[install-example] {failures} failure(s)", file=sys.stderr)
        return 1
    print(f"[install-example] {args.name} installed")
    return 0


def _cmd_import(args: argparse.Namespace) -> int:
    """Load a YAML/JSON model document into the catalog (one transaction).

    Mirrors the ``POST /api/import`` endpoint but runs without spinning up
    the FastAPI server — the lite deployment's authoring path.
    """
    import yaml as _yaml
    import teradatasql
    from .config import load_settings
    from .importer import import_entity, ordered_items, synthesize_filtered_expressions

    settings = load_settings()
    path = Path(args.file).resolve()
    if not path.is_file():
        print(f"[error] file not found: {path}", file=sys.stderr)
        return 2
    try:
        doc = _yaml.safe_load(path.read_text()) or {}
    except _yaml.YAMLError as e:
        print(f"[error] could not parse YAML/JSON: {e}", file=sys.stderr)
        return 2
    try:
        items = ordered_items(doc)
    except ValueError as e:
        print(f"[error] {e}", file=sys.stderr)
        return 2
    if not items:
        print("[info] empty payload — nothing to do")
        return 0

    model_name = args.model
    if not model_name:
        models = doc.get("models") or []
        if models and isinstance(models[0], dict) and models[0].get("name"):
            model_name = models[0]["name"]
    if not model_name:
        print("[error] could not infer model name; pass --model NAME or include "
              "a 'models:' block in the document", file=sys.stderr)
        return 2

    db = settings.catalog_db
    conn = teradatasql.connect(**settings.driver_kwargs())
    try:
        try:
            conn.autocommit = False
        except Exception:
            pass
        cur = conn.cursor()
        ok = err = 0
        for idx, (kind, payload) in enumerate(items, start=1):
            try:
                status, message, _ = import_entity(cur, db, model_name, kind, payload)
            except Exception as e:  # noqa: BLE001
                status, message = "ERROR", f"crash: {e}"
            tag = "OK " if status == "OK" else "ERR"
            print(f"  [{idx:>3}] {tag} {kind:<16} {message}")
            if status == "OK":
                ok += 1
            else:
                err += 1
        if err == 0 and not args.dry_run:
            synth_n = synthesize_filtered_expressions(cur, db, model_name)
            if synth_n:
                print(f"  [synth] denormalized {synth_n} filtered metric expression(s)")
            conn.commit()
            print(f"[import] committed {ok}/{ok} entities into model '{model_name}'")
            return 0
        conn.rollback()
        if args.dry_run:
            print(f"[import] --dry-run: rolled back ({ok} ok, {err} errors)")
        else:
            print(f"[import] {err} error(s); rolled back transaction", file=sys.stderr)
        return 0 if (args.dry_run and err == 0) else 1
    finally:
        try:
            cur.close()
        except Exception:
            pass
        try:
            conn.close()
        except Exception:
            pass


def _cmd_export(args: argparse.Namespace) -> int:
    """Render a semantic model as OSI 0.1.x YAML.

    Reads the model with the same Python exporter the FastAPI server
    uses (``/api/export/osi``) — single source of truth, no SP needed.
    The lite (server-less) deployment uses this CLI as its OSI export
    path.
    """
    import teradatasql
    from .config import load_settings
    from .exporter import export_osi_yaml

    settings = load_settings()
    conn = teradatasql.connect(**settings.driver_kwargs())
    try:
        cur = conn.cursor()
        try:
            text = export_osi_yaml(cur, settings.catalog_db, args.model)
        finally:
            try:
                cur.close()
            except Exception:
                pass
    finally:
        try:
            conn.close()
        except Exception:
            pass

    if text is None:
        print(f"[error] unknown model: {args.model}", file=sys.stderr)
        return 2
    if args.output:
        Path(args.output).write_text(text)
        print(f"[export] wrote {len(text):,} chars to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


def _cmd_uninstall_example(args: argparse.Namespace) -> int:
    """Run examples/<name>/teardown.sql."""
    import teradatasql
    from .config import load_settings
    settings = load_settings()
    ex_dir = _examples_dir() / args.name
    teardown = ex_dir / "teardown.sql"
    if not teardown.is_file():
        print(f"[error] no teardown for example: {args.name}", file=sys.stderr)
        return 2
    conn = teradatasql.connect(**settings.driver_kwargs())
    cur = conn.cursor()
    print(f"=> {args.name}/teardown.sql")
    failures = 0
    try:
        text = _render_sql(teardown.read_text(), settings.catalog_db)
        _submit_sql_file_tolerant(cur, text, mode="split", tolerate_errors=True)
        print("   ok")
    except Exception as e:  # noqa: BLE001
        failures = 1
        print(f"   FAILED: {e}", file=sys.stderr)
    cur.close()
    conn.close()
    return failures


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="semantic-catalog",
        description="Teradata semantic catalog GUI and tooling",
    )
    p.add_argument("--log-level", default=os.environ.get("SC_LOG_LEVEL", "info"))
    sub = p.add_subparsers(dest="command", required=True)

    sp_serve = sub.add_parser("serve", help="Start the web GUI server")
    sp_serve.add_argument("--host")
    sp_serve.add_argument("--port", type=int)
    sp_serve.add_argument("--reload", action="store_true",
                          help="Auto-reload on source changes (dev only)")
    sp_serve.set_defaults(func=_cmd_serve)

    sp_ping = sub.add_parser("ping", help="Verify database connectivity")
    sp_ping.set_defaults(func=_cmd_ping)

    sp_install = sub.add_parser(
        "install",
        help="Deploy the core catalog (DDL + stored procedures)",
    )
    sp_install.add_argument(
        "--force", action="store_true",
        help=(
            "Reinstall on top of an existing catalog. DROPS every catalog "
            "table in the target database first — destroys all model "
            "definitions, metrics, relationships, AI context, etc. Use "
            "with care."
        ),
    )
    # Deprecated alias kept so existing scripts keep working; emits a
    # warning at runtime (see _cmd_install).
    sp_install.add_argument("--fresh", action="store_true", help=argparse.SUPPRESS)
    sp_install.add_argument(
        "--with-sample",
        nargs="?",
        const="tpch_orders",
        default=None,
        dest="with_sample",
        metavar="NAME",
        help=(
            "Deploy a bundled example after the core catalog "
            "(default: tpch_orders — the only example shipped in the wheel). "
            "Source-tree installs can pass other names "
            "(school_gradebook, exec_dashboard, tpch_osi, tpch_physical, "
            "school_physical)."
        ),
    )
    sp_install.add_argument("--stop-on-error", action="store_true")
    sp_install.set_defaults(func=_cmd_install)

    sp_uninstall = sub.add_parser(
        "uninstall", help="Drop every core catalog object",
    )
    sp_uninstall.set_defaults(func=_cmd_uninstall)

    sp_install_ex = sub.add_parser(
        "install-example",
        help="Install a bundled demo scenario from examples/<name>/",
    )
    sp_install_ex.add_argument("name", help="Example directory name")
    sp_install_ex.add_argument("--stop-on-error", action="store_true")
    sp_install_ex.set_defaults(func=_cmd_install_example)

    sp_uninstall_ex = sub.add_parser(
        "uninstall-example",
        help="Run examples/<name>/teardown.sql",
    )
    sp_uninstall_ex.add_argument("name")
    sp_uninstall_ex.set_defaults(func=_cmd_uninstall_example)

    sp_import = sub.add_parser(
        "import",
        help="Load a YAML/JSON model document into the catalog (one transaction)",
    )
    sp_import.add_argument("file", help="Path to a YAML or JSON model document")
    sp_import.add_argument(
        "--model",
        help="Target model name. If omitted, taken from the first entry of "
             "the document's models: block.",
    )
    sp_import.add_argument(
        "--dry-run", action="store_true",
        help="Validate and report per-entity status, then roll back unconditionally",
    )
    sp_import.set_defaults(func=_cmd_import)

    sp_export = sub.add_parser(
        "export",
        help="Render a semantic model as OSI 0.1.x YAML (stdout by default)",
    )
    sp_export.add_argument("model", help="Semantic model name to export")
    sp_export.add_argument(
        "-o", "--output",
        help="Write YAML to this file instead of stdout",
    )
    sp_export.set_defaults(func=_cmd_export)

    # Low-level escape hatch for ad-hoc file deploys (previously the primary
    # install mechanism). Kept for scripts and tests; not the recommended UX.
    sp_deploy = sub.add_parser("deploy", help="[advanced] Deploy arbitrary .sql files")
    sp_deploy.add_argument("--sql-dir", help="Override the SQL directory")
    sp_deploy.add_argument(
        "--mode", default="split", choices=["split", "whole"],
        help="'split' for plain DDL/DML, 'whole' for stored-procedure bodies",
    )
    sp_deploy.add_argument("--include", nargs="+",
                           help="Run only these files (by name or stem)")
    sp_deploy.add_argument("--stop-on-error", action="store_true")
    sp_deploy.set_defaults(func=_cmd_deploy)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=args.log_level.upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
