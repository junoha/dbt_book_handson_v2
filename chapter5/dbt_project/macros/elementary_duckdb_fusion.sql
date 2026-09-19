{#
    Elementary を dbt v2（Rust エンジン）+ DuckDB で動かすための互換マクロ。

    dbt v2 は接続をプールし、文ごとに別セッションを使う。DuckDB の temp テーブルは
    セッションスコープのため、Elementary が中間テーブルとして作る temp テーブルが
    次の文から見えず、以下のエラーでビルドが失敗する。

      Catalog Error: Table with name dbt_models__tmp_<timestamp>... does not exist!
      Parser Error: TEMPORARY table names can *only* use the "temp" catalog

    Elementary は同じ問題を redshift / databricks / spark などでは
    elementary.is_dbt_fusion() による分岐で回避しているが、duckdb 用の分岐が
    まだ存在しない（elementary 0.26.0 時点）。そこで redshift 向けの実装と同じ方針
    ——temp テーブルの代わりに通常テーブルを作り、Elementary のクリーンアップに任せる——
    を duckdb に対して適用する。

    dbt_project.yml の dispatch 設定（macro_namespace: elementary）と対で機能する。
    upstream が duckdb 分岐を同梱したら、このファイルは削除できる。
#}

{% macro duckdb__has_temp_table_support() %}
    {% if elementary.is_dbt_fusion() %}{% do return(false) %}
    {% else %}{% do return(true) %}{% endif %}
{% endmacro %}


{% macro duckdb__edr_make_temp_relation(base_relation, suffix) %}
    {% if elementary.is_dbt_fusion() %}
        {% set tmp_identifier = elementary.table_name_with_suffix(
            base_relation.identifier, suffix
        ) %}
        {% do return(api.Relation.create(
            identifier=tmp_identifier,
            schema=base_relation.schema,
            database=base_relation.database,
            type="table",
        )) %}
    {% else %} {% do return(dbt.make_temp_relation(base_relation, suffix)) %}
    {% endif %}
{% endmacro %}


{% macro duckdb__edr_make_intermediate_relation(base_relation) %}
    {% do return(elementary.make_temp_table_relation(base_relation)) %}
{% endmacro %}


{% macro duckdb__edr_get_create_table_as_sql(
    temporary, relation, sql_query, expiration_hours=none
) %}
    {% if elementary.is_dbt_fusion() %}
  create or replace table {{ relation }} as {{ sql_query }}
    {% else %}
  create or replace {% if temporary %} temporary {% endif %} table {{ relation }}
  as {{ sql_query }}
    {% endif %}
{% endmacro %}
