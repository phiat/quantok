defmodule Quantok.Node.Collector.Numeric do
  @moduledoc false

  @doc """
  Returns the numeric values parsed from a buffer of tokenes,
  skipping any whose value doesn't parse as a number.
  """
  @spec parse([Quantok.Tokene.t()]) :: [number()]
  def parse(buffer) do
    Enum.flat_map(buffer, fn t ->
      case Float.parse(t.value) do
        {n, _} -> [n]
        :error -> []
      end
    end)
  end

  @doc """
  Formats a number as a string, dropping the decimal point for whole numbers.
  Returns a sentinel string for IEEE 754 infinity / NaN so that overflow in
  Enum.sum (e.g. summing 1.0e308 + 1.0e308) can't crash the collector.
  """
  @spec format(number()) :: binary()
  def format(n) when is_integer(n), do: Integer.to_string(n)

  def format(n) when is_float(n) do
    if n == trunc(n) do
      Integer.to_string(trunc(n))
    else
      :erlang.float_to_binary(n, decimals: 4)
    end
  end

  @doc """
  Runs a numeric reduction safely. Returns the formatted result, or
  "overflow" if the computation raises (e.g. IEEE 754 overflow when summing
  huge floats — Erlang's float arithmetic raises rather than producing inf).
  """
  @spec safe(([number()] -> number()), [Quantok.Tokene.t()], binary()) :: binary()
  def safe(reducer, buffer, empty_fallback \\ "") do
    case parse(buffer) do
      [] -> empty_fallback
      nums -> nums |> reducer.() |> format()
    end
  rescue
    _ -> "overflow"
  end
end
