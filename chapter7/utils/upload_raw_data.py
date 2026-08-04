"""jafgen で生成した CSV を S3 にアップロードする。

Usage:
    uv run python utils/upload_raw_data.py
"""

from pathlib import Path

from _common import HANDSON_DIR, print_step, require_env, s3_upload_file


def main() -> None:
    env = require_env("CH7_S3_BUCKET_NAME")
    bucket = env["CH7_S3_BUCKET_NAME"]

    jaffle_dir = HANDSON_DIR / "jaffle-data"
    if not jaffle_dir.is_dir():
        raise SystemExit("Error: jaffle-data directory not found. Run 'jafgen 1' first.")

    print_step("CSV を S3 にアップロード")
    for csv_file in sorted(jaffle_dir.glob("*.csv")):
        name = csv_file.stem
        key = f"raw-data/{name}/{name}.csv"
        print(f"  {name} -> s3://{bucket}/{key}")
        s3_upload_file(csv_file, bucket, key)

    print("Done!")


if __name__ == "__main__":
    main()
