defmodule Quantok.Node.Passive do
  @moduledoc """
  Passive nodes are static world elements that shape physics.

  Config:
  - :shape - :floor | :wall | :ramp | :funnel | :attractor | :repeller | :conveyor
  - :width / :height - dimensions
  - :angle - rotation for ramps (radians)
  - :strength - force magnitude for attractors/repellers
  - :radius - effect radius for attractors/repellers
  - :friction - surface friction coefficient
  - :restitution - bounciness (0.0 = no bounce, 1.0 = perfect bounce)
  - :speed - surface velocity for conveyors (px/s, signed; negative = leftward in local frame)
  """

  alias Quantok.Node

  @type shape :: :floor | :wall | :ramp | :funnel | :attractor | :repeller | :conveyor

  @doc """
  Creates a new passive node.
  """
  @spec new(shape(), keyword()) :: Node.t()
  def new(shape, opts \\ []) do
    config = %{
      shape: shape,
      width: Keyword.get(opts, :width, default_width(shape)),
      height: Keyword.get(opts, :height, default_height(shape)),
      angle: Keyword.get(opts, :angle, 0.0),
      strength: Keyword.get(opts, :strength, 1.0),
      radius: Keyword.get(opts, :radius, 100.0),
      friction: Keyword.get(opts, :friction, default_friction(shape)),
      restitution: Keyword.get(opts, :restitution, 0.3),
      speed: Keyword.get(opts, :speed, default_speed(shape))
    }

    Node.new(:passive, %{
      label: Keyword.get(opts, :label, passive_label(shape)),
      position: Keyword.get(opts, :position, {0.0, 0.0}),
      config: config
    })
  end

  @doc """
  Returns true if this passive is a force-based element (attractor/repeller).
  """
  @spec force_element?(Node.t()) :: boolean()
  def force_element?(%Node{config: %{shape: :attractor}}), do: true
  def force_element?(%Node{config: %{shape: :repeller}}), do: true
  def force_element?(_), do: false

  @doc """
  Returns true if this passive is a solid collision surface.
  """
  @spec solid?(Node.t()) :: boolean()
  def solid?(%Node{config: %{shape: shape}})
      when shape in [:floor, :wall, :ramp, :funnel, :conveyor],
      do: true

  def solid?(_), do: false

  @doc """
  Returns true if this passive applies a surface velocity (conveyor).
  """
  @spec conveyor?(Node.t()) :: boolean()
  def conveyor?(%Node{config: %{shape: :conveyor}}), do: true
  def conveyor?(_), do: false

  defp default_width(:floor), do: 200.0
  defp default_width(:wall), do: 10.0
  defp default_width(:ramp), do: 150.0
  defp default_width(:funnel), do: 120.0
  defp default_width(:conveyor), do: 240.0
  defp default_width(_), do: 0.0

  defp default_height(:floor), do: 10.0
  defp default_height(:wall), do: 150.0
  defp default_height(:ramp), do: 10.0
  defp default_height(:funnel), do: 80.0
  defp default_height(:conveyor), do: 12.0
  defp default_height(_), do: 0.0

  defp default_friction(:conveyor), do: 0.9
  defp default_friction(_), do: 0.5

  defp default_speed(:conveyor), do: 80.0
  defp default_speed(_), do: 0.0

  defp passive_label(:floor), do: "Floor"
  defp passive_label(:wall), do: "Wall"
  defp passive_label(:ramp), do: "Ramp"
  defp passive_label(:funnel), do: "Funnel"
  defp passive_label(:attractor), do: "Attractor"
  defp passive_label(:repeller), do: "Repeller"
  defp passive_label(:conveyor), do: "Conveyor"
end
