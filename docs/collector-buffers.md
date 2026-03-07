# Collector Buffer Redesign

## Overview

Collectors evolve from simple "catch N tokenes" to **physically meaningful buffer containers** with configurable trigger modes, directional ports, output re-emission, and emitter pairing.

## Node Ports (Universal)

Every node that has input or output flow gets **ports** with configurable direction. This applies to emitters, collectors, and transformers.

```elixir
%{
  input_port: %{direction: :top, offset: 0.0},
  output_port: %{direction: :bottom, offset: 0.0}
}
```

**Directions**: `:top | :bottom | :left | :right | :none`

- `direction` controls where the pipe spout renders, where sensors sit, where tokenes spawn/enter
- `offset` shifts the port laterally (-1.0 to 1.0) from center
- Configurable in hover menu (click to cycle direction)

```
    :top input                    :left input
       │                              │
   ┌───▼───┐                    ┌─────┤
   │       │                    │     │
   │  Node │                    │Node │
   │       │                    │     │
   └───┬───┘                    └─────┤
       │                              │
       ▼ :bottom output               ▼ :right output
```

**Defaults:**
- Emitters: `output: :bottom, input: :none`
- Collectors: `input: :top, output: :none` (or `:bottom` if output_mode is :emit)
- Transformers: `input: :top, output: :bottom`

This enables horizontal pipelines — use angled passives to deflect tokenes sideways into `:left`/`:right` ports.

## Trigger Modes

| Mode | When it fires | Timing basis | Use case |
|------|--------------|--------------|----------|
| `:manual` | User clicks "trigger" | — | Debugging, exploration |
| `:on_full` | Buffer hits capacity | — | Batch processing |
| `:timed` | Every N physics ticks | Physics time | Streaming, periodic processing |
| `:on_tick` | Every N physics ticks (legacy alias) | Physics time | Same as :timed |

### Timed Trigger Behavior

- Physics-tick based (synced with simulation speed, pauses when world pauses)
- Server tracks `ticks_since_trigger` on each physics step
- On tick threshold: if buffer non-empty, trigger. If empty, skip.
- Timer resets after any trigger (manual, full, or timed)
- Visual: progress arc/fill ring around collector showing time until next trigger

```elixir
%{
  trigger_mode: :timed,
  tick_interval: 120,         # physics ticks between triggers (~4s at 30 tick/s)
}
```

## Output Modes

After a collector triggers, its action processes the buffer text. The **output mode** determines what happens to the result:

| Mode | Behavior |
|------|----------|
| `:discard` | Output displayed/logged, not re-emitted (default) |
| `:emit` | Output re-chunked into new tokenes, emitted from output port |
| `:paired` | Buffer text sent as input to paired emitter, which fires with its own config |

### `:emit` — Collector as Processor

The collector re-chunks the action output and emits new tokenes from its output port.

```elixir
%{
  output_mode: :emit,
  output_chunker: Quantok.Chunker.Word,    # how to rechunk output
}
```

**Flow:**
```
Emitter (date · word) → "Thu" "Mar" "6" "2025"
    ↓ gravity
Collector (reverse · 4 slots · timed 120 ticks)
    ↓ trigger fires
    action: reverse → "5202 6 raM uhT"
    output_chunker: Word → "5202" "6" "raM" "uhT"
    ↓ emit from output port
New tokenes enter world with physics
```

Collector renders a pipe spout on its output port side (like emitters).

### `:paired` — Collector Controls an Emitter

The collector feeds its buffer contents to a paired emitter as input, then the emitter fires with its own chunker/config.

```elixir
%{
  output_mode: :paired,
  paired_emitter_id: "emitter-abc",
}
```

**Behavior:**
1. On trigger, collector's buffer text becomes the paired emitter's command input
2. Paired emitter fires with its own chunker, encoding, decay config
3. New tokenes appear from the emitter's output port (not the collector's)

**Use cases:**
- **Clock-driven pipeline**: timed collector triggers emitter on schedule
- **Data routing**: collect words, feed to emitter that re-chunks as bytes
- **Processing chains**: collect → reverse → feed to emitter → collect again

**Feedback loop safety**: Paired triggers carry a depth counter. Max depth = 3. If a trigger chain exceeds this, the final trigger is silently dropped. Prevents runaway `A→B→A→B→...` loops.

## Typed Slots

Each buffer slot has an **encoding type** and a **count capacity**:

```elixir
%{
  slot_encoding: :word,   # what encoding this slot accepts
  slot_capacity: 4,       # how many tokenes of that encoding fit
  slots: 4                # number of slots
}
```

**Matching rule**: strict encoding match. A `:word` slot only accepts `:word` tokenes. Mismatched tokenes bounce off. Use transformers upstream to convert between encodings.

**Special case**: `:any` encoding accepts all tokenes, measured by byte_size. Default for new users.

### Fit-or-Bounce

No splitting at collection. A tokene either fits or bounces:

- Byte_size (`:any` slots) or count (typed slots) checked against remaining capacity
- Fits → absorbed, stacked visually
- Doesn't fit → impulse applied, tokene bounces away
- Splitting is the job of the splitter transformer, not the collector

### Two Collection Modes

**Managed** (default): Collector routes tokenes to first slot with capacity. Single sensor zone.

**Independent**: Each slot has its own sensor at its opening. Tokenes fall into specific slots based on physics. Spatial positioning becomes a puzzle.

Config: `mode: :managed | :independent`

### Bounce Physics

```
Client: "tokene X near collector Y (slot Z in independent mode)"
Server: check encoding match + capacity
  → {:absorbed, slot_index, stack_position}
  → {:rejected, :wrong_encoding}
  → {:rejected, :slot_full}
  → {:rejected, :collector_full}
Client:
  absorbed → reparent tokene mesh into slot, remove physics body
  rejected → apply bounce impulse away from port opening
```

### Visual: Stacked Tokenes in Slots

- Absorbed tokenes visible inside slots, stacked from opening inward
- Tokene loses physics body, keeps visual (texture, color, encoding)
- Count/capacity indicator per slot
- Full slots glow or change border color
- On trigger: stacked meshes animate out (fade, dissolve, eject)

## Full Config

```elixir
%{
  # Slots
  slots: 4,
  slot_capacity: 4,
  slot_encoding: :any,
  mode: :managed,

  # Trigger
  trigger_mode: :on_full,       # :on_full | :manual | :timed
  tick_interval: 120,           # ticks between triggers (for :timed)

  # Action
  action: Collector.Echo,
  command: "echo",

  # Output
  output_mode: :discard,        # :discard | :emit | :paired
  output_chunker: nil,          # for :emit mode
  paired_emitter_id: nil,       # for :paired mode

  # Ports
  input_port: %{direction: :top, offset: 0.0},
  output_port: %{direction: :none, offset: 0.0},

  # State
  buffer: [],
  ticks_since_trigger: 0
}
```

## Encoding Hierarchy

```
sentence → phrase → word → token → rune → byte → bit
```

- Emitter encoding (chunker) must match collector slot encoding (typed mode)
- Transformers convert between levels:
  - Splitter: coarse → fine (word → tokens)
  - Merger (new): fine → coarse (bytes → word)
- Pipeline design = encoding routing puzzle

### Merger Transformer (New)

Combines N fine tokenes into one coarser tokene:

```
bytes "h","e","l","l","o" → merger(target: :word) → word "hello"
```

Needs a trigger condition (N inputs, delimiter-based, or manual). Design TBD.

## Implementation Phases

### Phase 1: Trigger modes + output emission
- Implement `:timed` trigger mode (physics-tick based)
- Add `output_mode: :emit` with `output_chunker`
- Collector emits new tokenes from output port after trigger
- Pipe spout rendering on output port
- Timer progress visual (arc/ring)

### Phase 2: Emitter pairing
- Add `output_mode: :paired` with `paired_emitter_id`
- On trigger, send buffer text as emitter input
- Paired emitter fires with its own config
- Feedback loop depth guard (max 3)
- UI: drag-connect collector to emitter to create pairing

### Phase 3: Configurable ports
- Add port direction config to all nodes (emitters, collectors, transformers)
- Port direction affects sensor placement, tokene spawn position, pipe rendering
- Hover menu: cycle port direction
- Enable horizontal pipeline layouts

### Phase 4: Typed slots + fit-or-bounce
- Add slot_encoding to collector config
- Strict encoding match on absorb
- Bounce impulse for rejected tokenes
- Byte-aware capacity for :any slots

### Phase 5: Independent mode + stacked visuals
- Per-slot sensors with own activation zones
- Slot walls as static physics bodies
- Stacked tokene rendering inside slots
- Trigger consumption animation

### Phase 6: Merger transformer
- New transformer type: combines fine tokenes into coarse
- Configurable target encoding and trigger condition
- Full encoding pipeline: emit → split → merge → collect
