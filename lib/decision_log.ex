defmodule DecisionLog do
  @moduledoc """
  Decision log for tracking decisions made during processing.

  ## Basic Example

      iex> DecisionLog.start_tag(:section_a)
      iex> DecisionLog.log(:first, "value1")
      iex> DecisionLog.log(:second, "value2")
      iex> DecisionLog.tag(:section_b)
      iex> DecisionLog.log(:other_step, "value")
      iex> DecisionLog.close()
      ["section_a_first: \"value1\"", "section_a_second: \"value2\"", "section_b_other_step: \"value\""]

  ## Simplified Usage with wrap/2

  For reduced friction, use `wrap/2` which handles lifecycle automatically:

      iex> {result, log} = DecisionLog.wrap(:order, fn ->
      ...>   DecisionLog.log(:status, :ok)
      ...>   {:ok, 42}
      ...> end)
      iex> result
      {:ok, 42}
      iex> log
      ["order_status: :ok"]

  ## Auto-start with log!/2 and log!/3

  For fire-and-forget logging that auto-initializes:

      iex> DecisionLog.log!(:validation, :passed)
      iex> DecisionLog.log!(:auth, :user_check, :valid)
      iex> DecisionLog.close()
      ["default_validation: :passed", "auth_user_check: :valid"]
  """

  @key :decision_log
  @default_tag :default

  @doc "Start a new decision log context"
  def start do
    Process.put(@key, [])
  end

  def start_tag(label) do
    Process.put(@key, [{label, []}])
  end

  def tag(label) when is_atom(label) do
    case Process.get(@key) do
      nil ->
        raise ArgumentError,
              "DecisionLog not initialized. Call DecisionLog.start() or DecisionLog.start_tag/1 first."

      log ->
        Process.put(@key, [{label, []} | log])
    end
  end

  @doc false
  # Silent version for decorator - no-op if log not initialized
  def maybe_tag(label) when is_atom(label) do
    case Process.get(@key) do
      nil -> :ok
      log -> Process.put(@key, [{label, []} | log])
    end
  end

  @doc """
  Log a single key-value pair.

  ## Examples

      # Explicit label and value
      DecisionLog.log(:status, :ok)

      # Single value with auto-generated label (step_0, step_1, etc.)
      DecisionLog.log("some value")

      # With custom formatter
      DecisionLog.log(:benefit, benefit, &format_benefit/1)
  """
  def log(label, value, formatter) when is_atom(label) and is_function(formatter, 1) do
    case Process.get(@key) do
      nil ->
        :ok

      [{current_label, steps} | rest] ->
        Process.put(@key, [{current_label, [{label, value, formatter} | steps]} | rest])
    end
  end

  def log(label, value) when is_atom(label) do
    case Process.get(@key) do
      nil ->
        :ok

      [{current_label, steps} | rest] ->
        Process.put(@key, [{current_label, [{label, value} | steps]} | rest])
    end
  end

  def log(value) do
    case Process.get(@key) do
      nil ->
        :ok

      [{current_label, steps} | rest] ->
        label = get_label(steps)
        Process.put(@key, [{current_label, [{label, value} | steps]} | rest])
    end
  end

  @doc """
  Log multiple key-value pairs at once.

  ## Example

      DecisionLog.log_all(input_start_date: date, provider_id: 123, time_zone: "UTC")
  """
  def log_all(items) when is_list(items) do
    case Process.get(@key) do
      nil ->
        :ok

      [{current_label, steps} | rest] ->
        new_steps =
          Enum.reduce(items, steps, fn {label, value}, acc ->
            [{label, value} | acc]
          end)

        Process.put(@key, [{current_label, new_steps} | rest])
    end
  end

  @doc """
  Log a value and return it. Useful in pipes and `with` statements.

  ## Examples

      # In pipes
      input
      |> transform()
      |> trace(:after_transform)
      |> process()

      # In with statements
      with true <- trace(check_user(input), :user_valid),
           :ok <- trace(validate_items(items), :items_check) do
        {:ok, result}
      end

      # Single value with auto-generated label
      trace("some value")

      # With custom formatter for this specific value
      benefit
      |> trace(:benefit, &format_benefit/1)
  """
  def trace(value, label, formatter) when is_atom(label) and is_function(formatter, 1) do
    case Process.get(@key) do
      nil ->
        value

      [{current_label, steps} | rest] ->
        Process.put(@key, [{current_label, [{label, value, formatter} | steps]} | rest])
        value
    end
  end

  def trace(value, label) when is_atom(label) do
    case Process.get(@key) do
      nil ->
        value

      [{current_label, steps} | rest] ->
        Process.put(@key, [{current_label, [{label, value} | steps]} | rest])
        value
    end
  end

  def trace(value) do
    case Process.get(@key) do
      nil ->
        value

      [{current_label, steps} | rest] ->
        label = get_label(steps)
        Process.put(@key, [{current_label, [{label, value} | steps]} | rest])
        value
    end
  end

  @doc """
  Log a value and return it as a tagged tuple. Useful in `with` statements.

  ## Examples

      with {:user, user} <- tagged(get_user(id), :user),
           {:order, order} <- tagged(get_order(user), :order) do
        {:ok, process(user, order)}
      end

      # With custom formatter
      with {:benefit, true} <- tagged(benefit_available?(b), :benefit, &inspect/1) do
        :ok
      end
  """
  def tagged(value, label, formatter) when is_atom(label) and is_function(formatter, 1) do
    case Process.get(@key) do
      nil ->
        {label, value}

      [{current_label, steps} | rest] ->
        Process.put(@key, [{current_label, [{label, value, formatter} | steps]} | rest])
        {label, value}
    end
  end

  def tagged(value, label) when is_atom(label) do
    case Process.get(@key) do
      nil ->
        {label, value}

      [{current_label, steps} | rest] ->
        Process.put(@key, [{current_label, [{label, value} | steps]} | rest])
        {label, value}
    end
  end

  @doc """
  Log multiple key-value pairs at once and return them.

  ## Example

      trace_all(method: "POST", path: "/api/orders")
      |> do_something_with_params()
  """
  def trace_all(items) when is_list(items) do
    case Process.get(@key) do
      nil ->
        items

      [{current_label, steps} | rest] ->
        new_steps =
          Enum.reduce(items, steps, fn {label, value}, acc ->
            [{label, value} | acc]
          end)

        Process.put(@key, [{current_label, new_steps} | rest])
        items
    end
  end

  @doc """
  Close the log and return formatted output strings.

  ## Options

    * `:formatter` - A function `(term() -> String.t())` to format values.
      Defaults to `inspect/1`. This is used as the default formatter for entries
      that don't have a per-entry formatter specified.

  ## Per-entry formatters

  When using `log/3`, `trace/3`, or `tagged/3` with a formatter argument,
  that formatter takes precedence over the default formatter passed to `close/1`.

  ## Examples

      # Default formatting
      DecisionLog.close()

      # Custom default formatter
      DecisionLog.close(formatter: &my_pretty_formatter/1)

      # Per-entry formatters override the default
      DecisionLog.trace(benefit, :benefit, &format_benefit/1)
      DecisionLog.trace(date, :date)  # uses default formatter
      DecisionLog.close(formatter: &inspect/1)
  """
  def close(opts \\ []) do
    log = Process.get(@key, [])
    Process.delete(@key)
    default_formatter = Keyword.get(opts, :formatter, &inspect/1)

    log
    |> view()
    |> Enum.flat_map(fn {step_name, steps} ->
      Enum.map(steps, fn entry ->
        serialize(step_name, entry, default_formatter)
      end)
    end)
  end

  defp serialize(step_name, {label, value, formatter}, _default_formatter) do
    "#{step_name}_#{label}: #{formatter.(value)}"
  end

  defp serialize(step_name, {label, value}, default_formatter) do
    "#{step_name}_#{label}: #{default_formatter.(value)}"
  end

  def get do
    log = Process.get(@key, [])
    view(log)
  end

  def view(log) do
    log
    |> Enum.map(fn {label, steps} -> {label, Enum.reverse(steps)} end)
    |> Enum.reverse()
  end

  @doc """
  Wrap a function with automatic decision log lifecycle management.

  Starts a new log with the given tag, executes the function, and returns
  both the function result and the closed log.

  ## Options

    * `:formatter` - A function `(term() -> String.t())` to format values.
      Defaults to `inspect/1`.

  ## Examples

      {result, log} = DecisionLog.wrap(:order_processing, fn ->
        DecisionLog.log(:validation, :passed)
        DecisionLog.tag(:pricing)
        DecisionLog.log(:total, 100)
        {:ok, order}
      end)

      # With custom formatter
      {result, log} = DecisionLog.wrap(:order, fn ->
        DecisionLog.log(:date, ~D[2025-01-01])
        :ok
      end, formatter: &Date.to_string/1)

  Returns `{function_result, decision_log}`.
  """
  @spec wrap(atom(), (-> result), keyword()) :: {result, [String.t()]} when result: term()
  def wrap(tag, fun, opts \\ []) when is_atom(tag) and is_function(fun, 0) do
    start_tag(tag)

    try do
      result = fun.()
      log = close(opts)
      {result, log}
    rescue
      e ->
        close()
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Log a value with auto-initialization.

  If no decision log exists, automatically starts one with a default tag.
  This enables fire-and-forget logging without explicit setup.

  ## Example

      DecisionLog.log!(:user_check, :valid)
      DecisionLog.log!(:items_check, :passed)
      log = DecisionLog.close()
  """
  @spec log!(atom(), term()) :: :ok
  def log!(label, value) when is_atom(label) do
    ensure_started()
    log(label, value)
  end

  @doc """
  Log a value with a tag and auto-initialization.

  If no decision log exists, automatically starts one. Creates or switches
  to the given tag section, then logs the value.

  ## Example

      DecisionLog.log!(:validation, :user_check, :valid)
      DecisionLog.log!(:validation, :schema_check, :passed)
      DecisionLog.log!(:pricing, :discount, :gold)
      log = DecisionLog.close()
  """
  @spec log!(atom(), atom(), term()) :: :ok
  def log!(tag, label, value) when is_atom(tag) and is_atom(label) do
    ensure_started()
    ensure_tag(tag)
    log(label, value)
  end

  @doc "Check if a decision log is currently active"
  @spec active?() :: boolean()
  def active? do
    Process.get(@key) != nil
  end

  defp ensure_started do
    case Process.get(@key) do
      nil -> start_tag(@default_tag)
      _ -> :ok
    end
  end

  defp ensure_tag(tag) do
    case Process.get(@key) do
      [{^tag, _} | _] -> :ok
      _ -> tag(tag)
    end
  end

  defp get_label(steps) do
    String.to_atom("step_#{Enum.count(steps)}")
  end
end
