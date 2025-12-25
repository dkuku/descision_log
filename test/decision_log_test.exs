defmodule DecisionLogTest do
  use ExUnit.Case, async: true

  describe "start/0" do
    test "initializes an empty decision log" do
      DecisionLog.start()

      assert Process.get(:decision_log) == []
    end
  end

  describe "start_tag/1" do
    test "initializes decision log with a tagged section" do
      DecisionLog.start_tag(:my_section)

      assert Process.get(:decision_log) == [{:my_section, []}]
    end
  end

  describe "tag/1" do
    test "adds a new tagged section to existing log" do
      DecisionLog.start()
      DecisionLog.tag(:first_section)
      DecisionLog.tag(:second_section)

      log = Process.get(:decision_log)

      assert [{:second_section, []}, {:first_section, []}] = log
    end
  end

  describe "log/2" do
    test "logs a value with explicit label to current section" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:my_label, "some value")

      [{:section, steps} | _] = Process.get(:decision_log)

      assert steps == [{:my_label, "some value"}]
    end

    test "logs multiple values to same section" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:first, "value1")
      DecisionLog.log(:second, "value2")

      [{:section, steps} | _] = Process.get(:decision_log)

      assert [{:second, "value2"}, {:first, "value1"}] = steps
    end
  end

  describe "log/3 with formatter" do
    test "stores value with custom formatter" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:date, ~D[2025-01-15], &Date.to_string/1)

      [{:section, steps} | _] = Process.get(:decision_log)

      assert [{:date, ~D[2025-01-15], formatter}] = steps
      assert is_function(formatter, 1)
    end

    test "per-entry formatter is used at close time" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:date, ~D[2025-01-15], &Date.to_string/1)

      result = DecisionLog.close()

      assert result == ["section_date: 2025-01-15"]
    end

    test "per-entry formatter overrides default formatter" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:date, ~D[2025-01-15], &Date.to_string/1)
      DecisionLog.log(:count, 42)

      # Default formatter would use inspect for both
      result = DecisionLog.close(formatter: fn _ -> "DEFAULT" end)

      assert result == ["section_date: 2025-01-15", "section_count: DEFAULT"]
    end

    test "is a no-op when log not initialized" do
      Process.delete(:decision_log)
      result = DecisionLog.log(:label, "value", &inspect/1)

      assert result == :ok
      assert Process.get(:decision_log) == nil
    end
  end

  describe "log/1" do
    test "logs a value with auto-generated step label" do
      DecisionLog.start_tag(:section)
      DecisionLog.log("first value")

      [{:section, steps} | _] = Process.get(:decision_log)

      assert [{:step_0, "first value"}] = steps
    end

    test "auto-generates sequential step labels" do
      DecisionLog.start_tag(:section)
      DecisionLog.log("first value")
      DecisionLog.log("second value")

      [{:section, steps} | _] = Process.get(:decision_log)

      assert [{:step_1, "second value"}, {:step_0, "first value"}] = steps
    end
  end

  describe "log_all/1" do
    test "logs multiple key-value pairs at once" do
      DecisionLog.start_tag(:section)
      DecisionLog.log_all(first: "a", second: "b", third: "c")

      [{:section, steps} | _] = Process.get(:decision_log)

      assert [{:third, "c"}, {:second, "b"}, {:first, "a"}] = steps
    end

    test "can be mixed with regular log calls" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:before, 1)
      DecisionLog.log_all(batch_a: "x", batch_b: "y")
      DecisionLog.log(:after, 2)

      log = DecisionLog.close()

      assert log == [
               "section_before: 1",
               "section_batch_a: \"x\"",
               "section_batch_b: \"y\"",
               "section_after: 2"
             ]
    end

    test "works with empty keyword list" do
      DecisionLog.start_tag(:section)
      DecisionLog.log_all([])

      [{:section, steps} | _] = Process.get(:decision_log)

      assert steps == []
    end

    test "is a no-op when log not initialized" do
      Process.delete(:decision_log)
      result = DecisionLog.log_all(a: 1, b: 2)

      assert result == :ok
      assert Process.get(:decision_log) == nil
    end
  end

  describe "trace/2" do
    test "logs and returns the value" do
      DecisionLog.start_tag(:section)
      result = DecisionLog.trace("my_value", :my_label)

      assert result == "my_value"

      [{:section, steps} | _] = Process.get(:decision_log)
      assert [{:my_label, "my_value"}] = steps
    end

    test "works in pipes" do
      DecisionLog.start_tag(:section)

      result =
        10
        |> DecisionLog.trace(:input)
        |> Kernel.*(2)
        |> DecisionLog.trace(:doubled)
        |> Kernel.+(5)
        |> DecisionLog.trace(:final)

      assert result == 25

      log = DecisionLog.close()

      assert log == [
               "section_input: 10",
               "section_doubled: 20",
               "section_final: 25"
             ]
    end

    test "works in with statements" do
      DecisionLog.start_tag(:section)

      result =
        with true <- DecisionLog.trace(1 > 0, :positive_check),
             :ok <- DecisionLog.trace(:ok, :status_check) do
          :success
        end

      assert result == :success

      log = DecisionLog.close()

      assert log == [
               "section_positive_check: true",
               "section_status_check: :ok"
             ]
    end

    test "returns value even when log not initialized" do
      Process.delete(:decision_log)
      result = DecisionLog.trace("value", :label)

      assert result == "value"
      assert Process.get(:decision_log) == nil
    end
  end

  describe "trace/3 with formatter" do
    test "logs with custom formatter and returns value" do
      DecisionLog.start_tag(:section)
      result = DecisionLog.trace(~D[2025-01-15], :date, &Date.to_string/1)

      assert result == ~D[2025-01-15]

      [{:section, steps} | _] = Process.get(:decision_log)
      assert [{:date, ~D[2025-01-15], formatter}] = steps
      assert is_function(formatter, 1)
    end

    test "works in pipes with custom formatter" do
      DecisionLog.start_tag(:section)

      result =
        ~D[2025-01-15]
        |> DecisionLog.trace(:start_date, &Date.to_string/1)
        |> Date.add(10)
        |> DecisionLog.trace(:end_date, &Date.to_string/1)

      assert result == ~D[2025-01-25]

      log = DecisionLog.close()

      assert log == [
               "section_start_date: 2025-01-15",
               "section_end_date: 2025-01-25"
             ]
    end

    test "per-entry formatter overrides default formatter" do
      DecisionLog.start_tag(:section)
      DecisionLog.trace(~D[2025-01-15], :date, &Date.to_string/1)
      DecisionLog.trace(:some_atom, :status)

      result = DecisionLog.close(formatter: fn _ -> "DEFAULT" end)

      assert result == ["section_date: 2025-01-15", "section_status: DEFAULT"]
    end

    test "returns value even when log not initialized" do
      Process.delete(:decision_log)
      result = DecisionLog.trace("value", :label, &inspect/1)

      assert result == "value"
      assert Process.get(:decision_log) == nil
    end

    test "same value can have different formatters in different contexts" do
      item = %{id: 1, name: "test", details: "secret"}

      DecisionLog.start_tag(:context_a)
      DecisionLog.trace(item, :item, fn s -> "Item##{s.id}" end)

      DecisionLog.tag(:context_b)
      DecisionLog.trace(item, :item, fn s -> "#{s.name} (#{s.id})" end)

      log = DecisionLog.close()

      assert log == [
               "context_a_item: Item#1",
               "context_b_item: test (1)"
             ]
    end
  end

  describe "trace/1" do
    test "logs with auto-generated label and returns value" do
      DecisionLog.start_tag(:section)
      result = DecisionLog.trace("my_value")

      assert result == "my_value"

      [{:section, steps} | _] = Process.get(:decision_log)
      assert [{:step_0, "my_value"}] = steps
    end
  end

  describe "trace_all/1" do
    test "logs multiple pairs and returns the items" do
      DecisionLog.start_tag(:section)
      items = [method: "POST", path: "/api"]
      result = DecisionLog.trace_all(items)

      assert result == items

      log = DecisionLog.close()

      assert log == [
               "section_method: \"POST\"",
               "section_path: \"/api\""
             ]
    end

    test "returns items even when log not initialized" do
      Process.delete(:decision_log)
      items = [a: 1, b: 2]
      result = DecisionLog.trace_all(items)

      assert result == items
    end
  end

  describe "tagged/2" do
    test "logs and returns tagged tuple" do
      DecisionLog.start_tag(:section)
      result = DecisionLog.tagged("my_value", :my_label)

      assert result == {:my_label, "my_value"}

      [{:section, steps} | _] = Process.get(:decision_log)
      assert [{:my_label, "my_value"}] = steps
    end

    test "returns tagged tuple even when log not initialized" do
      Process.delete(:decision_log)
      result = DecisionLog.tagged("value", :label)

      assert result == {:label, "value"}
      assert Process.get(:decision_log) == nil
    end
  end

  describe "tagged/3 with formatter" do
    test "logs with custom formatter and returns tagged tuple" do
      DecisionLog.start_tag(:section)
      result = DecisionLog.tagged(~D[2025-01-15], :date, &Date.to_string/1)

      assert result == {:date, ~D[2025-01-15]}

      [{:section, steps} | _] = Process.get(:decision_log)
      assert [{:date, ~D[2025-01-15], formatter}] = steps
      assert is_function(formatter, 1)
    end

    test "per-entry formatter is used at close time" do
      DecisionLog.start_tag(:section)
      DecisionLog.tagged(~D[2025-01-15], :date, &Date.to_string/1)

      result = DecisionLog.close()

      assert result == ["section_date: 2025-01-15"]
    end

    test "works in with statements" do
      DecisionLog.start_tag(:section)

      result =
        with {:valid, true} <- DecisionLog.tagged(true, :valid, &to_string/1),
             {:date, date} <- DecisionLog.tagged(~D[2025-01-15], :date, &Date.to_string/1) do
          {:ok, date}
        end

      assert result == {:ok, ~D[2025-01-15]}

      log = DecisionLog.close()

      assert log == [
               "section_valid: true",
               "section_date: 2025-01-15"
             ]
    end

    test "per-entry formatter overrides default formatter" do
      DecisionLog.start_tag(:section)
      DecisionLog.tagged(~D[2025-01-15], :date, &Date.to_string/1)
      DecisionLog.tagged(:some_atom, :status)

      result = DecisionLog.close(formatter: fn _ -> "DEFAULT" end)

      assert result == ["section_date: 2025-01-15", "section_status: DEFAULT"]
    end

    test "returns tagged tuple even when log not initialized" do
      Process.delete(:decision_log)
      result = DecisionLog.tagged("value", :label, &inspect/1)

      assert result == {:label, "value"}
      assert Process.get(:decision_log) == nil
    end
  end

  describe "close/0" do
    test "returns a list of strings and clears process dictionary" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:step, "value")

      result = DecisionLog.close()

      assert Process.get(:decision_log) == nil
      assert result == ["section_step: \"value\""]
    end

    test "returns empty list when no log exists" do
      Process.delete(:decision_log)

      result = DecisionLog.close()

      assert result == []
    end

    test "flattens multiple sections into an ordered list of strings" do
      DecisionLog.start_tag(:section_a)
      DecisionLog.log(:first, "value1")
      DecisionLog.log(:second, "value2")
      DecisionLog.tag(:section_b)
      DecisionLog.log(:other_step, "value")

      result = DecisionLog.close()

      assert result == [
               "section_a_first: \"value1\"",
               "section_a_second: \"value2\"",
               "section_b_other_step: \"value\""
             ]
    end

    test "result is JSON encodable" do
      DecisionLog.start_tag(:test)
      DecisionLog.log(:key, %{nested: "data"})

      result = DecisionLog.close()

      json = JSON.encode!(result)
      assert is_binary(json)
    end

    test "accepts custom formatter option" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:date, ~D[2025-01-15])
      DecisionLog.log(:count, 42)

      formatter = fn
        %Date{} = d -> Date.to_string(d)
        other -> inspect(other)
      end

      result = DecisionLog.close(formatter: formatter)

      assert result == [
               "section_date: 2025-01-15",
               "section_count: 42"
             ]
    end

    test "accepts inline formatter function" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:datetime, ~U[2025-01-15 10:30:00Z])
      DecisionLog.log(:status, :ok)

      formatter = fn
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        other -> inspect(other)
      end

      result = DecisionLog.close(formatter: formatter)

      assert result == [
               "section_datetime: 2025-01-15T10:30:00Z",
               "section_status: :ok"
             ]
    end
  end

  describe "get/0" do
    test "returns current log without clearing it" do
      DecisionLog.start_tag(:section)
      DecisionLog.log(:step, "value")

      result = DecisionLog.get()

      assert Process.get(:decision_log) != nil
      assert is_list(result)
    end

    test "returns empty list when no log exists" do
      Process.delete(:decision_log)

      result = DecisionLog.get()

      assert result == []
    end
  end

  describe "view/1" do
    test "reverses the log structure" do
      log = [{:second, [{:b, 2}, {:a, 1}]}, {:first, [{:y, "y"}, {:x, "x"}]}]

      result = DecisionLog.view(log)

      assert result == [{:first, [{:x, "x"}, {:y, "y"}]}, {:second, [{:a, 1}, {:b, 2}]}]
    end
  end

  describe "wrap/2" do
    test "handles lifecycle automatically and returns result with log" do
      {result, log} =
        DecisionLog.wrap(:order, fn ->
          DecisionLog.log(:status, :ok)
          {:ok, 42}
        end)

      assert result == {:ok, 42}
      assert log == ["order_status: :ok"]
    end

    test "supports multiple tags within wrapped function" do
      {result, log} =
        DecisionLog.wrap(:validation, fn ->
          DecisionLog.log(:user, :valid)
          DecisionLog.tag(:pricing)
          DecisionLog.log(:total, 100)
          :done
        end)

      assert result == :done

      assert log == [
               "validation_user: :valid",
               "pricing_total: 100"
             ]
    end

    test "cleans up log after function returns" do
      DecisionLog.wrap(:test, fn ->
        DecisionLog.log(:step, "value")
        :ok
      end)

      assert Process.get(:decision_log) == nil
    end

    test "cleans up log even when function raises" do
      assert_raise RuntimeError, "boom", fn ->
        DecisionLog.wrap(:test, fn ->
          DecisionLog.log(:step, "before error")
          raise "boom"
        end)
      end

      assert Process.get(:decision_log) == nil
    end

    test "returns empty log when no logging occurs" do
      {result, log} = DecisionLog.wrap(:empty, fn -> :nothing end)

      assert result == :nothing
      assert log == []
    end

    test "accepts custom formatter option" do
      {result, log} =
        DecisionLog.wrap(
          :order,
          fn ->
            DecisionLog.log(:date, ~D[2025-01-15])
            :ok
          end,
          formatter: &Date.to_string/1
        )

      assert result == :ok
      assert log == ["order_date: 2025-01-15"]
    end

    test "accepts inline formatter function" do
      formatter = fn
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        other -> inspect(other)
      end

      {result, log} =
        DecisionLog.wrap(
          :process,
          fn ->
            DecisionLog.log(:timestamp, ~U[2025-01-15 10:30:00Z])
            DecisionLog.log(:count, 5)
            :done
          end,
          formatter: formatter
        )

      assert result == :done

      assert log == [
               "process_timestamp: 2025-01-15T10:30:00Z",
               "process_count: 5"
             ]
    end
  end

  describe "log!/2" do
    test "auto-starts log with default tag if not initialized" do
      Process.delete(:decision_log)

      DecisionLog.log!(:check, :passed)

      log = DecisionLog.close()
      assert log == ["default_check: :passed"]
    end

    test "uses existing log if already initialized" do
      DecisionLog.start_tag(:existing)
      DecisionLog.log!(:check, :passed)

      log = DecisionLog.close()
      assert log == ["existing_check: :passed"]
    end

    test "logs multiple values sequentially" do
      Process.delete(:decision_log)

      DecisionLog.log!(:first, "a")
      DecisionLog.log!(:second, "b")

      log = DecisionLog.close()
      assert log == ["default_first: \"a\"", "default_second: \"b\""]
    end
  end

  describe "log!/3" do
    test "auto-starts log and creates tag if not initialized" do
      Process.delete(:decision_log)

      DecisionLog.log!(:validation, :user_check, :valid)

      log = DecisionLog.close()
      assert log == ["validation_user_check: :valid"]
    end

    test "switches to tag if different from current" do
      Process.delete(:decision_log)

      DecisionLog.log!(:validation, :check1, :ok)
      DecisionLog.log!(:pricing, :total, 100)
      DecisionLog.log!(:validation, :check2, :ok)

      log = DecisionLog.close()

      assert log == [
               "validation_check1: :ok",
               "pricing_total: 100",
               "validation_check2: :ok"
             ]
    end

    test "reuses current tag if same" do
      Process.delete(:decision_log)

      DecisionLog.log!(:validation, :check1, :ok)
      DecisionLog.log!(:validation, :check2, :ok)

      log = DecisionLog.close()

      assert log == [
               "validation_check1: :ok",
               "validation_check2: :ok"
             ]
    end
  end

  describe "active?/0" do
    test "returns false when no log is initialized" do
      Process.delete(:decision_log)

      refute DecisionLog.active?()
    end

    test "returns true when log is initialized" do
      DecisionLog.start()

      assert DecisionLog.active?()
    end

    test "returns true after start_tag" do
      DecisionLog.start_tag(:section)

      assert DecisionLog.active?()
    end

    test "returns false after close" do
      DecisionLog.start_tag(:section)
      DecisionLog.close()

      refute DecisionLog.active?()
    end
  end
end
