defmodule Quantok.Node.CollectorTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Collector
  alias Quantok.Tokene

  describe "new/1" do
    test "creates a collector with defaults" do
      node = Collector.new()
      assert node.type == :collector
      assert node.config.capacity == 8
      assert node.config.buffer == []
    end

    test "accepts custom capacity" do
      node = Collector.new(capacity: 3)
      assert node.config.capacity == 3
    end
  end

  describe "absorb/2" do
    test "adds tokene to buffer" do
      node = Collector.new(capacity: 3)
      tokene = Tokene.new("hello", :word)

      {:ok, updated} = Collector.absorb(node, tokene)
      assert Collector.buffer_count(updated) == 1
    end

    test "returns :full when buffer reaches capacity" do
      node = Collector.new(capacity: 2)
      t1 = Tokene.new("a", :byte)
      t2 = Tokene.new("b", :byte)

      {:ok, node} = Collector.absorb(node, t1)
      {:full, node} = Collector.absorb(node, t2)
      assert Collector.buffer_count(node) == 2
    end
  end

  describe "buffer_text/1" do
    test "concatenates buffer values" do
      node = Collector.new(capacity: 5)

      {:ok, node} = Collector.absorb(node, Tokene.new("hello", :word))
      {:ok, node} = Collector.absorb(node, Tokene.new(" ", :byte))
      {:ok, node} = Collector.absorb(node, Tokene.new("world", :word))

      assert Collector.buffer_text(node) == "hello world"
    end

    test "empty buffer returns empty string" do
      node = Collector.new()
      assert Collector.buffer_text(node) == ""
    end
  end

  describe "trigger/1" do
    test "returns buffer text and clears buffer" do
      node = Collector.new()
      {:ok, node} = Collector.absorb(node, Tokene.new("test", :word))

      {:ok, output, cleared} = Collector.trigger(node)
      assert output == "test"
      assert Collector.buffer_count(cleared) == 0
    end

    test "resets ticks_since_trigger to 0" do
      node = Collector.new(trigger_mode: :timed, tick_interval: 3)
      {:ok, node} = Collector.absorb(node, Tokene.new("a", :byte))
      {:ok, node} = Collector.tick(node)
      {:ok, node} = Collector.tick(node)
      assert node.config.ticks_since_trigger == 2

      {:ok, _output, cleared} = Collector.trigger(node)
      assert cleared.config.ticks_since_trigger == 0
    end
  end

  describe "tick/1" do
    test "increments ticks_since_trigger for timed collectors" do
      node = Collector.new(trigger_mode: :timed, tick_interval: 5)
      {:ok, node} = Collector.tick(node)
      assert node.config.ticks_since_trigger == 1
    end

    test "triggers when tick threshold reached and buffer non-empty" do
      node = Collector.new(trigger_mode: :timed, tick_interval: 2)
      {:ok, node} = Collector.absorb(node, Tokene.new("a", :byte))
      {:ok, node} = Collector.tick(node)
      {:trigger, node} = Collector.tick(node)
      assert node.config.ticks_since_trigger == 2
    end

    test "does not trigger when buffer empty even at threshold" do
      node = Collector.new(trigger_mode: :timed, tick_interval: 1)
      {:ok, node} = Collector.tick(node)
      assert node.config.ticks_since_trigger == 1
    end

    test "non-timed collectors just return :ok" do
      node = Collector.new(trigger_mode: :on_full)
      {:ok, same} = Collector.tick(node)
      assert same == node
    end
  end

  describe "trigger/1 with emit mode" do
    test "returns tokenes when output_mode is :emit with chunker" do
      node = Collector.new(
        output_mode: :emit,
        output_chunker: Quantok.Chunker.Word,
        action: Quantok.Node.Collector.Echo
      )
      {:ok, node} = Collector.absorb(node, Tokene.new("hello world", :word))
      {:ok, output, cleared, tokenes} = Collector.trigger(node)

      assert output == "hello world"
      assert Collector.buffer_count(cleared) == 0
      assert length(tokenes) == 2
      assert Enum.map(tokenes, & &1.value) == ["hello", "world"]
    end

    test "returns 3-tuple when output_mode is :discard" do
      node = Collector.new(output_mode: :discard)
      {:ok, node} = Collector.absorb(node, Tokene.new("test", :word))
      {:ok, _output, _cleared} = Collector.trigger(node)
    end
  end

  describe "trigger/1 with paired mode" do
    test "returns paired tuple when output_mode is :paired with paired_emitter_id" do
      node = Collector.new(
        output_mode: :paired,
        paired_emitter_id: "emitter-123",
        action: Quantok.Node.Collector.Reverse
      )
      {:ok, node} = Collector.absorb(node, Tokene.new("hello", :word))
      {:paired, output, cleared, emitter_id} = Collector.trigger(node)

      assert output == "olleh"
      assert emitter_id == "emitter-123"
      assert Collector.buffer_count(cleared) == 0
    end

    test "returns 3-tuple when paired_emitter_id is not set" do
      node = Collector.new(output_mode: :paired)
      {:ok, node} = Collector.absorb(node, Tokene.new("test", :word))
      {:ok, _output, _cleared} = Collector.trigger(node)
    end
  end

  describe "full?/1" do
    test "false when buffer has space" do
      node = Collector.new(capacity: 5)
      refute Collector.full?(node)
    end

    test "true when buffer is at capacity" do
      node = Collector.new(capacity: 1)
      {:full, node} = Collector.absorb(node, Tokene.new("x", :byte))
      assert Collector.full?(node)
    end
  end
end
