defmodule Quantok.Node.Passive do
  @moduledoc """
  Passive nodes are static world elements that shape physics.

  Config:
  - :shape - :floor | :wall | :ramp | :attractor | :repeller | :conveyor | :portal
  - :width / :height - dimensions
  - :angle - rotation for ramps (radians)
  - :strength - force magnitude for attractors/repellers
  - :radius - effect radius for attractors/repellers/portals
  - :friction - surface friction coefficient
  - :restitution - bounciness (0.0 = no bounce, 1.0 = perfect bounce)
  - :speed - surface velocity for conveyors (px/s, signed; negative = leftward in local frame)
  - :channel - pairing key for portals (same channel = paired endpoints)
  """

  alias Quantok.Node

  @type shape ::
          :floor | :wall | :ramp | :attractor | :repeller | :conveyor | :portal

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
      radius: Keyword.get(opts, :radius, default_radius(shape)),
      friction: Keyword.get(opts, :friction, default_friction(shape)),
      restitution: Keyword.get(opts, :restitution, 0.3),
      speed: Keyword.get(opts, :speed, default_speed(shape)),
      channel: Keyword.get(opts, :channel, default_channel(shape))
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
      when shape in [:floor, :wall, :ramp, :conveyor],
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
  defp default_width(:conveyor), do: 240.0
  defp default_width(:portal), do: 40.0
  defp default_width(_), do: 0.0

  defp default_height(:floor), do: 10.0
  defp default_height(:wall), do: 150.0
  defp default_height(:ramp), do: 10.0
  defp default_height(:conveyor), do: 12.0
  defp default_height(:portal), do: 40.0
  defp default_height(_), do: 0.0

  defp default_radius(:portal), do: 30.0
  defp default_radius(_), do: 100.0

  defp default_friction(:conveyor), do: 0.9
  defp default_friction(_), do: 0.5

  defp default_speed(:conveyor), do: 80.0
  defp default_speed(_), do: 0.0

  defp default_channel(:portal), do: "A"
  defp default_channel(_), do: nil

  defp passive_label(:floor), do: "Floor"
  defp passive_label(:wall), do: "Wall"
  defp passive_label(:ramp), do: "Ramp"
  defp passive_label(:attractor), do: "Attractor"
  defp passive_label(:repeller), do: "Repeller"
  defp passive_label(:conveyor), do: "Conveyor"
  defp passive_label(:portal), do: "Portal"
end
