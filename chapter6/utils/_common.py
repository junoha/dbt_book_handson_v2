"""第 6 章 ハンズオン用ユーティリティの共通モジュール。

setup.py / delete_resources.py から利用する。

依存関係: 標準ライブラリ + boto3 のみ。
"""

from __future__ import annotations

import fnmatch
import os
import sys
import time
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Any

import boto3
from botocore.client import BaseClient
from botocore.exceptions import ClientError, WaiterError

# ---------------------------------------------------------------------------
# 色付き出力
# ---------------------------------------------------------------------------

# Windows 10 1511+ の cmd.exe で ANSI エスケープシーケンスを有効化する慣用句。
# os.system("") を 1 回呼ぶと VT 処理が有効化される。
if os.name == "nt":  # pragma: no cover - Windows のみ
    os.system("")

# TTY ではない（パイプ/リダイレクト）または NO_COLOR が設定されていれば無色化。
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


# 変更セット作成失敗時に「変更なし」とみなす CFN メッセージ群。
# aws cloudformation deploy が "no changes" として扱うのと同じ判定。
_NO_CHANGE_MARKERS = (
    "didn't contain changes",
    "No updates are to be performed",
    "The submitted information didn't contain changes",
)


def deploy_stack(
    cfn: BaseClient,
    stack_name: str,
    template_path: Path,
    parameters: dict[str, str] | None = None,
    capabilities: Sequence[str] | None = None,
    waiter_delay: int = 30,
    waiter_max_attempts: int = 240,
) -> bool:
    """`aws cloudformation deploy` 相当の動作を行う。

    変更セットを作成して実行することで、新規作成と更新のどちらにも対応する。
    変更が無い場合は変更セットを削除して何もしない。

    Returns:
        True: 変更を適用した場合。
        False: 変更が無く、何もしなかった場合。
    """
    template_body = template_path.read_text(encoding="utf-8")

    # 既存スタックの状態から change_set_type を決定
    status = get_stack_status(cfn, stack_name)
    if status is None or status == "REVIEW_IN_PROGRESS":
        # REVIEW_IN_PROGRESS は「変更セットが作成されたが実行されていない」状態であり
        # 実体としてはスタック未作成なので CREATE 扱いにする。
        change_set_type = "CREATE"
    else:
        change_set_type = "UPDATE"

    change_set_name = f"deploy-{int(time.time())}"
    kwargs: dict[str, Any] = {
        "StackName": stack_name,
        "TemplateBody": template_body,
        "ChangeSetName": change_set_name,
        "ChangeSetType": change_set_type,
    }
    if parameters:
        kwargs["Parameters"] = [
            {"ParameterKey": k, "ParameterValue": v} for k, v in parameters.items()
        ]
    if capabilities:
        kwargs["Capabilities"] = list(capabilities)

    cfn.create_change_set(**kwargs)

    # 変更セットの作成完了を待機
    while True:
        resp = cfn.describe_change_set(ChangeSetName=change_set_name, StackName=stack_name)
        cs_status = resp["Status"]
        if cs_status == "CREATE_COMPLETE":
            break
        if cs_status == "FAILED":
            reason = resp.get("StatusReason", "") or ""
            if any(m in reason for m in _NO_CHANGE_MARKERS):
                # 変更なし: 変更セットを削除して終了
                cfn.delete_change_set(ChangeSetName=change_set_name, StackName=stack_name)
                if change_set_type == "CREATE":
                    # 空の REVIEW_IN_PROGRESS スタックが残るので削除しておく
                    try:
                        cfn.delete_stack(StackName=stack_name)
                    except ClientError:
                        pass
                return False
            raise RuntimeError(f"Change set creation failed: {reason}")
        time.sleep(5)

    cfn.execute_change_set(ChangeSetName=change_set_name, StackName=stack_name)

    waiter_name = "stack_create_complete" if change_set_type == "CREATE" else "stack_update_complete"
    waiter = cfn.get_waiter(waiter_name)
    try:
        waiter.wait(
            StackName=stack_name,
            WaiterConfig={"Delay": waiter_delay, "MaxAttempts": waiter_max_attempts},
        )
    except WaiterError as e:
        raise RuntimeError(f"Stack {stack_name} did not reach {change_set_type}_COMPLETE: {e}") from e

    return True


def delete_stack(cfn: BaseClient, stack_name: str) -> None:
    """スタック削除を非同期で開始する（完了は待機しない）。"""
    cfn.delete_stack(StackName=stack_name)


def wait_stack_delete(cfn: BaseClient, stack_name: str, timeout_seconds: int = 300) -> None:
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
# Glue
# ---------------------------------------------------------------------------


def glue_database_exists(glue: BaseClient, database_name: str) -> bool:
    try:
        glue.get_database(Name=database_name)
        return True
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") == "EntityNotFoundException":
            return False
        raise


# ---------------------------------------------------------------------------
# S3
# ---------------------------------------------------------------------------


def bucket_exists(s3: BaseClient, bucket: str) -> bool:
    try:
        s3.head_bucket(Bucket=bucket)
        return True
    except ClientError:
        return False


def _matches_any(rel_path: str, patterns: Iterable[str]) -> bool:
    return any(fnmatch.fnmatch(rel_path, p) for p in patterns)


def s3_sync(
    s3: BaseClient,
    local_dir: Path,
    bucket: str,
    exclude: Sequence[str] = (),
) -> int:
    """ローカルディレクトリを S3 バケットに同期する。

    ``aws s3 sync`` と同様、--delete 相当の動作は行わない（ローカルに無い
    リモートオブジェクトは削除しない）。比較は行わず、対象ファイルを毎回アップロード
    する単純実装。setup の対象ファイル数・サイズが小さいため十分。

    Args:
        exclude: ``aws s3 sync --exclude`` と同じ書式のシェル風グロブパターン群。
            各ファイルの POSIX 形式の相対パスに対して fnmatch で評価する。

    Returns:
        アップロードしたファイル数。
    """
    if not local_dir.is_dir():
        raise FileNotFoundError(f"local_dir not found: {local_dir}")

    uploaded = 0
    for path in sorted(local_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(local_dir).as_posix()
        if _matches_any(rel, exclude):
            continue
        s3.upload_file(str(path), bucket, rel)
        uploaded += 1

    print(f"  {uploaded} ファイルを s3://{bucket}/ にアップロードしました")
    return uploaded


def empty_s3_bucket(s3: BaseClient, bucket: str) -> None:
    """S3 バケットを空にする。バージョニング有効バケットにも対応する。

    バージョニング無効バケットでも安全に動作する（list_object_versions が空を返すため）。
    """
    if not bucket_exists(s3, bucket):
        return

    # まず現行バージョンを一括削除（オブジェクト数が多い場合に高速）
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
            # 1 ページごとに即削除して次のページに進む（巨大バケット対策）
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
