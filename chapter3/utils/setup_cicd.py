"""第 3 章ハンズオン (CI/CD) のセットアップスクリプト。

CloudFormation スタック `dbt-book-ch3-cicd` をデプロイし、GitHub Actions の
ランナーから AWS に接続するための IAM ロールや、dbt ドキュメントをホストする
Amplify アプリなどを作成する。作成したリソースの値 (`AWS_ROLE_ARN`,
`AMPLIFY_APP_ID`) を `.env` に追記する。

実行方法 (chapter3 ディレクトリ直下から)::

    uv run python utils/setup_cicd.py --github-account <GitHub アカウント名>

リポジトリ名を既定値 (dbt_handson3) から変えた場合は --repo で指定する::

    uv run python utils/setup_cicd.py --github-account <名前> --repo <リポジトリ名>

すでにアカウントに GitHub OIDC プロバイダーが存在する場合は
--no-create-oidc-provider を付けて重複作成エラーを回避する。

`.env` への追記後、以下のコマンドで GitHub シークレットを一括登録できる::

    gh secret set --env-file .env
"""

from __future__ import annotations

import argparse
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
    green,
    make_client,
    print_step,
    update_env_file,
)

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

CICD_STACK_NAME = "dbt-book-ch3-cicd"

CH3_DIR = _UTILS_DIR.parent
CFN_DIR = CH3_DIR / "cloudformation"
CICD_TEMPLATE = CFN_DIR / "cicd.yml"
ENV_FILE = CH3_DIR / ".env"


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="第 3 章 CI/CD リソースのセットアップ")
    parser.add_argument(
        "--github-account",
        required=True,
        help="GitHub アカウント名 (gh auth status で確認できます)",
    )
    parser.add_argument(
        "--repo",
        default="dbt_handson3",
        help="GitHub リポジトリ名 (既定: dbt_handson3)",
    )
    parser.add_argument(
        "--no-create-oidc-provider",
        action="store_true",
        help="アカウントに GitHub OIDC プロバイダーが既に存在する場合に指定",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    ensure_default_region()

    print_step("CI/CD 用リソース (IAM ロール・Amplify アプリ) の作成")
    cfn = make_client("cloudformation")
    deploy_stack(
        cfn,
        CICD_STACK_NAME,
        CICD_TEMPLATE,
        parameters={
            "GitHubAccount": args.github_account,
            "GitHubRepository": args.repo,
            "CreateOIDCProvider": "false" if args.no_create_oidc_provider else "true",
        },
        capabilities=["CAPABILITY_NAMED_IAM"],
    )

    outputs = get_stack_outputs(cfn, CICD_STACK_NAME)
    role_arn = outputs.get("IAMRoleArn", "")
    amplify_app_id = outputs.get("AmplifyAppId", "")
    amplify_url = outputs.get("AmplifyURL", "")
    if not role_arn or not amplify_app_id:
        raise RuntimeError(
            f"スタック {CICD_STACK_NAME} の Outputs に必要な値が見つかりません"
        )

    update_env_file(
        ENV_FILE,
        {"AWS_ROLE_ARN": role_arn, "AMPLIFY_APP_ID": amplify_app_id},
    )

    print_step("CI/CD セットアップ完了")
    print(green(f"IAM ロール ARN: {role_arn}"))
    print(green(f"Amplify アプリ ID: {amplify_app_id}"))
    if amplify_url:
        print(green(f"ドキュメント URL: {amplify_url}"))
    print()
    print("次のコマンドで GitHub シークレットを一括登録できます:")
    print("  gh secret set --env-file .env")
    return 0


if __name__ == "__main__":
    sys.exit(main())
