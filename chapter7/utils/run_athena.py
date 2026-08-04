"""Athena クエリ実行ヘルパー。

Usage:
    uv run python utils/run_athena.py "SELECT ..." [--stats]
"""

import sys

from _common import get_query_results, get_query_stats, require_env, run_athena_query

def main() -> None:
    env = require_env("ATHENA_WORKGROUP")

    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} \"QUERY\" [--stats]", file=sys.stderr)
        sys.exit(1)

    query = sys.argv[1]
    want_stats = "--stats" in sys.argv[2:]

    qid = run_athena_query(query, workgroup=env["ATHENA_WORKGROUP"])

    if want_stats:
        stats = get_query_stats(qid)
        print(f"{stats['DataScannedInBytes']}\t{stats['EngineExecutionTimeInMillis']}")

    rows = get_query_results(qid)
    # ヘッダ行を # コメントで出力
    if rows:
        print("# " + "\t".join(rows[0]))
        for row in rows[1:]:
            print("\t".join(row))


if __name__ == "__main__":
    main()
