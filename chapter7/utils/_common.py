"""第 7 章 ハンズオン用ユーティリティの共通モジュール。

依存関係: 標準ライブラリ + boto3 のみ。
"""

from __future__ import annotations

import os
import shutil
import sys
import time
from pathlib import Path
from typing import Any

import boto3
from botocore.client import BaseClient
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# パス
# ---------------------------------------------------------------------------

HANDSON_DIR = Path(__file__).resolve().parent.parent
STEPS_DIR = HANDSON_DIR / "steps"
DBT_ATHENA_PROJECT = HANDSON_DIR / "dbt-athena-project"
DBT_GLUE_PROJECT = HANDSON_DIR / "dbt-glue-project"
MODELS_STAGING = DBT_ATHENA_PROJECT / "models" / "staging"
MODELS_MARTS = DBT_ATHENA_PROJECT / "models" / "marts"

# ---------------------------------------------------------------------------
# 色付き出力
# ---------------------------------------------------------------------------

if os.name == "nt":
    os.system("")

_USE_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def _c(code: str, msg: str) -> str:
    return f"\033[{code}m{msg}\033[0m" if _USE_COLOR else msg


def green(msg: str) -> str:
    return _c("0;32", msg)


def red(msg: str) -> str:
    return _c("0;31", msg)


def print_step(msg: str) -> None:
    print(f"\n=== {msg} ===")


# ---------------------------------------------------------------------------
# 環境変数
# ---------------------------------------------------------------------------


def require_env(*keys: str) -> dict[str, str]:
    """必要な環境変数が設定されていることを確認し、値を返す。"""
    values = {}
    missing = []
    for key in keys:
        val = os.environ.get(key)
        if not val:
            missing.append(key)
        else:
            values[key] = val
    if missing:
        print(red(f"Error: 以下の環境変数が設定されていません: {', '.join(missing)}"))
        sys.exit(1)
    return values


# ---------------------------------------------------------------------------
# AWS クライアント
# ---------------------------------------------------------------------------


def make_client(service: str) -> BaseClient:
    region = os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-1")
    return boto3.client(service, region_name=region)


# ---------------------------------------------------------------------------
# Athena クエリ実行
# ---------------------------------------------------------------------------


def run_athena_query(
    query: str,
    workgroup: str,
    database: str = "jaffle_shop_iceberg",
    wait: bool = True,
) -> str:
    """Athena クエリを実行し、QueryExecutionId を返す。wait=True なら完了まで待機。"""
    athena = make_client("athena")
    resp = athena.start_query_execution(
        QueryString=query,
        WorkGroup=workgroup,
        QueryExecutionContext={"Database": database},
    )
    qid = resp["QueryExecutionId"]

    if not wait:
        return qid

    while True:
        status_resp = athena.get_query_execution(QueryExecutionId=qid)
        state = status_resp["QueryExecution"]["Status"]["State"]
        if state == "SUCCEEDED":
            return qid
        if state in ("FAILED", "CANCELLED"):
            reason = status_resp["QueryExecution"]["Status"].get("StateChangeReason", "")
            raise RuntimeError(f"Query {qid} {state}: {reason}")
        time.sleep(1)


def get_query_results(qid: str) -> list[list[str]]:
    """クエリ結果を2次元リストで返す（ヘッダ行含む）。"""
    athena = make_client("athena")
    rows = []
    paginator = athena.get_paginator("get_query_results")
    for page in paginator.paginate(QueryExecutionId=qid):
        for row in page["ResultSet"]["Rows"]:
            rows.append([col.get("VarCharValue", "") for col in row["Data"]])
    return rows


def get_query_stats(qid: str) -> dict[str, Any]:
    """DataScannedInBytes, EngineExecutionTimeInMillis を返す。"""
    athena = make_client("athena")
    resp = athena.get_query_execution(QueryExecutionId=qid)
    stats = resp["QueryExecution"]["Statistics"]
    return {
        "DataScannedInBytes": stats.get("DataScannedInBytes", 0),
        "EngineExecutionTimeInMillis": stats.get("EngineExecutionTimeInMillis", 0),
    }


def run_ddl(query: str, workgroup: str) -> None:
    """DDL文を実行して完了を待つ。"""
    run_athena_query(query, workgroup)


# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------


def s3_upload_file(local_path: Path, bucket: str, key: str) -> None:
    s3 = make_client("s3")
    s3.upload_file(str(local_path), bucket, key)


def s3_rm_prefix(bucket: str, prefix: str) -> None:
    """S3バケットの指定プレフィックス配下を全削除する。バージョニング有効バケットにも対応。"""
    s3 = make_client("s3")

    # 現行オブジェクトを削除
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        contents = page.get("Contents", [])
        if not contents:
            continue
        objects = [{"Key": o["Key"]} for o in contents]
        s3.delete_objects(Bucket=bucket, Delete={"Objects": objects, "Quiet": True})

    # バージョニング有効バケットの場合、古いバージョンと削除マーカーも削除
    versions_paginator = s3.get_paginator("list_object_versions")
    for page in versions_paginator.paginate(Bucket=bucket, Prefix=prefix):
        targets = []
        for v in page.get("Versions") or []:
            targets.append({"Key": v["Key"], "VersionId": v["VersionId"]})
        for m in page.get("DeleteMarkers") or []:
            targets.append({"Key": m["Key"], "VersionId": m["VersionId"]})
        if targets:
            # delete_objects は1リクエスト最大1000件
            for i in range(0, len(targets), 1000):
                chunk = targets[i:i+1000]
                s3.delete_objects(Bucket=bucket, Delete={"Objects": chunk, "Quiet": True})


# ---------------------------------------------------------------------------
# モデルファイルの更新
# ---------------------------------------------------------------------------


def copy_model_files(step_dir: Path, targets: dict[str, Path]) -> None:
    """step_dir内のファイルをtargetsで指定された場所にコピーする。

    targets: {ファイル名: コピー先パス} の辞書
    """
    for filename, dest in targets.items():
        src = step_dir / filename
        if not src.exists():
            print(red(f"  Warning: {src} が見つかりません"))
            continue
        shutil.copy2(src, dest)
        print(f"  {filename} -> {dest.relative_to(HANDSON_DIR)}")
