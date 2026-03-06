defmodule Quantok.Node.Collector.Echo do
  @moduledoc """
  Simple collector action that returns the buffered text as-is.
  """

  @spec process(binary(), binary()) :: binary()
  def process(_command, text), do: text
end
