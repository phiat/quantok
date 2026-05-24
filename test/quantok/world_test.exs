defmodule Quantok.WorldTest do
  use ExUnit.Case, async: true

  import Quantok.WorldHelpers

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
      emitter = manual_emitter("hello world", chunker: Quantok.Chunker.Word)
      tokenes = fire_into(w, emitter)

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
      collector = Collector.new(capacity: 5)
      {:ok, _} = World.add_node(w, collector)

      emitter = manual_emitter("test", chunker: Quantok.Chunker.Word)
      [tokene] = fire_into(w, emitter)

      {:ok, :ok} = World.absorb_tokene(w, collector.id, tokene.id)

      state = World.get_state(w)
      refute Map.has_key?(state.tokenes, tokene.id)
      collector_state = state.nodes[collector.id]
      assert length(collector_state.config.buffer) == 1
    end

    test "auto-trigger on_full collector", %{world: w} do
      collector = Collector.new(capacity: 1, trigger_mode: :on_full)
      {:ok, _} = World.add_node(w, collector)

      emitter = manual_emitter("x")
      [tokene] = fire_into(w, emitter)

      {:ok, :full} = World.absorb_tokene(w, collector.id, tokene.id)

      state = World.get_state(w)
      assert state.nodes[collector.id].config.buffer == []
    end

    test "absorb into full collector triggers and clears", %{world: w} do
      collector = Collector.new(capacity: 2, trigger_mode: :on_full)
      {:ok, _} = World.add_node(w, collector)

      emitter = manual_emitter("ab")
      [t1, t2] = fire_into(w, emitter)

      {:ok, :ok} = World.absorb_tokene(w, collector.id, t1.id)
      {:ok, :full} = World.absorb_tokene(w, collector.id, t2.id)

      state = World.get_state(w)
      assert state.nodes[collector.id].config.buffer == []
    end
  end

  describe "transformer" do
    test "apply transformer to tokene", %{world: w} do
      transformer = Transformer.new(:duplicator)
      {:ok, _} = World.add_node(w, transformer)

      emitter = manual_emitter("hi", chunker: Quantok.Chunker.Word)
      [tokene] = fire_into(w, emitter)

      {:ok, result} = World.apply_transformer(w, transformer.id, tokene.id)
      assert length(result) == 2

      state = World.get_state(w)
      assert map_size(state.tokenes) == 2
      assert Enum.all?(Map.values(state.tokenes), &(&1.value == "hi"))
    end
  end

  describe "collector trigger" do
    test "manual trigger returns output", %{world: w} do
      collector = Collector.new(trigger_mode: :manual)
      {:ok, _} = World.add_node(w, collector)
      fill_collector(w, collector.id, "hello", chunker: Quantok.Chunker.Word)

      {:ok, output} = World.trigger_collector(w, collector.id)
      assert output == "hello"

      state = World.get_state(w)
      assert state.nodes[collector.id].config.buffer == []
    end
  end

  describe "tokene removal" do
    test "remove offscreen tokene", %{world: w} do
      emitter = manual_emitter("x")
      [tokene] = fire_into(w, emitter)

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
      emitter = manual_emitter("test", chunker: Quantok.Chunker.Word)
      fire_into(w, emitter)

      events = World.get_events(w)
      types = Enum.map(events, &elem(&1, 0))
      assert :node_added in types
      assert :emitted in types
    end

    test "events can be filtered by type", %{world: w} do
      emitter = manual_emitter("test", chunker: Quantok.Chunker.Word)
      fire_into(w, emitter)

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

      rebuilt =
        Enum.reduce(
          events,
          %Quantok.World{id: actual_state.id, name: actual_state.name},
          fn event, acc ->
            Event.apply(acc, event)
          end
        )

      assert map_size(rebuilt.nodes) == map_size(actual_state.nodes)
      assert map_size(rebuilt.tokenes) == map_size(actual_state.tokenes)
      assert Map.keys(rebuilt.nodes) == Map.keys(actual_state.nodes)
      assert Map.keys(rebuilt.tokenes) == Map.keys(actual_state.tokenes)
    end
  end

  describe "tick" do
    test "tick increments tick_count", %{world: w} do
      World.tick(w)
      sync(w)
      state = World.get_state(w)
      assert state.tick_count == 1
    end

    test "tick does nothing when paused", %{world: w} do
      World.pause(w)
      World.tick(w)
      sync(w)
      state = World.get_state(w)
      assert state.tick_count == 0
    end

    test "timed collector triggers after enough ticks", %{world: w} do
      collector = Collector.new(trigger_mode: :timed, tick_interval: 3, capacity: 8)
      {:ok, _} = World.add_node(w, collector)
      fill_collector(w, collector.id, "x")

      Enum.each(1..3, fn _ -> World.tick(w) end)
      sync(w)

      state = World.get_state(w)
      assert state.nodes[collector.id].config.buffer == []
    end

    test "timed collector resets ticks_since_trigger after trigger", %{world: w} do
      collector = Collector.new(trigger_mode: :timed, tick_interval: 2, capacity: 8)
      {:ok, _} = World.add_node(w, collector)
      fill_collector(w, collector.id, "x")

      Enum.each(1..2, fn _ -> World.tick(w) end)
      sync(w)

      state = World.get_state(w)
      assert state.nodes[collector.id].config.ticks_since_trigger == 0
    end
  end

  describe "collector emit" do
    test "trigger with emit creates new tokenes in world", %{world: w} do
      collector =
        Collector.new(
          capacity: 8,
          trigger_mode: :manual,
          action: Quantok.Node.Collector.Reverse,
          emit: true,
          output_chunker: Quantok.Chunker.Byte
        )

      {:ok, _} = World.add_node(w, collector)
      fill_collector(w, collector.id, "abc", chunker: Quantok.Chunker.Word)

      {:ok, output} = World.trigger_collector(w, collector.id)
      assert output == "cba"

      state = World.get_state(w)
      values = state.tokenes |> Map.values() |> Enum.map(& &1.value) |> Enum.sort()
      assert values == ["a", "b", "c"]
    end

    test "emitted tokenes have collector as source_id", %{world: w} do
      collector =
        Collector.new(
          capacity: 8,
          trigger_mode: :manual,
          action: Quantok.Node.Collector.Echo,
          emit: true,
          output_chunker: Quantok.Chunker.Byte
        )

      {:ok, _} = World.add_node(w, collector)
      fill_collector(w, collector.id, "hi", chunker: Quantok.Chunker.Word)

      {:ok, _output} = World.trigger_collector(w, collector.id)

      state = World.get_state(w)
      emitted = Map.values(state.tokenes)
      assert Enum.all?(emitted, &(&1.source_id == collector.id))
    end

    test "emit broadcasts with collector emit_rate", %{world: w} do
      state = World.get_state(w)
      Phoenix.PubSub.subscribe(Quantok.PubSub, "world:#{state.id}")

      collector =
        Collector.new(
          capacity: 8,
          trigger_mode: :manual,
          action: Quantok.Node.Collector.Echo,
          emit: true,
          output_chunker: Quantok.Chunker.Word,
          emit_rate: 500
        )

      {:ok, _} = World.add_node(w, collector)
      assert_receive {:node_added, _}

      fill_collector(w, collector.id, "hello", chunker: Quantok.Chunker.Word)
      {:ok, _} = World.trigger_collector(w, collector.id)

      collector_id = collector.id
      assert_receive {:emit, ^collector_id, _tokenes, 500}
    end

    test "collector rejects absorbing its own emitted tokenes", %{world: w} do
      collector =
        Collector.new(
          capacity: 2,
          trigger_mode: :on_full,
          emit: true,
          output_chunker: Quantok.Chunker.Byte,
          action: Quantok.Node.Collector.Echo
        )

      {:ok, _} = World.add_node(w, collector)
      fill_collector(w, collector.id, "ab", chunker: Quantok.Chunker.Byte)

      state = World.get_state(w)
      emitted = Map.values(state.tokenes) |> hd()
      assert emitted.source_id == collector.id

      # Self-absorb should be rejected
      assert {:error, :self} = World.absorb_tokene(w, collector.id, emitted.id)

      # Another collector can absorb it
      other = Collector.new(capacity: 8)
      {:ok, _} = World.add_node(w, other)
      assert {:ok, :ok} = World.absorb_tokene(w, other.id, emitted.id)
    end

    test "non-emit collector does not create tokenes", %{world: w} do
      collector =
        Collector.new(
          capacity: 8,
          trigger_mode: :manual,
          emit: false
        )

      {:ok, _} = World.add_node(w, collector)
      fill_collector(w, collector.id, "hello", chunker: Quantok.Chunker.Word)

      {:ok, output} = World.trigger_collector(w, collector.id)
      assert output == "hello"

      state = World.get_state(w)
      assert state.tokenes == %{}
    end
  end

  describe "fire_all_emitters" do
    test "fires all emitters in single call", %{world: w} do
      e1 = manual_emitter("a")
      e2 = manual_emitter("b")
      {:ok, _} = World.add_node(w, e1)
      {:ok, _} = World.add_node(w, e2)

      {:ok, tokenes} = World.fire_all_emitters(w)
      values = Enum.map(tokenes, & &1.value) |> Enum.sort()
      assert values == ["a", "b"]

      state = World.get_state(w)
      assert map_size(state.tokenes) == 2
    end

    test "returns empty list when no emitters", %{world: w} do
      {:ok, tokenes} = World.fire_all_emitters(w)
      assert tokenes == []
    end
  end

  describe "event log compaction" do
    test "events are capped after periodic tick", %{world: w} do
      # Generate many events by firing emitters repeatedly
      emitter = manual_emitter("a b c d e f g h i j", chunker: Quantok.Chunker.Word)
      {:ok, _} = World.add_node(w, emitter)

      for _ <- 1..100 do
        {:ok, _} = World.fire_emitter(w, emitter.id)
      end

      events_before = World.get_events(w)
      assert length(events_before) > 100

      # Tick 300 times to trigger compaction
      for _ <- 1..300 do
        World.tick(w)
      end

      sync(w)

      events_after = World.get_events(w)
      assert length(events_after) <= 10_000
    end
  end

  describe "supervised start" do
    test "start_supervised creates a world under DynamicSupervisor" do
      {:ok, pid} = World.start_supervised(world_name: "Supervised World")
      state = World.get_state(pid)
      assert state.name == "Supervised World"
      DynamicSupervisor.terminate_child(Quantok.WorldSupervisor, pid)
    end
  end

  describe "pubsub events" do
    test "emitter fire broadcasts event", %{world: w} do
      state = World.get_state(w)
      Phoenix.PubSub.subscribe(Quantok.PubSub, "world:#{state.id}")

      emitter = manual_emitter("test", chunker: Quantok.Chunker.Word)
      {:ok, _} = World.add_node(w, emitter)

      assert_receive {:node_added, _}

      {:ok, _tokenes} = World.fire_emitter(w, emitter.id)
      expected_id = emitter.id
      assert_receive {:emit, ^expected_id, received_tokenes, emit_rate}
      assert length(received_tokenes) == 1
      assert hd(received_tokenes).value == "test"
      assert is_integer(emit_rate)
    end
  end
end
