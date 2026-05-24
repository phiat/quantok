# Quantok - Tokene Physics Sandbox
# Run `just` to see all available commands

default:
    @just --list

# --- Setup ---

# Install all dependencies (elixir + npm), then fetch BPE rank files
setup:
    mix deps.get
    cd assets && npm install
    mix ecto.create
    just download-ranks

# Download BPE rank files into the installed tiktokenex priv dir (one per Mix env)
# Hex packages exclude priv/ranks to keep download size small, so we fetch on demand.
download-ranks env='dev':
    #!/usr/bin/env bash
    set -euo pipefail
    dir="_build/{{env}}/lib/tiktokenex/priv/ranks"
    mkdir -p "$dir"
    for name in cl100k_base o200k_base; do
      f="$dir/$name.tiktoken"
      if [ ! -f "$f" ]; then
        echo "Fetching $name.tiktoken"
        curl -fsSL "https://openaipublic.blob.core.windows.net/encodings/$name.tiktoken" -o "$f"
      fi
    done
    echo "Ranks ready in $dir"

# Create and migrate database
db:
    mix ecto.setup

# Reset database
db-reset:
    mix ecto.reset

# --- Development ---

# Start Phoenix server with IEx
run:
    iex -S mix phx.server

# Alias for `just run`
dev: run

# Start without interactive shell
serve:
    mix phx.server

# Open IEx with project loaded
console:
    iex -S mix

# Quick chunk text from CLI (for debugging chunkers)
chunk text encoding='word':
    mix run -e 'mod = Module.concat(Quantok.Chunker, String.capitalize("{{encoding}}")); IO.inspect(mod.chunk("{{text}}"))'

# Fire an emitter and show output (debug a world in IEx)
fire command='date' chunker='word':
    mix run -e 'mod = Module.concat(Quantok.Chunker, String.capitalize("{{chunker}}")); e = Quantok.Node.Emitter.new(command: "{{command}}", chunker: mod); {:ok, ts} = Quantok.Node.Emitter.fire(e, %{}); Enum.each(ts, &IO.puts(&1.value))'

# List saved worlds
worlds:
    @ls -1 priv/worlds/*.json 2>/dev/null | xargs -I{} basename {} .json || echo "No saved worlds"

# --- Quality ---

# Run all checks (test + credo + compile warnings)
check: test lint compile-check

# Run tests
test *args='':
    mix test {{ args }}

# Run tests with coverage
cover:
    mix test --cover

# Run a specific test file
t file:
    mix test {{ file }}

# Run credo (static analysis)
lint:
    mix credo --strict

# Check for compile warnings
compile-check:
    mix compile --warnings-as-errors

# Format all code
fmt:
    mix format

# Check formatting without changing files
fmt-check:
    mix format --check-formatted

# --- Build ---

# Compile the project
build:
    mix compile

# Build frontend assets
assets:
    mix esbuild quantok
    mix tailwind quantok

# Pre-release pipeline: format-check, lint, test, warnings-as-errors, prod asset build
release-check:
    mix format --check-formatted
    mix credo --strict
    mix test
    mix compile --warnings-as-errors
    mix assets.deploy

# Run the production server (MIX_ENV=prod with digested assets)
prod-run:
    MIX_ENV=prod mix phx.server

# Clean build artifacts
clean:
    mix clean
    rm -rf _build

# Full clean (deps + build + node_modules)
nuke:
    mix clean
    rm -rf _build deps
    cd assets && rm -rf node_modules

# --- Beads (Issue Tracking) ---

# List all issues
issues:
    bd list

# Show ready-to-work issues
ready:
    @bd ready

# Show blocked issues
blocked:
    bd blocked

# Project stats
stats:
    @bd stats

# --- Generators ---

# Generate a new context module
gen-context name:
    mix phx.gen.context {{ name }}

# Generate a new LiveView
gen-live name:
    mix phx.gen.live {{ name }}
