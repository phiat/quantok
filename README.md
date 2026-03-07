# Quantok

A physics sandbox where data chunks are physical objects.

Emitters produce **tokenes** from commands and data. Tokenes fall through a 2D world affected by gravity, collide with surfaces, pass through transformers, and land in collectors that trigger actions. The chunking granularity — bits, bytes, runes, BPE tokens, words, phrases, sentences — determines a tokene's mass, size, and physical behavior.

## Quick Start

```bash
just setup   # install deps, create db, download BPE ranks
just dev     # start Phoenix server with IEx
```

Open [localhost:4000](http://localhost:4000). You'll see an emitter, a floor, and a collector. Click **fire all** to watch `date` output fall as word-tokenes.

## How It Works

```
Emitter (runs "date")
    |
    | pipe drops tokenes: "Thu" "Mar" "6" "2026" ...
    v
  [gravity]
    |
    v
Collector (8 slots) -> triggers action when full
```

- **Emitters** execute a source (shell command, clock, sequence, manual text) and chunk the output
- **Collectors** absorb tokenes into a buffer, trigger an action (echo, reverse, upcase, count, shell). Trigger modes: on-full, manual, or timed (physics-tick interval). Output modes: discard or emit (re-chunk output as new tokenes)
- **Transformers** modify tokenes by proximity — split, crush, heat, cool, filter, duplicate, paint
- **Passives** are static geometry — floors, walls, ramps, funnels

Nodes are draggable. Hover over a node for contextual actions (fire, trigger, clear, rotate, delete). Scroll to zoom, shift+drag to pan.

## Architecture

**Server** (Elixir/Phoenix): World GenServer owns all state with event sourcing — every mutation is recorded as a timestamped event. Emitter firing, absorption, transforms, and triggers are server-authoritative. Events broadcast via PubSub. Full event log enables replay and state reconstruction.

**Client** (Three.js + Rapier2D): Renders the scene with an orthographic camera. troika-three-text for crisp SDF text at any zoom. Bloom post-processing for subtle glow effects. Rapier2D WASM handles physics simulation. Sensor zones detect tokene proximity to collectors and transformers, reporting intersections to the server.

The server never simulates physics. The client never executes commands.

See [docs/architecture.md](docs/architecture.md) for the full module map and data flow.

## Chunking

The core mechanic. The same data chunked at different granularities produces tokenes with different physical properties:

| Encoding | Chunker   | Feel     | Example: "Hello"              |
|----------|-----------|----------|-------------------------------|
| bit      | Bit       | sand     | "0","1","0","0","1",...        |
| byte     | Byte      | gravel   | "H","e","l","l","o"           |
| rune     | Rune      | pebble   | "H","e","l","l","o"           |
| token    | BPE       | stone    | "Hello"                       |
| word     | Word      | brick    | "Hello"                       |
| phrase   | Phrase    | block    | "Hello"                       |
| sentence | Sentence  | boulder  | "Hello"                       |

Smaller chunks = lighter, more numerous. Larger chunks = heavier, fewer. A sentence-boulder behaves very differently from a stream of bit-sand.

## Tokene Decay

Tokenes can optionally decay over time. Each encoding level has a base half-life — coarse encodings (sentences, phrases) decay fast while fine encodings (bytes, bits) are stable or indestructible. Toggle decay globally from the topbar.

| Encoding | Half-life | Feel |
|----------|-----------|------|
| sentence | 8s        | fragile boulder |
| phrase   | 15s       | crumbling block |
| word     | 30s       | weathering brick |
| byte     | 2 min     | slow erosion |
| bit      | infinite  | indestructible |

Three config layers: world defaults, emitter overrides, encoding base half-lives. Decay is computed client-side per-frame (desaturation + opacity fade + death pulse). When integrity drops below threshold, tokenes shatter with one of four behaviors: **split** (child encoding), **dissolve** (vanish), **explode** (burst to bytes), or **fossilize** (freeze as static).

## Collector Buffers

Collectors have visible buffer slots that fill with tokene colors as data is absorbed. Three trigger modes control when a collector fires:

| Mode | When it fires |
|------|--------------|
| `:on_full` | Buffer hits capacity (default) |
| `:manual` | User clicks "trigger" |
| `:timed` | Every N physics ticks (~4s at 30Hz) |

After triggering, the output mode controls what happens to the result:

| Mode | Behavior |
|------|----------|
| `:discard` | Output displayed/logged, not re-emitted (default) |
| `:emit` | Output re-chunked into new tokenes, emitted into the world |

See [docs/collector-buffers.md](docs/collector-buffers.md) for the full redesign plan including emitter pairing, configurable ports, typed slots, and encoding-aware fit-or-bounce mechanics.

## Tiktokenex

Quantok includes a standalone pure-Elixir BPE tokenizer compatible with OpenAI's tiktoken encodings (cl100k_base, o200k_base). No NIFs required. See [tiktokenex/](tiktokenex/).

## Development

```bash
just check      # run tests + credo + compile warnings (both projects)
just test       # quantok tests only
just lint       # credo --strict
just fmt        # format all code
```

## Tech Stack

| Layer     | Choice                              |
|-----------|-------------------------------------|
| Backend   | Elixir, Phoenix 1.8, LiveView       |
| Rendering | Three.js, troika-three-text         |
| Physics   | Rapier2D (WASM)                     |
| PostFX    | Three.js EffectComposer, bloom      |
| Tokenizer | Tiktokenex (pure Elixir BPE)        |
| Database  | SQLite (dev) / Postgres (prod)      |
| Quality   | Credo, ExUnit (161 tests)           |
| Tasks     | just                                |

## License

MIT
