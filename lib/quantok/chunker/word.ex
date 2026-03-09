defmodule Quantok.Chunker.Word do
  @moduledoc false

  @behaviour Quantok.Chunker

  defstruct delimiter: " "

  @impl true
  def encoding, do: :word

  @impl true
  def chunk(<<>>), do: []

  def chunk(binary) when is_binary(binary) do
    binary
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Chunk by a custom delimiter.
  """
  @spec chunk(binary(), binary()) :: [binary()]
  def chunk(binary, delimiter) when is_binary(binary) and is_binary(delimiter) do
    binary
    |> String.split(delimiter)
    |> Enum.reject(&(&1 == ""))
  end
end
