defmodule DecisionLog.SerializerTest do
  use ExUnit.Case, async: true

  alias DecisionLog.Serializer

  describe "serialize/2 with :string format" do
    test "serializes simple entries" do
      log = [{:validation, [{:user_id, 123}, {:status, :ok}]}]

      result = Serializer.serialize(log, format: :string)

      assert result == [
               "validation.user_id: 123",
               "validation.status: :ok"
             ]
    end

    test "uses default inspect formatter" do
      log = [{:section, [{:key, "string value"}]}]

      result = Serializer.serialize(log, format: :string)

      assert result == ["section.key: \"string value\""]
    end

    test "uses custom formatter" do
      log = [{:section, [{:date, ~D[2025-01-15]}]}]

      result = Serializer.serialize(log, format: :string, formatter: &Date.to_string/1)

      assert result == ["section.date: 2025-01-15"]
    end

    test "per-entry formatter overrides default formatter" do
      log = [{:section, [{:date, ~D[2025-01-15], &Date.to_string/1}, {:count, 42}]}]

      result = Serializer.serialize(log, format: :string, formatter: fn _ -> "DEFAULT" end)

      assert result == ["section.date: 2025-01-15", "section.count: DEFAULT"]
    end

    test "handles multiple sections" do
      log = [
        {:validation, [{:user_id, 123}]},
        {:pricing, [{:total, 100}]}
      ]

      result = Serializer.serialize(log, format: :string)

      assert result == [
               "validation.user_id: 123",
               "pricing.total: 100"
             ]
    end

    test "handles empty log" do
      assert Serializer.serialize([], format: :string) == []
    end

    test "handles empty section" do
      log = [{:section, []}]

      assert Serializer.serialize(log, format: :string) == []
    end
  end

  describe "serialize/2 with :map format" do
    test "serializes simple entries to maps" do
      log = [{:validation, [{:user_id, 123}, {:status, :ok}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [
               %{section: "validation", key: "user_id", value: 123},
               %{section: "validation", key: "status", value: "ok"}
             ]
    end

    test "converts atoms to strings in values" do
      log = [{:section, [{:status, :approved}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "status", value: "approved"}]
    end

    test "converts dates to ISO8601 strings" do
      log = [{:section, [{:date, ~D[2025-01-15]}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "date", value: "2025-01-15"}]
    end

    test "converts datetimes to ISO8601 strings" do
      log = [{:section, [{:timestamp, ~U[2025-01-15 10:30:00Z]}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "timestamp", value: "2025-01-15T10:30:00Z"}]
    end

    test "converts naive datetimes to ISO8601 strings" do
      log = [{:section, [{:timestamp, ~N[2025-01-15 10:30:00]}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "timestamp", value: "2025-01-15T10:30:00"}]
    end

    test "converts times to ISO8601 strings" do
      log = [{:section, [{:time, ~T[10:30:00]}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "time", value: "10:30:00"}]
    end

    test "handles nested maps" do
      log = [{:section, [{:data, %{name: "test", count: 5}}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "data", value: %{"name" => "test", "count" => 5}}]
    end

    test "handles lists" do
      log = [{:section, [{:items, [1, 2, 3]}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "items", value: [1, 2, 3]}]
    end

    test "handles lists with atoms" do
      log = [{:section, [{:statuses, [:ok, :pending, :done]}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "statuses", value: ["ok", "pending", "done"]}]
    end

    test "handles tuples by converting to lists" do
      log = [{:section, [{:pair, {:a, :b}}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "pair", value: ["a", "b"]}]
    end

    test "handles multiple sections" do
      log = [
        {:validation, [{:user_id, 123}]},
        {:pricing, [{:total, 100}]}
      ]

      result = Serializer.serialize(log, format: :map)

      assert result == [
               %{section: "validation", key: "user_id", value: 123},
               %{section: "pricing", key: "total", value: 100}
             ]
    end

    test "ignores per-entry formatter (uses value normalization instead)" do
      log = [{:section, [{:date, ~D[2025-01-15], &Date.to_string/1}]}]

      result = Serializer.serialize(log, format: :map)

      # The formatter is ignored, value is normalized via normalize_value
      assert result == [%{section: "section", key: "date", value: "2025-01-15"}]
    end

    test "handles empty log" do
      assert Serializer.serialize([], format: :map) == []
    end

    test "handles empty section" do
      log = [{:section, []}]

      assert Serializer.serialize(log, format: :map) == []
    end

    test "result is JSON encodable" do
      log = [
        {:validation, [{:user_id, 123}, {:date, ~D[2025-01-15]}]},
        {:pricing, [{:items, [:a, :b]}, {:total, 99.99}]}
      ]

      result = Serializer.serialize(log, format: :map)

      json = JSON.encode!(result)
      assert is_binary(json)

      decoded = JSON.decode!(json)
      assert is_list(decoded)
      assert length(decoded) == 4
    end
  end

  describe "serialize/2 default format" do
    test "defaults to :string format" do
      log = [{:section, [{:key, 123}]}]

      result = Serializer.serialize(log)

      assert result == ["section.key: 123"]
    end
  end

  describe "to_string_format/2" do
    test "serializes to string format" do
      log = [{:section, [{:key, 123}]}]

      result = Serializer.to_string_format(log)

      assert result == ["section.key: 123"]
    end

    test "accepts custom formatter" do
      log = [{:section, [{:date, ~D[2025-01-15]}]}]

      result = Serializer.to_string_format(log, &Date.to_string/1)

      assert result == ["section.date: 2025-01-15"]
    end
  end

  describe "to_map_format/1" do
    test "serializes to map format" do
      log = [{:section, [{:key, 123}]}]

      result = Serializer.to_map_format(log)

      assert result == [%{section: "section", key: "key", value: 123}]
    end
  end

  describe "default_format/0" do
    test "returns :string by default" do
      assert Serializer.default_format() == :string
    end
  end

  describe "struct handling" do
    defmodule TestStruct do
      defstruct [:id, :name]
    end

    test "converts structs without String.Chars to maps" do
      log = [{:section, [{:item, %TestStruct{id: 1, name: "test"}}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "item", value: %{"id" => 1, "name" => "test"}}]
    end

    test "URI struct uses String.Chars" do
      uri = URI.parse("https://example.com/path")
      log = [{:section, [{:url, uri}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "url", value: "https://example.com/path"}]
    end

    test "Version struct uses String.Chars" do
      version = Version.parse!("1.2.3")
      log = [{:section, [{:version, version}]}]

      result = Serializer.serialize(log, format: :map)

      assert result == [%{section: "section", key: "version", value: "1.2.3"}]
    end
  end
end
