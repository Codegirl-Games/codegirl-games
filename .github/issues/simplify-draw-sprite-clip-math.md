# Reduce repeated clip-space work in `draw_sprite`

## Summary

`draw_sprite` calls `to_clip` four times for an axis-aligned quad:

```odin
p0 := to_clip(x0_px, y0_px, sw, sh)
p1 := to_clip(x1_px, y0_px, sw, sh)
p2 := to_clip(x1_px, y1_px, sw, sh)
p3 := to_clip(x0_px, y1_px, sw, sh)
```

This repeats the same divisions and converts duplicate x/y coordinates. An
axis-aligned sprite has only two unique x values and two unique y values.

This is a measurable optimization, but it is low priority at the current
128-sprite limit because the absolute saving is small.

## Evidence

The checked-in unoptimized profiles report `engine::to_clip` at 5.33% and 5.51%
self time. Those percentages are inflated by the unoptimized profiling build,
so the change was also measured with `-debug -o:speed`.

A temporary benchmark used the real baked toad metadata, changed sprite
position on every iteration, preallocated the queue, and performed two million
draws per mode over seven trials:

| Mode | Median time per draw |
| --- | ---: |
| Current `draw_sprite` | 25.128 ns |
| Precomputed clip scale and reused coordinates | 21.531 ns |
| Same math plus cached `Frame_Def` | 21.778 ns |

Simplifying the math improved isolated draw time by approximately **14.3%**.
Caching the resolved frame did not provide an additional benefit and should not
be included without new evidence.

At `MAX_SPRITES == 128`, the measured math saving is only about 0.46
microseconds per completely full frame. GPU/driver work dominated the
end-to-end benchmark, so this should follow the profiling and deterministic
benchmark improvements.

Follow-up paired full-frame experiments at the 128-sprite cap found no larger
renderer-architecture win: buffer cycling improved median frame time by 0.7%,
GPU instancing by 1.1%, and texture sorting by 1.9%, while culling, queue
repacking, and indexed quads were neutral or slower. The clip-space change
therefore remains the strongest measured optimization specifically inside
`draw_sprite`, although its absolute frame impact is still small.

Environment:

- Odin `dev-2026-05-nightly:ea5175d`
- Optimized with `-debug -o:speed`
- Linux x86-64

## Reproduction harness

Run the committed CPU harness on the baseline commit and again after applying
the suggested fix:

```bash
make perf-draw PERF_ODIN_FLAGS="-debug -o:speed"
```

Keep `PERF_DRAW_ITERATIONS`, `PERF_DRAW_WARMUP`, and `PERF_DRAW_TRIALS`
unchanged between commits. Compare `median_ns_per_draw`.

## Suggested fix

Compute clip scaling once and construct corners from the unique coordinates:

```odin
sprite_quad_to_clip :: proc(x0, y0, x1, y1, sw, sh: f32) -> [4]Vec2 {
	sx := 2.0 / sw
	sy := 2.0 / sh

	left   := x0 * sx - 1
	right  := x1 * sx - 1
	top    := 1 - y0 * sy
	bottom := 1 - y1 * sy

	return {
		{left, top},
		{right, top},
		{right, bottom},
		{left, bottom},
	}
}

points := sprite_quad_to_clip(x0_px, y0_px, x1_px, y1_px, sw, sh)
p0, p1, p2, p3 := points[0], points[1], points[2], points[3]
```

Keep `to_clip` for general callers and its existing tests; this change only
specializes quad construction inside `draw_sprite`.

Add an equivalence test before replacing the current calls:

```odin
@(test)
sprite_quad_clip_math_matches_to_clip :: proc(t: ^testing.T) {
	x0, y0 := f32(125), f32(80)
	x1, y1 := f32(325), f32(280)
	sw, sh := f32(800), f32(600)

	expected := [4]Vec2 {
		to_clip(x0, y0, sw, sh),
		to_clip(x1, y0, sw, sh),
		to_clip(x1, y1, sw, sh),
		to_clip(x0, y1, sw, sh),
	}
	actual := sprite_quad_to_clip(x0, y0, x1, y1, sw, sh)

	for i in 0 ..< 4 {
		testing.expect_value(t, actual[i], expected[i])
	}
}
```

## Acceptance criteria

- Existing sprite geometry, camera, UV, and batching tests pass.
- Add or extend a test that compares all four generated corners against
  `to_clip` for representative viewport and sprite coordinates.
- Flipped and unflipped sprites produce identical vertices to the current code.
- An optimized deterministic benchmark shows at least a 10% improvement in
  isolated `draw_sprite` time under comparable conditions.
- Do not add a per-sprite frame cache as part of this issue.
