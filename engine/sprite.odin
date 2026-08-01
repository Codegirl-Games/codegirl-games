package engine

import "core:mem"
import sdl "vendor:sdl3"

Vec2 :: [2]f32

Sprite :: struct {
	data:     ^Character_Data,
	position: Vec2,
	clip:     string,
	frame:    int,
}

spawn_sprite :: proc(
	data: ^Character_Data,
	position: Vec2,
	clip: string = "idle",
	frame: int = 0,
) -> Sprite {
	return Sprite{data = data, position = position, clip = clip, frame = frame}
}

// stubbed for later
update_sprite :: proc(sprite: ^Sprite, dt: f32) {
	_ = sprite
	_ = dt
}

to_clip :: proc(px, py, sw, sh: f32) -> [2]f32 {
	return {
		px / sw * 2 - 1,
		1 - py / sh * 2, // flip y (window pixels are y-down)
	}
}

draw_sprite :: proc(app: ^App, sprite: ^Sprite) {
	if app.render_pass == nil || app.cmd == nil || app.swapchain_texture == nil {
		return // begin_frame may have skipped (minimized window, etc.)
	}
	if sprite == nil || sprite.data == nil || sprite.data.texture == nil {
		return
	}

	rect, ok := character_frame_rect(sprite.data, sprite.clip, sprite.frame)
	if !ok {
		return
	}

	fw := f32(rect[2])
	fh := f32(rect[3])

	// Feet-centered placement, same as renderer version
	x0_px := sprite.position.x - fw * 0.5
	y0_px := sprite.position.y - fh
	x1_px := x0_px + fw
	y1_px := y0_px + fh

	sw := f32(app.swapchain_w)
	sh := f32(app.swapchain_h)
	p0 := to_clip(x0_px, y0_px, sw, sh) // top-left
	p1 := to_clip(x1_px, y0_px, sw, sh) // top-right
	p2 := to_clip(x1_px, y1_px, sw, sh) // bottom-right
	p3 := to_clip(x0_px, y1_px, sw, sh) // bottom-left

	tex_w := f32(sprite.data.width)
	tex_h := f32(sprite.data.height)
	u0 := f32(rect[0]) / tex_w
	v0 := f32(rect[1]) / tex_h
	u1 := f32(rect[0] + rect[2]) / tex_w
	v1 := f32(rect[1] + rect[3]) / tex_h

	// Two triangles: (0,1,2) and (0,2,3)
	verts := [6]Vertex {
		{pos = p0, uv = {u0, v0}},
		{pos = p1, uv = {u1, v0}},
		{pos = p2, uv = {u1, v1}},
		{pos = p0, uv = {u0, v0}},
		{pos = p2, uv = {u1, v1}},
		{pos = p3, uv = {u0, v1}},
	}

	map_ptr := sdl.MapGPUTransferBuffer(app.device, app.transfer_buffer, false)
	if map_ptr == nil {
		return
	}
	mem.copy(map_ptr, raw_data(verts[:]), size_of(verts))
	sdl.UnmapGPUTransferBuffer(app.device, app.transfer_buffer)

	// IMPORTANT: SDL does not allow beginning a copy pass while a render pass
	// is active on the same command buffer. Upload on a separate command buffer.
	copy_cmd := sdl.AcquireGPUCommandBuffer(app.device)
	if copy_cmd == nil {
		return
	}
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd)

	src := sdl.GPUTransferBufferLocation {
		transfer_buffer = app.transfer_buffer,
		offset          = 0,
	}
	dst := sdl.GPUBufferRegion {
		buffer = app.vertex_buffer,
		offset = 0,
		size   = u32(size_of(verts)),
	}
	sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
	sdl.EndGPUCopyPass(copy_pass)
	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(copy_cmd)
	if fence == nil {
		return
	}
	defer sdl.ReleaseGPUFence(app.device, fence)
	if !sdl.WaitForGPUFences(app.device, true, &fence, 1) {
		return
	}

	sampler_binding := sdl.GPUTextureSamplerBinding {
		texture = sprite.data.texture,
		sampler = app.sampler,
	}
	sdl.BindGPUFragmentSamplers(app.render_pass, 0, &sampler_binding, 1)

	vb_binding := sdl.GPUBufferBinding {
		buffer = app.vertex_buffer,
		offset = 0,
	}
	sdl.BindGPUVertexBuffers(app.render_pass, 0, &vb_binding, 1)

	sdl.DrawGPUPrimitives(app.render_pass, 6, 1, 0, 0)
}
