defmodule DecisionLog.Explicit do
  @moduledoc """
  Explicit decision log without hidden state.

  All functions take and return the log context explicitly,
  making it easy to pass through function calls and test.

  ## Example

      iex> context = DecisionLog.Explicit.new(:section_a)
      iex> context = DecisionLog.Explicit.log(context, :first, "value1")
      iex> context = DecisionLog.Explicit.log(context, :second, "value2")
      iex> context = DecisionLog.Explicit.tag(context, :section_b)
      iex> context = DecisionLog.Explicit.log(context, :other_step, "value")
      iex> DecisionLog.Explicit.close(context)
      ["section_a_first: \"value1\"", "section_a_second: \"value2\"", "section_b_other_step: \"value\""]
  """

  @type step :: {atom(), term()}
  @type section :: {atom(), [step()]}
  @type t :: [section()]

  @doc "Create a new empty decision log context"
  @spec new() :: t()
  def new do
    []
  end

  @doc "Create a new decision log context with an initial tag"
  @spec new(atom()) :: t()
  def new(label) when is_atom(label) do
    [{label, []}]
  end

  @doc "Add a new tagged section to the log"
  @spec tag(t(), atom()) :: t()
  def tag(context, label) when is_atom(label) do
    [{label, []} | context]
  end

  @doc "Log a value with an explicit label to the current section"
  @spec log(t(), atom(), term()) :: t()
  def log(context, label, value) when is_atom(label) do
    [{current_label, steps} | rest] = context
    [{current_label, [{label, value} | steps]} | rest]
  end

  @doc "Log a value with an auto-generated step label"
  @spec log(t(), term()) :: t()
  def log(context, value) do
    [{current_label, steps} | rest] = context
    label = get_label(steps)
    [{current_label, [{label, value} | steps]} | rest]
  end

  @doc """
  Log multiple key-value pairs at once.

  ## Example

      ctx = Explicit.log_all(ctx, input_start_date: date, provider_id: 123)
  """
  @spec log_all(t(), keyword()) :: t()
  def log_all(context, items) when is_list(items) do
    [{current_label, steps} | rest] = context

    new_steps =
      Enum.reduce(items, steps, fn {label, value}, acc ->
        [{label, value} | acc]
      end)

    [{current_label, new_steps} | rest]
  end

  @doc """
  Log a value and return both the value and updated context.
  Useful for threading context while also using the value.

  ## Examples

      # Pattern matching
      {user_valid, ctx} = Explicit.trace(ctx, check_user(input), :user_valid)

      # In with statements
      with {true, ctx} <- Explicit.trace(ctx, check_user(input), :user_valid),
           {:ok, ctx} <- Explicit.trace(ctx, validate_items(items), :items_check) do
        {{:ok, result}, ctx}
      end
  """
  @spec trace(t(), term(), atom()) :: {term(), t()}
  def trace(context, value, label) when is_atom(label) do
    [{current_label, steps} | rest] = context
    updated = [{current_label, [{label, value} | steps]} | rest]
    {value, updated}
  end

  @spec trace(t(), term()) :: {term(), t()}
  def trace(context, value) do
    [{current_label, steps} | rest] = context
    label = get_label(steps)
    updated = [{current_label, [{label, value} | steps]} | rest]
    {value, updated}
  end

  @doc """
  Log a value and return it as a tagged tuple with the updated context.
  Useful in `with` statements when threading context.

  ## Examples

      with {{:user, user}, ctx} <- Explicit.tagged(ctx, get_user(id), :user),
           {{:order, order}, ctx} <- Explicit.tagged(ctx, get_order(user), :order) do
        {{:ok, process(user, order)}, ctx}
      end
  """
  @spec tagged(t(), term(), atom()) :: {{atom(), term()}, t()}
  def tagged(context, value, label) when is_atom(label) do
    [{current_label, steps} | rest] = context
    updated = [{current_label, [{label, value} | steps]} | rest]
    {{label, value}, updated}
  end

  @doc """
  Log multiple key-value pairs and return both the items and updated context.

  ## Example

      {params, ctx} = Explicit.trace_all(ctx, method: "POST", path: "/api")
  """
  @spec trace_all(t(), keyword()) :: {keyword(), t()}
  def trace_all(context, items) when is_list(items) do
    [{current_label, steps} | rest] = context

    new_steps =
      Enum.reduce(items, steps, fn {label, value}, acc ->
        [{label, value} | acc]
      end)

    {items, [{current_label, new_steps} | rest]}
  end

  @doc """
  Close the log and return formatted output strings.

  ## Options

    * `:formatter` - A function `(term() -> String.t())` to format values.
      Defaults to `inspect/1`.

  ## Examples

      # Default formatting
      Explicit.close(context)

      # Custom formatter
      Explicit.close(context, formatter: &my_pretty_formatter/1)
  """
  @spec close(t(), keyword()) :: [String.t()]
  def close(context, opts \\ []) do
    formatter = Keyword.get(opts, :formatter, &inspect/1)

    context
    |> view()
    |> Enum.flat_map(fn {step_name, steps} ->
      Enum.map(steps, fn {label, value} ->
        serialize(step_name, label, value, formatter)
      end)
    end)
  end

  @doc "Get the current log in a readable format"
  @spec get(t()) :: t()
  def get(context) do
    view(context)
  end

  @doc "Transform log to chronological order"
  @spec view(t()) :: t()
  def view(context) do
    context
    |> Enum.map(fn {label, steps} -> {label, Enum.reverse(steps)} end)
    |> Enum.reverse()
  end

  defp serialize(step_name, label, value, formatter) do
    "#{step_name}_#{label}: #{formatter.(value)}"
  end

  @doc """
  Wrap a function with automatic decision log handling.

  Creates a new context with the given tag, passes it to the function,
  and returns both the function result and the closed log.

  The function receives the context and should return `{result, updated_context}`.

  ## Options

    * `:formatter` - A function `(term() -> String.t())` to format values.
      Defaults to `inspect/1`.

  ## Examples

      {result, log} = Explicit.wrap(:order, fn ctx ->
        ctx = Explicit.log(ctx, :status, :ok)
        {{:ok, 42}, ctx}
      end)

      # With custom formatter
      {result, log} = Explicit.wrap(:order, fn ctx ->
        ctx = Explicit.log(ctx, :date, ~D[2025-01-01])
        {:ok, ctx}
      end, formatter: &Date.to_string/1)

  Returns `{function_result, decision_log}`.
  """
  @spec wrap(atom(), (t() -> {result, t()}), keyword()) :: {result, [String.t()]}
        when result: term()
  def wrap(tag, fun, opts \\ []) when is_atom(tag) and is_function(fun, 1) do
    context = new(tag)
    {result, final_context} = fun.(context)
    log = close(final_context, opts)
    {result, log}
  end

  defp get_label(steps) do
    String.to_atom("step_#{Enum.count(steps)}")
  end
end
