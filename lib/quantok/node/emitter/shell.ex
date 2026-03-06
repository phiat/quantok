defmodule Quantok.Node.Emitter.Shell do
  @moduledoc """
  Shell source for emitters. Executes a shell command and captures stdout.
  """

  @doc """
  Executes a shell command and returns its stdout.
  """
  @spec execute(binary()) :: {:ok, binary()} | {:error, term()}
  def execute(command) when is_binary(command) do
    case System.cmd("sh", ["-c", command], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim_trailing(output, "\n")}
      {output, code} -> {:error, {code, output}}
    end
  end
end
