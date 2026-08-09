# Add deterministic CPU and frame benchmarks for sprite rendering

## Summary

The current `make flame` workflow is valuable for finding call stacks, but it
does not provide a reproducible performance metric:

- `examples/crowd` draws only 24 sprites.
- `MAX_SPRITES` limits the renderer to 128 sprites.
- Recording starts an interactive application and asks the user to play for
  10–20 seconds before quitting.
- The two checked-in reports contain only 499 and 469 samples.
- CPU queue construction and GPU submission are combined in one profile.
- The profiler currently builds unoptimized code.

These limitations make it difficult to tell whether a change made
`draw_sprite` faster, changed driver behavior, or merely changed sampling noise.

## Evidence

A temporary deterministic benchmark exposed two very different results:

1. CPU-only `draw_sprite`, two million calls and seven trials:
   - `-debug`: median 192.560 ns/draw
   - `-debug -o:speed`: median 19.154 ns/draw
2. Full 128-sprite frames through SDL GPU on Lavapipe, 1,000 measured frames
   and five trials:
   - `-debug`: median 2.486 ms/frame
   - `-debug -o:speed`: median 2.447 ms/frame

At the current cap, optimized CPU queue construction is approximately 3.2
microseconds for 128 sprites. The full software-rendered frame is around 2.45
milliseconds, so optimizing `draw_sprite` cannot materially improve that
specific end-to-end workload. A hardware GPU or a larger future sprite limit
may have a different balance.

This split also explains why percentages from the current unoptimized
flamegraphs overstate small helper functions.

## Proposed change

Add a non-interactive benchmark target with two explicitly separate workloads.

### CPU queue benchmark

- Construct `App`, `Character_Data`, and `Sprite` with real baked metadata.
- Use safe fake non-null GPU handles; `draw_sprite` only checks/stores these.
- Preallocate the draw list.
- Clear the queue whenever it reaches `MAX_SPRITES`.
- Vary sprite position between calls so the compiler cannot hoist the work.
- Warm up before timing.
- Run at least one million calls and report nanoseconds per draw.
- Build with `-o:speed` by default.

### Full-frame benchmark

- Use a real SDL GPU device and baked texture.
- Warm up before timing.
- Run a fixed number of frames without interactive input.
- Report milliseconds per frame and sprites per second.
- Record GPU backend, present mode, compiler version, compiler flags, and sprite
  count.

The CPU benchmark should be available without a display or GPU. The full-frame
benchmark may remain opt-in where a suitable GPU backend is unavailable.

Do not add a strict CI regression threshold initially; hosted runner variance
will make a single threshold flaky. CI can still compile the benchmark and
verify that it completes.

## Acceptance criteria

- A Makefile target runs the optimized CPU benchmark non-interactively.
- Results include compiler flags, iteration count, median, and per-trial values.
- CPU queue time is reported separately from complete frame time.
- Sprite positions or frames vary during the measured loop.
- The draw list never silently exceeds `MAX_SPRITES`.
- The benchmark has documented commands for repeatable local comparison.
- `make check` and `make test` continue to pass.
