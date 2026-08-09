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

### Follow-up enhancement benchmarks

Six proposed renderer changes were implemented temporarily and measured before
being discarded. Full-frame tests used:

- Odin `dev-2026-05-nightly:ea5175d`
- `-debug -o:speed`
- SDL 3.4.12 with Vulkan/Lavapipe
- 128 animated sprites using real baked toad metadata and textures
- Warm-up before measurement
- Paired baseline/change samples on the same device with alternating order
- Ten 400-frame samples per mode, except culling, which used seven 750-frame
  samples per mode

Each row is a separate paired run, so absolute frame times should only be
compared within that row.

| Enhancement | Baseline median | Changed median | Result |
| --- | ---: | ---: | ---: |
| Viewport culling, all visible | 4.845 ms | 4.822 ms | 0.5% faster |
| Viewport culling, 50% offscreen | 2.856 ms | 2.878 ms | 0.8% slower |
| SDL transfer and vertex buffer cycling | 4.869 ms | 4.834 ms | 0.7% faster |
| Contiguous vertex queue and one upload-side copy | 4.793 ms | 4.809 ms | 0.3% slower |
| Four-vertex indexed quads | 4.745 ms | 4.830 ms | 1.8% slower |
| GPU instancing with 32-byte instance records | 5.527 ms | 5.467 ms | 1.1% faster |
| Texture sorting, including sort cost, 128 runs to 2 | 5.765 ms | 5.654 ms | 1.9% faster |

Interpretation:

- Viewport culling is neutral at the current cap. The GPU already clips
  offscreen triangles, and the sprites remain in one batched draw.
- SDL buffer cycling is a small performance improvement and is also the
  documented way to avoid overwriting resources still bound by prior frames.
- Repacking the CPU queue does not help at 128 sprites; extra dynamic-array
  work offsets the saved small-copy loop.
- Indexed quads regress performance despite reducing dynamic vertex data.
- Instancing reduces per-sprite upload data from 96 to 32 bytes, but the 1.1%
  gain does not justify a second pipeline and shader path at the current cap.
- Texture sorting has the largest full-frame gain, but unrestricted sorting can
  change alpha compositing. It is only safe within compatible layer/order
  groups.

The recommended order is:

1. Profile optimized builds and establish the deterministic benchmark.
2. Apply the clip-space math simplification documented in the related issue.
3. Enable SDL buffer cycling for correct cross-frame resource reuse.
4. Consider layer-aware texture grouping if a 1.9% workload-specific gain is
   worth the ordering complexity.
5. Defer culling, queue repacking, indexed quads, and instancing until the
   sprite limit or measured workload grows substantially.

These results are from a software Vulkan backend. Hardware drivers may have a
different balance, which is another reason to keep the benchmark reproducible
and report backend details.

## Suggested fix

Add a non-interactive benchmark target with two explicitly separate workloads.

Add dedicated Makefile targets that always build optimized benchmark code:

```make
PERF_ITERATIONS ?= 2000000
PERF_FRAMES ?= 1000

perf-draw:
	odin run examples/draw_bench \
		-collection:pkg=. \
		-debug -o:speed \
		-define:PERF_ITERATIONS=$(PERF_ITERATIONS)

perf-frame:
	odin run examples/frame_bench \
		-collection:pkg=. \
		-debug -o:speed \
		-define:PERF_FRAMES=$(PERF_FRAMES)
```

### CPU queue benchmark

- Construct `App`, `Character_Data`, and `Sprite` with real baked metadata.
- Use safe fake non-null GPU handles; `draw_sprite` only checks/stores these.
- Preallocate the draw list.
- Clear the queue whenever it reaches `MAX_SPRITES`.
- Vary sprite position between calls so the compiler cannot hoist the work.
- Warm up before timing.
- Run at least one million calls and report nanoseconds per draw.
- Build with `-o:speed` by default.

The measured loop should clear the queue at its cap, vary input to prevent
compiler hoisting, and report time per draw:

```odin
PERF_ITERATIONS :: #config(PERF_ITERATIONS, 2_000_000)

start := sdl.GetTicksNS()
for i in 0 ..< PERF_ITERATIONS {
	if len(app.draw_list) == eng.MAX_SPRITES {
		clear(&app.draw_list)
	}
	sprite.position.x = f32(i & 1023)
	eng.draw_sprite(&app, &sprite)
}
elapsed := sdl.GetTicksNS() - start

fmt.printfln(
	"%.3f ns/draw",
	f64(elapsed) / f64(PERF_ITERATIONS),
)
```

### Full-frame benchmark

- Use a real SDL GPU device and baked texture.
- Warm up before timing.
- Run a fixed number of frames without interactive input.
- Report milliseconds per frame and sprites per second.
- Record GPU backend, present mode, compiler version, compiler flags, and sprite
  count.

Use a fixed frame count rather than an interactive quit time:

```odin
PERF_FRAMES :: #config(PERF_FRAMES, 1_000)

for _ in 0 ..< 100 {
	draw_benchmark_frame(&app, sprites[:]) // warm-up
}

start := sdl.GetTicksNS()
for _ in 0 ..< PERF_FRAMES {
	draw_benchmark_frame(&app, sprites[:])
}
elapsed := sdl.GetTicksNS() - start

fmt.printfln(
	"%.3f ms/frame",
	f64(elapsed) / f64(PERF_FRAMES) / 1_000_000.0,
)
```

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
