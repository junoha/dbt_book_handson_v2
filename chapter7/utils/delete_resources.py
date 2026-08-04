"""ハンズオンのAWSリソースを一括削除する。

Usage:
    uv run python utils/delete_resources.py
"""

import sys

from _common import green, make_client, print_step, red, s3_rm_prefix


def main() -> None:
    stack_name = "dbt-book-ch7-iceberg"
    cfn = make_client("cloudformation")

    print_step("第7章のハンズオンリソースを削除します")

    # スタックの存在確認
    try:
        resp = cfn.describe_stacks(StackName=stack_name)
    except cfn.exceptions.ClientError:
        print(f"スタック {stack_name} が見つかりません。すでに削除済みの可能性があります。")
        return

    # 確認プロンプト
    print(f"スタック: {stack_name}")
    answer = input("本当に削除しますか？ (yes/no): ").strip()
    if answer != "yes":
        print("削除をキャンセルしました。")
        return

    # Outputs からバケット名とデータベース名を取得
    outputs = {o["OutputKey"]: o["OutputValue"] for o in resp["Stacks"][0].get("Outputs", [])}
    bucket = outputs.get("S3BucketName", "")
    glue_db = outputs.get("GlueDatabaseName", "")

    # 1. Glue テーブルの削除
    if glue_db:
        print_step(f"Glue Database '{glue_db}' 内のテーブルを削除")
        glue = make_client("glue")
        try:
            tables_resp = glue.get_tables(DatabaseName=glue_db)
            for table in tables_resp.get("TableList", []):
                name = table["Name"]
                print(f"  テーブル削除: {name}")
                glue.delete_table(DatabaseName=glue_db, Name=name)
        except Exception as e:
            print(f"  Warning: {e}")

    # 2. S3 バケットを空にする
    if bucket:
        print_step(f"S3 バケット '{bucket}' を空にする")
        s3_rm_prefix(bucket, "")
        print("  -> Done")

    # 3. CloudFormation スタックの削除
    print_step("CloudFormation スタックを削除")
    cfn.delete_stack(StackName=stack_name)
    print("削除処理を開始しました。完了まで数分かかります。")

    waiter = cfn.get_waiter("stack_delete_complete")
    try:
        waiter.wait(StackName=stack_name, WaiterConfig={"Delay": 10, "MaxAttempts": 60})
        print(green("すべてのリソースが削除されました。"))
    except Exception as e:
        print(red(f"削除待機中にエラー: {e}"))
        sys.exit(1)


if __name__ == "__main__":
    main()
