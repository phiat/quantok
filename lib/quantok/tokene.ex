defmodule Quantok.Tokene do
  @moduledoc """
  A tokene is a chunk of data with physical properties.

  Tokenes are the fundamental unit in the Quantok world - they're emitted by
  emitters, fall through the world affected by physics, and are absorbed by
  collectors. Their size and mass derive from byte_size, and their integrity
  determines how resistant they are to splitting.

  ## Decay

  Tokenes can optionally decay over time based on their encoding's base
  half-life, modified by world and emitter rate multipliers. Decay is off
  by default. When integrity reaches 0, the tokene shatters according to
  its configured shatter behavior (:split, :dissolve, :explode, :fossilize).
  """

  @type encoding ::
          :bit | :byte | :rune | :token | :token_id | :ngram | :word | :phrase | :sentence

  @type shatter :: :split | :dissolve | :explode | :fossilize

  @type decay_config :: %{
          enabled: boolean(),
          half_life: number() | :infinite,
          shatter: shatter()
        }

  @type t :: %__MODULE__{
          id: binary(),
          value: binary(),
          encoding: encoding(),
          byte_size: non_neg_integer(),
          integrity: float(),
          source_id: binary() | nil,
          created_at: integer(),
          metadata: map(),
          decay: decay_config()
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
    metadata: %{},
    decay: %{enabled: false, half_life: :infinite, shatter: :split}
  ]

  @split_hierarchy [:sentence, :phrase, :word, :token, :rune, :byte, :bit]

  @default_integrity %{
    bit: 1.0,
    byte: 0.95,
    rune: 0.8,
    token: 0.6,
    # token_id is the numeric form of a token — same granularity, but a more
    # "compressed" representation, so we give it slightly higher integrity.
    token_id: 0.7,
    ngram: 0.5,
    word: 0.4,
    phrase: 0.2,
    sentence: 0.1
  }

  # Base half-lives in milliseconds per encoding level.
  # Coarse encodings decay fast, fine encodings are stable.
  @base_half_life %{
    sentence: 8_000,
    phrase: 15_000,
    word: 30_000,
    token: 45_000,
    token_id: 60_000,
    ngram: 50_000,
    rune: 60_000,
    byte: 120_000,
    bit: :infinite
  }

  @doc """
  Creates a new tokene from a value and encoding.
  Accepts optional keyword opts for source_id and decay config.
  """
  @spec new(binary(), encoding(), binary() | nil | keyword()) :: t()
  def new(value, encoding, source_id_or_opts \\ nil)

  def new(value, encoding, opts) when is_list(opts) do
    source_id = Keyword.get(opts, :source_id)
    decay_opts = Keyword.get(opts, :decay, %{})
    do_new(value, encoding, source_id, decay_opts)
  end

  def new(value, encoding, source_id) do
    do_new(value, encoding, source_id, %{})
  end

  defp do_new(value, encoding, source_id, decay_opts) do
    enabled = Map.get(decay_opts, :enabled, false)
    rate = Map.get(decay_opts, :rate, 1.0)
    shatter = Map.get(decay_opts, :shatter, :split)

    base = Map.fetch!(@base_half_life, encoding)

    half_life =
      if base == :infinite or not enabled do
        :infinite
      else
        round(base / max(rate, 0.01))
      end

    %__MODULE__{
      id: generate_id(),
      value: value,
      encoding: encoding,
      byte_size: byte_size(value),
      integrity: Map.fetch!(@default_integrity, encoding),
      source_id: source_id,
      created_at: System.monotonic_time(:millisecond),
      metadata: %{},
      decay: %{enabled: enabled, half_life: half_life, shatter: shatter}
    }
  end

  @doc """
  Returns the base half-life (ms) for an encoding level.
  """
  @spec base_half_life(encoding()) :: non_neg_integer() | :infinite
  def base_half_life(encoding), do: Map.fetch!(@base_half_life, encoding)

  @doc """
  Compute current integrity based on elapsed time and decay config.
  Returns the original integrity if decay is disabled.
  """
  @spec current_integrity(t()) :: float()
  def current_integrity(%__MODULE__{decay: %{enabled: false}, integrity: i}), do: i
  def current_integrity(%__MODULE__{decay: %{half_life: :infinite}, integrity: i}), do: i

  def current_integrity(%__MODULE__{integrity: initial, created_at: created_at, decay: decay}) do
    elapsed = System.monotonic_time(:millisecond) - created_at
    initial * :math.pow(0.5, elapsed / decay.half_life)
  end

  @doc """
  Returns true if the tokene has decayed past the shatter threshold.
  """
  @spec shattered?(t()) :: boolean()
  def shattered?(tokene), do: current_integrity(tokene) < 0.05

  @doc """
  Shatters a tokene according to its decay shatter behavior.
  Returns `{:ok, behavior, result_tokenes}`.

  - `:split` — split into child encoding chunks
  - `:dissolve` — removed, no fragments
  - `:explode` — shatter all the way to bytes
  - `:fossilize` — return a frozen copy (integrity locked, decay disabled)
  """
  @spec shatter(t()) :: {:ok, shatter(), [t()]}
  def shatter(%__MODULE__{encoding: :bit} = tokene), do: {:ok, :fossilize, [fossilize(tokene)]}

  def shatter(%__MODULE__{decay: %{shatter: :dissolve}}), do: {:ok, :dissolve, []}

  def shatter(%__MODULE__{decay: %{shatter: :split}} = tokene) do
    if splittable?(tokene) do
      child_enc = child_encoding(tokene.encoding)
      chunker = chunker_for_encoding(child_enc)
      chunks = chunker.chunk(tokene.value)
      children = Enum.map(chunks, &new(&1, child_enc, source_id: tokene.source_id))
      {:ok, :split, children}
    else
      {:ok, :fossilize, [fossilize(tokene)]}
    end
  end

  def shatter(%__MODULE__{decay: %{shatter: :explode}} = tokene) do
    chunks = chunker_for_encoding(:byte).chunk(tokene.value)
    fragments = Enum.map(chunks, &new(&1, :byte, source_id: tokene.source_id))
    {:ok, :explode, fragments}
  end

  def shatter(%__MODULE__{decay: %{shatter: :fossilize}} = tokene) do
    {:ok, :fossilize, [fossilize(tokene)]}
  end

  defp fossilize(tokene) do
    %{
      tokene
      | decay: %{enabled: false, half_life: :infinite, shatter: :fossilize},
        integrity: max(current_integrity(tokene), 0.05)
    }
  end

  defp chunker_for_encoding(:sentence), do: Quantok.Chunker.Sentence
  defp chunker_for_encoding(:phrase), do: Quantok.Chunker.Phrase
  defp chunker_for_encoding(:word), do: Quantok.Chunker.Word
  defp chunker_for_encoding(:token), do: Quantok.Chunker.BPE
  defp chunker_for_encoding(:rune), do: Quantok.Chunker.Rune
  defp chunker_for_encoding(:byte), do: Quantok.Chunker.Byte
  defp chunker_for_encoding(:bit), do: Quantok.Chunker.Bit
  defp chunker_for_encoding(_), do: Quantok.Chunker.Byte

  @doc """
  Returns the encoding one level below in the split hierarchy.
  Returns nil if already at the atomic level (:bit).

  `:token_id` is not in the linear hierarchy (it's an alternate representation
  of `:token`, not a finer granularity), but splitting a token_id chunks its
  digit string into rune characters, so we route it to `:rune`.
  """
  @spec child_encoding(encoding()) :: encoding() | nil
  def child_encoding(:token_id), do: :rune

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
    0.1 + :math.log2(max(size, 1)) * 0.5
  end

  @doc """
  Derives display dimensions {width, height} from byte_size.
  """
  # Approximate per-character pixel width matching the client's SDF font at
  # height 12 — chosen so the box hugs the rendered text with minimal padding.
  @char_px 5.5

  @spec dimensions(t()) :: {float(), float()}
  def dimensions(%__MODULE__{} = tokene) do
    len = String.length(display_value(tokene))
    w = max(len * @char_px, 12.0)
    h = 12.0
    {w, h}
  end

  @doc """
  Returns a JSON-safe string for the tokene's value. Byte-chunked emoji and
  bit tokenes produce sub-rune or sub-byte binaries that aren't valid UTF-8,
  so we represent them as hex (`F0`) or bit (`0`/`1`) glyphs the client can render.
  """
  @spec display_value(t()) :: String.t()
  def display_value(%__MODULE__{value: value, encoding: :bit}) do
    case value do
      <<0::1>> -> "0"
      <<1::1>> -> "1"
      _ -> "?"
    end
  end

  def display_value(%__MODULE__{value: value}) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      value
      |> :binary.bin_to_list()
      |> Enum.map_join(" ", &Integer.to_string(&1, 16))
      |> String.upcase()
    end
  end

  def display_value(%__MODULE__{}), do: ""

  @doc """
  Returns true if this tokene can be split further.
  """
  @spec splittable?(t()) :: boolean()
  def splittable?(%__MODULE__{encoding: :bit}), do: false
  # A 1-byte byte tokene is still splittable into 8 bits — atomic only at :bit.
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
