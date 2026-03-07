# Quantok - Tokene Physics Sandbox
# Run `just` to see all available commands

default:
    @just --list

# --- Setup ---

# Install all dependencies (elixir + tiktokenex + npm + ranks)
setup:
    mix deps.get
    cd tiktokenex && mix deps.get
    cd assets && npm install
    cd tiktokenex && just download-ranks
    mix ecto.create

# Create and migrate database
db:
    mix ecto.setup

# Reset database
db-reset:
    mix ecto.reset

# --- Development ---

# Start Phoenix server with IEx
dev:
    iex -S mix phx.server

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

# Run all checks (test + credo + compile warnings) for both projects
check: check-quantok check-ttex

# Run Quantok checks
check-quantok: test lint compile-check

# Run tiktokenex checks
check-ttex:
    cd tiktokenex && just check

# Run Quantok tests
test *args='':
    mix test {{ args }}

# Run all tests (Quantok + tiktokenex)
test-all:
    mix test
    cd tiktokenex && mix test

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
    cd tiktokenex && mix format

# Check formatting without changing files
fmt-check:
    mix format --check-formatted
    cd tiktokenex && mix format --check-formatted

# --- Build ---

# Compile the project
build:
    mix compile

# Build frontend assets
assets:
    mix esbuild quantok
    mix tailwind quantok

# Clean build artifacts
clean:
    mix clean
    rm -rf _build

# Full clean (deps + build + tiktokenex + node_modules)
nuke:
    mix clean
    rm -rf _build deps
    cd assets && rm -rf node_modules
    cd tiktokenex && rm -rf _build deps

# --- Beads (Issue Tracking) ---

# List all Quantok issues
issues:
    bd list

# List tiktokenex issues
issues-ttex:
    cd tiktokenex && bd list

# Show ready-to-work issues (both projects)
ready:
    @echo "=== Quantok ==="
    @bd ready
    @echo ""
    @echo "=== Tiktokenex ==="
    @cd tiktokenex && bd ready

# Show blocked issues
blocked:
    bd blocked

# Project stats
stats:
    @echo "=== Quantok ==="
    @bd stats
    @echo ""
    @echo "=== Tiktokenex ==="
    @cd tiktokenex && bd stats

# --- Generators ---

# Generate a new context module
gen-context name:
    mix phx.gen.context {{ name }}

# Generate a new LiveView
gen-live name:
    mix phx.gen.live {{ name }}
