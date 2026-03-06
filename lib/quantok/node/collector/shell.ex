defmodule Quantok.Node.Collector.Shell do
  @moduledoc """
  Collector action that runs a shell command with the buffered text as argument.
  """

  @spec process(binary(), binary()) :: binary()
  def process(command, text) do
    [prog | args] = String.split(command, ~r/\s+/, trim: true)

    case System.cmd(prog, args ++ [text], stderr_to_stdout: true) do
      {output, 0} -> String.trim_trailing(output, "\n")
      {output, _code} -> output
    end
  rescue
    _ -> "error: command failed"
  end
end
