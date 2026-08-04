-- 本書独自の current_date ラッパーマクロ
--
-- モデル内で {{ book_current_date() }} を使用することで、Unit Test 時に
-- overrides 機能で日付を固定できます（通常実行時はデータベースの current_date を返します）。
{% macro book_current_date() %}
  CAST(current_date as date)
{% endmacro %}
