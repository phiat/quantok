defmodule Quantok.TokeneTest do
  use ExUnit.Case, async: true

  alias Quantok.Tokene

  describe "new/3" do
    test "creates a tokene with correct defaults" do
      t = Tokene.new("hello", :word, "emitter-1")

      assert t.value == "hello"
      assert t.encoding == :word
      assert t.byte_size == 5
      assert t.integrity == 0.4
      assert t.source_id == "emitter-1"
      assert is_binary(t.id)
    end

    test "sets integrity based on encoding" do
      assert Tokene.new("x", :bit).integrity == 1.0
      assert Tokene.new("x", :byte).integrity == 0.95
      assert Tokene.new("x", :rune).integrity == 0.8
      assert Tokene.new("x", :token).integrity == 0.6
      assert Tokene.new("x", :word).integrity == 0.4
      assert Tokene.new("x", :phrase).integrity == 0.2
      assert Tokene.new("x", :sentence).integrity == 0.1
    end

    test "computes byte_size from value" do
      assert Tokene.new("", :byte).byte_size == 0
      assert Tokene.new("a", :byte).byte_size == 1
      assert Tokene.new("hello", :word).byte_size == 5
      # Multi-byte unicode (fire emoji = 4 bytes UTF-8)
      assert Tokene.new("\u{1F525}", :rune).byte_size == 4
    end
  end

  describe "child_encoding/1" do
    test "returns next level down" do
      assert Tokene.child_encoding(:sentence) == :phrase
      assert Tokene.child_encoding(:phrase) == :word
      assert Tokene.child_encoding(:word) == :token
      assert Tokene.child_encoding(:token) == :rune
      assert Tokene.child_encoding(:rune) == :byte
      assert Tokene.child_encoding(:byte) == :bit
    end

    test "returns nil for atomic level" do
      assert Tokene.child_encoding(:bit) == nil
    end
  end

  describe "parent_encoding/1" do
    test "returns next level up" do
      assert Tokene.parent_encoding(:bit) == :byte
      assert Tokene.parent_encoding(:byte) == :rune
      assert Tokene.parent_encoding(:word) == :phrase
    end

    test "returns nil for top level" do
      assert Tokene.parent_encoding(:sentence) == nil
    end
  end

  describe "mass/1" do
    test "larger tokenes have more mass" do
      small = Tokene.new("a", :byte)
      large = Tokene.new("hello world this is a sentence", :sentence)

      assert Tokene.mass(large) > Tokene.mass(small)
    end

    test "mass is always positive" do
      empty = Tokene.new("", :byte)
      assert Tokene.mass(empty) > 0
    end
  end

  describe "dimensions/1" do
    test "larger tokenes have bigger dimensions" do
      small = Tokene.new("a", :byte)
      large = Tokene.new("hello world", :word)

      {sw, _sh} = Tokene.dimensions(small)
      {lw, _lh} = Tokene.dimensions(large)

      assert lw > sw
    end

    test "dimensions have minimum sizes" do
      tiny = Tokene.new("", :bit)
      {w, h} = Tokene.dimensions(tiny)

      assert w >= 12.0
      assert h >= 12.0
    end
  end

  describe "splittable?/1" do
    test "bits cannot be split" do
      refute Tokene.splittable?(Tokene.new("x", :bit))
    end

    test "single bytes can be split into bits" do
      # Single-byte tokenes are atomic at the byte level but still
      # decomposable into 8 bits, so the cascade word→token→rune→byte→bit
      # never dead-ends prematurely.
      assert Tokene.splittable?(Tokene.new("x", :byte))
    end

    test "multi-byte bytes can be split" do
      assert Tokene.splittable?(Tokene.new("hello", :byte))
    end

    test "words can be split" do
      assert Tokene.splittable?(Tokene.new("hello", :word))
    end
  end

  describe "new/3 with decay opts" do
    test "decay disabled by default" do
      t = Tokene.new("hello", :word)
      assert t.decay.enabled == false
      assert t.decay.half_life == :infinite
      assert t.decay.shatter == :split
    end

    test "decay enabled computes half_life from encoding base" do
      t = Tokene.new("hello", :word, decay: %{enabled: true, rate: 1.0, shatter: :dissolve})
      assert t.decay.enabled == true
      assert t.decay.half_life == 30_000
      assert t.decay.shatter == :dissolve
    end

    test "decay rate scales half_life" do
      t = Tokene.new("hello", :word, decay: %{enabled: true, rate: 2.0})
      # word base is 30_000, rate 2.0 -> 15_000
      assert t.decay.half_life == 15_000
    end

    test "bit encoding always has infinite half_life" do
      t = Tokene.new("1", :bit, decay: %{enabled: true, rate: 1.0})
      assert t.decay.half_life == :infinite
    end

    test "keyword opts with source_id and decay" do
      t = Tokene.new("x", :byte, source_id: "e1", decay: %{enabled: true, rate: 1.0})
      assert t.source_id == "e1"
      assert t.decay.enabled == true
      assert t.decay.half_life == 120_000
    end
  end

  describe "current_integrity/1" do
    test "returns base integrity when decay disabled" do
      t = Tokene.new("hello", :word)
      assert Tokene.current_integrity(t) == 0.4
    end

    test "returns base integrity when half_life is infinite" do
      t = Tokene.new("1", :bit, decay: %{enabled: true, rate: 1.0})
      assert Tokene.current_integrity(t) == 1.0
    end

    test "integrity decreases over time when decay enabled" do
      t = Tokene.new("hello", :word, decay: %{enabled: true, rate: 1.0})
      # Immediately after creation, integrity should be close to initial
      assert_in_delta Tokene.current_integrity(t), 0.4, 0.01

      # Simulate elapsed time by backdating created_at
      old_t = %{t | created_at: t.created_at - 30_000}
      # After one half-life (30s for word), integrity should be ~half
      assert_in_delta Tokene.current_integrity(old_t), 0.2, 0.02
    end
  end

  describe "shattered?/1" do
    test "not shattered when decay disabled" do
      t = Tokene.new("hello", :word)
      refute Tokene.shattered?(t)
    end

    test "shattered after many half-lives" do
      t = Tokene.new("hello", :word, decay: %{enabled: true, rate: 1.0})
      # Backdate by 5 half-lives (150s) — integrity should be ~0.0125
      old_t = %{t | created_at: t.created_at - 150_000}
      assert Tokene.shattered?(old_t)
    end
  end

  describe "base_half_life/1" do
    test "returns encoding-specific half-lives" do
      assert Tokene.base_half_life(:sentence) == 8_000
      assert Tokene.base_half_life(:word) == 30_000
      assert Tokene.base_half_life(:byte) == 120_000
      assert Tokene.base_half_life(:bit) == :infinite
    end

    test "token_id is more stable than token (it's the compressed form)" do
      assert Tokene.base_half_life(:token_id) > Tokene.base_half_life(:token)
    end
  end

  describe "token_id encoding" do
    test "creates with numeric value, has higher integrity than token" do
      tok = Tokene.new("hello", :token, "src")
      tid = Tokene.new("15339", :token_id, "src")

      assert tid.encoding == :token_id
      assert tid.value == "15339"
      assert tid.integrity > tok.integrity
    end

    test "child_encoding/1 routes token_id to rune (digit chars)" do
      assert Tokene.child_encoding(:token_id) == :rune
    end

    test "splittable and splits its digit string into runes" do
      t = Tokene.new("15339", :token_id, decay: %{enabled: true, rate: 1.0, shatter: :split})
      assert Tokene.splittable?(t)
      {:ok, :split, children} = Tokene.shatter(t)
      assert length(children) == 5
      assert Enum.all?(children, &(&1.encoding == :rune))
      assert Enum.map(children, & &1.value) == ["1", "5", "3", "3", "9"]
    end
  end

  describe "shatter/1" do
    test "split produces child-encoding tokenes" do
      t = Tokene.new("hello world", :word, decay: %{enabled: true, rate: 1.0, shatter: :split})
      {:ok, :split, children} = Tokene.shatter(t)
      assert children != []
      assert Enum.all?(children, &(&1.encoding == :token))
    end

    test "dissolve returns empty list" do
      t = Tokene.new("hello", :word, decay: %{enabled: true, rate: 1.0, shatter: :dissolve})
      assert {:ok, :dissolve, []} = Tokene.shatter(t)
    end

    test "explode shatters to bytes" do
      t = Tokene.new("hello", :word, decay: %{enabled: true, rate: 1.0, shatter: :explode})
      {:ok, :explode, fragments} = Tokene.shatter(t)
      assert length(fragments) == 5
      assert Enum.all?(fragments, &(&1.encoding == :byte))
    end

    test "fossilize returns frozen tokene" do
      t = Tokene.new("hello", :word, decay: %{enabled: true, rate: 1.0, shatter: :fossilize})
      {:ok, :fossilize, [fossil]} = Tokene.shatter(t)
      assert fossil.decay.enabled == false
      assert fossil.decay.half_life == :infinite
    end

    test "bits always fossilize regardless of shatter config" do
      t = Tokene.new("1", :bit, decay: %{enabled: true, rate: 1.0, shatter: :dissolve})
      {:ok, :fossilize, [fossil]} = Tokene.shatter(t)
      assert fossil.encoding == :bit
      assert fossil.decay.enabled == false
    end

    test "bit tokene fossilizes on split (only truly-atomic level)" do
      t = Tokene.new("1", :bit, decay: %{enabled: true, rate: 1.0, shatter: :split})
      {:ok, :fossilize, [fossil]} = Tokene.shatter(t)
      assert fossil.decay.enabled == false
    end

    test "split cascade reaches bits all the way down" do
      # Hierarchy: word -> token -> rune -> byte -> bit -> (fossilize)
      start = Tokene.new("hi", :word, decay: %{enabled: true, rate: 1.0, shatter: :split})

      final =
        Enum.reduce([:token, :rune, :byte, :bit], start, fn target, parent ->
          {:ok, :split, children} = Tokene.shatter(parent)
          assert children != [], "no children when splitting from #{parent.encoding}"
          child = hd(children)
          assert child.encoding == target, "expected #{target}, got #{child.encoding}"
          # Children spawn with shatter: :split by default; we don't need to
          # re-attach decay since shatter only reads decay.shatter.
          child
        end)

      # At a bit. Further shatter must fossilize, not split.
      assert final.encoding == :bit
      {:ok, :fossilize, [fossil]} = Tokene.shatter(final)
      assert fossil.encoding == :bit
      assert fossil.decay.enabled == false
    end
  end

  describe "unique IDs" do
    test "each tokene gets a unique id" do
      ids = for _ <- 1..100, do: Tokene.new("x", :byte).id
      assert length(Enum.uniq(ids)) == 100
    end
  end
end
