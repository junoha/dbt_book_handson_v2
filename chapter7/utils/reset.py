"""ハンズオンを最初からやり直すためのリセットスクリプト。
AWSリソース（CloudFormationスタック）は残したまま、データとモデルの状態を初期化する。

Usage:
    uv run python utils/reset.py
"""

import shutil
import subprocess
import sys
from pathlib import Path

from _common import (
    DBT_ATHENA_PROJECT,
    DBT_GLUE_PROJECT,
    HANDSON_DIR,
    MODELS_MARTS,
    MODELS_STAGING,
    STEPS_DIR,
    green,
    make_client,
    print_step,
    require_env,
    s3_rm_prefix,
)


def main() -> None:
    env = require_env("CH7_S3_BUCKET_NAME", "ATHENA_WORKGROUP")
    bucket = env["CH7_S3_BUCKET_NAME"]

    print_step("ハンズオンのリセットを開始します")

    # 1. dbt が作成した Iceberg テーブルを削除
    print_step("dbt が作成したテーブルを削除")
    glue = make_client("glue")
    tables = ["stg_customers", "stg_orders", "orders", "customer_orders", "rfm_input", "customer_rfm"]
    for table in tables:
        print(f"  Deleting: jaffle_shop_iceberg.{table}")
        try:
            glue.delete_table(DatabaseName="jaffle_shop_iceberg", Name=table)
        except glue.exceptions.EntityNotFoundException:
            pass

    # 2. S3 の dbt 出力データを削除
    print_step("S3 の dbt 出力データを削除")
    s3_rm_prefix(bucket, "dbt-tables/")
    s3_rm_prefix(bucket, "dbt-glue-tables/")
    s3_rm_prefix(bucket, "athena-results/")
    print("  -> Done")

    # 3. raw データを再生成
    print_step("raw データを再生成")
    jaffle_dir = HANDSON_DIR / "jaffle-data"
    if jaffle_dir.exists():
        shutil.rmtree(jaffle_dir)

    import subprocess
    # jafgen は仮想環境の bin/ にインストールされている
    jafgen_path = Path(sys.executable).parent / "jafgen"
    subprocess.run([str(jafgen_path), "1"], cwd=str(HANDSON_DIR), check=True)

    # アップロードとテーブル作成
    from upload_raw_data import main as upload_main
    from create_raw_tables import main as create_tables_main
    upload_main()
    create_tables_main()

    # 4. モデルファイルを初期状態に戻す
    print_step("モデルファイルを初期状態に戻す")

    (MODELS_STAGING / "stg_customers.sql").write_text(
        '{{ config(\n'
        '    materialized=\'table\',\n'
        '    table_type=\'iceberg\',\n'
        '    format=\'parquet\'\n'
        ') }}\n'
        '\n'
        'select\n'
        '    id as customer_id,\n'
        '    name as customer_name\n'
        'from {{ source(\'raw\', \'raw_customers\') }}\n'
    )

    (MODELS_STAGING / "stg_orders.sql").write_text(
        '{{ config(materialized=\'view\') }}\n'
        '\n'
        'select\n'
        '    id as order_id,\n'
        '    customer as customer_id,\n'
        '    ordered_at,\n'
        '    store_id,\n'
        '    cast(subtotal as integer) as subtotal,\n'
        '    cast(tax_paid as integer) as tax_paid,\n'
        '    cast(order_total as integer) as order_total\n'
        'from {{ source(\'raw\', \'raw_orders\') }}\n'
    )

    (MODELS_MARTS / "orders.sql").write_text(
        '{{ config(\n'
        '    materialized=\'incremental\',\n'
        '    table_type=\'iceberg\',\n'
        '    format=\'parquet\',\n'
        '    incremental_strategy=\'append\',\n'
        '    partitioned_by=[\'day(ordered_at)\'],\n'
        '    on_schema_change=\'append_new_columns\'\n'
        ') }}\n'
        '\n'
        'select\n'
        '    order_id,\n'
        '    customer_id,\n'
        '    cast(from_iso8601_timestamp(ordered_at) as timestamp(6)) as ordered_at,\n'
        '    store_id,\n'
        '    subtotal,\n'
        '    tax_paid,\n'
        '    order_total\n'
        'from {{ ref(\'stg_orders\') }}\n'
        '\n'
        '{% if is_incremental() %}\n'
        'where cast(from_iso8601_timestamp(ordered_at) as timestamp(6)) > (select max(ordered_at) from {{ this }})\n'
        '{% endif %}\n'
    )

    (MODELS_MARTS / "customer_orders.sql").write_text(
        '{{ config(\n'
        '    materialized=\'incremental\',\n'
        '    table_type=\'iceberg\',\n'
        '    format=\'parquet\',\n'
        '    incremental_strategy=\'merge\',\n'
        '    unique_key=\'customer_id\',\n'
        '    on_schema_change=\'append_new_columns\'\n'
        ') }}\n'
        '\n'
        'with order_summary as (\n'
        '    select\n'
        '        customer_id,\n'
        '        count(*) as order_count,\n'
        '        sum(order_total) as total_amount,\n'
        '        min(ordered_at) as first_order_at,\n'
        '        max(ordered_at) as last_order_at\n'
        '    from {{ ref(\'orders\') }}\n'
        '    group by customer_id\n'
        ')\n'
        '\n'
        'select\n'
        '    c.customer_id,\n'
        '    c.customer_name,\n'
        '    coalesce(o.order_count, 0) as order_count,\n'
        '    coalesce(o.total_amount, 0) as total_amount,\n'
        '    o.first_order_at,\n'
        '    o.last_order_at\n'
        'from {{ ref(\'stg_customers\') }} c\n'
        'left join order_summary o on c.customer_id = o.customer_id\n'
    )

    print("  -> Done")

    # 5. target/ を削除
    print_step("target/ を削除")
    target_athena = DBT_ATHENA_PROJECT / "target"
    target_glue = DBT_GLUE_PROJECT / "target"
    if target_athena.exists():
        shutil.rmtree(target_athena)
    if target_glue.exists():
        shutil.rmtree(target_glue)
    print("  -> Done")

    print(f"\n{green('リセット完了')} Step 1 から再開できます。")


if __name__ == "__main__":
    main()
