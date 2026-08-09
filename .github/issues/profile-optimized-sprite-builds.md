# Profile optimized sprite builds instead of unoptimized debug code

## Summary

`make flame-build` currently compiles the selected example with `-debug` but
without an optimization mode:

```make
odin build examples/$(FLAME_EXAMPLE) -collection:pkg=. -out:$(FLAME_BIN) -debug
```

This makes the flamegraph useful for debugging but misleading for performance
decisions. The current profiles largely describe code that will disappear or
be inlined in an optimized build.

## Evidence

The two checked-in `crowd` profiles were captured from this unoptimized binary.
They report:

- `engine::draw_sprite`: 9.56% and 12.22% self time
- `engine::to_clip`: 5.33% and 5.51% self time
- `engine::sprite_feet_quad`: 3.98% and 3.30% self time
- Additional time in string hashing/map lookup, bounds checks, and dynamic
  array append helpers

A CPU-only benchmark using the real `draw_sprite`, real baked toad metadata,
preallocated draw list, changing sprite positions, and two million draws per
trial produced:

| Build | Median time per draw | Trials |
| --- | ---: | ---: |
| `-debug` (current Makefile behavior) | 192.560 ns | 7 |
| `-debug -o:speed` | 19.154 ns | 7 |

The optimized build is about **10.1x faster** without an engine code change.

An end-to-end 128-sprite benchmark on SDL 3.4.12 with Lavapipe showed only a
small full-frame difference (median 2.486 ms debug versus 2.447 ms optimized)
because software GPU/driver work dominated. This does not invalidate the CPU
result; it shows why CPU queue time and full-frame time must be reported
separately.

Environment:

- Odin `dev-2026-05-nightly:ea5175d` (the version pinned by CI)
- SDL 3.4.12
- Linux x86-64

## Suggested fix

Compile profiling binaries with optimization while retaining symbols:

```make
FLAME_ODIN_FLAGS ?= -debug -o:speed

flame-build:
	odin build examples/$(FLAME_EXAMPLE) \
		-collection:pkg=. \
		-out:$(FLAME_BIN) \
		$(FLAME_ODIN_FLAGS)
```

Keeping the flags configurable allows an explicitly unoptimized diagnostic run
without making it the performance default.

Example usage:

```bash
# Representative performance profile: optimized code with debug symbols.
make flame FLAME_EXAMPLE=crowd

# Explicitly profile unoptimized code when investigating debug-only behavior.
make flame FLAME_EXAMPLE=crowd FLAME_ODIN_FLAGS="-debug -o:none"
```

Reproduce the isolated build-mode comparison with the committed CPU harness:

```bash
make perf-draw PERF_ODIN_FLAGS="-debug -o:none"
make perf-draw PERF_ODIN_FLAGS="-debug -o:speed"
```

Both runs print the Git commit, Odin version, compiler flags, every trial, and
the median nanoseconds per draw.

Consider applying an explicit optimization mode to performance-oriented example
runs as well. Plain `odin run` currently uses Odin's unoptimized default.

## Acceptance criteria

- `make flame-build` produces an optimized binary with debug symbols.
- `FLAME_ODIN_FLAGS` can override the default for diagnostic builds.
- `make check` and `make test` continue to pass.
- A new `crowd` profile records the exact compiler flags in its report or
  accompanying documentation.
- Performance conclusions distinguish CPU `draw_sprite` cost from complete
  frame/GPU submission cost.
