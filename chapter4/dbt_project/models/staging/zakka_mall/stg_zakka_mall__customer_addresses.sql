{{
  config(
    materialized='view',
    tags=['staging', 'customer']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'customer_address') }}
),

cleaned as (
    select
        address_id,
        customer_id,
        address_type,
        postal_code,
        prefecture,
        city,
        address_line1,
        address_line2,
        is_default,
        created_at,
        updated_at,

        -- 正規化された住所
        concat_ws(
            ' ',
            prefecture,
            city,
            address_line1,
            coalesce(address_line2, '')
        ) as full_address,

        -- 地域区分
        case
            when prefecture in ('北海道') then '北海道'
            when prefecture in ('青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県') then '東北'
            when prefecture in ('茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県') then '関東'
            when prefecture in ('新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県') then '中部'
            when prefecture in ('三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県') then '関西'
            when prefecture in ('鳥取県', '島根県', '岡山県', '広島県', '山口県') then '中国'
            when prefecture in ('徳島県', '香川県', '愛媛県', '高知県') then '四国'
            when prefecture in ('福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県') then '九州・沖縄'
            else 'その他'
        end as region

    from source
),

with_quality as (
    select
        *,

        -- データ品質フラグ（DB 制約に頼れないビジネスルールを検証）
        -- 形式・値域に関する検証のみを is_valid_record に集中させる。
        case
            -- 郵便番号は 7 桁数字（ハイフン有無は問わない）
            when postal_code !~ '^[0-9]{3}-?[0-9]{4}$' then false
            -- 住所詳細が空文字列のみ
            when trim(address_line1) = '' then false
            -- 都道府県が 47 都道府県以外（region 判定で「その他」になるケース）
            when region = 'その他' then false
            else true
        end as is_valid_record

    from cleaned
)

select * from with_quality
