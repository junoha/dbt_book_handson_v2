"""第 3 章ハンズオンで作成した AWS リソースを削除するスクリプト。

実行方法 (chapter3 ディレクトリ直下から)::

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
    glue_database_exists,
    green,
    make_client,
    prompt_yes_no,
    red,
    stack_exists,
    wait_stack_delete,
)

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

# setup.py / setup_cicd.py と揃えた固定スタック名。
ATHENA_STACK_NAME = "dbt-book-ch3-athena"
CICD_STACK_NAME = "dbt-book-ch3-cicd"

# dbt プロジェクトおよび load_raw_data.py の実行で作成される Glue データベース。
GLUE_DATABASES = (
    "jaffle_shop_ch3_raw",
    "jaffle_shop_ch3_dev",
    "jaffle_shop_ch3_ci",
    "jaffle_shop_ch3",
)


# ---------------------------------------------------------------------------
# 削除対象列挙
# ---------------------------------------------------------------------------


def _enumerate_targets(cfn, glue, s3) -> tuple[list[str], list[str], str]:
    """削除対象 / スキップ対象を列挙する。

    Returns:
        (to_delete, to_skip, s3_bucket_athena)
    """
    to_delete: list[str] = []
    to_skip: list[str] = []
    s3_bucket_athena = ""

    # CI/CD スタック
    if stack_exists(cfn, CICD_STACK_NAME):
        to_delete.append(f"[CloudFormation] {CICD_STACK_NAME}")
    else:
        to_skip.append(f"[CloudFormation] {CICD_STACK_NAME}")

    # Athena スタックと、その配下のバケット
    if stack_exists(cfn, ATHENA_STACK_NAME):
        to_delete.append(f"[CloudFormation] {ATHENA_STACK_NAME}")
        try:
            outputs = get_stack_outputs(cfn, ATHENA_STACK_NAME)
        except ClientError:
            outputs = {}
        s3_bucket_athena = outputs.get("S3BucketAthena", "")
        if s3_bucket_athena and bucket_exists(s3, s3_bucket_athena):
            to_delete.append(
                f"[S3 バケット] {s3_bucket_athena} "
                "(中身を空にしてから Athena スタックと一緒に削除)"
            )
    else:
        to_skip.append(f"[CloudFormation] {ATHENA_STACK_NAME}")

    # Glue データベース
    for db in GLUE_DATABASES:
        if glue_database_exists(glue, db):
            to_delete.append(f"[Glue DB] {db}")
        else:
            to_skip.append(f"[Glue DB] {db}")

    return to_delete, to_skip, s3_bucket_athena


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
    glue = make_client("glue")
    s3 = make_client("s3")

    account_id = _check_aws_credentials()
    print(f"AWS アカウント ID: {account_id}")
    print(f"リージョン: {region}")
    print()

    to_delete, to_skip, s3_bucket_athena = _enumerate_targets(cfn, glue, s3)

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

    # 1. CI/CD スタックの削除
    if stack_exists(cfn, CICD_STACK_NAME):
        print()
        print("CI/CD CloudFormation スタックを削除中...")
        delete_stack(cfn, CICD_STACK_NAME)
        wait_stack_delete(cfn, CICD_STACK_NAME)

    # 2. Glue データベースの削除
    print()
    print("Glue データベースを削除中...")
    for db in GLUE_DATABASES:
        if glue_database_exists(glue, db):
            glue.delete_database(Name=db)
            print(green(f"  {db} を削除しました"))

    # 3. S3 バケットを空にする (Athena スタック削除の前に実施)
    if s3_bucket_athena and bucket_exists(s3, s3_bucket_athena):
        print()
        print(f"S3 バケットを空にしています: {s3_bucket_athena}")
        empty_s3_bucket(s3, s3_bucket_athena)
        print(green(f"S3 バケット {s3_bucket_athena} を空にしました"))

    # 4. Athena スタックの削除
    if stack_exists(cfn, ATHENA_STACK_NAME):
        print()
        print("Athena CloudFormation スタックを削除中...")
        delete_stack(cfn, ATHENA_STACK_NAME)
        wait_stack_delete(cfn, ATHENA_STACK_NAME)

    print()
    print(green("削除が完了しました"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
