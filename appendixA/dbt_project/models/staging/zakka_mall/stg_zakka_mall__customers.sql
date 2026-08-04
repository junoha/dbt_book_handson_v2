{{
  config(
    materialized='view',
    tags=['staging', 'customer']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'customer') }}
),

cleaned as (
    select
        customer_id,
        phone,
        registration_date,
        status as customer_status,
        created_at,
        updated_at,
        trim(customer_name) as customer_name,
        lower(trim(email)) as email,

        -- 計算フィールド
        -- 継続期間セグメントは var('analysis_as_of_date') を基準日として判定する。
        -- 区切りは「登録から 1 年未満 / 1〜2 年 / 2 年以上」。
        case
            when registration_date >= '{{ var("analysis_as_of_date") }}'::date - interval '1 year' then 'new'
            when registration_date >= '{{ var("analysis_as_of_date") }}'::date - interval '2 years' then 'existing'
            else 'long_term'
        end as customer_tenure_segment,

        -- データ品質フラグ
        case
            when customer_name is null or trim(customer_name) = '' then false
            when email is null or trim(email) = '' then false
            when email not like '%@%' then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
