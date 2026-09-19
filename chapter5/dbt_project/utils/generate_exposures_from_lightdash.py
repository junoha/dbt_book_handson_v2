"""Lightdash YAML から dbt Exposures を生成するスクリプト.

このスクリプトは、Lightdash ディレクトリ内のダッシュボードとチャートの YAML ファイルを解析し、
dbt Exposures の定義を自動生成します。

使用例:
    python utils/generate_exposures_from_lightdash.py
    python utils/generate_exposures_from_lightdash.py --lightdash-dir lightdash
"""

import argparse
from pathlib import Path
from typing import Any

import yaml


def load_yaml(file_path: Path) -> dict[str, Any]:
    """YAML ファイルを読み込む.

    Args:
        file_path: YAML ファイルのパス

    Returns:
        YAML ファイルの内容
    """
    with open(file_path) as f:
        return yaml.safe_load(f)


def extract_table_names_from_chart(chart_data: dict[str, Any]) -> list[str]:
    """チャート定義から参照テーブル名を抽出.

    Args:
        chart_data: チャートの YAML データ

    Returns:
        参照されているテーブル名のリスト
    """
    table_names = set()

    # tableName フィールドから抽出
    if "tableName" in chart_data:
        table_names.add(chart_data["tableName"])

    # metricQuery.exploreName からも抽出
    if "metricQuery" in chart_data:
        metric_query = chart_data["metricQuery"]
        if "exploreName" in metric_query:
            table_names.add(metric_query["exploreName"])

    return sorted(table_names)


def generate_exposure_from_dashboard(
    dashboard_file: Path, charts_dir: Path
) -> dict[str, Any]:
    """ダッシュボード YAML から exposure 定義を生成.

    Args:
        dashboard_file: ダッシュボード YAML ファイルのパス
        charts_dir: チャート YAML ファイルが格納されているディレクトリ

    Returns:
        dbt exposure 定義
    """
    dashboard_data = load_yaml(dashboard_file)

    # ダッシュボードに含まれるチャートを特定
    chart_slugs = []
    if "tiles" in dashboard_data:
        for tile in dashboard_data["tiles"]:
            if tile.get("type") == "saved_chart":
                properties = tile.get("properties", {})
                chart_slug = properties.get("chartSlug")
                if chart_slug:
                    chart_slugs.append(chart_slug)

    # 各チャートから参照テーブルを抽出
    all_table_names = set()
    for chart_slug in chart_slugs:
        chart_file = charts_dir / f"{chart_slug}.yml"
        if chart_file.exists():
            chart_data = load_yaml(chart_file)
            table_names = extract_table_names_from_chart(chart_data)
            all_table_names.update(table_names)

    # exposure 定義を生成
    dashboard_name = dashboard_data.get("name", "unknown_dashboard")
    dashboard_slug = dashboard_data.get("slug", "unknown-dashboard")
    description = dashboard_data.get(
        "description", f"Lightdash dashboard: {dashboard_name}"
    )

    # テーブル名から ref() を生成
    depends_on = [f'ref("{table}")' for table in sorted(all_table_names)]

    exposure = {
        "name": f"lightdash_{dashboard_slug.replace('-', '_')}",
        "label": dashboard_name,
        "type": "dashboard",
        "maturity": "medium",
        "url": f"http://localhost:8081/projects/xxxx/dashboards/yyyy/view",
        "description": description,
        "depends_on": depends_on,
        "owner": {"name": "データチーム", "email": "data-team@zakkamall.example.com"},
        # dbt v2 では meta を config 配下に置く（トップレベルの meta は解釈されない）
        "config": {
            "meta": {
                "business_impact": "high",
                "refresh_schedule": "daily",
                "source": "lightdash",
                "chart_count": len(chart_slugs),
            },
        },
    }

    return exposure


def generate_exposures_yaml(lightdash_dir: Path) -> dict[str, Any]:
    """Lightdash ディレクトリから exposures.yml を生成.

    Args:
        lightdash_dir: Lightdash YAML ファイルが格納されているディレクトリ

    Returns:
        exposures.yml の内容
    """
    dashboards_dir = lightdash_dir / "dashboards"
    charts_dir = lightdash_dir / "charts"

    if not dashboards_dir.exists():
        msg = f"ダッシュボードディレクトリが見つかりません: {dashboards_dir}"
        raise FileNotFoundError(msg)

    if not charts_dir.exists():
        msg = f"チャートディレクトリが見つかりません: {charts_dir}"
        raise FileNotFoundError(msg)

    # 全ダッシュボードを処理
    exposures = []
    for dashboard_file in dashboards_dir.glob("*.yml"):
        exposure = generate_exposure_from_dashboard(dashboard_file, charts_dir)
        exposures.append(exposure)

    # exposures.yml の形式で出力
    output = {
        "version": 2,
        "exposures": exposures,
    }

    return output


def main() -> None:
    """メイン処理."""
    parser = argparse.ArgumentParser(
        description="Lightdash YAML から dbt Exposures を生成"
    )
    parser.add_argument(
        "--lightdash-dir",
        type=Path,
        default=Path("lightdash"),
        help="Lightdash YAML ディレクトリのパス（デフォルト: lightdash）",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("models/exposures_from_lightdash.yml"),
        help="出力ファイルのパス（デフォルト: models/exposures_from_lightdash.yml）",
    )

    args = parser.parse_args()

    lightdash_dir = args.lightdash_dir
    output_file = args.output

    # Exposures YAML を生成
    exposures_yaml = generate_exposures_yaml(lightdash_dir)

    # ファイルに出力
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, "w") as f:
        # YAML フォーマットで出力（日本語をそのまま出力）
        yaml.dump(
            exposures_yaml,
            f,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
        )

    print(f"✅ Exposures を生成しました: {output_file}")
    print(f"   ダッシュボード数: {len(exposures_yaml['exposures'])}")


if __name__ == "__main__":
    main()
