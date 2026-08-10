package engine

import "core:fmt"
import "core:mem"
import sdl "vendor:sdl3"

// Enough for an 8-digit rate plus " FPS".
FPS_OVERLAY_MAX_GLYPHS :: 12
FPS_GLYPH_W :: 5
FPS_GLYPH_H :: 7
FPS_CELL_W :: 6
FPS_CELL_H :: 8
FPS_ATLAS_COLS :: 16
FPS_SCALE :: 2
FPS_MARGIN :: 8
FPS_UPDATE_INTERVAL :: 0.25

// Glyph indices in the debug atlas.
FPS_GLYPH_DIGIT_0 :: 0
FPS_GLYPH_F :: 10
FPS_GLYPH_P :: 11
FPS_GLYPH_S :: 12
FPS_GLYPH_SPACE :: 13

// 5x7 bitmaps (MSB = left). Digits 0-9, then F/P/S/space.
@(private)
fps_glyph_rows := [14][7]u8 {
	{0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E}, // 0
	{0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E}, // 1
	{0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F}, // 2
	{0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E}, // 3
	{0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02}, // 4
	{0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E}, // 5
	{0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E}, // 6
	{0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08}, // 7
	{0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E}, // 8
	{0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C}, // 9
	{0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10}, // F
	{0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10}, // P
	{0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E}, // S
	{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, // space
}

set_show_fps :: proc(app: ^App, enabled: bool) {
	if app == nil do return
	app.show_fps = enabled
}

@(private)
fps_overlay_init :: proc(app: ^App) -> bool {
	app.show_fps = true
	app.fps_smooth = 0
	app.fps_display = 0
	app.fps_last_time = 0
	app.fps_update_accum = 0
	app.fps_texture = nil

	atlas_w := FPS_ATLAS_COLS * FPS_CELL_W
	atlas_h := FPS_CELL_H
	pixels := make([]u8, atlas_w * atlas_h * 4)
	defer delete(pixels)

	for gi in 0 ..< len(fps_glyph_rows) {
		gx := gi * FPS_CELL_W
		rows := fps_glyph_rows[gi]
		for row in 0 ..< FPS_GLYPH_H {
			bits := rows[row]
			for col in 0 ..< FPS_GLYPH_W {
				on := (bits >> u8(FPS_GLYPH_W - 1 - col)) & 1 == 1
				px := gx + col
				py := row
				i := (py * atlas_w + px) * 4
				if on {
					pixels[i + 0] = 255
					pixels[i + 1] = 255
					pixels[i + 2] = 255
					pixels[i + 3] = 255
				}
			}
		}
	}

	app.fps_texture = sdl.CreateGPUTexture(
		app.device,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = u32(atlas_w),
			height = u32(atlas_h),
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		},
	)
	if app.fps_texture == nil {
		fmt.eprintfln("FPS overlay CreateGPUTexture failed: %s", sdl.GetError())
		return false
	}

	upload_size := atlas_w * atlas_h * 4
	tbuf := sdl.CreateGPUTransferBuffer(app.device, {usage = .UPLOAD, size = u32(upload_size)})
	if tbuf == nil {
		fmt.eprintfln("FPS overlay CreateGPUTransferBuffer failed: %s", sdl.GetError())
		sdl.ReleaseGPUTexture(app.device, app.fps_texture)
		app.fps_texture = nil
		return false
	}
	defer sdl.ReleaseGPUTransferBuffer(app.device, tbuf)

	map_ptr := sdl.MapGPUTransferBuffer(app.device, tbuf, false)
	if map_ptr == nil {
		fmt.eprintfln("FPS overlay MapGPUTransferBuffer failed: %s", sdl.GetError())
		sdl.ReleaseGPUTexture(app.device, app.fps_texture)
		app.fps_texture = nil
		return false
	}
	mem.copy(map_ptr, raw_data(pixels), upload_size)
	sdl.UnmapGPUTransferBuffer(app.device, tbuf)

	cmd := sdl.AcquireGPUCommandBuffer(app.device)
	if cmd == nil {
		fmt.eprintfln("FPS overlay AcquireGPUCommandBuffer failed: %s", sdl.GetError())
		sdl.ReleaseGPUTexture(app.device, app.fps_texture)
		app.fps_texture = nil
		return false
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	transfer := sdl.GPUTextureTransferInfo {
		transfer_buffer = tbuf,
		offset          = 0,
		pixels_per_row  = u32(atlas_w),
		rows_per_layer  = u32(atlas_h),
	}
	region := sdl.GPUTextureRegion {
		texture = app.fps_texture,
		w       = u32(atlas_w),
		h       = u32(atlas_h),
		d       = 1,
	}
	sdl.UploadToGPUTexture(copy_pass, transfer, region, false)
	sdl.EndGPUCopyPass(copy_pass)

	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
	if fence == nil {
		fmt.eprintfln("FPS overlay texture upload submit failed: %s", sdl.GetError())
		sdl.ReleaseGPUTexture(app.device, app.fps_texture)
		app.fps_texture = nil
		return false
	}
	defer sdl.ReleaseGPUFence(app.device, fence)

	if !sdl.WaitForGPUFences(app.device, true, &fence, 1) {
		fmt.eprintfln("FPS overlay WaitForGPUFences failed: %s", sdl.GetError())
		sdl.ReleaseGPUTexture(app.device, app.fps_texture)
		app.fps_texture = nil
		return false
	}

	return true
}

@(private)
fps_overlay_shutdown :: proc(app: ^App) {
	if app.device != nil && app.fps_texture != nil {
		sdl.ReleaseGPUTexture(app.device, app.fps_texture)
	}
	app.fps_texture = nil
}

@(private)
fps_overlay_begin_frame :: proc(app: ^App) {
	now := now_seconds()
	if app.fps_last_time > 0 {
		dt := now - app.fps_last_time
		if dt > 0 {
			instant := f32(1.0 / dt)
			if app.fps_smooth <= 0 {
				app.fps_smooth = instant
			} else {
				app.fps_smooth = app.fps_smooth * 0.9 + instant * 0.1
			}
			app.fps_update_accum += f32(dt)
			if app.fps_display == 0 || app.fps_update_accum >= FPS_UPDATE_INTERVAL {
				app.fps_display = int(app.fps_smooth + 0.5)
				app.fps_update_accum = 0
			}
		}
	}
	app.fps_last_time = now
}

@(private)
fps_overlay_queue :: proc(app: ^App) {
	if !app.show_fps || app.fps_texture == nil do return
	if app.cmd == nil || app.swapchain_texture == nil do return
	if app.swapchain_w == 0 || app.swapchain_h == 0 do return

	fps := app.fps_display
	if fps < 0 do fps = 0

	// Build "N… FPS" with the full measured rate (no artificial cap).
	glyphs: [FPS_OVERLAY_MAX_GLYPHS]int
	count := 0

	digits: [8]int
	dcount := 0
	if fps == 0 {
		digits[0] = 0
		dcount = 1
	} else {
		v := fps
		for v > 0 && dcount < len(digits) {
			digits[dcount] = v % 10
			dcount += 1
			v /= 10
		}
		for i in 0 ..< dcount / 2 {
			digits[i], digits[dcount - 1 - i] = digits[dcount - 1 - i], digits[i]
		}
	}

	for i in 0 ..< dcount {
		if count >= FPS_OVERLAY_MAX_GLYPHS do break
		glyphs[count] = FPS_GLYPH_DIGIT_0 + digits[i]
		count += 1
	}
	if count + 4 <= FPS_OVERLAY_MAX_GLYPHS {
		glyphs[count] = FPS_GLYPH_SPACE
		count += 1
		glyphs[count] = FPS_GLYPH_F
		count += 1
		glyphs[count] = FPS_GLYPH_P
		count += 1
		glyphs[count] = FPS_GLYPH_S
		count += 1
	}

	sw := f32(app.swapchain_w)
	sh := f32(app.swapchain_h)
	atlas_w := f32(FPS_ATLAS_COLS * FPS_CELL_W)
	atlas_h := f32(FPS_CELL_H)
	gw := f32(FPS_GLYPH_W * FPS_SCALE)
	gh := f32(FPS_GLYPH_H * FPS_SCALE)
	advance := f32(FPS_CELL_W * FPS_SCALE)
	x := f32(FPS_MARGIN)
	y := f32(FPS_MARGIN)

	for i in 0 ..< count {
		if len(app.draw_list) >= MAX_SPRITES do break

		gi := glyphs[i]
		u0 := f32(gi * FPS_CELL_W) / atlas_w
		v0 := f32(0)
		u1 := f32(gi * FPS_CELL_W + FPS_GLYPH_W) / atlas_w
		v1 := f32(FPS_GLYPH_H) / atlas_h

		x0 := x + f32(i) * advance
		y0 := y
		x1 := x0 + gw
		y1 := y0 + gh

		p0 := to_clip(x0, y0, sw, sh)
		p1 := to_clip(x1, y0, sw, sh)
		p2 := to_clip(x1, y1, sw, sh)
		p3 := to_clip(x0, y1, sw, sh)

		verts := [SPRITE_VERT_COUNT]Vertex {
			{pos = p0, uv = {u0, v0}},
			{pos = p1, uv = {u1, v0}},
			{pos = p2, uv = {u1, v1}},
			{pos = p0, uv = {u0, v0}},
			{pos = p2, uv = {u1, v1}},
			{pos = p3, uv = {u0, v1}},
		}
		append(&app.draw_list, Queued_Sprite{texture = app.fps_texture, verts = verts})
	}
}
