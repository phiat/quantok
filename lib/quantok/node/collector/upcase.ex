defmodule Quantok.Node.Collector.Upcase do
  @moduledoc """
  Upcase collector action. Uppercases the buffered text.
  """

  @spec process(binary(), binary(), [Quantok.Tokene.t()]) :: binary()
  def process(_command, text, _buffer), do: String.upcase(text)
end
