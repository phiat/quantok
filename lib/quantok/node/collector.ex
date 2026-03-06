defmodule Quantok.Node.Collector do
  @moduledoc """
  Collector nodes absorb tokenes into a buffer and trigger actions when conditions are met.

  Config:
  - :capacity - max buffer slots
  - :trigger_mode - :on_full | :manual | :on_tick
  - :tick_interval - ticks between auto-triggers (if :on_tick)
  - :action - module that processes buffer contents on trigger
  - :command - command string passed to action
  - :output_chunker - optional chunker for re-emitting output as tokenes
  """

  alias Quantok.{Node, Tokene}

  @type trigger_mode :: :on_full | :manual | :on_tick

  @doc """
  Creates a new collector node.
  """
  @spec new(keyword()) :: Node.t()
  def new(opts \\ []) do
    config = %{
      capacity: Keyword.get(opts, :capacity, 8),
      trigger_mode: Keyword.get(opts, :trigger_mode, :on_full),
      tick_interval: Keyword.get(opts, :tick_interval, 60),
      action: Keyword.get(opts, :action, __MODULE__.Echo),
      command: Keyword.get(opts, :command, "echo"),
      output_chunker: Keyword.get(opts, :output_chunker, nil),
      buffer: [],
      ticks_since_trigger: 0
    }

    Node.new(:collector, %{
      label: Keyword.get(opts, :label, "Collector"),
      position: Keyword.get(opts, :position, {0.0, 0.0}),
      config: config
    })
  end

  @doc """
  Absorb a tokene into the buffer. Returns updated node and whether the buffer is now full.
  """
  @spec absorb(Node.t(), Tokene.t()) :: {:ok, Node.t()} | {:full, Node.t()}
  def absorb(%Node{type: :collector, config: config} = node, tokene) do
    buffer = config.buffer ++ [tokene]

    updated =
      %{node | config: %{config | buffer: buffer}}

    if length(buffer) >= config.capacity do
      {:full, updated}
    else
      {:ok, updated}
    end
  end

  @doc """
  Returns the current buffer contents as a concatenated string.
  """
  @spec buffer_text(Node.t()) :: binary()
  def buffer_text(%Node{type: :collector, config: %{buffer: buffer}}) do
    Enum.map_join(buffer, & &1.value)
  end

  @doc """
  Returns the number of occupied buffer slots.
  """
  @spec buffer_count(Node.t()) :: non_neg_integer()
  def buffer_count(%Node{type: :collector, config: %{buffer: buffer}}) do
    length(buffer)
  end

  @doc """
  Trigger the collector: process buffer contents and clear the buffer.
  Returns the output string and the updated (cleared) node.
  """
  @spec trigger(Node.t()) :: {:ok, binary(), Node.t()}
  def trigger(%Node{type: :collector, config: config} = node) do
    text = buffer_text(node)
    output = config.action.process(config.command, text)
    cleared = %{node | config: %{config | buffer: [], ticks_since_trigger: 0}}
    {:ok, output, cleared}
  end

  @doc """
  Clear the buffer without triggering.
  """
  @spec clear(Node.t()) :: Node.t()
  def clear(%Node{type: :collector, config: config} = node) do
    %{node | config: %{config | buffer: []}}
  end

  @doc """
  Returns true if the buffer is full.
  """
  @spec full?(Node.t()) :: boolean()
  def full?(%Node{type: :collector, config: config}) do
    length(config.buffer) >= config.capacity
  end
end
