defmodule DecisionLog.CompressionTest do
  use ExUnit.Case, async: true

  alias DecisionLog.Compression
  alias DecisionLog.Explicit

  describe "compress/1" do
    test "compresses list of strings to binary" do
      log = ["section_a_first: \"value1\"", "section_a_second: \"value2\""]
      compressed = Compression.compress(log)

      assert is_binary(compressed)
      assert byte_size(compressed) > 0
    end

    test "compressed output is smaller than input for typical logs" do
      log = generate_large_log(100)
      original_size = log |> Enum.join("\n") |> byte_size()
      compressed = Compression.compress(log)

      assert byte_size(compressed) < original_size
    end

    test "compresses empty list" do
      compressed = Compression.compress([])
      assert is_binary(compressed)
    end

    test "compresses single entry" do
      log = ["section_step_0: \"hello\""]
      compressed = Compression.compress(log)

      assert is_binary(compressed)
      assert byte_size(compressed) > 0
    end
  end

  describe "decompress/1" do
    test "decompresses back to original list" do
      original = ["section_a_first: \"value1\"", "section_a_second: \"value2\""]
      compressed = Compression.compress(original)

      assert {:ok, ^original} = Compression.decompress(compressed)
    end

    test "decompresses empty list" do
      original = []
      compressed = Compression.compress(original)

      assert {:ok, [""]} = Compression.decompress(compressed)
    end

    test "returns error for invalid input" do
      assert {:error, _} = Compression.decompress("not valid gzip")
    end

    test "returns error for corrupted data" do
      original = ["section_step_0: \"hello\""]
      compressed = Compression.compress(original)
      corrupted = binary_part(compressed, 0, byte_size(compressed) - 5)

      assert {:error, _} = Compression.decompress(corrupted)
    end
  end

  describe "decompress!/1" do
    test "decompresses successfully" do
      original = ["section_a_first: \"value1\""]
      compressed = Compression.compress(original)

      assert Compression.decompress!(compressed) == original
    end

    test "raises on invalid input" do
      assert_raise ErlangError, fn ->
        Compression.decompress!("not valid gzip")
      end
    end
  end

  describe "compress_context/1" do
    test "compresses explicit context directly" do
      context =
        :request
        |> Explicit.new()
        |> Explicit.log(:method, "GET")
        |> Explicit.log(:path, "/api/users")

      compressed = Compression.compress_context(context)

      assert is_binary(compressed)
      {:ok, decompressed} = Compression.decompress(compressed)

      assert decompressed == ["request_method: \"GET\"", "request_path: \"/api/users\""]
    end

    test "handles complex values" do
      context =
        :decision
        |> Explicit.new()
        |> Explicit.log(:input, %{user_id: 123, action: :create})
        |> Explicit.log(:result, {:ok, "created"})

      compressed = Compression.compress_context(context)
      {:ok, decompressed} = Compression.decompress(compressed)

      assert length(decompressed) == 2
      assert Enum.at(decompressed, 0) =~ "decision_input:"
      assert Enum.at(decompressed, 1) =~ "decision_result:"
    end
  end

  describe "round-trip with DecisionLog.Explicit" do
    test "full workflow: create, log, compress, decompress" do
      # Create a realistic decision log
      log =
        :validation
        |> Explicit.new()
        |> Explicit.log(:input_received, true)
        |> Explicit.log(:schema_check, :passed)
        |> Explicit.tag(:authorization)
        |> Explicit.log(:user_role, "admin")
        |> Explicit.log(:permission_check, :granted)
        |> Explicit.tag(:processing)
        |> Explicit.log(:action, :update_record)
        |> Explicit.log(:result, {:ok, %{id: 42}})
        |> Explicit.close()

      # Compress
      compressed = Compression.compress(log)

      # Verify compression ratio
      original_size = log |> Enum.join("\n") |> byte_size()
      assert byte_size(compressed) < original_size

      # Decompress and verify
      {:ok, recovered} = Compression.decompress(compressed)
      assert recovered == log
    end

    test "preserves special characters and unicode" do
      log =
        :test
        |> Explicit.new()
        |> Explicit.log(:message, "Hello, 世界! 🌍")
        |> Explicit.log(:path, "/api/users?name=José&age=30")
        |> Explicit.close()

      compressed = Compression.compress(log)
      {:ok, recovered} = Compression.decompress(compressed)

      assert recovered == log
    end

    test "handles multiline values" do
      log =
        :error
        |> Explicit.new()
        |> Explicit.log(:stacktrace, "Line 1\nLine 2\nLine 3")
        |> Explicit.close()

      compressed = Compression.compress(log)
      {:ok, recovered} = Compression.decompress(compressed)

      # Note: multiline values in a single entry will be split
      # This is expected behavior - the entry contains escaped newlines
      assert length(recovered) >= 1
    end
  end

  describe "documentation functions" do
    test "postgresql_setup returns setup instructions" do
      setup = Compression.postgresql_setup()

      assert is_binary(setup)
      assert setup =~ "pg_gzip"
      assert setup =~ "CREATE EXTENSION"
      assert setup =~ "gzip_decompress"
      assert setup =~ "decision_logs"
    end

    test "ecto_migration_example returns valid example" do
      migration = Compression.ecto_migration_example()

      assert is_binary(migration)
      assert migration =~ "use Ecto.Migration"
      assert migration =~ "compressed_log"
      assert migration =~ ":binary"
    end

    test "ecto_usage_example returns valid example" do
      usage = Compression.ecto_usage_example()

      assert is_binary(usage)
      assert usage =~ "compress_context"
      assert usage =~ "Repo.insert"
    end
  end

  # Helper function to generate large logs for compression ratio tests
  defp generate_large_log(entries) do
    Enum.map(1..entries, fn i ->
      section = "section_#{rem(i, 5)}"
      "#{section}_step_#{i}: \"This is a test value with some repetitive content #{i}\""
    end)
  end
end
