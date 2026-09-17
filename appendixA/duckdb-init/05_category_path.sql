/*
category_path の生成（DuckDB 版のみ必要）

PostgreSQL 版ではトリガー trigger_category_path が LTREE 型の category_path を
INSERT / UPDATE のたびに自動生成していた。DuckDB にはトリガーも LTREE も無いため、
カテゴリ投入後に再帰 CTE でルートからのパスを組み立てて VARCHAR 列に書き込む。

出力形式は PostgreSQL の LTREE のテキスト表現に合わせる（例: electronics.computers）。
category_path は stg_zakka_mall__categories / dim_products が参照するため付録Aでも必須。
*/

SET search_path = 'zakka_mall';
SET TimeZone = 'UTC';

CREATE OR REPLACE TEMP TABLE category_paths AS
WITH RECURSIVE paths AS (
    SELECT
        category_id,
        category_code AS category_path
    FROM zakka_mall.category
    WHERE parent_category_id IS NULL

    UNION ALL

    SELECT
        child.category_id,
        parent.category_path || '.' || child.category_code AS category_path
    FROM zakka_mall.category AS child
    INNER JOIN paths AS parent
        ON child.parent_category_id = parent.category_id
)

SELECT
    category_id,
    category_path
FROM paths;

UPDATE zakka_mall.category
SET category_path = category_paths.category_path
FROM category_paths
WHERE zakka_mall.category.category_id = category_paths.category_id;

DROP TABLE category_paths;
