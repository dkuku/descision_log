defmodule DecisionLog.Serializer do
  @moduledoc """
  Serialization formats for decision logs.

  Provides different output formats for decision logs:

  - `:string` - The default format, returns a list of strings like `"section.key: value"`
  - `:map` - Returns a list of maps with `section`, `key`, and `value` fields (PostgreSQL jsonb-friendly)

  ## Configuration

  You can set the default format globally in your config:

      config :decision_log, :default_format, :map

  Or pass the format option to `close/1`:

      DecisionLog.close(format: :map)

  ## PostgreSQL Integration

  The `:map` format is designed for PostgreSQL `jsonb` columns where array order is preserved:

      # In your schema
      field :decision_log, {:array, :map}

      # Query examples
      # Find orders with a specific validation check
      from o in Order,
        where: fragment("? @> ?", o.decision_log, ^[%{section: "validation", key: "user_id"}])
  """

  @type format :: :string | :map
  @type entry :: {atom(), term()} | {atom(), term(), (term() -> String.t())}
  @type section :: {atom(), [entry()]}

  @doc """
  Serialize a decision log to the specified format.

  ## Options

    * `:format` - Output format, either `:string` (default) or `:map`
    * `:formatter` - A function `(term() -> String.t())` to format values.
      Only used with `:string` format. Defaults to `inspect/1`.

  ## Examples

      iex> log = [{:validation, [{:user_id, 123}, {:status, :ok}]}]
      iex> DecisionLog.Serializer.serialize(log, format: :string)
      ["validation.user_id: 123", "validation.status: :ok"]

      iex> log = [{:validation, [{:user_id, 123}, {:status, :ok}]}]
      iex> DecisionLog.Serializer.serialize(log, format: :map)
      [%{section: "validation", key: "user_id", value: 123},
       %{section: "validation", key: "status", value: :ok}]
  """
  @spec serialize([section()], keyword()) :: [String.t()] | [map()]
  def serialize(log, opts \\ []) do
    format = Keyword.get(opts, :format, default_format())
    formatter = Keyword.get(opts, :formatter, &inspect/1)

    do_serialize(log, format, formatter)
  end

  @doc """
  Returns the default serialization format.

  Can be configured via:

      config :decision_log, :default_format, :map

  Defaults to `:string` if not configured.
  """
  @spec default_format() :: format()
  def default_format do
    Application.get_env(:decision_log, :default_format, :string)
  end

  @doc """
  Serialize to string format.

  Returns a list of strings in the format `"section.key: formatted_value"`.
  """
  @spec to_string_format([section()], (term() -> String.t())) :: [String.t()]
  def to_string_format(log, formatter \\ &inspect/1) do
    do_serialize(log, :string, formatter)
  end

  @doc """
  Serialize to map format.

  Returns a list of maps with `section`, `key`, and `value` fields.
  This format is ideal for PostgreSQL jsonb storage where array order is preserved.
  """
  @spec to_map_format([section()]) :: [map()]
  def to_map_format(log) do
    do_serialize(log, :map, nil)
  end

  # Private implementation

  defp do_serialize(log, :string, formatter) do
    Enum.flat_map(log, fn {section_name, entries} ->
      Enum.map(entries, fn entry ->
        serialize_string_entry(section_name, entry, formatter)
      end)
    end)
  end

  defp do_serialize(log, :map, _formatter) do
    Enum.flat_map(log, fn {section_name, entries} ->
      Enum.map(entries, fn entry ->
        serialize_map_entry(section_name, entry)
      end)
    end)
  end

  # String format serialization

  defp serialize_string_entry(section_name, {label, value, entry_formatter}, _default_formatter) do
    "#{section_name}.#{label}: #{entry_formatter.(value)}"
  end

  defp serialize_string_entry(section_name, {label, value}, default_formatter) do
    "#{section_name}.#{label}: #{default_formatter.(value)}"
  end

  # Map format serialization

  defp serialize_map_entry(section_name, {label, value, _formatter}) do
    %{
      section: to_string(section_name),
      key: to_string(label),
      value: normalize_value(value)
    }
  end

  defp serialize_map_entry(section_name, {label, value}) do
    %{
      section: to_string(section_name),
      key: to_string(label),
      value: normalize_value(value)
    }
  end

  # Normalize values for JSON compatibility
  defp normalize_value(value) when is_atom(value), do: to_string(value)
  defp normalize_value(%Date{} = date), do: Date.to_iso8601(date)
  defp normalize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp normalize_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp normalize_value(%Time{} = time), do: Time.to_iso8601(time)

  defp normalize_value(%{__struct__: _} = struct) do
    if impl_string_chars?(struct) do
      to_string(struct)
    else
      struct
      |> Map.from_struct()
      |> normalize_value()
    end
  end

  defp normalize_value(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize_value(v)} end)
  end

  defp normalize_value(list) when is_list(list) do
    Enum.map(list, &normalize_value/1)
  end

  defp normalize_value(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> normalize_value()
  end

  defp normalize_value(value), do: value

  defp impl_string_chars?(value) do
    String.Chars.impl_for(value) != nil
  end
end
