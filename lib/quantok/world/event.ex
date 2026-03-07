defmodule Quantok.World.Event do
  @moduledoc """
  Events represent every state change in a World.
  The world state is a projection (fold) over its event log.
  """

  @type t ::
          {:node_added, node :: Quantok.Node.t(), timestamp :: integer()}
          | {:node_removed, node_id :: binary(), timestamp :: integer()}
          | {:node_moved, node_id :: binary(), position :: {float(), float()}, timestamp :: integer()}
          | {:node_updated, node :: Quantok.Node.t(), timestamp :: integer()}
          | {:emitted, emitter_id :: binary(), tokenes :: [Quantok.Tokene.t()], timestamp :: integer()}
          | {:absorbed, collector_id :: binary(), tokene_id :: binary(), updated_collector :: Quantok.Node.t(), timestamp :: integer()}
          | {:triggered, collector_id :: binary(), output :: binary(), cleared_collector :: Quantok.Node.t(), timestamp :: integer()}
          | {:transformed, transformer_id :: binary(), old_tokene_id :: binary(), new_tokenes :: [Quantok.Tokene.t()], timestamp :: integer()}
          | {:tokene_removed, tokene_id :: binary(), timestamp :: integer()}
          | {:collector_cleared, collector_id :: binary(), cleared_collector :: Quantok.Node.t(), timestamp :: integer()}
          | {:passive_rotated, node_id :: binary(), updated_node :: Quantok.Node.t(), timestamp :: integer()}
          | {:gravity_changed, gravity :: {float(), float()}, timestamp :: integer()}
          | {:paused, timestamp :: integer()}
          | {:resumed, timestamp :: integer()}

  @doc """
  Apply an event to a world state, returning the updated world.
  """
  @spec apply(Quantok.World.t(), t()) :: Quantok.World.t()
  def apply(world, {:node_added, node, _ts}) do
    %{world | nodes: Map.put(world.nodes, node.id, node)}
  end

  def apply(world, {:node_removed, node_id, _ts}) do
    %{world | nodes: Map.delete(world.nodes, node_id)}
  end

  def apply(world, {:node_moved, node_id, position, _ts}) do
    case Map.get(world.nodes, node_id) do
      nil -> world
      node ->
        updated = %{node | position: position}
        %{world | nodes: Map.put(world.nodes, node_id, updated)}
    end
  end

  def apply(world, {:node_updated, node, _ts}) do
    %{world | nodes: Map.put(world.nodes, node.id, node)}
  end

  def apply(world, {:emitted, _emitter_id, tokenes, _ts}) do
    new_tokenes = Map.new(tokenes, fn t -> {t.id, t} end)
    %{world | tokenes: Map.merge(world.tokenes, new_tokenes)}
  end

  def apply(world, {:absorbed, collector_id, tokene_id, updated_collector, _ts}) do
    %{
      world
      | nodes: Map.put(world.nodes, collector_id, updated_collector),
        tokenes: Map.delete(world.tokenes, tokene_id)
    }
  end

  def apply(world, {:triggered, collector_id, _output, cleared_collector, _ts}) do
    %{world | nodes: Map.put(world.nodes, collector_id, cleared_collector)}
  end

  def apply(world, {:transformed, _transformer_id, old_tokene_id, new_tokenes, _ts}) do
    new_tokene_map = Map.new(new_tokenes, fn t -> {t.id, t} end)

    %{
      world
      | tokenes:
          world.tokenes
          |> Map.delete(old_tokene_id)
          |> Map.merge(new_tokene_map)
    }
  end

  def apply(world, {:tokene_removed, tokene_id, _ts}) do
    %{world | tokenes: Map.delete(world.tokenes, tokene_id)}
  end

  def apply(world, {:collector_cleared, collector_id, cleared_collector, _ts}) do
    %{world | nodes: Map.put(world.nodes, collector_id, cleared_collector)}
  end

  def apply(world, {:passive_rotated, _node_id, updated_node, _ts}) do
    %{world | nodes: Map.put(world.nodes, updated_node.id, updated_node)}
  end

  def apply(world, {:gravity_changed, gravity, _ts}) do
    %{world | environment: Map.put(world.environment, :gravity, gravity)}
  end

  def apply(world, {:paused, _ts}), do: %{world | paused: true}
  def apply(world, {:resumed, _ts}), do: %{world | paused: false}

  @doc """
  Get the timestamp from an event.
  """
  @spec timestamp(t()) :: integer()
  def timestamp(event) do
    event |> Tuple.to_list() |> List.last()
  end
end
