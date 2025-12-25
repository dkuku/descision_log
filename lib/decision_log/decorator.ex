defmodule DecisionLog.Decorator do
  @moduledoc """
  Function decorator for automatic decision log tagging.

  This decorator adds a section tag when entering a function.
  The caller is responsible for initializing and closing the log.

  ## Usage

      defmodule MyModule do
        use DecisionLog.Decorator

        @decorate decision_log()
        def process(input) do
          DecisionLog.log(:input, input)
          DecisionLog.log(:result, input * 2)
          input * 2
        end
      end

      # Caller manages the log lifecycle
      DecisionLog.start_tag(:request)
      DecisionLog.log(:user_id, 123)
      result = MyModule.process(10)  # Adds :process tag automatically
      log = DecisionLog.close()

  ## Behavior

  - Adds a section tag (via `DecisionLog.tag/1`) when entering the function
  - Returns the function result directly (not a tuple)
  - Raises if no log is initialized (caller forgot to start)
  - Works only with the implicit (process dictionary) API

  ## Options

  - No arguments: uses function name as tag
  - Atom argument: uses that atom as tag

  ## Examples

      # Uses function name as tag
      @decorate decision_log()
      def validate(data), do: ...

      # Uses custom tag
      @decorate decision_log(:validation_step)
      def validate(data), do: ...
  """

  use Decorator.Define, decision_log: 0, decision_log: 1

  @doc """
  Decorator that adds a section tag when entering a function.

  Without arguments, uses the function name as the tag.
  """
  def decision_log(body, context) do
    tag = context.name

    quote do
      DecisionLog.maybe_tag(unquote(tag))
      unquote(body)
    end
  end

  @doc """
  Decorator with custom tag.

  ## Example

      @decorate decision_log(:my_section)
      def my_function(x), do: ...
  """
  def decision_log(tag, body, _context) when is_atom(tag) do
    quote do
      DecisionLog.maybe_tag(unquote(tag))
      unquote(body)
    end
  end
end
