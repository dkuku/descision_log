# DecisionLog

A lightweight Elixir library for tracking decisions made during processing. Provides structured logging with compression support for PostgreSQL storage.

## Installation

```elixir
def deps do
  [
    {:decision_log, "~> 0.1.0"}
  ]
end
```

## Three APIs

DecisionLog provides three ways to log decisions:

| API | Use Case |
|-----|----------|
| **Implicit** | Simple, process-scoped logging |
| **Explicit** | Functional, pipe-friendly, testable |
| **Decorator** | Automatic section tagging for functions |

## Comparison to Logger and Telemetry

| Aspect | DecisionLog | Logger | Telemetry |
|--------|-------------|--------|-----------|
| **Purpose** | "Why was this decision made?" | "What happened?" | "How often does X happen?" |
| **Output** | Structured key-value pairs | Text messages | Event metrics |
| **Storage** | Per-request snapshot | Log files | Time-series DB |
| **Query Pattern** | Point-in-time audit trail | Sequential text search | Aggregated metrics |
| **Use Case** | Business logic branches | Debugging | Performance monitoring |

## Usage

### Implicit API (process dictionary)

```elixir
DecisionLog.start_tag(:validation)
DecisionLog.log(:input_valid, true)
DecisionLog.log(:schema_check, :passed)

DecisionLog.tag(:authorization)
DecisionLog.log(:user_role, "admin")
DecisionLog.log(:access_granted, true)

log = DecisionLog.close()
# ["validation_input_valid: true", "validation_schema_check: :passed",
#  "authorization_user_role: \"admin\"", "authorization_access_granted: true"]
```

#### Batch logging with `log_all/1`

Log multiple key-value pairs in a single call:

```elixir
DecisionLog.start_tag(:request)
DecisionLog.log_all(method: "POST", path: "/api/orders", user_id: 123)
DecisionLog.log(:status, :processed)

log = DecisionLog.close()
# ["request_method: \"POST\"", "request_path: \"/api/orders\"",
#  "request_user_id: 123", "request_status: :processed"]
```

#### Transparent logging with `trace/2`

Use `trace` when you need to log a value and continue using it in pipes or `with` statements:

```elixir
# In pipes
result =
  input
  |> transform()
  |> DecisionLog.trace(:after_transform)
  |> process()
  |> DecisionLog.trace(:final_result)

# In with statements
with true <- DecisionLog.trace(check_user(input), :user_valid),
     :ok <- DecisionLog.trace(validate_items(items), :items_check) do
  {:ok, result}
end
```

#### Custom Formatters

By default, values are formatted using `inspect/1` at close time. You can pass a custom formatter to `close/1`:

```elixir
DecisionLog.start_tag(:section)
DecisionLog.log(:date, ~D[2025-01-15])
DecisionLog.log(:count, 42)

formatter = fn
  %Date{} = d -> Date.to_string(d)
  other -> inspect(other)
end

log = DecisionLog.close(formatter: formatter)
# ["section_date: 2025-01-15", "section_count: 42"]
```

#### Per-Entry Formatters

For context-specific formatting, pass a formatter directly to `log/3`, `trace/3`, or `tagged/3`. The per-entry formatter takes precedence over the default:

```elixir
defp format_user_summary(user), do: "User<#{user.id}>"
defp format_user_detail(user), do: "User<#{user.id}, #{user.email}, #{user.role}>"

DecisionLog.start_tag(:auth)
DecisionLog.trace(user, :authenticated_user, &format_user_detail/1)

DecisionLog.tag(:audit)
DecisionLog.trace(user, :actor, &format_user_summary/1)

log = DecisionLog.close()
# ["auth_authenticated_user: User<123, alice@example.com, admin>",
#  "audit_actor: User<123>"]
```

This is useful when the same struct needs different representations in different contexts:

```elixir
# In a benefits calculator - show allowances in calculate context
benefit
|> DecisionLog.trace(:add_on_benefit, fn b ->
  "Benefit<id: #{b.id}, sms: #{b.monthly_sms_allowance}>"
end)

# Later in phone support context - just show id
benefit
|> DecisionLog.trace(:benefit, fn b -> "Benefit<id: #{b.id}>" end)
```

### Explicit API (functional, pipe-friendly)

```elixir
alias DecisionLog.Explicit, as: Log

log =
  Log.new(:request)
  |> Log.log(:method, "GET")
  |> Log.log(:path, "/api/users")
  |> Log.tag(:response)
  |> Log.log(:status, 200)
  |> Log.close()
```

With batch logging:

```elixir
log =
  Log.new(:request)
  |> Log.log_all(method: "POST", path: "/api/orders", user_id: 123)
  |> Log.tag(:response)
  |> Log.log(:status, 201)
  |> Log.close()
```

With `trace` (returns `{value, context}` for threading both):

```elixir
ctx = Log.new(:validation)

with {true, ctx} <- Log.trace(ctx, check_user(input), :user_valid),
     {:ok, ctx} <- Log.trace(ctx, validate_items(items), :items_check) do
  {{:ok, result}, ctx}
end
```

### Decorator API

The decorator automatically adds a section tag when entering a function.
The caller manages the log lifecycle (start/close).

```elixir
defmodule MyModule do
  use DecisionLog.Decorator

  @decorate decision_log()  # uses function name as tag
  def validate(input) do
    DecisionLog.log(:input, input)
    DecisionLog.log(:valid, true)
    :ok
  end

  @decorate decision_log(:authorization)  # custom tag
  def authorize(user) do
    DecisionLog.log(:user_id, user.id)
    DecisionLog.log(:role, user.role)
    :granted
  end
end

# Caller manages lifecycle
DecisionLog.start_tag(:request)
DecisionLog.log(:request_id, "abc-123")

MyModule.validate(%{name: "test"})  # adds :validate section
MyModule.authorize(user)             # adds :authorization section

log = DecisionLog.close()
```

Benefits of this design:
- Nested decorated calls all contribute to the same log
- Caller decides when logging starts and ends
- Clean separation between function logic and log lifecycle

## Logging Control Flow Decisions

### if/else

```elixir
# Implicit
if user_valid do
  DecisionLog.log(:user_check, :valid)
else
  DecisionLog.log(:user_check, :invalid)
end

# Explicit
{result, ctx} =
  if user_valid do
    {:ok, Log.log(ctx, :user_check, :valid)}
  else
    {:error, Log.log(ctx, :user_check, :invalid)}
  end
```

### case

```elixir
# Implicit
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

# Explicit
{status, ctx} =
  case items do
    [] -> {:error, Log.log(ctx, :items_check, :empty_cart)}
    [_] -> {:ok, Log.log(ctx, :items_check, :single_item)}
    _ -> {:ok, Log.log(ctx, :items_check, :multiple_items)}
  end
```

### cond

```elixir
# Implicit
discount =
  cond do
    total >= 100 ->
      DecisionLog.log(:discount_tier, :gold)
      0.20

    total >= 50 ->
      DecisionLog.log(:discount_tier, :silver)
      0.10

    true ->
      DecisionLog.log(:discount_tier, :none)
      0.0
  end

# Explicit
{discount, ctx} =
  cond do
    total >= 100 -> {0.20, Log.log(ctx, :discount_tier, :gold)}
    total >= 50 -> {0.10, Log.log(ctx, :discount_tier, :silver)}
    true -> {0.0, Log.log(ctx, :discount_tier, :none)}
  end
```

### with

```elixir
# Implicit
result =
  with :ok <- validate_user(user),
       :ok <- validate_items(items),
       :ok <- validate_shipping(shipping) do
    DecisionLog.log(:fulfillment_status, :approved)
    {:ok, order}
  else
    {:error, :invalid_user} ->
      DecisionLog.log(:fulfillment_status, :rejected_user)
      {:error, :invalid_user}

    {:error, reason} ->
      DecisionLog.log(:fulfillment_status, {:rejected, reason})
      {:error, reason}
  end

# Explicit - bind ctx in else clauses
{result, ctx} =
  with :ok <- validate_user(user),
       :ok <- validate_items(items) do
    {{:ok, order}, Log.log(ctx, :status, :approved)}
  else
    error ->
      {{:error, error}, Log.log(ctx, :status, {:rejected, error})}
  end
```

### Pattern Matching in Function Heads

```elixir
# With decorator - single annotation covers all clauses
@decorate decision_log(:shipping)
def calculate_shipping(order)

def calculate_shipping(%{shipping: :express, items: items}) when length(items) > 5 do
  DecisionLog.log(:method, :express)
  DecisionLog.log(:bulk_order, true)
  DecisionLog.log(:cost, 15.0)
  15.0
end

def calculate_shipping(%{shipping: :express}) do
  DecisionLog.log(:method, :express)
  DecisionLog.log(:bulk_order, false)
  DecisionLog.log(:cost, 25.0)
  25.0
end

def calculate_shipping(%{shipping: :standard}) do
  DecisionLog.log(:method, :standard)
  DecisionLog.log(:cost, 5.0)
  5.0
end
```

## Compression for PostgreSQL Storage

Compress decision logs for efficient storage in PostgreSQL:

```elixir
# With implicit API - compress after close
DecisionLog.start_tag(:request)
DecisionLog.log(:method, "POST")
log = DecisionLog.close()
compressed = DecisionLog.Compression.compress(log)

# With explicit API - compress context directly
alias DecisionLog.Explicit, as: Log
context = Log.new(:request) |> Log.log(:method, "POST")
compressed = DecisionLog.Compression.compress_context(context)

# Decompress
{:ok, log} = DecisionLog.Compression.decompress(compressed)
```

### PostgreSQL Decompression

Decision logs can be decompressed directly in PostgreSQL using the `pg_gzip` extension:

```sql
-- Install extension
CREATE EXTENSION IF NOT EXISTS gzip;

-- Decompress log
SELECT convert_from(gzip_decompress(compressed_log), 'UTF8')
FROM decision_logs
WHERE request_id = 'abc-123';

-- Split into rows
SELECT unnest(string_to_array(
    convert_from(gzip_decompress(compressed_log), 'UTF8'),
    E'\n'
)) AS log_entry
FROM decision_logs;
```

For complete PostgreSQL setup instructions:

```elixir
IO.puts(DecisionLog.Compression.postgresql_setup())
```

### Plug Integration

Initialize decision logging at the start of a request and store it at the end:

```elixir
defmodule MyApp.Plugs.DecisionLog do
  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    request_id = get_req_header(conn, "x-request-id") |> List.first() || Ecto.UUID.generate()

    # Initialize log with request metadata
    DecisionLog.start_tag(:request)
    DecisionLog.log_all(
      request_id: request_id,
      method: conn.method,
      path: conn.request_path,
      user_agent: get_req_header(conn, "user-agent") |> List.first()
    )

    # Store request_id for later and register callback to save log
    conn
    |> assign(:request_id, request_id)
    |> register_before_send(&save_decision_log/1)
  end

  defp save_decision_log(conn) do
    DecisionLog.tag(:response)
    DecisionLog.log(:status, conn.status)

    log = DecisionLog.close()
    compressed = DecisionLog.Compression.compress(log)

    # Store asynchronously to not block response
    Task.start(fn ->
      MyApp.DecisionLogs.store(conn.assigns.request_id, compressed)
    end)

    conn
  end
end
```

Add to your endpoint or router:

```elixir
plug MyApp.Plugs.DecisionLog
```

Now any code in your controllers/contexts can add to the log:

```elixir
def create(conn, params) do
  DecisionLog.tag(:validation)

  with {:ok, user} <- validate_user(params) |> DecisionLog.trace(:user_valid),
       {:ok, order} <- create_order(user, params) |> DecisionLog.trace(:order_created) do
    DecisionLog.log(:outcome, :success)
    json(conn, order)
  else
    {:error, reason} ->
      DecisionLog.log(:outcome, {:failed, reason})
      conn |> put_status(422) |> json(%{error: reason})
  end
end
```

### Ecto Integration

```elixir
# Migration
create table(:decision_logs) do
  add :request_id, :uuid, null: false
  add :compressed_log, :binary, null: false
  timestamps()
end

# Storing logs
def store_decision_log(request_id, log_context) do
  compressed = DecisionLog.Compression.compress_context(log_context)

  %DecisionLog{}
  |> DecisionLog.changeset(%{
    request_id: request_id,
    compressed_log: compressed
  })
  |> Repo.insert()
end
```

## Examples

See `examples/demo.ex` for complete examples comparing all three APIs:

```elixir
# All three produce identical logs
{result, log} = DecisionLog.Demo.Implicit.process_order(order)
{result, log} = DecisionLog.Demo.Explicit.process_order(order)
{result, log} = DecisionLog.Demo.Decorated.process_order(order)
```

The demo module demonstrates:
- `if/else` expressions
- `case` expressions
- `cond` expressions
- `with` expressions
- Pattern matching in function heads
