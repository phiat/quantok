defmodule Quantok.Chunker.Phrase do
  @moduledoc false

  @behaviour Quantok.Chunker

  @impl true
  def encoding, do: :phrase

  @impl true
  def chunk(<<>>), do: []

  def chunk(binary) when is_binary(binary) do
    # Split on phrase boundaries: commas, semicolons, colons, dashes, parens
    Regex.split(~r/\s*[,;:\-\(\)]\s*/, binary)
    |> Enum.reject(&(&1 == ""))
  end
end
