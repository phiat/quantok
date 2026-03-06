defmodule Quantok.NodeTest do
  use ExUnit.Case, async: true

  alias Quantok.Node

  test "new/2 creates a node with unique id" do
    node = Node.new(:emitter)
    assert node.type == :emitter
    assert is_binary(node.id)
  end

  test "new/2 accepts attrs" do
    node = Node.new(:collector, %{label: "My Collector", position: {10.0, 20.0}})
    assert node.label == "My Collector"
    assert node.position == {10.0, 20.0}
  end

  test "unique ids" do
    ids = for _ <- 1..50, do: Node.new(:passive).id
    assert length(Enum.uniq(ids)) == 50
  end
end
