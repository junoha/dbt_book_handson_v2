"""第 3 章ハンズオン (Athena 準備) のセットアップスクリプト。

ハンズオンのセットアップは次の 3 ステップに分かれており、本スクリプトは
最後のステップ (AWS 側の準備とデータのロード) を担当する。

1. `uv sync` で Python 仮想環境を構築する
2. `uv run jafgen` でソースの raw データ (CSV) を生成する
3. 本スクリプトを実行する
   - CloudFormation スタック `dbt-book-ch3-athena` により S3 バケットと
     Athena ワークグループを作成
   - 生成済みの CSV を S3 にアップロードし、Athena (Glue) のテーブルを作成
   - 取得した S3 バケット名を `.env` に書き出し、環境変数 `S3_BUCKET_ATHENA` の設定方法を表示

ステップ 2 の `uv run jafgen` を先に実行し、`jaffle-data/` に CSV が生成されて
いる必要がある (未生成の場合はその旨を表示して終了する)。

実行方法 (chapter3 ディレクトリ直下から)::

    uv run python utils/setup.py
"""

from __future__ import annotations

import os
import subprocess
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
    print_env_export_hint,
    print_step,
    red,
    update_env_file,
)

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

ATHENA_STACK_NAME = "dbt-book-ch3-athena"

CH3_DIR = _UTILS_DIR.parent
CFN_DIR = CH3_DIR / "cloudformation"
ATHENA_TEMPLATE = CFN_DIR / "athena.yml"
ENV_FILE = CH3_DIR / ".env"

# `uv run jafgen` が生成する raw データ (CSV) の配置先と、load_raw_data.py が
# 読み込む CSV ファイル群。ステップ 2 を実行済みかの確認に使う。
JAFFLE_DATA_DIR = CH3_DIR / "jaffle-data"
REQUIRED_CSVS = (
    "raw_customers.csv",
    "raw_orders.csv",
    "raw_items.csv",
    "raw_products.csv",
)


# ---------------------------------------------------------------------------
# 個別ステップ
# ---------------------------------------------------------------------------


def _run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> None:
    """サブプロセスを実行する。失敗時は CalledProcessError が伝播する。"""
    print(f"  $ {' '.join(cmd)}")
    subprocess.run(cmd, cwd=str(cwd), check=True, env=env)


def ensure_raw_data_generated() -> None:
    """`uv run jafgen` による raw データが生成済みかを確認する。

    未生成の場合は、実行すべきコマンドを案内して終了する。
    """
    missing = [
        name for name in REQUIRED_CSVS if not (JAFFLE_DATA_DIR / name).is_file()
    ]
    if missing:
        print(
            red(
                "raw データ (CSV) が見つかりません: "
                f"{', '.join(missing)}"
            )
        )
        print(
            "先に `uv run jafgen` を実行して、ソースの raw データを生成してください。"
        )
        raise SystemExit(1)


def deploy_athena_stack() -> str:
    """Athena 用スタックをデプロイし、S3 バケット名を返す。"""
    print_step("S3 バケットと Athena ワークグループの作成")
    cfn = make_client("cloudformation")
    deploy_stack(cfn, ATHENA_STACK_NAME, ATHENA_TEMPLATE)
    outputs = get_stack_outputs(cfn, ATHENA_STACK_NAME)
    bucket = outputs.get("S3BucketAthena")
    if not bucket:
        raise RuntimeError(
            f"スタック {ATHENA_STACK_NAME} の Outputs に S3BucketAthena が見つかりません"
        )
    return bucket


def load_raw_data(bucket: str) -> None:
    """CSV を S3 にアップロードし Athena のテーブルを作成する。

    `load_raw_data.py` は環境変数 `S3_BUCKET_ATHENA` を参照するため、
    サブプロセスの環境に値を渡して実行する。
    """
    print_step("raw データのアップロードとテーブル作成")
    env = dict(os.environ)
    env["S3_BUCKET_ATHENA"] = bucket
    _run(["uv", "run", "python", "utils/load_raw_data.py"], cwd=CH3_DIR, env=env)


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------


def main() -> int:
    ensure_default_region()

    ensure_raw_data_generated()

    bucket = deploy_athena_stack()
    load_raw_data(bucket)

    # dbt の profiles.yml が参照する S3 バケット名を .env に保存する。
    update_env_file(ENV_FILE, {"S3_BUCKET_ATHENA": bucket})

    print_step("セットアップ完了")
    print_env_export_hint("S3_BUCKET_ATHENA", bucket)
    return 0


if __name__ == "__main__":
    sys.exit(main())
