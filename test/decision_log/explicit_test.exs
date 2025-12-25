defmodule DecisionLog.ExplicitTest do
  use ExUnit.Case, async: true

  alias DecisionLog.Explicit

  describe "new/0" do
    test "creates an empty decision log context" do
      assert Explicit.new() == []
    end
  end

  describe "new/1" do
    test "creates a context with an initial tagged section" do
      assert Explicit.new(:my_section) == [{:my_section, []}]
    end
  end

  describe "tag/2" do
    test "adds a new tagged section to existing context" do
      context =
        Explicit.new()
        |> Explicit.tag(:first_section)
        |> Explicit.tag(:second_section)

      assert [{:second_section, []}, {:first_section, []}] = context
    end
  end

  describe "log/3" do
    test "logs a value with explicit label to current section" do
      context =
        Explicit.new(:section)
        |> Explicit.log(:my_label, "some value")

      [{:section, steps} | _] = context

      assert steps == [{:my_label, "some value"}]
    end

    test "logs multiple values to same section" do
      context =
        Explicit.new(:section)
        |> Explicit.log(:first, "value1")
        |> Explicit.log(:second, "value2")

      [{:section, steps} | _] = context

      assert [{:second, "value2"}, {:first, "value1"}] = steps
    end
  end

  describe "log/2" do
    test "logs a value with auto-generated step label" do
      context =
        Explicit.new(:section)
        |> Explicit.log("first value")

      [{:section, steps} | _] = context

      assert [{:step_0, "first value"}] = steps
    end

    test "auto-generates sequential step labels" do
      context =
        Explicit.new(:section)
        |> Explicit.log("first value")
        |> Explicit.log("second value")

      [{:section, steps} | _] = context

      assert [{:step_1, "second value"}, {:step_0, "first value"}] = steps
    end
  end

  describe "log_all/2" do
    test "logs multiple key-value pairs at once" do
      context =
        Explicit.new(:section)
        |> Explicit.log_all(first: "a", second: "b", third: "c")

      [{:section, steps} | _] = context

      assert [{:third, "c"}, {:second, "b"}, {:first, "a"}] = steps
    end

    test "can be mixed with regular log calls" do
      result =
        Explicit.new(:section)
        |> Explicit.log(:before, 1)
        |> Explicit.log_all(batch_a: "x", batch_b: "y")
        |> Explicit.log(:after, 2)
        |> Explicit.close()

      assert result == [
               "section_before: 1",
               "section_batch_a: \"x\"",
               "section_batch_b: \"y\"",
               "section_after: 2"
             ]
    end

    test "works with empty keyword list" do
      context =
        Explicit.new(:section)
        |> Explicit.log_all([])

      [{:section, steps} | _] = context

      assert steps == []
    end
  end

  describe "trace/3" do
    test "logs and returns value with updated context" do
      ctx = Explicit.new(:section)
      {value, ctx} = Explicit.trace(ctx, "my_value", :my_label)

      assert value == "my_value"

      [{:section, steps} | _] = ctx
      assert [{:my_label, "my_value"}] = steps
    end

    test "works in with statements" do
      ctx = Explicit.new(:section)

      result =
        with {true, ctx} <- Explicit.trace(ctx, 1 > 0, :positive_check),
             {:ok, ctx} <- Explicit.trace(ctx, :ok, :status_check) do
          {:success, ctx}
        end

      assert {:success, final_ctx} = result

      log = Explicit.close(final_ctx)

      assert log == [
               "section_positive_check: true",
               "section_status_check: :ok"
             ]
    end

    test "can chain multiple traces" do
      ctx = Explicit.new(:section)

      {a, ctx} = Explicit.trace(ctx, 10, :input)
      {b, ctx} = Explicit.trace(ctx, a * 2, :doubled)
      {c, ctx} = Explicit.trace(ctx, b + 5, :final)

      assert c == 25

      log = Explicit.close(ctx)

      assert log == [
               "section_input: 10",
               "section_doubled: 20",
               "section_final: 25"
             ]
    end
  end

  describe "trace/2" do
    test "logs with auto-generated label and returns value" do
      ctx = Explicit.new(:section)
      {value, ctx} = Explicit.trace(ctx, "my_value")

      assert value == "my_value"

      [{:section, steps} | _] = ctx
      assert [{:step_0, "my_value"}] = steps
    end
  end

  describe "trace_all/2" do
    test "logs multiple pairs and returns items with context" do
      ctx = Explicit.new(:section)
      items = [method: "POST", path: "/api"]
      {result, ctx} = Explicit.trace_all(ctx, items)

      assert result == items

      log = Explicit.close(ctx)

      assert log == [
               "section_method: \"POST\"",
               "section_path: \"/api\""
             ]
    end
  end

  describe "close/1" do
    test "returns a list of formatted strings" do
      result =
        Explicit.new(:section)
        |> Explicit.log(:step, "value")
        |> Explicit.close()

      assert result == ["section_step: \"value\""]
    end

    test "returns empty list for empty context" do
      result = Explicit.close([])

      assert result == []
    end

    test "flattens multiple sections into an ordered list of strings" do
      result =
        Explicit.new(:section_a)
        |> Explicit.log(:first, "value1")
        |> Explicit.log(:second, "value2")
        |> Explicit.tag(:section_b)
        |> Explicit.log(:other_step, "value")
        |> Explicit.close()

      assert result == [
               "section_a_first: \"value1\"",
               "section_a_second: \"value2\"",
               "section_b_other_step: \"value\""
             ]
    end

    test "result is JSON encodable" do
      result =
        Explicit.new(:test)
        |> Explicit.log(:key, %{nested: "data"})
        |> Explicit.close()

      json = JSON.encode!(result)
      assert is_binary(json)
    end

    test "accepts custom formatter option" do
      formatter = fn
        %Date{} = d -> Date.to_string(d)
        other -> inspect(other)
      end

      result =
        Explicit.new(:section)
        |> Explicit.log(:date, ~D[2025-01-15])
        |> Explicit.log(:count, 42)
        |> Explicit.close(formatter: formatter)

      assert result == [
               "section_date: 2025-01-15",
               "section_count: 42"
             ]
    end

    test "accepts inline formatter function" do
      formatter = fn
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        other -> inspect(other)
      end

      result =
        Explicit.new(:section)
        |> Explicit.log(:datetime, ~U[2025-01-15 10:30:00Z])
        |> Explicit.log(:status, :ok)
        |> Explicit.close(formatter: formatter)

      assert result == [
               "section_datetime: 2025-01-15T10:30:00Z",
               "section_status: :ok"
             ]
    end
  end

  describe "get/1" do
    test "returns current log in readable format" do
      context =
        Explicit.new(:section)
        |> Explicit.log(:step, "value")

      result = Explicit.get(context)

      assert result == [{:section, [{:step, "value"}]}]
    end

    test "returns empty list for empty context" do
      result = Explicit.get([])

      assert result == []
    end
  end

  describe "view/1" do
    test "reverses the log structure to chronological order" do
      context = [{:second, [{:b, 2}, {:a, 1}]}, {:first, [{:y, "y"}, {:x, "x"}]}]

      result = Explicit.view(context)

      assert result == [{:first, [{:x, "x"}, {:y, "y"}]}, {:second, [{:a, 1}, {:b, 2}]}]
    end
  end

  describe "context is immutable" do
    test "original context is not modified by operations" do
      original = Explicit.new(:section)
      _modified = Explicit.log(original, :key, "value")

      assert original == [{:section, []}]
    end
  end

  describe "pipe-friendly API" do
    test "supports full pipeline usage" do
      result =
        Explicit.new(:init)
        |> Explicit.log(:step1, "a")
        |> Explicit.tag(:middle)
        |> Explicit.log(:step2, "b")
        |> Explicit.log("auto")
        |> Explicit.tag(:final)
        |> Explicit.log(:done, true)
        |> Explicit.close()

      assert result == [
               "init_step1: \"a\"",
               "middle_step2: \"b\"",
               "middle_step_1: \"auto\"",
               "final_done: true"
             ]
    end
  end

  describe "wrap/2" do
    test "handles lifecycle automatically and returns result with log" do
      {result, log} =
        Explicit.wrap(:order, fn ctx ->
          ctx = Explicit.log(ctx, :status, :ok)
          {{:ok, 42}, ctx}
        end)

      assert result == {:ok, 42}
      assert log == ["order_status: :ok"]
    end

    test "supports multiple tags within wrapped function" do
      {result, log} =
        Explicit.wrap(:validation, fn ctx ->
          ctx =
            ctx
            |> Explicit.log(:user, :valid)
            |> Explicit.tag(:pricing)
            |> Explicit.log(:total, 100)

          {:done, ctx}
        end)

      assert result == :done

      assert log == [
               "validation_user: :valid",
               "pricing_total: 100"
             ]
    end

    test "returns empty log when no logging occurs" do
      {result, log} =
        Explicit.wrap(:empty, fn ctx ->
          {:nothing, ctx}
        end)

      assert result == :nothing
      assert log == []
    end

    test "supports complex nested operations" do
      validate = fn ctx, data ->
        ctx
        |> Explicit.log(:input, data)
        |> Explicit.log(:valid, data > 0)
      end

      calculate = fn ctx, value ->
        ctx
        |> Explicit.tag(:calculation)
        |> Explicit.log(:result, value * 2)
      end

      {result, log} =
        Explicit.wrap(:process, fn ctx ->
          ctx = validate.(ctx, 5)
          ctx = calculate.(ctx, 5)
          {10, ctx}
        end)

      assert result == 10

      assert log == [
               "process_input: 5",
               "process_valid: true",
               "calculation_result: 10"
             ]
    end

    test "accepts custom formatter option" do
      {result, log} =
        Explicit.wrap(
          :order,
          fn ctx ->
            ctx = Explicit.log(ctx, :date, ~D[2025-01-15])
            {:ok, ctx}
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
        Explicit.wrap(
          :process,
          fn ctx ->
            ctx =
              ctx
              |> Explicit.log(:timestamp, ~U[2025-01-15 10:30:00Z])
              |> Explicit.log(:count, 5)

            {:done, ctx}
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
end
