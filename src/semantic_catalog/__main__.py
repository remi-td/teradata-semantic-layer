"""CLI entrypoint.

Commands::

    semantic-catalog serve [--host HOST] [--port PORT] [--reload]
    semantic-catalog ping
    semantic-catalog install [--fresh]
    semantic-catalog uninstall
    semantic-catalog install-example <name>
    semantic-catalog uninstall-example <name>
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
            text = f.read_text()
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
    """Locate the repo-root examples/ directory.

    Only shipped when installed from source; not bundled with the pip package
    because examples are demo data, not part of the product.
    """
    repo_root = Path(__file__).parent.parent.parent
    return repo_root / "examples"


# Files shipped in sql/ (and sql_bundle/) — the core product. Order matters.
# 'split'           = multi-statement DDL.
# 'whole'           = single procedure/macro body (semicolons inside the body).
# 'split-tolerant'  = multi-statement DDL, swallow per-statement errors (for
#                     GTT re-creation: Teradata refuses DROP TABLE on a GTT
#                     that any session has materialised, so we treat an
#                     already-existing GTT as idempotent).
_CORE_SEQUENCE: list[tuple[str, str]] = [
    ("split", "01_ddl_enums"),
    ("split", "02_ddl_core"),
    ("split", "03_ddl_relationships"),
    ("split", "04_ddl_metrics"),
    ("split", "05_ddl_views"),
    ("split", "06_ddl_metadata"),
    ("split", "07_comments"),
    ("split", "08_collect_stats"),
    ("split", "09_seed_enums"),
    ("split-tolerant", "19_gtt_yaml_tmp"),
    ("whole", "20_export_osi"),
    ("whole", "30_sp_semantic_search"),
    ("whole", "31_sp_semantic_describe"),
    ("split-tolerant", "32_request_staging"),
    ("whole", "33_sp_semantic_request"),
    ("whole", "60_sp_semantic_import"),
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
    """Deploy the core catalog (DDL + SPs + idempotent schema extensions)."""
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

    if args.fresh:
        print("[install] --fresh: dropping existing catalog objects first")
        failures += _run_file(cur, sql_dir, "00_drop_all", mode="split",
                              catalog_db=settings.catalog_db, tolerate_errors=True)

    for mode, stem in _CORE_SEQUENCE:
        failures += _run_file(cur, sql_dir, stem, mode=mode,
                              catalog_db=settings.catalog_db)
        if failures and args.stop_on_error:
            break

    cur.close()
    conn.close()
    if failures:
        print(f"[install] {failures} failure(s)", file=sys.stderr)
        return 1
    print("[install] core catalog deployed")
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
        "--fresh", action="store_true",
        help="Run 00_drop_all.sql first so install starts from a clean slate",
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
