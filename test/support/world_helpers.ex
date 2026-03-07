defmodule Quantok.WorldHelpers do
  @moduledoc """
  Shared test helpers for World, Emitter, Collector setup.
  """

  alias Quantok.Node.Emitter
  alias Quantok.World

  @doc """
  Creates a Manual emitter with the given command and chunker (default: Byte).
  """
  def manual_emitter(command, opts \\ []) do
    chunker = Keyword.get(opts, :chunker, Quantok.Chunker.Byte)

    Emitter.new(
      Keyword.merge(
        [source: Quantok.Node.Emitter.Manual, command: command, chunker: chunker],
        opts
      )
    )
  end

  @doc """
  Adds an emitter to the world, fires it, and returns the resulting tokenes.
  """
  def fire_into(world_pid, emitter) do
    {:ok, _} = World.add_node(world_pid, emitter)
    {:ok, tokenes} = World.fire_emitter(world_pid, emitter.id)
    tokenes
  end

  @doc """
  Creates a manual emitter, fires it, and absorbs all tokenes into a collector.
  Returns the list of tokenes that were absorbed.
  """
  def fill_collector(world_pid, collector_id, command, opts \\ []) do
    emitter = manual_emitter(command, opts)
    tokenes = fire_into(world_pid, emitter)

    Enum.each(tokenes, fn t ->
      World.absorb_tokene(world_pid, collector_id, t.id)
    end)

    tokenes
  end

  @doc """
  Synchronize with the World GenServer after a cast.
  Makes a call to ensure all preceding casts have been processed.
  """
  def sync(world_pid) do
    World.get_state(world_pid)
  end
end
