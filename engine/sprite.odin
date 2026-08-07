package engine

import sdl "vendor:sdl3"

Vec2 :: [2]f32

Sprite :: struct {
	data:     ^Character_Data,
	position: Vec2,
	clip:     string,
	frame:    int,
	time:     f32,
	flip_x:   bool,

	draw_ok:          bool,
	draw_cache_dirty: bool,
	draw_src_w:       f32,
	draw_src_h:       f32,
	draw_fw:          f32,
	draw_fh:          f32,
	draw_trim_x:      f32,
	draw_trim_y:      f32,
	draw_u0:          f32,
	draw_v0:          f32,
	draw_u1:          f32,
	draw_v1:          f32,
}

spawn_sprite :: proc(
	data: ^Character_Data,
	position: Vec2,
	clip: string = "idle",
	frame: int = 0,
) -> Sprite {
	sprite := Sprite {
		data     = data,
		position = position,
	}
	set_sprite_clip(&sprite, clip)
	if frame != 0 {
		c, ok := character_clip(sprite.data, sprite.clip)
		if ok {
			if frame < 0 {
				sprite.frame = 0
			} else if frame >= len(c.frames) {
				sprite.frame = len(c.frames) - 1
			} else {
				sprite.frame = frame
			}
		}
	}
	invalidate_sprite_draw_cache(&sprite)
	return sprite
}

update_sprite :: proc(sprite: ^Sprite, dt: f32) {
	if sprite == nil || sprite.data == nil do return
	if dt <= 0 do return

	clip, ok := character_clip(sprite.data, sprite.clip)
	if !ok do return

	frame_count := len(clip.frames)
	if frame_count <= 0 do return

	if sprite.frame < 0 do sprite.frame = 0
	if sprite.frame >= frame_count do sprite.frame = frame_count - 1

	if clip.fps <= 0 do return

	sprite.time += dt
	frame_duration := 1.0 / clip.fps

	frame_changed := false

	for sprite.time >= frame_duration {
		sprite.time -= frame_duration
		next := sprite.frame + 1

		if next >= frame_count {
			if clip.loop {
				sprite.frame = 0
				frame_changed = true
			} else {
				sprite.frame = frame_count - 1
				sprite.time = 0
				break
			}
		} else {
			sprite.frame = next
			frame_changed = true
		}
	}

	if frame_changed {
		invalidate_sprite_draw_cache(sprite)
	}
}

to_clip :: proc(px, py, sw, sh: f32) -> [2]f32 {
	return {
		px / sw * 2 - 1,
		1 - py / sh * 2, // flip y (window pixels are y-down)
	}
}

refresh_sprite_draw_cache :: proc(sprite: ^Sprite) {
	if sprite == nil || sprite.data == nil {
		return
	}
	if !sprite.draw_cache_dirty {
		return
	}

	frame, ok := character_frame(sprite.data, sprite.clip, sprite.frame)
	if !ok {
		sprite.draw_ok = false
		sprite.draw_cache_dirty = false
		return
	}

	src_w := f32(frame.source_size[0])
	src_h := f32(frame.source_size[1])
	if src_w <= 0 do src_w = f32(frame.rect[2])
	if src_h <= 0 do src_h = f32(frame.rect[3])

	tex_w := f32(sprite.data.width)
	tex_h := f32(sprite.data.height)
	u0, v0, u1, v1 := frame_uvs(frame.rect, tex_w, tex_h, false)

	sprite.draw_src_w = src_w
	sprite.draw_src_h = src_h
	sprite.draw_fw = f32(frame.rect[2])
	sprite.draw_fh = f32(frame.rect[3])
	sprite.draw_trim_x = f32(frame.trim_offset[0])
	sprite.draw_trim_y = f32(frame.trim_offset[1])
	sprite.draw_u0 = u0
	sprite.draw_v0 = v0
	sprite.draw_u1 = u1
	sprite.draw_v1 = v1
	sprite.draw_ok = true
	sprite.draw_cache_dirty = false
}

invalidate_sprite_draw_cache :: proc(sprite: ^Sprite) {
	if sprite == nil do return
	sprite.draw_cache_dirty = true
	refresh_sprite_draw_cache(sprite)
}

draw_sprite :: proc(app: ^App, sprite: ^Sprite) {
	if app.cmd == nil || app.swapchain_texture == nil {
		return
	}
	if sprite == nil || sprite.data == nil || sprite.data.texture == nil {
		return
	}
	if len(app.draw_list) >= MAX_SPRITES {
		return
	}
	if !sprite.draw_ok {
		return
	}

	src_w := sprite.draw_src_w
	src_h := sprite.draw_src_h
	fw := sprite.draw_fw
	fh := sprite.draw_fh
	trim_x := sprite.draw_trim_x
	trim_y := sprite.draw_trim_y
	pivot := sprite.data.def.pivot

	u0, v0 := sprite.draw_u0, sprite.draw_v0
	u1, v1 := sprite.draw_u1, sprite.draw_v1
	if sprite.flip_x {
		u0, u1 = u1, u0
	}

	viewport := Vec2{f32(app.swapchain_w), f32(app.swapchain_h)}
	feet := world_to_screen(app.camera, sprite.position, viewport)

	x0_px, y0_px, x1_px, y1_px := sprite_feet_quad(
		feet,
		src_w,
		src_h,
		{trim_x, trim_y},
		{fw, fh},
		pivot,
		sprite.flip_x,
	)

	sw := f32(app.swapchain_w)
	sh := f32(app.swapchain_h)

	if x1_px < 0 || y1_px < 0 || x0_px > sw || y0_px > sh {
		return
	}

	p0 := to_clip(x0_px, y0_px, sw, sh)
	p1 := to_clip(x1_px, y0_px, sw, sh)
	p2 := to_clip(x1_px, y1_px, sw, sh)
	p3 := to_clip(x0_px, y1_px, sw, sh)

	verts := [SPRITE_VERT_COUNT]Vertex {
		{pos = p0, uv = {u0, v0}},
		{pos = p1, uv = {u1, v0}},
		{pos = p2, uv = {u1, v1}},
		{pos = p0, uv = {u0, v0}},
		{pos = p2, uv = {u1, v1}},
		{pos = p3, uv = {u0, v1}},
	}

	append(&app.draw_list, Queued_Sprite{texture = sprite.data.texture, verts = verts})
}

set_sprite_clip :: proc(sprite: ^Sprite, clip: string) {
	if sprite == nil || sprite.data == nil do return

	if sprite.clip == clip do return

	_, ok := character_clip(sprite.data, clip)
	if !ok do return

	sprite.clip = clip
	sprite.frame = 0
	sprite.time = 0
	invalidate_sprite_draw_cache(sprite)
}

sprite_quad_origin :: proc(position: Vec2, size: Vec2, pivot: [2]f32) -> Vec2 {
	return {position.x - size.x * pivot[0], position.y - size.y * pivot[1]}
}

frame_uvs :: proc(rect: [4]int, tex_w, tex_h: f32, flip_x: bool) -> (u0, v0, u1, v1: f32) {
	u0 = f32(rect[0]) / tex_w
	v0 = f32(rect[1]) / tex_h
	u1 = f32(rect[0] + rect[2]) / tex_w
	v1 = f32(rect[1] + rect[3]) / tex_h
	if flip_x do u0, u1 = u1, u0
	return
}

sprite_feet_quad :: proc(
	feet: Vec2,
	src_w, src_h: f32,
	trim: Vec2,
	size: Vec2,
	pivot: [2]f32,
	flip_x: bool,
) -> (
	x0, y0, x1, y1: f32,
) {
	canvas_top := feet.y - src_h * pivot[1]
	if flip_x {
		canvas_left := feet.x - (1.0 - pivot[0]) * src_w
		x0 = canvas_left + (src_w - trim.x - size.x)
		y0 = canvas_top + trim.y
	} else {
		canvas_left := feet.x - src_w * pivot[0]
		x0 = canvas_left + trim.x
		y0 = canvas_top + trim.y
	}
	x1 = x0 + size.x
	y1 = y0 + size.y
	return
}

set_sprite_flip_x :: proc(sprite: ^Sprite, flip: bool) {
	if sprite == nil do return
	sprite.flip_x = flip
}
