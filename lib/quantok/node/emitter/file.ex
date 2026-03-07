defmodule Quantok.Node.Emitter.File do
  @moduledoc """
  File source for emitters. Reads a file and returns its contents.
  Restricted to the configured safe directory (priv/data by default).
  """

  @spec execute(binary()) :: {:ok, binary()} | {:error, term()}
  def execute(path) when is_binary(path) do
    basename = Path.basename(path)

    if basename != path or String.contains?(path, "..") do
      {:error, :path_outside_safe_directory}
    else
      safe_dir = safe_directory()
      full_path = Path.join(safe_dir, basename)

      case File.read(full_path) do
        {:ok, contents} -> {:ok, contents}
        {:error, reason} -> {:error, {:file_read, reason}}
      end
    end
  end

  defp safe_directory do
    Application.app_dir(:quantok, "priv/data")
  end
end
