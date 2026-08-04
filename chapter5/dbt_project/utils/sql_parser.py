"""
SQLファイルからFROM句のテーブルを抽出するスクリプト

dbt の Exposure を Lightdash ダッシュボード定義から自動生成するための補助ツールです。
SQL パーサーとして `sqlglot` (https://github.com/tobymao/sqlglot) を利用し、
CTE やサブクエリを除外して物理テーブル (ref / source 対象) のみを抽出します。
sqlglot は Python 製のマルチ方言 SQL パーサーで、パースした AST からテーブル名や
CTE、サブクエリなどを構造的に識別できるため、正規表現による抽出より堅牢です。

使い方:
    python sql_parser.py <sql_file_path>

例:
    python sql_parser.py ../target/compiled/zakkamall_data_quality/models/marts/dim_customers.sql
"""

import argparse
import sys
from pathlib import Path

import sqlglot
from sqlglot import exp


def extract_physical_tables(sql: str, verbose: bool = False) -> list[str]:
    """
    SQL 文から FROM 句のテーブルを抽出する

    Args:
        sql: 解析対象のSQL文
        verbose: デバッグ情報を出力するか

    Returns:
        物理テーブル名のリスト（CTE、サブクエリを除外）
    """
    parsed = sqlglot.parse_one(sql)

    # 除外対象は DerivedTable でも可
    # https://sqlglot.com/sqlglot/expressions.html#DerivedTable
    cte_names = {cte.alias_or_name for cte in parsed.find_all(exp.CTE)}
    subquery_aliases = {sq.alias for sq in parsed.find_all(exp.Subquery) if sq.alias}

    if verbose:
        print(f"CTE names: {cte_names}", file=sys.stderr)
        print(f"Subquery aliases: {subquery_aliases}", file=sys.stderr)

    # 全テーブルから CTE とサブクエリを除外
    tables = []
    for table in parsed.find_all(exp.Table):
        if table.name not in cte_names and table.name not in subquery_aliases:
            # 完全修飾名を取得（database.schema.tableの形式）
            full_name = table.sql(dialect="postgres")
            tables.append(full_name)

    return tables


def main() -> None:
    """メイン処理"""
    parser = argparse.ArgumentParser(
        description="SQLファイルからFROM句のテーブルを抽出する",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
例:
  %(prog)s models/marts/customer_order_summary.sql
  %(prog)s ../models/quality/metadata_ecosystem_dashboard.sql --verbose
        """,
    )
    parser.add_argument(
        "sql_file", type=Path, help="解析対象のSQLファイルパス"
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="デバッグ情報を出力する",
    )

    args = parser.parse_args()

    if not args.sql_file.exists():
        print(f"エラー: ファイルが見つかりません: {args.sql_file}", file=sys.stderr)
        sys.exit(1)

    try:
        sql_content = args.sql_file.read_text(encoding="utf-8")
    except Exception as e:
        print(f"エラー: ファイル読み込みに失敗しました: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        tables = extract_physical_tables(sql_content, verbose=args.verbose)
    except Exception as e:
        print(f"エラー: SQL解析に失敗しました: {e}", file=sys.stderr)
        sys.exit(1)

    if args.verbose:
        print(f"\n参照テーブル数: {len(tables)}", file=sys.stderr)
        print("=" * 50, file=sys.stderr)

    for table in tables:
        print(table)


if __name__ == "__main__":
    main()