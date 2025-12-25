defmodule DecisionLog.Demo do
  @moduledoc """
  Demo module showcasing decision logging across different Elixir constructs.

  This module demonstrates how to log decisions in:
  - `if/else` expressions
  - `case` expressions
  - `cond` expressions
  - `with` expressions
  - Pattern matching in function heads

  Three implementations are provided:
  - `DecisionLog.Demo.Implicit` - Using process dictionary API
  - `DecisionLog.Demo.Explicit` - Using functional/explicit API
  - `DecisionLog.Demo.Decorated` - Using the @decorate decorator

  All implementations produce identical logs for the same inputs.
  """
end

defmodule DecisionLog.Demo.Implicit do
  @moduledoc """
  Demo using the implicit DecisionLog API (process dictionary).
  """

  @doc """
  Process an order through validation, pricing, and fulfillment.

  Demonstrates: if/else, case, cond, with, pattern matching
  """
  def process_order(order) do
    DecisionLog.start_tag(:validation)

    # Pattern matching extraction
    %{user_id: user_id, items: items, shipping: shipping} = order
    DecisionLog.log(:user_id, user_id)
    DecisionLog.log(:item_count, length(items))

    # if/else - check user status
    user_valid =
      if user_id > 0 do
        DecisionLog.log(:user_check, :valid)
        true
      else
        DecisionLog.log(:user_check, :invalid)
        false
      end

    # case - validate items
    items_status =
      case items do
        [] ->
          DecisionLog.log(:items_check, :empty_cart)
          :error

        [_single] ->
          DecisionLog.log(:items_check, :single_item)
          :ok

        _multiple ->
          DecisionLog.log(:items_check, :multiple_items)
          :ok
      end

    DecisionLog.tag(:pricing)

    # trace - log values in a pipeline and return the value
    total =
      items
      |> Enum.map(& &1.price)
      |> Enum.sum()
      |> DecisionLog.trace(:subtotal)

    discount =
      cond do
        total >= 100 ->
          DecisionLog.log(:discount_tier, :gold)
          0.20

        total >= 50 ->
          DecisionLog.log(:discount_tier, :silver)
          0.10

        total >= 25 ->
          DecisionLog.log(:discount_tier, :bronze)
          0.05

        true ->
          DecisionLog.log(:discount_tier, :none)
          0.0
      end

    final_total = total * (1 - discount)
    DecisionLog.log(:final_total, final_total)

    DecisionLog.tag(:fulfillment)

    # tagged - log and return tagged tuple for pattern matching in with
    # use {_, value} on happy path, tag in else to identify which step failed
    result =
      with {_, true} <- DecisionLog.tagged(user_valid, :user),
           {_, :ok} <- DecisionLog.tagged(items_status, :items),
           {_, :ok} <- DecisionLog.tagged(validate_shipping(shipping), :shipping) do
        DecisionLog.log(:fulfillment_status, :approved)
        {:ok, %{total: final_total, discount: discount}}
      else
        {:user, false} ->
          DecisionLog.log(:fulfillment_status, :rejected_user)
          {:error, :invalid_user}

        {:items, :error} ->
          DecisionLog.log(:fulfillment_status, :rejected_items)
          {:error, :invalid_items}

        {:shipping, {:error, reason}} ->
          DecisionLog.log(:fulfillment_status, {:rejected_shipping, reason})
          {:error, reason}
      end

    log = DecisionLog.close()
    {result, log}
  end

  defp validate_shipping(:standard), do: :ok
  defp validate_shipping(:express), do: :ok
  defp validate_shipping(other), do: {:error, {:invalid_shipping, other}}

  @doc """
  Demonstrates pattern matching in function heads.
  """
  def calculate_shipping(order)

  def calculate_shipping(%{shipping: :express, items: items}) when length(items) > 5 do
    DecisionLog.start_tag(:shipping)
    # Using log_all to log multiple related fields at once
    DecisionLog.log_all(method: :express, bulk_order: true, cost: 15.0)
    {15.0, DecisionLog.close()}
  end

  def calculate_shipping(%{shipping: :express}) do
    DecisionLog.start_tag(:shipping)
    DecisionLog.log_all(method: :express, bulk_order: false, cost: 25.0)
    {25.0, DecisionLog.close()}
  end

  def calculate_shipping(%{shipping: :standard}) do
    DecisionLog.start_tag(:shipping)
    DecisionLog.log(:method, :standard)
    DecisionLog.log(:cost, 5.0)
    {5.0, DecisionLog.close()}
  end

  def calculate_shipping(%{shipping: :pickup}) do
    DecisionLog.start_tag(:shipping)
    DecisionLog.log(:method, :pickup)
    DecisionLog.log(:cost, 0.0)
    {0.0, DecisionLog.close()}
  end
end

defmodule DecisionLog.Demo.Explicit do
  @moduledoc """
  Demo using the explicit DecisionLog.Explicit API (functional).
  """

  alias DecisionLog.Explicit, as: Log

  @doc """
  Process an order through validation, pricing, and fulfillment.
  """
  def process_order(order) do
    %{user_id: user_id, items: items, shipping: shipping} = order

    ctx =
      Log.new(:validation)
      |> Log.log(:user_id, user_id)
      |> Log.log(:item_count, length(items))

    # if/else - check user status
    {user_valid, ctx} =
      if user_id > 0 do
        {true, Log.log(ctx, :user_check, :valid)}
      else
        {false, Log.log(ctx, :user_check, :invalid)}
      end

    # case - validate items
    {items_status, ctx} =
      case items do
        [] ->
          {:error, Log.log(ctx, :items_check, :empty_cart)}

        [_single] ->
          {:ok, Log.log(ctx, :items_check, :single_item)}

        _multiple ->
          {:ok, Log.log(ctx, :items_check, :multiple_items)}
      end

    ctx = Log.tag(ctx, :pricing)

    # trace - log value in expression and return {value, ctx}
    {total, ctx} =
      items
      |> Enum.map(& &1.price)
      |> Enum.sum()
      |> then(&Log.trace(ctx, &1, :subtotal))

    {discount, ctx} =
      cond do
        total >= 100 ->
          {0.20, Log.log(ctx, :discount_tier, :gold)}

        total >= 50 ->
          {0.10, Log.log(ctx, :discount_tier, :silver)}

        total >= 25 ->
          {0.05, Log.log(ctx, :discount_tier, :bronze)}

        true ->
          {0.0, Log.log(ctx, :discount_tier, :none)}
      end

    final_total = total * (1 - discount)
    ctx = Log.log(ctx, :final_total, final_total)

    ctx = Log.tag(ctx, :fulfillment)

    # tagged - log and return {{tag, value}, ctx} for with statements
    {result, ctx} =
      with {{_, true}, ctx} <- Log.tagged(ctx, user_valid, :user),
           {{_, :ok}, ctx} <- Log.tagged(ctx, items_status, :items),
           {{_, :ok}, ctx} <- Log.tagged(ctx, validate_shipping(shipping), :shipping) do
        ctx = Log.log(ctx, :fulfillment_status, :approved)
        {{:ok, %{total: final_total, discount: discount}}, ctx}
      else
        {{:user, false}, ctx} ->
          ctx = Log.log(ctx, :fulfillment_status, :rejected_user)
          {{:error, :invalid_user}, ctx}

        {{:items, :error}, ctx} ->
          ctx = Log.log(ctx, :fulfillment_status, :rejected_items)
          {{:error, :invalid_items}, ctx}

        {{:shipping, {:error, reason}}, ctx} ->
          ctx = Log.log(ctx, :fulfillment_status, {:rejected_shipping, reason})
          {{:error, reason}, ctx}
      end

    log = Log.close(ctx)
    {result, log}
  end

  defp validate_shipping(:standard), do: :ok
  defp validate_shipping(:express), do: :ok
  defp validate_shipping(other), do: {:error, {:invalid_shipping, other}}

  @doc """
  Demonstrates pattern matching in function heads.
  """
  def calculate_shipping(order)

  def calculate_shipping(%{shipping: :express, items: items}) when length(items) > 5 do
    # Using log_all to log multiple related fields at once
    log =
      Log.new(:shipping)
      |> Log.log_all(method: :express, bulk_order: true, cost: 15.0)
      |> Log.close()

    {15.0, log}
  end

  def calculate_shipping(%{shipping: :express}) do
    log =
      Log.new(:shipping)
      |> Log.log_all(method: :express, bulk_order: false, cost: 25.0)
      |> Log.close()

    {25.0, log}
  end

  def calculate_shipping(%{shipping: :standard}) do
    log =
      Log.new(:shipping)
      |> Log.log(:method, :standard)
      |> Log.log(:cost, 5.0)
      |> Log.close()

    {5.0, log}
  end

  def calculate_shipping(%{shipping: :pickup}) do
    log =
      Log.new(:shipping)
      |> Log.log(:method, :pickup)
      |> Log.log(:cost, 0.0)
      |> Log.close()

    {0.0, log}
  end
end

defmodule DecisionLog.Demo.Decorated do
  @moduledoc """
  Demo using the @decorate decision_log() decorator.

  The decorator only adds a tag when entering a function.
  The caller is responsible for starting and closing the log.

  This module provides two APIs:
  - `process_order/1`, `calculate_shipping/1` - wrapper functions that
    manage the log lifecycle (for comparison with Implicit/Explicit)
  - `do_process_order/1`, `do_calculate_shipping/1` - decorated functions
    that can be called when caller manages the log
  """

  use DecisionLog.Decorator

  @doc """
  Process an order (manages log lifecycle for API compatibility).
  """
  def process_order(order) do
    DecisionLog.start()
    result = do_process_order(order)
    log = DecisionLog.close()
    {result, log}
  end

  @doc """
  Calculate shipping (manages log lifecycle for API compatibility).
  """
  def calculate_shipping(order) do
    DecisionLog.start()
    result = do_calculate_shipping(order)
    log = DecisionLog.close()
    {result, log}
  end

  # --- Decorated internal functions ---

  @doc """
  Process order logic with automatic tagging.
  Expects caller to have initialized the log.
  """
  @decorate decision_log(:validation)
  def do_process_order(order) do
    %{user_id: user_id, items: items, shipping: shipping} = order

    DecisionLog.log(:user_id, user_id)
    DecisionLog.log(:item_count, length(items))

    # if/else - check user status
    user_valid =
      if user_id > 0 do
        DecisionLog.log(:user_check, :valid)
        true
      else
        DecisionLog.log(:user_check, :invalid)
        false
      end

    # case - validate items
    items_status =
      case items do
        [] ->
          DecisionLog.log(:items_check, :empty_cart)
          :error

        [_single] ->
          DecisionLog.log(:items_check, :single_item)
          :ok

        _multiple ->
          DecisionLog.log(:items_check, :multiple_items)
          :ok
      end

    DecisionLog.tag(:pricing)

    # trace - log values in a pipeline and return the value
    total =
      items
      |> Enum.map(& &1.price)
      |> Enum.sum()
      |> DecisionLog.trace(:subtotal)

    discount =
      cond do
        total >= 100 ->
          DecisionLog.log(:discount_tier, :gold)
          0.20

        total >= 50 ->
          DecisionLog.log(:discount_tier, :silver)
          0.10

        total >= 25 ->
          DecisionLog.log(:discount_tier, :bronze)
          0.05

        true ->
          DecisionLog.log(:discount_tier, :none)
          0.0
      end

    final_total = total * (1 - discount)
    DecisionLog.log(:final_total, final_total)

    DecisionLog.tag(:fulfillment)

    # tagged - log and return tagged tuple for pattern matching in with
    with {_, true} <- DecisionLog.tagged(user_valid, :user),
         {_, :ok} <- DecisionLog.tagged(items_status, :items),
         {_, :ok} <- DecisionLog.tagged(validate_shipping(shipping), :shipping) do
      DecisionLog.log(:fulfillment_status, :approved)
      {:ok, %{total: final_total, discount: discount}}
    else
      {:user, false} ->
        DecisionLog.log(:fulfillment_status, :rejected_user)
        {:error, :invalid_user}

      {:items, :error} ->
        DecisionLog.log(:fulfillment_status, :rejected_items)
        {:error, :invalid_items}

      {:shipping, {:error, reason}} ->
        DecisionLog.log(:fulfillment_status, {:rejected_shipping, reason})
        {:error, reason}
    end
  end

  defp validate_shipping(:standard), do: :ok
  defp validate_shipping(:express), do: :ok
  defp validate_shipping(other), do: {:error, {:invalid_shipping, other}}

  @doc """
  Calculate shipping with automatic tagging.
  Expects caller to have initialized the log.
  """
  @decorate decision_log(:shipping)
  def do_calculate_shipping(order)

  def do_calculate_shipping(%{shipping: :express, items: items}) when length(items) > 5 do
    # Using log_all to log multiple related fields at once
    DecisionLog.log_all(method: :express, bulk_order: true, cost: 15.0)
    15.0
  end

  def do_calculate_shipping(%{shipping: :express}) do
    DecisionLog.log_all(method: :express, bulk_order: false, cost: 25.0)
    25.0
  end

  def do_calculate_shipping(%{shipping: :standard}) do
    DecisionLog.log(:method, :standard)
    DecisionLog.log(:cost, 5.0)
    5.0
  end

  def do_calculate_shipping(%{shipping: :pickup}) do
    DecisionLog.log(:method, :pickup)
    DecisionLog.log(:cost, 0.0)
    0.0
  end
end
