defmodule DecisionLog.Compression do
  @moduledoc """
  Gzip compression for decision logs.

  Compresses decision logs for efficient storage in databases like PostgreSQL.
  Uses gzip (via Erlang's :zlib) which can be decompressed in PostgreSQL
  using the pg_gzip extension.

  ## When to Use Compression

  Gzip has ~20 byte header overhead, so compression only saves space for
  logs above ~100 bytes (typically 5+ entries):

  | Log Size | Entries | Compression Result |
  |----------|---------|-------------------|
  | < 100 bytes | 1-4 | **Larger** (avoid) |
  | 100-300 bytes | 5-10 | ~40-60% savings |
  | 300+ bytes | 10+ | ~60-85% savings |

  Use `compress/2` with `min_size: :auto` to skip compression for small logs,
  or call `compress/1` directly when you know the log is large enough.

  ## Example

      iex> log = ["section_a_first: \"value1\"", "section_a_second: \"value2\""]
      iex> compressed = DecisionLog.Compression.compress(log)
      iex> DecisionLog.Compression.decompress(compressed)
      {:ok, ["section_a_first: \"value1\"", "section_a_second: \"value2\""]}

  ## PostgreSQL Decompression

  In PostgreSQL, you can decompress using the pg_gzip extension:

      SELECT convert_from(gzip_decompress(compressed_log), 'UTF8')
      FROM decision_logs;

  See `DecisionLog.Compression.postgresql_setup/0` for setup instructions.
  """

  @separator "\n"
  # Gzip header overhead is ~20 bytes; compression breaks even around 100 bytes
  @default_min_size 100

  @typedoc """
  Result of compression with metadata.

  - `{:compressed, binary}` - Data was compressed
  - `{:raw, binary}` - Data stored uncompressed (below min_size threshold)
  """
  @type compression_result :: {:compressed, binary()} | {:raw, binary()}

  @doc """
  Compress a list of log strings to gzip binary.

  Always compresses regardless of size. Use `compress/2` with options
  for automatic size-based decisions.

  Takes the output from `DecisionLog.close/0` or `DecisionLog.Explicit.close/1`
  and returns a compressed binary suitable for storage as `bytea` in PostgreSQL.

  ## Example

      iex> log = DecisionLog.Explicit.new(:request)
      ...> |> DecisionLog.Explicit.log(:method, "GET")
      ...> |> DecisionLog.Explicit.log(:path, "/api/users")
      ...> |> DecisionLog.Explicit.close()
      iex> compressed = DecisionLog.Compression.compress(log)
      iex> is_binary(compressed) and byte_size(compressed) > 0
      true
  """
  @spec compress([String.t()]) :: binary()
  def compress(log_strings) when is_list(log_strings) do
    log_strings
    |> Enum.join(@separator)
    |> :zlib.gzip()
  end

  @doc """
  Compress with options for size-based decisions.

  ## Options

    * `:min_size` - Minimum byte size to compress. Below this threshold,
      returns raw data. Use `:auto` for the default (#{@default_min_size} bytes).
      Set to `0` to always compress.

  ## Returns

    * `{:compressed, binary}` - Data was compressed
    * `{:raw, binary}` - Data stored uncompressed (below threshold)

  ## Example

      iex> small_log = ["step_0: :ok"]
      iex> {:raw, data} = DecisionLog.Compression.compress(small_log, min_size: :auto)
      iex> data
      "step_0: :ok"

      iex> large_log = Enum.map(1..20, &"step_\#{&1}: :ok")
      iex> {:compressed, _} = DecisionLog.Compression.compress(large_log, min_size: :auto)
  """
  @spec compress([String.t()], keyword()) :: compression_result()
  def compress(log_strings, opts) when is_list(log_strings) and is_list(opts) do
    min_size =
      case Keyword.get(opts, :min_size, 0) do
        :auto -> @default_min_size
        n when is_integer(n) -> n
      end

    joined = Enum.join(log_strings, @separator)

    if byte_size(joined) < min_size do
      {:raw, joined}
    else
      {:compressed, :zlib.gzip(joined)}
    end
  end

  @doc """
  Decompress a gzip binary back to a list of log strings.

  ## Example

      iex> original = ["section_a_step_0: \"hello\""]
      iex> compressed = DecisionLog.Compression.compress(original)
      iex> DecisionLog.Compression.decompress(compressed)
      {:ok, ["section_a_step_0: \"hello\""]}
  """
  @spec decompress(binary()) :: {:ok, [String.t()]} | {:error, term()}
  def decompress(compressed) when is_binary(compressed) do
    decompressed = :zlib.gunzip(compressed)
    {:ok, String.split(decompressed, @separator)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Decompress a tagged compression result from `compress/2`.

  Handles both `{:compressed, binary}` and `{:raw, binary}` tuples.

  ## Example

      iex> result = DecisionLog.Compression.compress(["step: :ok"], min_size: :auto)
      iex> {:ok, ["step: :ok"]} = DecisionLog.Compression.decompress_result(result)
  """
  @spec decompress_result(compression_result()) :: {:ok, [String.t()]} | {:error, term()}
  def decompress_result({:raw, data}) when is_binary(data) do
    {:ok, String.split(data, @separator)}
  end

  def decompress_result({:compressed, data}) when is_binary(data) do
    decompress(data)
  end

  @doc """
  Decompress a gzip binary, raising on error.

  ## Example

      iex> original = ["section_a_step_0: \"hello\""]
      iex> compressed = DecisionLog.Compression.compress(original)
      iex> DecisionLog.Compression.decompress!(compressed)
      ["section_a_step_0: \"hello\""]
  """
  @spec decompress!(binary()) :: [String.t()]
  def decompress!(compressed) when is_binary(compressed) do
    compressed
    |> :zlib.gunzip()
    |> String.split(@separator)
  end

  @doc """
  Compress a log context directly (before calling close).

  This is a convenience function that closes the log and compresses in one step.

  ## Example

      iex> context = DecisionLog.Explicit.new(:section)
      ...> |> DecisionLog.Explicit.log(:key, "value")
      iex> compressed = DecisionLog.Compression.compress_context(context)
      iex> is_binary(compressed)
      true

  With options:

      iex> context = DecisionLog.Explicit.new(:section)
      ...> |> DecisionLog.Explicit.log(:key, "value")
      iex> {:raw, _} = DecisionLog.Compression.compress_context(context, min_size: :auto)
  """
  @spec compress_context(DecisionLog.Explicit.t(), keyword()) :: binary() | compression_result()
  def compress_context(context, opts \\ [])

  def compress_context(context, []) do
    context
    |> DecisionLog.Explicit.close()
    |> compress()
  end

  def compress_context(context, opts) do
    context
    |> DecisionLog.Explicit.close()
    |> compress(opts)
  end

  @doc """
  Returns PostgreSQL setup instructions for decompression.

  ## Example

      iex> DecisionLog.Compression.postgresql_setup() |> String.contains?("pg_gzip")
      true
  """
  @spec postgresql_setup() :: String.t()
  def postgresql_setup do
    """
    -- PostgreSQL Setup for Decision Log Decompression
    -- ================================================
    --
    -- 1. Install pg_gzip extension (requires superuser):
    --
    --    Option A: Using pgxn
    --    $ pgxn install gzip
    --
    --    Option B: From source (https://github.com/pramsey/pgsql-gzip)
    --    $ git clone https://github.com/pramsey/pgsql-gzip.git
    --    $ cd pgsql-gzip
    --    $ make && make install
    --
    -- 2. Enable extension in your database:

    CREATE EXTENSION IF NOT EXISTS gzip;

    -- 3. Example table schema:

    CREATE TABLE decision_logs (
        id BIGSERIAL PRIMARY KEY,
        request_id UUID NOT NULL,
        compressed_log BYTEA NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
    );

    -- 4. Decompression queries:

    -- Get decompressed log as text
    SELECT
        id,
        request_id,
        convert_from(gzip_decompress(compressed_log), 'UTF8') AS log_text
    FROM decision_logs
    WHERE request_id = 'your-request-id';

    -- Create a view for easy access
    CREATE VIEW decision_logs_readable AS
    SELECT
        id,
        request_id,
        convert_from(gzip_decompress(compressed_log), 'UTF8') AS log_text,
        created_at
    FROM decision_logs;

    -- Split into rows (one per log entry)
    SELECT
        id,
        request_id,
        unnest(string_to_array(
            convert_from(gzip_decompress(compressed_log), 'UTF8'),
            E'\\n'
        )) AS log_entry
    FROM decision_logs
    WHERE request_id = 'your-request-id';

    -- Parse key-value pairs (section_label: value format)
    WITH log_entries AS (
        SELECT
            id,
            request_id,
            unnest(string_to_array(
                convert_from(gzip_decompress(compressed_log), 'UTF8'),
                E'\\n'
            )) AS entry
        FROM decision_logs
        WHERE request_id = 'your-request-id'
    )
    SELECT
        id,
        request_id,
        split_part(entry, ': ', 1) AS key,
        split_part(entry, ': ', 2) AS value
    FROM log_entries;
    """
  end

  @doc """
  Returns an Ecto migration example for storing compressed logs.
  """
  @spec ecto_migration_example() :: String.t()
  def ecto_migration_example do
    """
    defmodule MyApp.Repo.Migrations.CreateDecisionLogs do
      use Ecto.Migration

      def change do
        create table(:decision_logs) do
          add :request_id, :uuid, null: false
          add :compressed_log, :binary, null: false
          add :algorithm, :string, default: "gzip"

          timestamps(type: :utc_datetime)
        end

        create index(:decision_logs, [:request_id])
        create index(:decision_logs, [:inserted_at])
      end
    end
    """
  end

  @doc """
  Returns example Elixir code for storing logs in Ecto.
  """
  @spec ecto_usage_example() :: String.t()
  def ecto_usage_example do
    """
    # In your context module:

    def store_decision_log(request_id, log_context) do
      compressed = DecisionLog.Compression.compress_context(log_context)

      %DecisionLog{}
      |> DecisionLog.changeset(%{
        request_id: request_id,
        compressed_log: compressed
      })
      |> Repo.insert()
    end

    # Or with the implicit API:

    def store_decision_log(request_id) do
      log_strings = DecisionLog.close()
      compressed = DecisionLog.Compression.compress(log_strings)

      %DecisionLog{}
      |> DecisionLog.changeset(%{
        request_id: request_id,
        compressed_log: compressed
      })
      |> Repo.insert()
    end
    """
  end
end
