# Add opt-in order-safe texture batching

## Summary

`end_frame` batches only consecutive sprites that use the same texture.
Alternating two textures therefore produces one sampler bind and draw call per
sprite even when some sprites could safely be regrouped.

Globally sorting transparent sprites by texture is not correct: overlapping
sprites may blend differently when submission order changes. Batching should
therefore be opt-in within explicit groups whose members are safe to reorder.

## Evidence

A temporary paired benchmark used:

- Odin `dev-2026-05-nightly:ea5175d` with `-debug -o:speed`
- SDL 3.4.12 and Vulkan/Lavapipe
- 128 animated sprites alternating between two equivalent textures
- Sorting cost included in the measured frame
- Ten order-alternated samples of 400 frames per mode

| Mode | Texture runs | Median frame time |
| --- | ---: | ---: |
| Submission order | 128 | 5.765 ms |
| Texture grouped | 2 | 5.654 ms |

Sorting and grouping improved median frame time by approximately **1.9%**.
Hardware drivers with higher draw-call overhead may show a different result.

## Reproduction harness

Run the committed alternating-texture workload on the baseline and candidate
commits:

```bash
make perf-frame \
	PERF_FRAME_SCENARIO=2 \
	PERF_ODIN_FLAGS="-debug -o:speed"
```

Keep all `PERF_FRAME_*` values unchanged. The baseline should produce one
texture run per sprite; the candidate should reduce runs only inside explicit
reorder-safe groups. Compare `median_ms_per_frame` and verify rendered output.

## Suggested fix

Add an explicit batch group to queued sprites. Group `0` keeps strict submission
order; nonzero groups may be reordered only when the caller guarantees that
their members are order-independent.

```odin
Queued_Sprite :: struct {
	texture:     ^sdl.GPUTexture,
	verts:       [SPRITE_VERT_COUNT]Vertex,
	batch_group: u32, // 0 = strict order; nonzero = caller permits regrouping
}
```

Sort each contiguous, nonzero group by texture immediately before upload:

```odin
group_texture_runs :: proc(list: []Queued_Sprite) {
	start := 0
	for start < len(list) {
		group := list[start].batch_group
		if group == 0 {
			start += 1
			continue
		}

		end := start + 1
		for end < len(list) && list[end].batch_group == group {
			end += 1
		}

		// Stable insertion sort is sufficient while MAX_SPRITES is 128.
		for i in start + 1 ..< end {
			item := list[i]
			j := i
			for j > start {
				if uintptr(list[j - 1].texture) <= uintptr(item.texture) {
					break
				}
				list[j] = list[j - 1]
				j -= 1
			}
			list[j] = item
		}
		start = end
	}
}
```

Call it after all sprites are queued and before the transfer-buffer copy:

```odin
group_texture_runs(app.draw_list[:])
```

Expose batching through a separate API or explicit parameter so existing
`draw_sprite` calls remain strict-order by default:

```odin
draw_sprite_batched(&app, &sprite, batch_group = 1)
```

## Acceptance criteria

- Existing `draw_sprite` behavior preserves exact submission order.
- Reordering requires an explicit nonzero batch group.
- Sorting never moves a sprite across a strict-order entry or group boundary.
- Add tests for strict order, group boundaries, stable same-texture ordering,
  and reduced texture-run count.
- Add a visual overlap test confirming default alpha compositing is unchanged.
- Benchmark sorting cost and draw-call reduction on a hardware GPU.
