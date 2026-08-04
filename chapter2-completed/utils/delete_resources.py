"""第 2 章ハンズオンで作成した AWS リソースを削除するスクリプト。

処理の流れ:
    1. CloudFormation スタック `dbt-book-ch2` の Outputs から S3 バケット名を取得
    2. Landing S3 バケットの中身を全削除
    3. CloudFormation スタック `dbt-book-ch2` を削除
    4. Secrets Manager の Redshift 管理者パスワード (`dbt-book-ch2-redshift-admin`)
        を復旧期間なしで即時削除

実行方法 (chapter2-completed ディレクトリ直下から)::

    uv run python utils/delete_resources.py
"""

from __future__ import annotations

import sys
from pathlib import Path

# このスクリプトを直接実行した場合でも `_common` を import できるよう、
# utils/ ディレクトリを sys.path に追加する。
_UTILS_DIR = Path(__file__).resolve().parent
if str(_UTILS_DIR) not in sys.path:
    sys.path.insert(0, str(_UTILS_DIR))

from botocore.exceptions import ClientError  # noqa: E402

from _common import (  # noqa: E402
    bucket_exists,
    delete_stack,
    empty_s3_bucket,
    ensure_default_region,
    get_stack_outputs,
    green,
    make_client,
    prompt_yes_no,
    red,
    stack_exists,
    wait_stack_delete,
    yellow,
)

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

STACK_NAME = "dbt-book-ch2"
SECRET_NAME = "dbt-book-ch2-redshift-admin"


# ---------------------------------------------------------------------------
# 削除対象列挙
# ---------------------------------------------------------------------------


def _enumerate_targets(cfn, s3, secrets) -> tuple[list[str], list[str], str]:
    """削除対象 / スキップ対象を列挙する。

    Returns:
        (to_delete, to_skip, landing_bucket)
    """
    to_delete: list[str] = []
    to_skip: list[str] = []
    landing_bucket = ""

    # CloudFormation スタックとその配下のバケット
    if stack_exists(cfn, STACK_NAME):
        to_delete.append(f"[CloudFormation] {STACK_NAME}")
        try:
            outputs = get_stack_outputs(cfn, STACK_NAME)
        except ClientError:
            outputs = {}
        landing_bucket = outputs.get("LandingBucketName", "")
        if landing_bucket and bucket_exists(s3, landing_bucket):
            to_delete.append(
                f"[S3 バケット] {landing_bucket} "
                "(中身を空にしてから CloudFormation スタックと一緒に削除)"
            )
    else:
        to_skip.append(f"[CloudFormation] {STACK_NAME}")

    # Secrets Manager: Redshift 管理者パスワード
    try:
        secrets.describe_secret(SecretId=SECRET_NAME)
        to_delete.append(
            f"[Secrets Manager] {SECRET_NAME} (`--force-delete-without-recovery` で即時削除)"
        )
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code == "ResourceNotFoundException":
            to_skip.append(f"[Secrets Manager] {SECRET_NAME}")
        else:
            raise

    return to_delete, to_skip, landing_bucket


def _check_aws_credentials() -> str:
    """AWS 認証情報の有効性を確認し、アカウント ID を返す。"""
    sts = make_client("sts")
    try:
        resp = sts.get_caller_identity()
    except ClientError as e:
        print(red(f"エラー: AWS 認証情報が無効です: {e}"))
        raise SystemExit(1) from e
    return resp["Account"]


# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------


def main() -> int:
    region = ensure_default_region()

    cfn = make_client("cloudformation")
    s3 = make_client("s3")
    secrets = make_client("secretsmanager")

    account_id = _check_aws_credentials()
    print(f"AWS アカウント ID: {account_id}")
    print(f"リージョン: {region}")
    print()

    to_delete, to_skip, landing_bucket = _enumerate_targets(cfn, s3, secrets)

    if not to_delete:
        print("削除対象のリソースはありません。")
        if to_skip:
            print()
            print("存在しないためスキップ:")
            for item in to_skip:
                print(f"  {item}")
        return 0

    print("削除対象のリソース:")
    for item in to_delete:
        print(f"  {item}")
    if to_skip:
        print()
        print("存在しないためスキップ:")
        for item in to_skip:
            print(f"  {item}")

    print()
    if not prompt_yes_no("上記を全て削除します。続行しますか? (y/N)"):
        print("削除をキャンセルしました")
        return 0

    # 1. S3 バケットを空にする (CloudFormation スタック削除の前に実施)
    if landing_bucket and bucket_exists(s3, landing_bucket):
        print()
        print(f"S3 バケットを空にしています: {landing_bucket}")
        empty_s3_bucket(s3, landing_bucket)
        print(green(f"S3 バケット {landing_bucket} を空にしました"))

    # 2. CloudFormation スタックの削除
    if stack_exists(cfn, STACK_NAME):
        print()
        print("CloudFormation スタックを削除中...")
        delete_stack(cfn, STACK_NAME)
        wait_stack_delete(cfn, STACK_NAME)

    # 3. Secrets Manager シークレットの即時削除
    try:
        secrets.delete_secret(
            SecretId=SECRET_NAME,
            ForceDeleteWithoutRecovery=True,
        )
        print(green(f"Secrets Manager シークレット {SECRET_NAME} を削除しました"))
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code == "ResourceNotFoundException":
            print(yellow(f"Secrets Manager シークレット {SECRET_NAME} は既に存在しません"))
        else:
            raise

    print()
    print(green("削除が完了しました"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
