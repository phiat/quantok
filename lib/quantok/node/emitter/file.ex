defmodule Quantok.Node.Emitter.File do
  @moduledoc """
  File source for emitters. Reads a file and returns its contents.
  """

  @spec execute(binary()) :: {:ok, binary()} | {:error, term()}
  def execute(path) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, {:file_read, reason}}
    end
  end
end
