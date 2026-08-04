"""Step 2-c: customer_orders.sql に delete_condition を追加する。

Usage:
    uv run python utils/apply_delete_condition.py
"""

from _common import MODELS_MARTS, STEPS_DIR, copy_model_files, print_step


def main() -> None:
    print_step("customer_orders.sql に delete_condition を追加")
    copy_model_files(
        STEPS_DIR / "step2",
        {"customer_orders_delete.sql": MODELS_MARTS / "customer_orders.sql"},
    )
    print("\nDone!")


if __name__ == "__main__":
    main()
