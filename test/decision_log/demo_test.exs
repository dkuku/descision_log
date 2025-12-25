defmodule DecisionLog.DemoTest do
  use ExUnit.Case, async: true

  alias DecisionLog.Demo.Decorated
  alias DecisionLog.Demo.Explicit
  alias DecisionLog.Demo.Implicit

  # Test fixtures
  defp valid_order do
    %{
      user_id: 123,
      items: [
        %{name: "Widget", price: 30},
        %{name: "Gadget", price: 45}
      ],
      shipping: :standard
    }
  end

  defp empty_cart_order do
    %{
      user_id: 456,
      items: [],
      shipping: :standard
    }
  end

  defp high_value_order do
    %{
      user_id: 789,
      items: [
        %{name: "Premium Widget", price: 150}
      ],
      shipping: :express
    }
  end

  defp bulk_order do
    %{
      user_id: 100,
      items: Enum.map(1..10, fn i -> %{name: "Item #{i}", price: 10} end),
      shipping: :express
    }
  end

  defp invalid_shipping_order do
    %{
      user_id: 200,
      items: [%{name: "Thing", price: 20}],
      shipping: :drone
    }
  end

  describe "process_order - all implementations produce identical logs" do
    test "valid order with silver discount" do
      order = valid_order()

      {result_implicit, log_implicit} = Implicit.process_order(order)
      {result_explicit, log_explicit} = Explicit.process_order(order)
      {result_decorated, log_decorated} = Decorated.process_order(order)

      # Results should be identical
      assert result_implicit == result_explicit
      assert result_explicit == result_decorated

      # Logs should be identical
      assert log_implicit == log_explicit
      assert log_explicit == log_decorated

      # Verify expected log content
      assert {:ok, %{total: 67.5, discount: 0.10}} = result_implicit

      assert log_implicit == [
               "validation_user_id: 123",
               "validation_item_count: 2",
               "validation_user_check: :valid",
               "validation_items_check: :multiple_items",
               "pricing_subtotal: 75",
               "pricing_discount_tier: :silver",
               "pricing_final_total: 67.5",
               "fulfillment_user: true",
               "fulfillment_items: :ok",
               "fulfillment_shipping: :ok",
               "fulfillment_fulfillment_status: :approved"
             ]
    end

    test "empty cart order" do
      order = empty_cart_order()

      {result_implicit, log_implicit} = Implicit.process_order(order)
      {result_explicit, log_explicit} = Explicit.process_order(order)
      {result_decorated, log_decorated} = Decorated.process_order(order)

      # All should return same error
      assert result_implicit == {:error, :invalid_items}
      assert result_implicit == result_explicit
      assert result_explicit == result_decorated

      # All logs should be identical
      assert log_implicit == log_explicit
      assert log_explicit == log_decorated

      # Verify rejection is logged
      assert "fulfillment_fulfillment_status: :rejected_items" in log_implicit
    end

    test "high value order with gold discount" do
      order = high_value_order()

      {result_implicit, log_implicit} = Implicit.process_order(order)
      {result_explicit, log_explicit} = Explicit.process_order(order)
      {result_decorated, log_decorated} = Decorated.process_order(order)

      assert result_implicit == result_explicit
      assert result_explicit == result_decorated

      assert log_implicit == log_explicit
      assert log_explicit == log_decorated

      assert {:ok, %{discount: 0.20}} = result_implicit
      assert "pricing_discount_tier: :gold" in log_implicit
    end

    test "invalid shipping order" do
      order = invalid_shipping_order()

      {result_implicit, log_implicit} = Implicit.process_order(order)
      {result_explicit, log_explicit} = Explicit.process_order(order)
      {result_decorated, log_decorated} = Decorated.process_order(order)

      assert result_implicit == {:error, {:invalid_shipping, :drone}}
      assert result_implicit == result_explicit
      assert result_explicit == result_decorated

      assert log_implicit == log_explicit
      assert log_explicit == log_decorated
    end
  end

  describe "calculate_shipping - pattern matching function heads" do
    test "express shipping for small order" do
      order = %{shipping: :express, items: [%{price: 10}]}

      {cost_implicit, log_implicit} = Implicit.calculate_shipping(order)
      {cost_explicit, log_explicit} = Explicit.calculate_shipping(order)
      {cost_decorated, log_decorated} = Decorated.calculate_shipping(order)

      assert cost_implicit == 25.0
      assert cost_implicit == cost_explicit
      assert cost_explicit == cost_decorated

      assert log_implicit == log_explicit
      assert log_explicit == log_decorated

      assert log_implicit == [
               "shipping_method: :express",
               "shipping_bulk_order: false",
               "shipping_cost: 25.0"
             ]
    end

    test "express shipping for bulk order (>5 items)" do
      order = bulk_order()

      {cost_implicit, log_implicit} = Implicit.calculate_shipping(order)
      {cost_explicit, log_explicit} = Explicit.calculate_shipping(order)
      {cost_decorated, log_decorated} = Decorated.calculate_shipping(order)

      assert cost_implicit == 15.0
      assert cost_implicit == cost_explicit
      assert cost_explicit == cost_decorated

      assert log_implicit == log_explicit
      assert log_explicit == log_decorated

      assert "shipping_bulk_order: true" in log_implicit
    end

    test "standard shipping" do
      order = %{shipping: :standard}

      {cost_implicit, log_implicit} = Implicit.calculate_shipping(order)
      {cost_explicit, log_explicit} = Explicit.calculate_shipping(order)
      {cost_decorated, log_decorated} = Decorated.calculate_shipping(order)

      assert cost_implicit == 5.0
      assert cost_implicit == cost_explicit
      assert cost_explicit == cost_decorated

      assert log_implicit == log_explicit
      assert log_explicit == log_decorated

      assert log_implicit == [
               "shipping_method: :standard",
               "shipping_cost: 5.0"
             ]
    end

    test "pickup - no shipping cost" do
      order = %{shipping: :pickup}

      {cost_implicit, log_implicit} = Implicit.calculate_shipping(order)
      {cost_explicit, log_explicit} = Explicit.calculate_shipping(order)
      {cost_decorated, log_decorated} = Decorated.calculate_shipping(order)

      assert cost_implicit == 0.0
      assert cost_implicit == cost_explicit
      assert cost_explicit == cost_decorated

      assert log_implicit == log_explicit
      assert log_explicit == log_decorated
    end
  end

  describe "log structure verification" do
    test "logs contain all expected sections" do
      order = valid_order()
      {_result, log} = Implicit.process_order(order)

      sections =
        log
        |> Enum.map(&String.split(&1, "_", parts: 2))
        |> Enum.map(&hd/1)
        |> Enum.uniq()

      assert sections == ["validation", "pricing", "fulfillment"]
    end

    test "logs are in chronological order" do
      order = valid_order()
      {_result, log} = Implicit.process_order(order)

      # First entries should be validation
      assert String.starts_with?(Enum.at(log, 0), "validation_")

      # Find where pricing starts
      pricing_idx = Enum.find_index(log, &String.starts_with?(&1, "pricing_"))
      fulfillment_idx = Enum.find_index(log, &String.starts_with?(&1, "fulfillment_"))

      assert pricing_idx < fulfillment_idx
    end
  end
end
