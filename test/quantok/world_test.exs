defmodule Quantok.WorldTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.{Collector, Emitter, Transformer}
  alias Quantok.World

  setup do
    {:ok, pid} = World.start_link(world_name: "Test World")
    %{world: pid}
  end

  describe "state" do
    test "initial state", %{world: w} do
      state = World.get_state(w)
      assert state.name == "Test World"
      assert state.nodes == %{}
      assert state.tokenes == %{}
      assert state.paused == false
    end
  end

  describe "nodes" do
    test "add and retrieve a node", %{world: w} do
      emitter = Emitter.new(command: "echo test")
      {:ok, _} = World.add_node(w, emitter)

      state = World.get_state(w)
      assert Map.has_key?(state.nodes, emitter.id)
    end

    test "remove a node", %{world: w} do
      emitter = Emitter.new()
      {:ok, _} = World.add_node(w, emitter)
      {:ok, removed} = World.remove_node(w, emitter.id)

      assert removed.id == emitter.id
      state = World.get_state(w)
      refute Map.has_key?(state.nodes, emitter.id)
    end

    test "update a node", %{world: w} do
      emitter = Emitter.new(label: "Old")
      {:ok, _} = World.add_node(w, emitter)
      {:ok, updated} = World.update_node(w, emitter.id, %{label: "New"})

      assert updated.label == "New"
    end

    test "update non-existent node returns error", %{world: w} do
      assert {:error, :not_found} = World.update_node(w, "fake-id", %{label: "x"})
    end
  end

  describe "emitter firing" do
    test "fire emitter creates tokenes in world", %{world: w} do
      emitter = Emitter.new(command: "echo hello world", chunker: Quantok.Chunker.Word)
      {:ok, _} = World.add_node(w, emitter)
      {:ok, tokenes} = World.fire_emitter(w, emitter.id)

      assert length(tokenes) == 2
      state = World.get_state(w)
      assert map_size(state.tokenes) == 2
    end

    test "fire non-existent emitter returns error", %{world: w} do
      assert {:error, :not_found} = World.fire_emitter(w, "fake-id")
    end
  end

  describe "collector absorption" do
    test "absorb tokene into collector", %{world: w} do
      emitter = Emitter.new(command: "echo test", chunker: Quantok.Chunker.Word)
      collector = Collector.new(capacity: 5)

      {:ok, _} = World.add_node(w, emitter)
      {:ok, _} = World.add_node(w, collector)
      {:ok, [tokene]} = World.fire_emitter(w, emitter.id)

      {:ok, :ok} = World.absorb_tokene(w, collector.id, tokene.id)

      state = World.get_state(w)
      # Tokene removed from world
      refute Map.has_key?(state.tokenes, tokene.id)
      # Tokene in collector buffer
      collector_state = state.nodes[collector.id]
      assert length(collector_state.config.buffer) == 1
    end

    test "auto-trigger on_full collector", %{world: w} do
      collector = Collector.new(capacity: 1, trigger_mode: :on_full)
      {:ok, _} = World.add_node(w, collector)

      emitter =
        Emitter.new(
          source: Quantok.Node.Emitter.Manual,
          command: "x",
          chunker: Quantok.Chunker.Byte
        )

      {:ok, _} = World.add_node(w, emitter)
      {:ok, [tokene]} = World.fire_emitter(w, emitter.id)

      {:ok, :full} = World.absorb_tokene(w, collector.id, tokene.id)

      # Buffer should be cleared after auto-trigger
      state = World.get_state(w)
      assert state.nodes[collector.id].config.buffer == []
    end
  end

  describe "transformer" do
    test "apply transformer to tokene", %{world: w} do
      transformer = Transformer.new(:duplicator)
      {:ok, _} = World.add_node(w, transformer)

      emitter =
        Emitter.new(
          source: Quantok.Node.Emitter.Manual,
          command: "hi",
          chunker: Quantok.Chunker.Word
        )

      {:ok, _} = World.add_node(w, emitter)
      {:ok, [tokene]} = World.fire_emitter(w, emitter.id)

      {:ok, result} = World.apply_transformer(w, transformer.id, tokene.id)
      assert length(result) == 2

      state = World.get_state(w)
      # Duplicator keeps original + adds copy
      assert map_size(state.tokenes) == 2
      assert Enum.all?(Map.values(state.tokenes), &(&1.value == "hi"))
    end
  end

  describe "collector trigger" do
    test "manual trigger returns output", %{world: w} do
      collector = Collector.new(trigger_mode: :manual)
      {:ok, _} = World.add_node(w, collector)

      emitter =
        Emitter.new(
          source: Quantok.Node.Emitter.Manual,
          command: "hello",
          chunker: Quantok.Chunker.Word
        )

      {:ok, _} = World.add_node(w, emitter)
      {:ok, [tokene]} = World.fire_emitter(w, emitter.id)
      {:ok, :ok} = World.absorb_tokene(w, collector.id, tokene.id)

      {:ok, output} = World.trigger_collector(w, collector.id)
      assert output == "hello"

      state = World.get_state(w)
      assert state.nodes[collector.id].config.buffer == []
    end
  end

  describe "tokene removal" do
    test "remove offscreen tokene", %{world: w} do
      emitter =
        Emitter.new(
          source: Quantok.Node.Emitter.Manual,
          command: "x",
          chunker: Quantok.Chunker.Byte
        )

      {:ok, _} = World.add_node(w, emitter)
      {:ok, [tokene]} = World.fire_emitter(w, emitter.id)

      :ok = World.remove_tokene(w, tokene.id)
      state = World.get_state(w)
      assert state.tokenes == %{}
    end
  end

  describe "controls" do
    test "pause and resume", %{world: w} do
      World.pause(w)
      assert World.get_state(w).paused == true

      World.resume(w)
      assert World.get_state(w).paused == false
    end

    test "set gravity", %{world: w} do
      World.set_gravity(w, {0.0, 20.0})
      state = World.get_state(w)
      assert state.environment.gravity == {0.0, 20.0}
    end
  end

  describe "event sourcing" do
    test "events are recorded", %{world: w} do
      emitter = Emitter.new(command: "echo test", chunker: Quantok.Chunker.Word)
      {:ok, _} = World.add_node(w, emitter)
      {:ok, _} = World.fire_emitter(w, emitter.id)

      events = World.get_events(w)
      types = Enum.map(events, &elem(&1, 0))
      assert :node_added in types
      assert :emitted in types
    end

    test "events can be filtered by type", %{world: w} do
      emitter = Emitter.new(command: "echo test", chunker: Quantok.Chunker.Word)
      {:ok, _} = World.add_node(w, emitter)
      {:ok, _} = World.fire_emitter(w, emitter.id)

      events = World.get_events(w, types: [:emitted])
      assert length(events) == 1
      assert elem(hd(events), 0) == :emitted
    end

    test "state can be rebuilt from events", %{world: w} do
      alias Quantok.World.Event

      emitter = Emitter.new(command: "echo hi", chunker: Quantok.Chunker.Word)
      collector = Collector.new(capacity: 8)
      {:ok, _} = World.add_node(w, emitter)
      {:ok, _} = World.add_node(w, collector)
      {:ok, _} = World.fire_emitter(w, emitter.id)

      events = World.get_events(w)
      actual_state = World.get_state(w)

      # Replay events from scratch
      rebuilt =
        Enum.reduce(events, %Quantok.World{id: actual_state.id, name: actual_state.name}, fn event, acc ->
          Event.apply(acc, event)
        end)

      assert map_size(rebuilt.nodes) == map_size(actual_state.nodes)
      assert map_size(rebuilt.tokenes) == map_size(actual_state.tokenes)
      assert Map.keys(rebuilt.nodes) == Map.keys(actual_state.nodes)
      assert Map.keys(rebuilt.tokenes) == Map.keys(actual_state.tokenes)
    end
  end

  describe "tick" do
    test "tick increments tick_count", %{world: w} do
      World.tick(w)
      # cast is async, give it a moment
      Process.sleep(10)
      state = World.get_state(w)
      assert state.tick_count == 1
    end

    test "tick does nothing when paused", %{world: w} do
      World.pause(w)
      World.tick(w)
      Process.sleep(10)
      state = World.get_state(w)
      assert state.tick_count == 0
    end

    test "timed collector triggers after enough ticks", %{world: w} do
      collector = Collector.new(trigger_mode: :timed, tick_interval: 3, capacity: 8)
      {:ok, _} = World.add_node(w, collector)

      emitter = Emitter.new(source: Quantok.Node.Emitter.Manual, command: "x", chunker: Quantok.Chunker.Byte)
      {:ok, _} = World.add_node(w, emitter)
      {:ok, [tokene]} = World.fire_emitter(w, emitter.id)
      {:ok, :ok} = World.absorb_tokene(w, collector.id, tokene.id)

      # Tick 3 times to hit the interval
      Enum.each(1..3, fn _ ->
        World.tick(w)
        Process.sleep(5)
      end)
      Process.sleep(10)

      state = World.get_state(w)
      assert state.nodes[collector.id].config.buffer == []
    end
  end

  describe "emit output mode" do
    test "trigger with emit mode creates new tokenes in world", %{world: w} do
      collector = Collector.new(
        capacity: 8,
        trigger_mode: :manual,
        action: Quantok.Node.Collector.Reverse,
        output_mode: :emit,
        output_chunker: Quantok.Chunker.Byte
      )
      {:ok, _} = World.add_node(w, collector)

      emitter = Emitter.new(source: Quantok.Node.Emitter.Manual, command: "abc", chunker: Quantok.Chunker.Word)
      {:ok, _} = World.add_node(w, emitter)
      {:ok, [tokene]} = World.fire_emitter(w, emitter.id)
      {:ok, :ok} = World.absorb_tokene(w, collector.id, tokene.id)

      {:ok, output} = World.trigger_collector(w, collector.id)
      assert output == "cba"

      state = World.get_state(w)
      # Reverse of "abc" = "cba", chunked by byte = ["c", "b", "a"]
      values = state.tokenes |> Map.values() |> Enum.map(& &1.value) |> Enum.sort()
      assert values == ["a", "b", "c"]
    end
  end

  describe "pubsub events" do
    test "emitter fire broadcasts event", %{world: w} do
      state = World.get_state(w)
      Phoenix.PubSub.subscribe(Quantok.PubSub, "world:#{state.id}")

      emitter =
        Emitter.new(
          source: Quantok.Node.Emitter.Manual,
          command: "test",
          chunker: Quantok.Chunker.Word
        )

      {:ok, _} = World.add_node(w, emitter)

      # Flush the :node_added message
      assert_receive {:node_added, _}

      {:ok, _tokenes} = World.fire_emitter(w, emitter.id)
      expected_id = emitter.id
      assert_receive {:emit, ^expected_id, received_tokenes}
      assert length(received_tokenes) == 1
      assert hd(received_tokenes).value == "test"
    end
  end
end
