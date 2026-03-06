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
- **Passives** are static geometry — floors, walls, ramps, funnels, attractors, repellers

Nodes are draggable. Hover over a node for contextual actions (fire, trigger, clear, rotate, delete).

## Architecture

**Server** (Elixir/Phoenix): World GenServer owns all state. Emitter firing, absorption, transforms, and triggers are server-authoritative. Events broadcast via PubSub.

**Client** (Three.js + Rapier2D): Renders the scene with an orthographic camera. Rapier2D WASM handles physics simulation. Sensor zones detect tokene proximity to collectors and transformers, reporting intersections to the server.

The server never simulates physics. The client never executes commands.

See [docs/architecture.md](docs/architecture.md) for the full module map, data flow, and tech stack.

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

## Tiktokenex

Quantok includes a standalone pure-Elixir BPE tokenizer compatible with OpenAI's tiktoken encodings (cl100k_base, o200k_base). No NIFs required. See [tiktokenex/](tiktokenex/).

## Development

```bash
just check      # run tests + credo + compile warnings (both projects)
just test       # quantok tests only
just lint       # credo --strict
just fmt        # format all code
just ready      # show available beads issues
```

## Tech Stack

| Layer     | Choice                        |
|-----------|-------------------------------|
| Backend   | Elixir, Phoenix 1.8, LiveView |
| Rendering | Three.js (ortho camera)       |
| Physics   | Rapier2D (WASM)               |
| Tokenizer | Tiktokenex (pure Elixir)      |
| Database  | SQLite (dev) / Postgres (prod)|
| Quality   | Credo, ExUnit (130+ tests)    |
| Tasks     | just, beads                   |

## License

MIT
