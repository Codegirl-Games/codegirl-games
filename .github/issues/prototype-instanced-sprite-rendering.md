# Prototype instanced sprite rendering for larger batches

## Summary

The renderer currently generates and uploads six complete vertices per sprite:

```text
6 vertices × (position float2 + UV float2) = 96 bytes/sprite/frame
```

Instancing can keep one immutable six-corner unit quad on the GPU and upload one
rectangle/UV record per sprite:

```text
clip rectangle float4 + UV rectangle float4 = 32 bytes/sprite/frame
```

This reduces dynamic upload volume by two thirds, but requires another pipeline
and backend-specific vertex shader. At the current 128-sprite cap, the measured
gain is too small to justify enabling it unconditionally.

## Evidence

A complete temporary instanced path was implemented with:

- A static six-corner vertex buffer
- A 32-byte per-instance buffer
- Vertex-rate and instance-rate pipeline inputs
- One instanced draw per texture run
- Validated SPIR-V and SDL's debug GPU device

The paired benchmark used ten order-alternated samples of 400 frames:

| Mode | Median frame time |
| --- | ---: |
| Six dynamic vertices per sprite | 5.527 ms |
| 32-byte instance per sprite | 5.467 ms |

Instancing improved median frame time by approximately **1.1%** on
Vulkan/Lavapipe with 128 sprites.

## Reproduction harness

Run the committed visible full-frame workload on baseline and candidate commits:

```bash
make perf-frame \
	PERF_FRAME_SCENARIO=0 \
	PERF_FRAME_SPRITES=128 \
	PERF_ODIN_FLAGS="-debug -o:speed"
```

Keep all other `PERF_FRAME_*` values unchanged and compare
`median_ms_per_frame`. To test 512 or more sprites, first raise the engine's
`MAX_SPRITES` and associated buffer capacities on the candidate branch, then
set `PERF_FRAME_SPRITES` to the same value.

## Suggested fix

Treat this as a prototype gated by larger sprite counts or a demonstrated
hardware bottleneck, not as an immediate replacement.

Define the compact instance payload:

```odin
Sprite_Instance :: struct {
	clip_rect: [4]f32, // left, top, right, bottom
	uv_rect:   [4]f32, // u0, v0, u1, v1
}
```

Queue one record after the existing quad and UV calculations:

```odin
instance := Sprite_Instance {
	clip_rect = {p0.x, p0.y, p2.x, p2.y},
	uv_rect   = {u0, v0, u1, v1},
}
append(&app.instance_list, instance)
```

Use a static unit quad:

```odin
UNIT_QUAD := [6]Vec2 {
	{0, 0}, {1, 0}, {1, 1},
	{0, 0}, {1, 1}, {0, 1},
}
```

The instanced vertex shader reconstructs position and UV:

```glsl
#version 450

layout(location = 0) in vec2 in_corner;
layout(location = 1) in vec4 in_clip_rect;
layout(location = 2) in vec4 in_uv_rect;

layout(location = 0) out vec2 v_uv;

void main() {
    vec2 position = mix(in_clip_rect.xy, in_clip_rect.zw, in_corner);
    v_uv = mix(in_uv_rect.xy, in_uv_rect.zw, in_corner);
    gl_Position = vec4(position, 0.0, 1.0);
}
```

Configure slot 0 as vertex-rate and slot 1 as instance-rate, then draw each
texture run with six vertices and `run` instances:

```odin
vb_descs := [2]sdl.GPUVertexBufferDescription {
	{slot = 0, pitch = u32(size_of(Vec2)), input_rate = .VERTEX},
	{slot = 1, pitch = u32(size_of(Sprite_Instance)), input_rate = .INSTANCE},
}

sdl.DrawGPUPrimitives(
	app.render_pass,
	6,        // unit-quad vertices
	u32(run), // sprite instances in this texture run
	0,
	0,
)
```

Keep the current path as a fallback until the instanced implementation exists
for Vulkan, D3D12, and Metal and demonstrates a meaningful hardware win.

## Acceptance criteria

- Benchmark at 128, 512, 2,048, and 10,000 sprites or the highest supported
  counts.
- Report CPU queue time, bytes uploaded, and complete frame time separately.
- Require a meaningful hardware improvement before changing the default path.
- Supply equivalent Vulkan, D3D12, and Metal shaders.
- Preserve texture-run batching and sprite flip/trim behavior.
- Add visual equivalence tests for position, UVs, animation frames, and flip.
- Retain the existing six-vertex path as a fallback during evaluation.
