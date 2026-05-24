defmodule Quantok.Node.Collector.Min do
  @moduledoc """
  Min collector action. Emits the smallest numeric tokene value in the buffer,
  ignoring non-numeric entries. Empty buffer (or all non-numeric) emits "".
  """

  alias Quantok.Node.Collector.Numeric

  @spec process(binary(), binary(), [Quantok.Tokene.t()]) :: binary()
  def process(_command, _text, buffer), do: Numeric.safe(&Enum.min/1, buffer)
end
