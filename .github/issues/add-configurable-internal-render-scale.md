# Add configurable internal render scale to improve fill-bound FPS

## Summary

Complete-frame benchmarks show that the current sprite renderer is primarily
pixel/fill bound on Vulkan/Lavapipe, not CPU draw-preparation bound. Rendering
the world into a smaller offscreen color target and nearest-blitting it to the
native swapchain produced the largest measured FPS improvement.

This should be an opt-in render-quality setting with a native-resolution
fallback. For pixel art, a 50% scale is especially useful because it maps to an
exact 2× nearest-neighbor upscale.

## Evidence

Environment:

- Commit `dc66203259e92ce39291556f7b6c26c8dd999b84`
- Odin `dev-2026-05-nightly:ea5175d`
- `-debug -o:speed`
- SDL 3.4.12, Vulkan/Lavapipe, immediate present
- 800×600 swapchain
- Five 150-frame trials per invocation after 50 warm-up frames
- Order-balanced baseline/candidate invocations
- GPU idle wait included before stopping each trial timer

### Fill and overdraw scaling

The committed `perf-frame` harness produced:

| Workload | Median frame time | Median FPS |
| --- | ---: | ---: |
| 1 visible sprite | 0.592 ms | 1,690 |
| 24 visible sprites | 2.249 ms | 445 |
| 64 visible sprites | 4.017 ms | 249 |
| 128 visible sprites | 6.255 ms | 160 |
| 128 stacked sprites | 7.692 ms | 130 |

Stacking the same 128 sprites increased frame time by approximately 23%,
confirming that overdraw matters.

With one centered sprite, render-target scaling produced:

| Window size | Pixels | Median frame time |
| --- | ---: | ---: |
| 400×300 | 120,000 | 0.268 ms |
| 800×600 | 480,000 | 0.545 ms |
| 1600×1200 | 1,920,000 | 2.075 ms |

The near-linear increase at larger sizes is further evidence of a pixel-bound
workload.

### Internal render-scale prototype

The temporary candidate kept the physical swapchain at 800×600, rendered
sprites into a smaller `COLOR_TARGET | SAMPLER` texture, and used
`BlitGPUTexture` with nearest filtering to upscale into the swapchain.

Aggregate medians across ten trials per mode:

| Workload | Native | 75% scale | 50% scale |
| --- | ---: | ---: | ---: |
| 128 spread sprites | 6.082 ms / 164 FPS | 4.082 ms / 245 FPS | 3.082 ms / 325 FPS |
| 128 stacked sprites | 7.912 ms / 126 FPS | 5.116 ms / 195 FPS | 3.034 ms / 330 FPS |

Compared with native resolution:

- 75% reduced frame time by 33–35% and increased FPS by 49–55%.
- 50% reduced frame time by 49–62% and increased FPS by 97–161%.

A visual smoke test confirmed that the 50% path rendered the complete scene at
the correct orientation and 800×600 output size. It was visibly coarser, as
expected. A 75% scale at 800×600 does not produce an integer upscale and can
create uneven pixel sizing with nearest filtering.

## Reproduction harness

Native spread and stacked workloads:

```bash
make perf-frame \
	PERF_FRAME_SCENARIO=0 \
	PERF_FRAME_SPRITES=128 \
	PERF_FRAME_WIDTH=800 \
	PERF_FRAME_HEIGHT=600

make perf-frame \
	PERF_FRAME_SCENARIO=3 \
	PERF_FRAME_SPRITES=128 \
	PERF_FRAME_WIDTH=800 \
	PERF_FRAME_HEIGHT=600
```

Run the same commands on the candidate branch with internal render scale set to
75% and 50%. Keep every `PERF_FRAME_*` value unchanged between comparisons.

## Suggested fix

Add explicit logical/output and internal-render dimensions to `App`:

```odin
Render_Scale :: enum {
	Native,
	Three_Quarter,
	Half,
}

App :: struct {
	// Existing swapchain fields remain the logical/output dimensions.
	swapchain_texture: ^sdl.GPUTexture,
	swapchain_w:       u32,
	swapchain_h:       u32,

	render_scale:   Render_Scale,
	scene_texture:  ^sdl.GPUTexture,
	scene_w:        u32,
	scene_h:        u32,
}
```

Create the offscreen target with the swapchain format and both usages required
by SDL's blit path:

```odin
app.scene_texture = sdl.CreateGPUTexture(
	app.device,
	{
		type = .D2,
		format = sdl.GetGPUSwapchainTextureFormat(app.device, app.window),
		usage = {.COLOR_TARGET, .SAMPLER},
		width = app.scene_w,
		height = app.scene_h,
		layer_count_or_depth = 1,
		num_levels = 1,
		sample_count = ._1,
	},
)
```

Render the sprite pass into `scene_texture`. Continue using the logical
swapchain dimensions for camera and clip-space calculations so world layout
does not change with render scale:

```odin
color_info := sdl.GPUColorTargetInfo {
	texture = app.scene_texture,
	clear_color = app.clear_color,
	load_op = .CLEAR,
	store_op = .STORE,
	cycle = true,
}
```

After ending the render pass, upscale into the full swapchain:

```odin
blit := sdl.GPUBlitInfo {
	source = {
		texture = app.scene_texture,
		w = app.scene_w,
		h = app.scene_h,
	},
	destination = {
		texture = app.swapchain_texture,
		w = app.swapchain_w,
		h = app.swapchain_h,
	},
	load_op = .DONT_CARE,
	filter = .NEAREST,
}
sdl.BlitGPUTexture(app.cmd, blit)
```

Use the existing direct-to-swapchain path at native scale to avoid an
unnecessary blit. Recreate the offscreen texture whenever the swapchain size,
format, or render-scale setting changes. If native-resolution UI or text is
added later, render it after the world blit in a separate swapchain pass.

## Rejected experiment: fragment alpha discard

Approximately 49.7% of pixels inside the baked frame rectangles have exact
alpha zero. A temporary fragment shader discarded those texels:

```glsl
vec4 texel = texture(u_tex, v_uv);
if (texel.a == 0.0) {
    discard;
}
out_color = texel;
```

Despite the high transparent coverage, this regressed frame time by roughly
5–6% in both spread and stacked workloads. Do not add alpha discard without
contradictory hardware-GPU evidence.

## Acceptance criteria

- Native, 75%, and 50% internal render-scale settings are available.
- Native scale retains the current direct-to-swapchain path.
- The scene target is recreated safely on resize, format change, or scale
  change and released during shutdown.
- Camera/world coordinates remain stable when render scale changes.
- Nearest filtering is used for pixel-art output.
- Add screenshot-based checks for output orientation, viewport coverage, and
  stable sprite placement at every scale.
- Benchmark spread and stacked scenarios on at least one hardware GPU.
- Document the quality tradeoff and recommend integer upscale ratios for pixel
  art.
