"""第 2 章 ハンズオン用ユーティリティの共通モジュール。

load_raw_data.py / delete_resources.py から利用する。

依存関係: 標準ライブラリ + boto3 のみ。
"""

from __future__ import annotations

import os
import sys
import time
from collections.abc import Iterable, Sequence

import boto3
from botocore.client import BaseClient
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# 色付き出力
# ---------------------------------------------------------------------------

# Windows 10 1511+ の cmd.exe / PowerShell で ANSI エスケープシーケンスを
# 有効化する慣用句。os.system("") を 1 回呼ぶと VT 処理が有効化される。
if os.name == "nt":  # pragma: no cover - Windows のみ
    os.system("")

# TTY ではない (パイプ/リダイレクト) または NO_COLOR が設定されていれば無色化。
_USE_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def _c(code: str, msg: str) -> str:
    return f"\033[{code}m{msg}\033[0m" if _USE_COLOR else msg


def red(msg: str) -> str:
    return _c("0;31", msg)


def green(msg: str) -> str:
    return _c("0;32", msg)


def yellow(msg: str) -> str:
    return _c("1;33", msg)


def print_step(msg: str) -> None:
    """ステップ見出しを `=== ... ===` 形式で出力する。"""
    print(f"=== {msg} ===")


# ---------------------------------------------------------------------------
# AWS クライアント
# ---------------------------------------------------------------------------


def ensure_default_region(default: str = "ap-northeast-1") -> str:
    """AWS_DEFAULT_REGION が未設定なら `default` を設定し、現在値を返す。"""
    os.environ.setdefault("AWS_DEFAULT_REGION", default)
    return os.environ["AWS_DEFAULT_REGION"]


def make_client(service: str, region: str | None = None) -> BaseClient:
    """boto3 クライアントを生成する。region を明示しない場合は既定リージョンを使う。"""
    return boto3.client(service, region_name=region or os.environ.get("AWS_DEFAULT_REGION"))


# ---------------------------------------------------------------------------
# CloudFormation
# ---------------------------------------------------------------------------


def stack_exists(cfn: BaseClient, stack_name: str) -> bool:
    try:
        cfn.describe_stacks(StackName=stack_name)
        return True
    except ClientError as e:
        msg = str(e)
        if "does not exist" in msg or "ValidationError" in e.response.get("Error", {}).get("Code", ""):
            return False
        raise


def get_stack_status(cfn: BaseClient, stack_name: str) -> str | None:
    try:
        resp = cfn.describe_stacks(StackName=stack_name)
        return resp["Stacks"][0]["StackStatus"]
    except ClientError as e:
        if "does not exist" in str(e):
            return None
        raise


def get_stack_outputs(cfn: BaseClient, stack_name: str) -> dict[str, str]:
    """指定スタックの Outputs を {OutputKey: OutputValue} の dict で返す。"""
    resp = cfn.describe_stacks(StackName=stack_name)
    outputs = resp["Stacks"][0].get("Outputs", []) or []
    return {o["OutputKey"]: o["OutputValue"] for o in outputs}


def delete_stack(cfn: BaseClient, stack_name: str) -> None:
    """スタック削除を非同期で開始する (完了は待機しない)。"""
    cfn.delete_stack(StackName=stack_name)


def wait_stack_delete(cfn: BaseClient, stack_name: str, timeout_seconds: int = 600) -> None:
    """スタックが完全に消えるまでポーリングで待機する。

    boto3 標準の `stack_delete_complete` waiter ではなくポーリング方式にしているのは、
    途中ステータスを進捗ログとして表示するため。
    """
    elapsed = 0
    print(f"スタック {stack_name} の削除を待機中...")

    while stack_exists(cfn, stack_name):
        if elapsed >= timeout_seconds:
            print(red(f"スタック {stack_name} の削除がタイムアウトしました ({timeout_seconds} 秒)"))
            raise SystemExit(1)

        status = get_stack_status(cfn, stack_name) or "DELETE_COMPLETE"

        if status == "DELETE_FAILED":
            print(red(f"スタック {stack_name} の削除に失敗しました"))
            raise SystemExit(1)

        print(f"  ステータス: {status}")
        time.sleep(10)
        elapsed += 10

    print(green(f"スタック {stack_name} が正常に削除されました"))


# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------


def bucket_exists(s3: BaseClient, bucket: str) -> bool:
    try:
        s3.head_bucket(Bucket=bucket)
        return True
    except ClientError:
        return False


def empty_s3_bucket(s3: BaseClient, bucket: str) -> None:
    """S3 バケットを空にする。バージョニング有効バケットにも対応する。

    バージョニング無効バケットでも安全に動作する (list_object_versions が空を返すため)。
    """
    if not bucket_exists(s3, bucket):
        return

    # まず現行バージョンを一括削除 (オブジェクト数が多い場合に高速)
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket):
        contents = page.get("Contents") or []
        if not contents:
            continue
        objects = [{"Key": o["Key"]} for o in contents]
        # delete_objects は 1 リクエストあたり最大 1000 件
        for chunk in _chunked(objects, 1000):
            s3.delete_objects(Bucket=bucket, Delete={"Objects": chunk, "Quiet": True})

    # バージョニング有効バケットでは古いバージョンや削除マーカーが残るため削除
    versions_paginator = s3.get_paginator("list_object_versions")
    while True:
        targets: list[dict[str, str]] = []
        for page in versions_paginator.paginate(Bucket=bucket, MaxKeys=1000):
            for v in page.get("Versions") or []:
                targets.append({"Key": v["Key"], "VersionId": v["VersionId"]})
            for m in page.get("DeleteMarkers") or []:
                targets.append({"Key": m["Key"], "VersionId": m["VersionId"]})
            # 1 ページごとに即削除して次のページに進む (巨大バケット対策)
            if targets:
                break
        if not targets:
            break
        print(f"  バージョンと削除マーカーを {len(targets)} 件削除中...")
        for chunk in _chunked(targets, 1000):
            s3.delete_objects(Bucket=bucket, Delete={"Objects": chunk, "Quiet": True})


def _chunked(seq: Sequence[dict], size: int) -> Iterable[list[dict]]:
    for i in range(0, len(seq), size):
        yield list(seq[i : i + size])


# ---------------------------------------------------------------------------
# プロンプト
# ---------------------------------------------------------------------------


def prompt_yes_no(message: str, default: bool = False) -> bool:
    """y/N プロンプト。default=False の場合は明示的に y/yes を入力した場合のみ True。"""
    print(yellow(message))
    try:
        response = input().strip().lower()
    except EOFError:
        return default
    if response in ("y", "yes"):
        return True
    return default
