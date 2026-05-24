defmodule Quantok.Node.Collector.Sum do
  @moduledoc """
  Sum collector action. Parses each tokene value as a number (skipping any
  that don't parse) and emits the total. Use with `emit: true` and an output
  chunker of `word` to keep the result as a single tokene.
  """

  alias Quantok.Node.Collector.Numeric

  @spec process(binary(), binary(), [Quantok.Tokene.t()]) :: binary()
  def process(_command, _text, buffer), do: Numeric.safe(&Enum.sum/1, buffer, "0")
end
