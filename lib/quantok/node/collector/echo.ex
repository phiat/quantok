defmodule Quantok.Node.Collector.Echo do
  @moduledoc """
  Simple collector action that returns the buffered text as-is.
  """

  @spec process(binary(), binary(), [Quantok.Tokene.t()]) :: binary()
  def process(_command, text, _buffer), do: text
end
