"""第 6 章ハンズオンの MWAA 環境セットアップスクリプト。

前提: 先に ``uv sync --frozen`` と ``uv run jafgen`` を実行し、
``jaffle-data/`` 配下に raw データ (CSV) を生成しておくこと。

実行方法 (ch6 ディレクトリ直下から)::

    uv run python utils/setup.py

以下を順に実行する::

    1. S3 バケットと Athena WorkGroup の作成 (CloudFormation)
    2. jafgen 生成物を dags/jafgen_data/ に配置
    3. mwaa/ を MWAA 用 S3 バケットにアップロード
    4. MWAA 環境の作成 (CloudFormation)
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

# このスクリプトを直接実行した場合でも `_common` を import できるよう、
# utils/ ディレクトリを sys.path に追加する。
_UTILS_DIR = Path(__file__).resolve().parent
if str(_UTILS_DIR) not in sys.path:
    sys.path.insert(0, str(_UTILS_DIR))

from _common import (  # noqa: E402
    deploy_stack,
    ensure_default_region,
    get_stack_outputs,
    make_client,
    print_step,
    s3_sync,
)

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

STACK_NAME = "dbt-book-ch6"
MWAA_STACK_NAME = "dbt-book-ch6-mwaa"

# jafgen の生成物 7 つのうち、MWAA の DAG が利用する 4 つだけを mwaa/dags/ にコピーする。
JAFGEN_TABLES_FOR_DAGS = (
    "raw_customers",
    "raw_orders",
    "raw_items",
    "raw_products",
)

# aws s3 sync ... --exclude と同じパターン。
S3_SYNC_EXCLUDES = (
    "*/target/*",
    "*/dbt_packages/*",
    "*/logs/*",
    "*/edr_target/*",
    "*/.user.yml",
)

CH6_DIR = _UTILS_DIR.parent
CFN_DIR = CH6_DIR / "cloudformation"
S3_TEMPLATE = CFN_DIR / "s3.yml"
MWAA_TEMPLATE = CFN_DIR / "mwaa.yml"
JAFFLE_DATA_DIR = CH6_DIR / "jaffle-data"
DAGS_JAFGEN_DIR = CH6_DIR / "mwaa" / "dags" / "jafgen_data"
MWAA_LOCAL_DIR = CH6_DIR / "mwaa"


# ---------------------------------------------------------------------------
# 個別ステップ
# ---------------------------------------------------------------------------


def check_jafgen_output() -> None:
    """jafgen の生成物が揃っているか確認する。

    ローカル準備 (``uv sync`` / ``uv run jafgen``) は README の手順で
    事前に実行する想定のため、AWS リソースを作成する前にここで検証する。
    """
    print_step("jafgen 生成物の確認")
    missing = [
        f"{table}.csv"
        for table in JAFGEN_TABLES_FOR_DAGS
        if not (JAFFLE_DATA_DIR / f"{table}.csv").is_file()
    ]
    if missing:
        raise SystemExit(
            f"jaffle-data/ に {', '.join(missing)} が見つかりません。\n"
            "先に `uv run jafgen` を実行して raw データを生成してください。"
        )
    print(f"  {JAFFLE_DATA_DIR} に必要な CSV が揃っています")


def deploy_s3_stack() -> str:
    """S3 / Athena 用スタックをデプロイし、MWAA 用バケット名を返す。"""
    print_step("S3 バケットと Athena WorkGroup の作成")
    cfn = make_client("cloudformation")
    deploy_stack(cfn, STACK_NAME, S3_TEMPLATE)
    outputs = get_stack_outputs(cfn, STACK_NAME)
    bucket = outputs.get("S3BucketMWAA")
    if not bucket:
        raise RuntimeError(f"スタック {STACK_NAME} の Outputs に S3BucketMWAA が見つかりません")
    return bucket


def copy_jafgen_to_dags() -> None:
    print_step("jafgen 生成物を dags/jafgen_data/ に配置")
    DAGS_JAFGEN_DIR.mkdir(parents=True, exist_ok=True)
    for table in JAFGEN_TABLES_FOR_DAGS:
        src = JAFFLE_DATA_DIR / f"{table}.csv"
        dst = DAGS_JAFGEN_DIR / f"{table}.csv"
        shutil.copy2(src, dst)
    print(f"  {len(JAFGEN_TABLES_FOR_DAGS)} 個の CSV を {DAGS_JAFGEN_DIR} にコピーしました")


def upload_mwaa_files(bucket: str) -> None:
    print_step("MWAA 用ファイルのアップロード")
    s3 = make_client("s3")
    s3_sync(s3, MWAA_LOCAL_DIR, bucket, exclude=S3_SYNC_EXCLUDES)


def deploy_mwaa_stack() -> None:
    print_step("MWAA 環境の作成")
    cfn = make_client("cloudformation")
    deploy_stack(
        cfn,
        MWAA_STACK_NAME,
        MWAA_TEMPLATE,
        parameters={"S3StackName": STACK_NAME},
        capabilities=["CAPABILITY_NAMED_IAM"],
    )


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------


def main() -> int:
    ensure_default_region()

    check_jafgen_output()
    bucket = deploy_s3_stack()
    copy_jafgen_to_dags()
    upload_mwaa_files(bucket)
    deploy_mwaa_stack()

    print_step("セットアップ完了")
    return 0


if __name__ == "__main__":
    sys.exit(main())
