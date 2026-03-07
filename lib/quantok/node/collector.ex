defmodule Quantok.Node.Collector do
  @moduledoc """
  Collector nodes absorb tokenes into a buffer and trigger actions when conditions are met.

  Config:
  - :capacity - max buffer slots
  - :trigger_mode - :on_full | :manual | :timed
  - :tick_interval - physics ticks between auto-triggers (if :timed)
  - :action - module that processes buffer contents on trigger
  - :command - command string passed to action
  - :output_mode - :discard | :emit | :paired (what happens to action output)
  - :output_chunker - chunker for re-emitting output as tokenes (if :emit)
  - :paired_emitter_id - emitter to fire with output as command (if :paired)
  """

  alias Quantok.{Node, Tokene}

  @type trigger_mode :: :on_full | :manual | :timed

  @doc """
  Creates a new collector node.
  """
  @spec new(keyword()) :: Node.t()
  def new(opts \\ []) do
    config = %{
      capacity: Keyword.get(opts, :capacity, 8),
      trigger_mode: Keyword.get(opts, :trigger_mode, :on_full),
      tick_interval: Keyword.get(opts, :tick_interval, 120),
      action: Keyword.get(opts, :action, __MODULE__.Echo),
      command: Keyword.get(opts, :command, "echo"),
      output_mode: Keyword.get(opts, :output_mode, :discard),
      output_chunker: Keyword.get(opts, :output_chunker, nil),
      paired_emitter_id: Keyword.get(opts, :paired_emitter_id, nil),
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
  Returns `{:ok, output, cleared_node}` for :discard mode,
  `{:ok, output, cleared_node, tokenes}` for :emit mode,
  or `{:paired, output, cleared_node, paired_emitter_id}` for :paired mode.
  """
  @spec trigger(Node.t()) ::
          {:ok, binary(), Node.t()}
          | {:ok, binary(), Node.t(), [Tokene.t()]}
          | {:paired, binary(), Node.t(), binary()}
  def trigger(%Node{type: :collector, config: config} = node) do
    text = buffer_text(node)
    output = config.action.process(config.command, text)
    cleared = %{node | config: %{config | buffer: [], ticks_since_trigger: 0}}

    case config.output_mode do
      :emit when config.output_chunker != nil ->
        chunks = config.output_chunker.chunk(output)
        encoding = config.output_chunker.encoding()
        tokenes = Enum.map(chunks, &Tokene.new(&1, encoding, source_id: node.id))
        {:ok, output, cleared, tokenes}

      :paired when config.paired_emitter_id != nil ->
        {:paired, output, cleared, config.paired_emitter_id}

      _ ->
        {:ok, output, cleared}
    end
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

  @doc """
  Advance the tick counter. Returns `{:trigger, updated_node}` if a timed
  trigger is due (buffer non-empty and tick threshold reached), otherwise
  `{:ok, updated_node}`.
  """
  @spec tick(Node.t()) :: {:ok, Node.t()} | {:trigger, Node.t()}
  def tick(%Node{type: :collector, config: %{trigger_mode: :timed} = config} = node) do
    ticks = config.ticks_since_trigger + 1

    if ticks >= config.tick_interval and config.buffer != [] do
      {:trigger, %{node | config: %{config | ticks_since_trigger: ticks}}}
    else
      {:ok, %{node | config: %{config | ticks_since_trigger: ticks}}}
    end
  end

  def tick(%Node{type: :collector} = node), do: {:ok, node}
end
