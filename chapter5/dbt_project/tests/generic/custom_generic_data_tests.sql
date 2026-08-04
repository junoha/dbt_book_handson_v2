-- カスタムジェネリックテスト: データ鮮度チェック
{% test test_data_freshness_within_hours(model, column_name, hours_threshold=24) %}
  select *
  from {{ model }}
  where {{ column_name }} < current_timestamp - interval '{{ hours_threshold }} hours'
{% endtest %}

-- カスタムジェネリックテスト: 値の範囲チェック
{% test test_values_in_range(model, column_name, min_value, max_value) %}
  select *
  from {{ model }}
  where {{ column_name }} < {{ min_value }}
     or {{ column_name }} > {{ max_value }}
{% endtest %}

-- カスタムジェネリックテスト: 参照整合性チェック（複数カラム対応）
{% test test_multi_column_relationships(model, to_ref, from_columns, to_columns) %}
{% set from_cols = from_columns | join(', ') %}
{% set to_cols = to_columns | join(', ') %}
  
  select {{ from_cols }}
  from {{ model }}
  where ({{ from_cols }}) not in (
    select {{ to_cols }}
    from {{ to_ref }}
  )
{% endtest %}

-- カスタムジェネリックテスト: 重複レコード検出（複数カラム）
{% test test_unique_combination(model, columns) %}
{% set cols = columns | join(', ') %}
  select {{ cols }}, count(*) as cnt
  from {{ model }}
  group by {{ cols }}
  having count(*) > 1
{% endtest %}

-- カスタムジェネリックテスト: 統計的外れ値検出
{% test test_statistical_outliers(model, column_name, z_score_threshold=3) %}
  with stats as (
    select 
      avg({{ column_name }}) as mean_val,
      stddev({{ column_name }}) as stddev_val
    from {{ model }}
    where {{ column_name }} is not null
  ),
  outliers as (
    select 
      *,
      abs({{ column_name }} - stats.mean_val) / stats.stddev_val as z_score
    from {{ model }}
    cross join stats
    where stats.stddev_val > 0
  )
  select *
  from outliers
  where z_score > {{ z_score_threshold }}
{% endtest %}

-- カスタムジェネリックテスト: ビジネス日の検証
{% test test_business_days_only(model, column_name) %}
  select *
  from {{ model }}
  where extract(dow from {{ column_name }}) in (0, 6)  -- 日曜日(0)、土曜日(6)
{% endtest %}


-- 日本の携帯電話・固定電話番号の基本フォーマットをチェック
{% test expect_column_values_to_match_phone_format(model, column_name) %}
  select *
  from {{ model }}
  where {{ column_name }} is not null
    and not (
      -- 携帯電話: 090/080/070-xxxx-xxxx
      {{ column_name }} ~ '^(090|080|070)-\d{4}-\d{4}$'
      or
      -- 固定電話: 0x-xxxx-xxxx (市外局番2-4桁)
      {{ column_name }} ~ '^0\d{1,3}-\d{4}-\d{4}$'
      )

{% endtest %}

-- 金額の正当性チェック（負の値や異常に大きな値を検出）
{% test expect_column_values_to_be_reasonable_amount(model, column_name, min_value=0, max_value=10000000) %}
  select *
  from {{ model }}
  where {{ column_name }} is not null
    and (
        {{ column_name }} < {{ min_value }}
        or 
        {{ column_name }} > {{ max_value }}
        or
        -- NaN や Infinity の検出
        {{ column_name }}::text in ('NaN', 'Infinity', '-Infinity')
      )
{% endtest %}

-- メールアドレスドメインの拒否リスト検証
{% test expect_email_domain_not_in_denylist(model, column_name, denylist=['spam.com', 'fake.com', 'test.test']) %}
  select *
  from {{ model }}
  where {{ column_name }} is not null
    and lower(split_part({{ column_name }}, '@', 2)) in (
        {% for domain in denylist %}
            '{{ domain.lower() }}'{% if not loop.last %},{% endif %}
        {% endfor %}
    )
{% endtest %}

-- テスト5: 文字列長の範囲チェック（可変パラメータ対応）
{% test expect_column_text_length_between(model, column_name, min_length=1, max_length=255) %}
  select *
  from {{ model }}
  where {{ column_name }} is not null
    and (
        length(trim({{ column_name }})) < {{ min_length }}
        or 
        length(trim({{ column_name }})) > {{ max_length }}
    )
{% endtest %}


-- パーセンテージ値の妥当性チェック（0-100% または 0.0-1.0）
{% test expect_percentage_values_in_valid_range(model, column_name, percentage_format='decimal') %}
  select *
  from {{ model }}
  where {{ column_name }} is not null
    and (
      case 
        when '{{ percentage_format }}' = 'decimal' then 
            {{ column_name }} < 0.0 or {{ column_name }} > 1.0
        when '{{ percentage_format }}' = 'percentage' then 
            {{ column_name }} < 0.0 or {{ column_name }} > 100.0
        else false
      end
    )
{% endtest %}