-- Singular Test: 顧客の年齢と生年月日の整合性検証
--
-- ビジネスルール:
-- 顧客の年齢 (age) は生年月日 (birth_date) から計算した年齢と一致する必要がある。
-- データ入力エラーや更新タイミングのずれを検出する。

with checked as (
    select
        customer_id,
        customer_name,
        birth_date,
        age as recorded_age,
        -- 生年月日から「今日時点」の年齢を再計算
        -- doy（年内通算日）の比較で誕生日未到来なら 1 を引く
        date_part('year', {{ book_current_date() }}) - date_part('year', birth_date::date)
        - case
            when date_part('doy', {{ book_current_date() }}) < date_part('doy', birth_date::date)
                then 1
            else 0
        end as calculated_age
    from {{ ref('stg_zakka_mall__customers') }}
    where
        birth_date is not null
        and age is not null
)

select
    customer_id,
    customer_name,
    birth_date,
    recorded_age,
    calculated_age,
    recorded_age - calculated_age as age_difference
from checked
where abs(recorded_age - calculated_age) > 1  -- 1 歳以上の差異があるケースを検出
