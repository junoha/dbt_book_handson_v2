"""第 6 章ハンズオンで作成した AWS リソースを削除するスクリプト。

実行方法 (ch6 ディレクトリ直下から)::

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
    get_stack_status,
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

# setup.py と揃えた固定スタック名。
STACK_NAME = "dbt-book-ch6"
MWAA_STACK_NAME = "dbt-book-ch6-mwaa"

# DAG や dbt プロジェクトの実行で作成される Glue データベース。
GLUE_DATABASES = (
    "jaffle_shop_ch6_raw",
    "jaffle_shop_ch6_prod",
)

# MWAA 環境の削除は 20〜30 分要するため、待機タイムアウトを長めに取る。
MWAA_DELETE_TIMEOUT_SECONDS = 2400


# ---------------------------------------------------------------------------
# 削除対象列挙
# ---------------------------------------------------------------------------


def _enumerate_targets(
    cfn,
    glue,
    s3,
) -> tuple[list[str], list[str], str, str]:
    """削除対象 / スキップ対象を列挙する。

    Returns:
        (to_delete, to_skip, s3_bucket_mwaa, s3_bucket_athena)
    """
    to_delete: list[str] = []
    to_skip: list[str] = []
    s3_bucket_mwaa = ""
    s3_bucket_athena = ""

    # MWAA スタック
    if stack_exists(cfn, MWAA_STACK_NAME):
        to_delete.append(f"[CloudFormation] {MWAA_STACK_NAME}")
    else:
        to_skip.append(f"[CloudFormation] {MWAA_STACK_NAME}")

    # Glue データベース
    for db in GLUE_DATABASES:
        if glue_database_exists(glue, db):
            to_delete.append(f"[Glue DB] {db}")
        else:
            to_skip.append(f"[Glue DB] {db}")

    # S3/Athena スタックと、その配下のバケット
    if stack_exists(cfn, STACK_NAME):
        to_delete.append(f"[CloudFormation] {STACK_NAME}")
        try:
            outputs = get_stack_outputs(cfn, STACK_NAME)
        except ClientError:
            outputs = {}

        s3_bucket_mwaa = outputs.get("S3BucketMWAA", "")
        s3_bucket_athena = outputs.get("S3BucketAthena", "")

        if s3_bucket_mwaa and bucket_exists(s3, s3_bucket_mwaa):
            to_delete.append(
                f"[S3 バケット] {s3_bucket_mwaa} "
                "(バージョン込みで空にしてから S3/Athena スタックと一緒に削除)"
            )
        if s3_bucket_athena and bucket_exists(s3, s3_bucket_athena):
            to_delete.append(
                f"[S3 バケット] {s3_bucket_athena} "
                "(中身を空にしてから S3/Athena スタックと一緒に削除)"
            )
    else:
        to_skip.append(f"[CloudFormation] {STACK_NAME}")

    return to_delete, to_skip, s3_bucket_mwaa, s3_bucket_athena


# ---------------------------------------------------------------------------
# 認証情報の確認
# ---------------------------------------------------------------------------


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

    to_delete, to_skip, s3_bucket_mwaa, s3_bucket_athena = _enumerate_targets(
        cfn, glue, s3
    )

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

    # ---------------------------------------------------------------------
    # 1. MWAA スタックの削除を非同期で開始する
    #    MWAA 環境の削除は 20〜30 分を要することがあるため、短時間で終わる Glue 削除を
    #    その待ち時間にかぶせて全体所要時間を短縮する。
    #    なお S3/Athena スタックは mwaa.yml の !ImportValue で参照されているため、
    #    MWAA スタックが完全に削除されるまで削除できない。そのためまずこのタイミングで
    #    削除を起動する。
    # ---------------------------------------------------------------------
    if stack_exists(cfn, MWAA_STACK_NAME):
        mwaa_status = get_stack_status(cfn, MWAA_STACK_NAME)
        if mwaa_status == "DELETE_IN_PROGRESS":
            print()
            print("MWAA CloudFormation スタックは既に削除中です。")
        else:
            print()
            print("MWAA CloudFormation スタックの削除を開始...")
            delete_stack(cfn, MWAA_STACK_NAME)

    # ---------------------------------------------------------------------
    # 2. Glue データベースの削除 (MWAA スタックの削除完了を待たずに実施)
    # ---------------------------------------------------------------------
    print()
    print("Glue データベースを削除中...")
    for db in GLUE_DATABASES:
        if glue_database_exists(glue, db):
            glue.delete_database(Name=db)
            print(green(f"  {db} を削除しました"))

    # ---------------------------------------------------------------------
    # 3. MWAA スタック削除の完了を待機する
    # ---------------------------------------------------------------------
    if stack_exists(cfn, MWAA_STACK_NAME):
        print()
        wait_stack_delete(cfn, MWAA_STACK_NAME, timeout_seconds=MWAA_DELETE_TIMEOUT_SECONDS)

    # ---------------------------------------------------------------------
    # 4. S3 バケットを空にする (MWAA バケットはバージョニング有効)
    #    MWAA スタックの削除完了後に実施する。MWAA 環境は削除中にもログや状態を
    #    バケットに書き込むため、先に空にするとレースコンディションで MWAA の削除
    #    自体が失敗しうる。
    # ---------------------------------------------------------------------
    if s3_bucket_mwaa and bucket_exists(s3, s3_bucket_mwaa):
        print()
        print(f"S3 バケット (MWAA) を空にしています: {s3_bucket_mwaa}")
        empty_s3_bucket(s3, s3_bucket_mwaa)
        print(green(f"S3 バケット {s3_bucket_mwaa} を空にしました"))

    if s3_bucket_athena and bucket_exists(s3, s3_bucket_athena):
        print()
        print(f"S3 バケット (Athena) を空にしています: {s3_bucket_athena}")
        empty_s3_bucket(s3, s3_bucket_athena)
        print(green(f"S3 バケット {s3_bucket_athena} を空にしました"))

    # ---------------------------------------------------------------------
    # 5. S3/Athena スタックの削除
    # ---------------------------------------------------------------------
    if stack_exists(cfn, STACK_NAME):
        print()
        print("S3/Athena CloudFormation スタックを削除中...")
        delete_stack(cfn, STACK_NAME)
        wait_stack_delete(cfn, STACK_NAME)

    print()
    print(green("削除が完了しました"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
