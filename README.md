# DecisionLog

A lightweight Elixir library for tracking decisions made during processing.

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
# ["validation.input_valid: true", "validation.schema_check: :passed",
#  "authorization.user_role: \"admin\"", "authorization.access_granted: true"]
```

#### Batch logging with `log_all/1`

Log multiple key-value pairs in a single call:

```elixir
DecisionLog.start_tag(:request)
DecisionLog.log_all(method: "POST", path: "/api/orders", user_id: 123)
DecisionLog.log(:status, :processed)

log = DecisionLog.close()
# ["request.method: \"POST\"", "request.path: \"/api/orders\"",
#  "request.user_id: 123", "request.status: :processed"]
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
# ["section.date: 2025-01-15", "section.count: 42"]
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
# ["auth.authenticated_user: User<123, alice@example.com, admin>",
#  "audit.actor: User<123>"]
```

This is useful when the same struct needs different representations in different contexts:

```elixir
# In a benefits calculator - show allowances in calculate context
benefit
|> DecisionLog.trace(:add_on_benefit, fn b ->
  "Benefit<id: #{b.id}, sms: #{b.monthly_sms_allowance}>"
end)
# Logs: "pricing.add_on_benefit: Benefit<id: 42, sms: 100>"

# Later in phone support context - just show id
benefit
|> DecisionLog.trace(:benefit, fn b -> "Benefit<id: #{b.id}>" end)
# Logs: "support.benefit: Benefit<id: 42>"
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

## Output Formats

DecisionLog supports two serialization formats:

### String Format (default)

The default format returns a list of strings:

```elixir
DecisionLog.start_tag(:validation)
DecisionLog.log(:user_id, 123)
DecisionLog.log(:status, :ok)

log = DecisionLog.close()
# ["validation.user_id: 123", "validation.status: :ok"]
```

### Map Format (PostgreSQL jsonb-friendly)

For structured storage in PostgreSQL `jsonb` columns, use the `:map` format:

```elixir
log = DecisionLog.close(format: :map)
# [
#   %{section: "validation", key: "user_id", value: 123},
#   %{section: "validation", key: "status", value: "ok"}
# ]
```

The map format automatically normalizes values for JSON compatibility:
- Atoms → strings (`:ok` → `"ok"`)
- Dates → ISO8601 (`~D[2025-01-15]` → `"2025-01-15"`)
- DateTime/NaiveDateTime/Time → ISO8601
- Structs → maps with string keys
- Tuples → lists

### Global Configuration

Set the default format in your config:

```elixir
# config/config.exs
config :decision_log, :default_format, :map
```

### PostgreSQL Integration

Store decision logs in a `jsonb` column (array order is preserved):

```elixir
# In your Ecto schema
field :decision_log, {:array, :map}
```

Query examples:

```sql
-- Find orders with a specific section
SELECT * FROM orders
WHERE decision_log @> '[{"section": "validation"}]';

-- Find by section and key
SELECT * FROM orders
WHERE decision_log @> '[{"section": "pricing", "key": "discount_tier"}]';

-- Extract values
SELECT elem->>'value'
FROM orders, jsonb_array_elements(decision_log) AS elem
WHERE elem->>'key' = 'total';
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
