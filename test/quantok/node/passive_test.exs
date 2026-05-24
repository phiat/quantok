defmodule Quantok.Node.PassiveTest do
  use ExUnit.Case, async: true

  alias Quantok.Node.Passive

  test "creates a floor with defaults" do
    node = Passive.new(:floor)
    assert node.type == :passive
    assert node.config.shape == :floor
    assert node.config.width == 200.0
    assert node.label == "Floor"
  end

  test "creates an attractor" do
    node = Passive.new(:attractor, strength: 2.0, radius: 150.0)
    assert node.config.strength == 2.0
    assert node.config.radius == 150.0
  end

  test "force_element? for attractor/repeller" do
    assert Passive.force_element?(Passive.new(:attractor))
    assert Passive.force_element?(Passive.new(:repeller))
    refute Passive.force_element?(Passive.new(:floor))
  end

  test "solid? for collision surfaces" do
    assert Passive.solid?(Passive.new(:floor))
    assert Passive.solid?(Passive.new(:wall))
    assert Passive.solid?(Passive.new(:ramp))
    assert Passive.solid?(Passive.new(:funnel))
    assert Passive.solid?(Passive.new(:conveyor))
    refute Passive.solid?(Passive.new(:attractor))
    refute Passive.solid?(Passive.new(:repeller))
  end

  test "creates a conveyor with surface speed and grippy friction" do
    node = Passive.new(:conveyor)
    assert node.config.shape == :conveyor
    assert node.config.speed == 80.0
    assert node.config.friction == 0.9
    assert node.label == "Conveyor"
  end

  test "conveyor speed is overridable (signed for direction)" do
    node = Passive.new(:conveyor, speed: -160.0)
    assert node.config.speed == -160.0
  end

  test "conveyor?/1" do
    assert Passive.conveyor?(Passive.new(:conveyor))
    refute Passive.conveyor?(Passive.new(:floor))
  end
end
