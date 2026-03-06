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
