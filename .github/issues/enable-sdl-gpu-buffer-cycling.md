# Enable SDL GPU buffer cycling for per-frame sprite uploads

## Summary

`end_frame` overwrites the same transfer buffer and vertex buffer every frame,
but both SDL calls currently pass `cycle = false`:

```odin
sdl.MapGPUTransferBuffer(app.device, app.transfer_buffer, false)
sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
```

SDL documents cycling as the mechanism that rotates to an unbound internal
resource when the previous frame still references the current one. Enabling it
avoids an unnecessary resource dependency and makes the overwrite pattern
explicitly safe.

## Evidence

A temporary paired benchmark used:

- Odin `dev-2026-05-nightly:ea5175d` with `-debug -o:speed`
- SDL 3.4.12 and Vulkan/Lavapipe
- 128 animated sprites
- Ten order-alternated samples of 400 frames per mode

| Mode | Median frame time |
| --- | ---: |
| Cycling disabled | 4.869 ms |
| Cycling enabled | 4.834 ms |

Cycling improved median frame time by approximately **0.7%**. This is a small
performance change, but it also follows SDL's documented resource-reuse model.

## Reproduction harness

Run the committed full-frame harness on the baseline commit and candidate
commit:

```bash
make perf-frame \
	PERF_FRAME_SCENARIO=0 \
	PERF_ODIN_FLAGS="-debug -o:speed"
```

Keep all `PERF_FRAME_*` values unchanged. Compare `median_ms_per_frame`; the
harness waits for GPU idle before stopping each trial timer.

## Suggested fix

Cycle both resources that are fully overwritten each frame:

```odin
map_ptr := sdl.MapGPUTransferBuffer(
	app.device,
	app.transfer_buffer,
	true, // rotate if the previous frame still binds this transfer buffer
)

// Write the complete [0, n * SPRITE_VERTS_SIZE) range, then unmap.
sdl.UnmapGPUTransferBuffer(app.device, app.transfer_buffer)

copy_pass := sdl.BeginGPUCopyPass(cmd)
sdl.UploadToGPUBuffer(
	copy_pass,
	src,
	dst,
	true, // rotate the destination vertex buffer if it is still bound
)
sdl.EndGPUCopyPass(copy_pass)
```

Cycling makes previous contents undefined, so this remains correct only because
the renderer writes the complete vertex range used by the frame before drawing.
Do not enable cycling for partial updates that depend on untouched data.

## Acceptance criteria

- Both `MapGPUTransferBuffer` and `UploadToGPUBuffer` use `cycle = true`.
- The complete submitted vertex range is rewritten every frame.
- Existing engine tests and examples continue to pass.
- A full-frame benchmark confirms no regression on a hardware GPU backend.
- Add a comment explaining why cycling is safe for this full-overwrite path.
