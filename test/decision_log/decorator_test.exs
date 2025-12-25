defmodule DecisionLog.DecoratorTest do
  use ExUnit.Case, async: true

  defmodule TestModule do
    @moduledoc false
    use DecisionLog.Decorator

    @decorate decision_log()
    def simple_function(x) do
      DecisionLog.log(:input, x)
      DecisionLog.log(:doubled, x * 2)
      x * 2
    end

    @decorate decision_log(:custom_tag)
    def with_custom_tag(x) do
      DecisionLog.log(:value, x)
      x + 1
    end

    @decorate decision_log()
    def with_sections(x) do
      DecisionLog.log(:start, x)
      DecisionLog.tag(:middle)
      DecisionLog.log(:processing, true)
      DecisionLog.tag(:finish)
      DecisionLog.log(:done, x * 2)
      x * 2
    end

    # Multi-clause function with pattern matching
    @decorate decision_log(:math)
    def calculate(op, a, b)

    def calculate(:add, a, b) do
      DecisionLog.log(:operation, :add)
      DecisionLog.log(:result, a + b)
      a + b
    end

    def calculate(:sub, a, b) do
      DecisionLog.log(:operation, :sub)
      DecisionLog.log(:result, a - b)
      a - b
    end

    def calculate(:mul, a, b) do
      DecisionLog.log(:operation, :mul)
      DecisionLog.log(:result, a * b)
      a * b
    end

    # Nested decorated functions
    @decorate decision_log(:outer)
    def outer_function(x) do
      DecisionLog.log(:outer_input, x)
      result = inner_function(x * 2)
      DecisionLog.log(:outer_output, result)
      result
    end

    @decorate decision_log(:inner)
    def inner_function(x) do
      DecisionLog.log(:inner_input, x)
      DecisionLog.log(:inner_output, x + 1)
      x + 1
    end
  end

  describe "decision_log decorator - basic behavior" do
    test "adds tag and returns result directly" do
      DecisionLog.start()
      result = TestModule.simple_function(5)

      assert result == 10

      log = DecisionLog.close()
      assert is_list(log)
      assert length(log) == 2
    end

    test "uses function name as default tag" do
      DecisionLog.start()
      TestModule.simple_function(3)
      log = DecisionLog.close()

      assert Enum.all?(log, &String.starts_with?(&1, "simple_function_"))
    end

    test "accepts custom tag as atom" do
      DecisionLog.start()
      result = TestModule.with_custom_tag(10)

      assert result == 11

      log = DecisionLog.close()
      assert Enum.all?(log, &String.starts_with?(&1, "custom_tag_"))
    end

    test "silently skips logging when log not initialized" do
      # Ensure no log exists
      Process.delete(:decision_log)

      # Decorator uses maybe_tag() which is silent if log not initialized
      result = TestModule.simple_function(5)
      assert result == 10

      # No log was created
      assert Process.get(:decision_log) == nil
    end
  end

  describe "decision_log decorator - sections" do
    test "handles multiple sections within decorated function" do
      DecisionLog.start()
      result = TestModule.with_sections(10)

      assert result == 20

      log = DecisionLog.close()

      # Verify entries from different sections are present
      assert Enum.any?(log, &String.starts_with?(&1, "with_sections_"))
      assert Enum.any?(log, &String.starts_with?(&1, "middle_"))
      assert Enum.any?(log, &String.starts_with?(&1, "finish_"))
    end
  end

  describe "decision_log decorator - pattern matching" do
    test "works with multi-clause functions" do
      DecisionLog.start()
      result_add = TestModule.calculate(:add, 3, 4)
      log_add = DecisionLog.close()

      DecisionLog.start()
      result_sub = TestModule.calculate(:sub, 10, 3)
      log_sub = DecisionLog.close()

      DecisionLog.start()
      result_mul = TestModule.calculate(:mul, 5, 6)
      log_mul = DecisionLog.close()

      assert result_add == 7
      assert result_sub == 7
      assert result_mul == 30

      assert "math_operation: :add" in log_add
      assert "math_operation: :sub" in log_sub
      assert "math_operation: :mul" in log_mul
    end
  end

  describe "decision_log decorator - nested calls" do
    test "nested decorated calls all add their tags to same log" do
      DecisionLog.start()
      result = TestModule.outer_function(5)
      log = DecisionLog.close()

      assert result == 11

      # Both outer and inner sections should be in the log
      assert Enum.any?(log, &String.starts_with?(&1, "outer_"))
      assert Enum.any?(log, &String.starts_with?(&1, "inner_"))

      # Note: after inner_function adds :inner tag, subsequent logs
      # in outer_function are under :inner section (tags don't "restore")
      assert "outer_outer_input: 5" in log
      assert "inner_inner_input: 10" in log
      assert "inner_inner_output: 11" in log
      # outer_output is logged after inner returns, so it's under :inner tag
      assert "inner_outer_output: 11" in log
    end

    test "nested calls maintain chronological ordering" do
      DecisionLog.start()
      TestModule.outer_function(3)
      log = DecisionLog.close()

      # Find indices to verify chronological order
      outer_input_idx = Enum.find_index(log, &(&1 == "outer_outer_input: 3"))
      inner_input_idx = Enum.find_index(log, &(&1 =~ "inner_inner_input"))
      outer_output_idx = Enum.find_index(log, &(&1 =~ "outer_output"))

      assert outer_input_idx < inner_input_idx
      assert inner_input_idx < outer_output_idx
    end
  end

  describe "decorator isolation between calls" do
    test "each call starts fresh when caller manages lifecycle" do
      DecisionLog.start()
      TestModule.simple_function(1)
      log1 = DecisionLog.close()

      DecisionLog.start()
      TestModule.simple_function(2)
      log2 = DecisionLog.close()

      # Logs should be independent
      assert "simple_function_input: 1" in log1
      assert "simple_function_input: 2" in log2

      refute "simple_function_input: 1" in log2
      refute "simple_function_input: 2" in log1
    end
  end
end
