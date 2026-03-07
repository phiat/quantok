defmodule Quantok.Node.Collector.Shell do
  @moduledoc """
  Collector action that runs a shell command with the buffered text as argument.
  """

  # Max bytes passed as shell argument to prevent unbounded input
  @max_text_bytes 8_192

  @spec process(binary(), binary()) :: binary()
  def process(command, text) do
    safe_text = binary_slice(text, 0, @max_text_bytes)
    [prog | args] = String.split(command, ~r/\s+/, trim: true)

    case System.cmd(prog, args ++ [safe_text], stderr_to_stdout: true) do
      {output, 0} -> String.trim_trailing(output, "\n")
      {output, _code} -> output
    end
  rescue
    _ -> "error: command failed"
  end
end
