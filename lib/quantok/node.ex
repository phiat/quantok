defmodule Quantok.Node do
  @moduledoc """
  Behaviour and common structure for all nodes in the Quantok world.

  Nodes are the interactive elements: emitters produce tokenes, collectors
  absorb them, transformers modify them, and passives shape the physical world.
  """

  @type node_type :: :emitter | :collector | :transformer | :passive
  @type position :: {float(), float()}

  @type t :: %__MODULE__{
          id: binary(),
          type: node_type(),
          label: String.t(),
          position: position(),
          config: map(),
          created_at: integer()
        }

  @enforce_keys [:id, :type]
  defstruct [
    :id,
    :type,
    label: "",
    position: {0.0, 0.0},
    config: %{},
    created_at: 0
  ]

  @callback tick(node :: t(), context :: map()) ::
              {:ok, t()} | {:ok, t(), [event :: term()]}

  @doc """
  Creates a new node with a generated ID.
  """
  @spec new(node_type(), map()) :: t()
  def new(type, attrs \\ %{}) do
    %__MODULE__{
      id: generate_id(),
      type: type,
      label: Map.get(attrs, :label, ""),
      position: Map.get(attrs, :position, {0.0, 0.0}),
      config: Map.get(attrs, :config, %{}),
      created_at: System.monotonic_time(:millisecond)
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
