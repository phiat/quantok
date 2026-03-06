defmodule Quantok.Tokene do
  @moduledoc """
  A tokene is a chunk of data with physical properties.

  Tokenes are the fundamental unit in the Quantok world - they're emitted by
  emitters, fall through the world affected by physics, and are absorbed by
  collectors. Their size and mass derive from byte_size, and their integrity
  determines how resistant they are to splitting.
  """

  @type encoding ::
          :bit | :byte | :rune | :token | :ngram | :word | :phrase | :sentence

  @type t :: %__MODULE__{
          id: binary(),
          value: binary(),
          encoding: encoding(),
          byte_size: non_neg_integer(),
          integrity: float(),
          source_id: binary() | nil,
          created_at: integer(),
          metadata: map()
        }

  @enforce_keys [:id, :value, :encoding]
  defstruct [
    :id,
    :value,
    :encoding,
    :byte_size,
    :source_id,
    integrity: 0.5,
    created_at: 0,
    metadata: %{}
  ]

  @split_hierarchy [:sentence, :phrase, :word, :token, :rune, :byte, :bit]

  @default_integrity %{
    bit: 1.0,
    byte: 0.95,
    rune: 0.8,
    token: 0.6,
    ngram: 0.5,
    word: 0.4,
    phrase: 0.2,
    sentence: 0.1
  }

  @doc """
  Creates a new tokene from a value and encoding.
  """
  @spec new(binary(), encoding(), binary() | nil) :: t()
  def new(value, encoding, source_id \\ nil) do
    %__MODULE__{
      id: generate_id(),
      value: value,
      encoding: encoding,
      byte_size: byte_size(value),
      integrity: Map.fetch!(@default_integrity, encoding),
      source_id: source_id,
      created_at: System.monotonic_time(:millisecond),
      metadata: %{}
    }
  end

  @doc """
  Returns the encoding one level below in the split hierarchy.
  Returns nil if already at the atomic level (:bit).
  """
  @spec child_encoding(encoding()) :: encoding() | nil
  def child_encoding(encoding) do
    case Enum.drop_while(@split_hierarchy, &(&1 != encoding)) do
      [^encoding, child | _] -> child
      _ -> nil
    end
  end

  @doc """
  Returns the encoding one level above in the split hierarchy.
  Returns nil if already at the top level (:sentence).
  """
  @spec parent_encoding(encoding()) :: encoding() | nil
  def parent_encoding(encoding) do
    @split_hierarchy
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn
      [parent, ^encoding] -> parent
      _ -> nil
    end)
  end

  @doc """
  Derives mass from byte_size. Larger tokenes are heavier.
  """
  @spec mass(t()) :: float()
  def mass(%__MODULE__{byte_size: size}) do
    # Base mass + logarithmic scaling so sentences aren't absurdly heavy
    0.1 + :math.log2(max(size, 1)) * 0.5
  end

  @doc """
  Derives display dimensions {width, height} from byte_size.
  """
  @spec dimensions(t()) :: {float(), float()}
  def dimensions(%__MODULE__{value: value}) do
    len = String.length(value || "")
    w = max(len * 7.0, 14.0)
    h = 12.0
    {w, h}
  end

  @doc """
  Returns true if this tokene can be split further.
  """
  @spec splittable?(t()) :: boolean()
  def splittable?(%__MODULE__{encoding: :bit}), do: false
  def splittable?(%__MODULE__{byte_size: 1, encoding: :byte}), do: false
  def splittable?(%__MODULE__{}), do: true

  @doc """
  Returns the split hierarchy as a list from coarsest to finest.
  """
  @spec split_hierarchy() :: [encoding()]
  def split_hierarchy, do: @split_hierarchy

  @doc """
  Returns default integrity for an encoding level.
  """
  @spec default_integrity(encoding()) :: float()
  def default_integrity(encoding), do: Map.fetch!(@default_integrity, encoding)

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
