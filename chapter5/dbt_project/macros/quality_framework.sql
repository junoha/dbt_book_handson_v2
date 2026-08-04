-- データ品質フレームワーク用マクロ集

-- 完全性チェック（NULL値の割合を計算）
{% macro calculate_completeness(column_name, table_name) %}
  select
    '{{ column_name }}' as column_name,
    '{{ table_name.identifier }}' as table_name,
    'completeness' as quality_dimension,
    count(*) as total_records,
    count({{ column_name }}) as non_null_records,
    round(count({{ column_name }})::numeric / count(*)::numeric * 100, 2) as completeness_percentage,
    case 
      when count({{ column_name }})::numeric / count(*)::numeric >= {{ var('completeness_threshold') }}
      then 'PASS' 
      else 'FAIL' 
    end as quality_status
  from {{ table_name }}
{% endmacro %}

-- 一意性チェック（重複レコードの検出）
{% macro calculate_uniqueness(column_name, table_name) %}
  select
    '{{ column_name }}' as column_name,
    '{{ table_name.identifier }}' as table_name,
    'uniqueness' as quality_dimension,
    count(*) as total_records,
    count(distinct {{ column_name }}) as unique_records,
    round(count(distinct {{ column_name }})::numeric / count(*)::numeric * 100, 2) as uniqueness_percentage,
    case 
      when count(distinct {{ column_name }}) = count(*)
      then 'PASS' 
      else 'FAIL' 
    end as quality_status
  from {{ table_name }}
  where {{ column_name }} is not null
{% endmacro %}

-- 妥当性チェック（値の範囲や形式をチェック）
{% macro calculate_validity(column_name, table_name, validation_rule) %}
  select
    '{{ column_name }}' as column_name,
    '{{ table_name.identifier }}' as table_name,
    'validity' as quality_dimension,
    count(*) as total_records,
    count(case when {{ validation_rule }} then 1 end) as valid_records,
    round(count(case when {{ validation_rule }} then 1 end)::numeric / count(*)::numeric * 100, 2) as validity_percentage,
    case 
      when count(case when {{ validation_rule }} then 1 end)::numeric / count(*)::numeric >= {{ var('validity_threshold') }}
      then 'PASS' 
      else 'FAIL' 
    end as quality_status
  from {{ table_name }}
  where {{ column_name }} is not null
{% endmacro %}

-- 一貫性チェック（クロステーブル検証）
{% macro calculate_consistency(column_name, source_table, target_table) %}
  select
    '{{ column_name }}' as column_name,
    '{{ target_table.identifier }}' as table_name,
    'consistency' as quality_dimension,
    consistency_check.total_target_records as total_records,
    consistency_check.consistent_records,
    round(
      consistency_check.consistent_records::numeric
      / nullif(consistency_check.total_target_records, 0)::numeric
      * 100,
      2
    ) as consistency_percentage,
    case
      when
        consistency_check.consistent_records::numeric
        / nullif(consistency_check.total_target_records, 0)::numeric
        >= {{ var('consistency_threshold') }}
      then 'PASS'
      else 'FAIL'
    end as quality_status
  from (
    select
      count(distinct t.{{ column_name }}) as total_target_records,
      count(distinct s.{{ column_name }}) as consistent_records
    from (
      select distinct {{ column_name }}
      from {{ target_table }}
      where {{ column_name }} is not null
    ) as t
    left join (
      select distinct {{ column_name }}
      from {{ source_table }}
      where {{ column_name }} is not null
    ) as s on t.{{ column_name }} = s.{{ column_name }}
  ) as consistency_check
{% endmacro %}

-- 一貫性チェック（金額の突合）
--
-- calculate_consistency が「参照先に値が存在するか」を見るのに対し、
-- こちらは結合した 2 テーブルの金額が一致しているかを見る。
-- 注文金額と支払金額のように、同じ値が 2 か所に保持されている場合の
-- 整合性を測るために使う。
{% macro calculate_amount_consistency(column_name, left_table, right_table, join_key, left_amount, right_amount) %}
  select
    '{{ column_name }}' as column_name,
    '{{ right_table.identifier }}' as table_name,
    'consistency' as quality_dimension,
    count(*) as total_records,
    count(case when abs(l.{{ left_amount }} - r.{{ right_amount }}) <= {{ var('payment_mismatch_threshold') }} then 1 end) as consistent_records,
    round(
      count(case when abs(l.{{ left_amount }} - r.{{ right_amount }}) <= {{ var('payment_mismatch_threshold') }} then 1 end)::numeric
      / nullif(count(*), 0)::numeric
      * 100,
      2
    ) as consistency_percentage,
    case
      when
        count(case when abs(l.{{ left_amount }} - r.{{ right_amount }}) <= {{ var('payment_mismatch_threshold') }} then 1 end)::numeric
        / nullif(count(*), 0)::numeric
        >= {{ var('consistency_threshold') }}
      then 'PASS'
      else 'FAIL'
    end as quality_status
  from {{ left_table }} as l
  inner join {{ right_table }} as r on l.{{ join_key }} = r.{{ join_key }}
  where l.{{ left_amount }} is not null
    and r.{{ right_amount }} is not null
{% endmacro %}
