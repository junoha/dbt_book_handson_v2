-- 日付ディメンション
--
-- Grain: 1 row per date_day
-- Business process: （時間軸の汎用ディメンション）
--
-- dbt_utils.date_spine で dbt_project.yml の vars（start_date / end_date）で指定した
-- 範囲の日付系列を生成し、年月日・四半期・曜日・会計年度（4 月始まり）などの属性を付与する。
-- MetricFlow の time spine として dimensional/models.yml 側で登録している。
{{
  config(
    materialized='table',
    tags=['dimensional', 'dimension']
  )
}}

with date_spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('start_date') ~ "' as date)",
        end_date="cast('" ~ var('end_date') ~ "' as date)"
    ) }}),

date_dimension as (
    select
        date_day as date_key,
        date_day,
        extract(year from date_day) as year,
        extract(month from date_day) as month,
        extract(day from date_day) as day,
        extract(quarter from date_day) as quarter,
        extract(dow from date_day) as day_of_week,
        extract(doy from date_day) as day_of_year,
        extract(week from date_day) as week_of_year,

        -- 日本語の曜日名
        case extract(dow from date_day)
            when 0 then '日曜日'
            when 1 then '月曜日'
            when 2 then '火曜日'
            when 3 then '水曜日'
            when 4 then '木曜日'
            when 5 then '金曜日'
            when 6 then '土曜日'
        end as day_name,

        -- 月名
        case extract(month from date_day)
            when 1 then '1月'
            when 2 then '2月'
            when 3 then '3月'
            when 4 then '4月'
            when 5 then '5月'
            when 6 then '6月'
            when 7 then '7月'
            when 8 then '8月'
            when 9 then '9月'
            when 10 then '10月'
            when 11 then '11月'
            when 12 then '12月'
        end as month_name,

        -- 四半期名
        'Q' || extract(quarter from date_day) as quarter_name,

        -- 平日・休日フラグ
        case
            when extract(dow from date_day) in (0, 6) then '休日'
            else '平日'
        end as weekday_flag,

        -- 月初・月末フラグ
        coalesce(extract(day from date_day) = 1, false) as is_month_start,
        coalesce(date_day = date_trunc('month', date_day) + interval '1 month' - interval '1 day', false) as is_month_end,

        -- 年度（4月始まり）
        case
            when extract(month from date_day) >= 4 then extract(year from date_day)
            else extract(year from date_day) - 1
        end as fiscal_year,

        -- 年度四半期
        case
            when extract(month from date_day) in (4, 5, 6) then 1
            when extract(month from date_day) in (7, 8, 9) then 2
            when extract(month from date_day) in (10, 11, 12) then 3
            else 4
        end as fiscal_quarter

    from date_spine
)

select * from date_dimension
