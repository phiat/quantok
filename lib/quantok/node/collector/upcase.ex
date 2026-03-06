defmodule Quantok.Node.Collector.Upcase do
  @moduledoc """
  Upcase collector action. Uppercases the buffered text.
  """

  @spec process(binary(), binary()) :: binary()
  def process(_command, text), do: String.upcase(text)
end
