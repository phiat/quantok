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
- **Collectors** absorb tokenes into a buffer, trigger an action when full (echo, reverse, upcase, count, shell)
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

## Collector Buffers

Collectors have visible buffer slots that fill with tokene colors as data is absorbed. Trigger a collector (manually or on-full) to process its buffer contents. See [docs/collector-buffers.md](docs/collector-buffers.md) for the upcoming typed-slot redesign with encoding-aware fit-or-bounce mechanics.

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
| Quality   | Credo, ExUnit (134 tests)           |
| Tasks     | just                                |

## License

MIT
