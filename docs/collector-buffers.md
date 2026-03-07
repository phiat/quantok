# Collector Buffer Redesign

## Overview

Collectors evolve from simple "catch N tokenes" to **physically meaningful buffer containers** where slot encoding, capacity, and geometry drive collection behavior.

## Core Concepts

### Typed Slots

Each buffer slot has an **encoding type** and a **count capacity**:

```elixir
%{
  slot_encoding: :word,   # what encoding this slot accepts
  slot_capacity: 4,       # how many tokenes of that encoding fit
  slots: 4                # number of slots
}
```

**Matching rule**: strict encoding match. A `:word` slot only accepts `:word` tokenes. Mismatched tokenes bounce off. To convert between encodings, use transformers upstream (splitters to go finer, mergers to go coarser).

**Special case**: `:any` encoding accepts all tokenes, measured by byte_size. This is the simple default for new users.

```elixir
# Default — accepts anything, byte-measured
Collector.new(slots: 4, slot_capacity: 16, slot_encoding: :any)

# Typed — only words, count-measured
Collector.new(slots: 4, slot_capacity: 4, slot_encoding: :word)
```

### Fit-or-Bounce

No splitting at collection. A tokene either fits in a slot or it bounces off:

- Tokene byte_size (for :any slots) or count (for typed slots) checked against remaining capacity
- If it fits → absorbed into slot, stacked visually
- If it doesn't fit → impulse applied, tokene bounces away
- Splitting is the job of the **splitter transformer**, not the collector

This creates natural pipeline design: `emitter → splitter → collector`

### Two Collection Modes

**Managed** (default): The collector decides which slot receives the tokene. Scans slots left-to-right, places in first slot with capacity. Single sensor zone covers the whole collector.

```
Tokene "the" (3 bytes) → slot 0 has 5/16 used → fits → slot 0 (8/16)
Tokene "fox" (3 bytes) → slot 0 has 8/16 → fits → slot 0 (11/16)
Tokene "magnificent" (11 bytes) → slot 0 has 11/16, only 5 left → skip → slot 1
```

**Independent**: Each slot has its **own sensor/activation zone** at its opening. Tokenes fall toward specific slots based on physics. Spatial positioning becomes a puzzle.

```
  ┌────┐  ┌────┐  ┌────┐  ┌────┐
  │    │  │ fox│  │    │  │    │
  │    │  │the │  │    │  │    │
  │jump│  │lazy│  │    │  │    │
  │over│  │dog │  │    │  │    │
  └════┘  └════┘  └════┘  └════┘
   1/4     4/4     0/4     0/4
    ↑ each slot has its own sensor at the opening
```

Config: `mode: :managed | :independent`

Default view uses independent mode to emphasize tokenes and make the sandbox visual.

### Bounce Physics

When a tokene is rejected (wrong encoding or slot full):

```
Client: "tokene X near collector Y (slot Z in independent mode)"
Server: check encoding match + capacity
  → {:absorbed, slot_index, stack_position}
  → {:rejected, :wrong_encoding}
  → {:rejected, :slot_full}
  → {:rejected, :collector_full}
Client:
  absorbed → reparent tokene mesh into slot, remove physics body
  rejected → apply bounce impulse away from slot opening
```

### Visual: Stacked Tokenes in Slots

Absorbed tokenes remain visible inside their slots, stacked bottom-up:

- On absorption: tokene mesh reparented into slot group, repositioned to stack
- Tokene loses its physics body but keeps its visual (texture, color, encoding)
- Each slot shows count/capacity indicator
- Full slots glow or change border color
- On trigger/flush: stacked meshes animate out (fade, dissolve, or eject)

### Slot as Physical Container

Each slot is a mini physics container:

```
  ┌──┐   walls = static Rapier bodies
  │  │   floor = static Rapier body
  │  │   opening = sensor zone (activation area)
  └──┘
```

In independent mode, the slot walls physically contain tokenes. In managed mode, walls are visual-only (server routes tokenes, no physical containment needed).

## Encoding Hierarchy Interactions

The existing hierarchy becomes mechanically meaningful:

```
sentence → phrase → word → token → rune → byte → bit
```

- Emitter encoding (determined by chunker) must match collector slot encoding
- Transformers convert between levels:
  - Splitter: coarse → fine (word → tokens, sentence → words)
  - Merger (new): fine → coarse (bytes → word, words → sentence)
- Pipeline design = encoding routing puzzle

### Merger Transformer (New)

Combines N fine-grained tokenes into one coarser tokene:

```
bytes "h","e","l","l","o" → merger(target: :word) → word "hello"
```

Needs a trigger condition (N inputs, or delimiter-based, or manual). Design TBD.

## Trigger Behavior

When a collector triggers (manually, on-full, or on-tick):

1. All slot contents are read (per-slot or concatenated, depending on action config)
2. Action processes the buffer (echo, reverse, upcase, shell, etc.)
3. Slot visuals animate out (consumed)
4. Output optionally re-emitted as new tokenes (if output_chunker configured)

Future: per-slot actions, selective triggering, partial consumption.

## Config Summary

```elixir
%{
  # Slot configuration
  slots: 4,                    # number of buffer slots
  slot_capacity: 4,            # capacity per slot (count for typed, bytes for :any)
  slot_encoding: :word,        # :any | :bit | :byte | :rune | :token | :word | :phrase | :sentence

  # Collection mode
  mode: :independent,          # :managed | :independent

  # Trigger
  trigger_mode: :on_full,      # :on_full | :manual | :on_tick
  tick_interval: 60,           # ticks between auto-triggers

  # Action
  action: Collector.Echo,      # module that processes buffer
  command: "echo",             # command passed to action
  output_chunker: nil          # optional re-emission chunker
}
```

## Implementation Phases

### Phase 1: Byte-aware slots with stacked visuals
- Add slot_capacity (bytes) to collector config
- Track bytes-used-per-slot on server
- Render stacked tokene meshes inside slots (reparent on absorb)
- Fit-or-bounce logic (reject tokenes that don't fit)
- Bounce impulse on client side
- Keep single sensor (managed mode only)

### Phase 2: Encoding-typed slots
- Add slot_encoding to config
- Strict encoding match check on absorb
- Encoding mismatch → bounce
- Update sidebar buttons to show slot encoding options

### Phase 3: Independent mode with per-slot sensors
- Each slot gets its own Rapier sensor at opening
- Slot walls as static physics bodies
- Client reports slot index in sensor events
- Spatial positioning matters

### Phase 4: Merger transformer
- New transformer type: combines fine tokenes into coarse
- Configurable target encoding and trigger condition
- Enables full encoding pipeline: emit → split → merge → collect

### Phase 5: Trigger animations and output
- Slot consumption animation (fade/dissolve/eject)
- Re-emission from collector output port
- Per-slot vs concatenated trigger modes
